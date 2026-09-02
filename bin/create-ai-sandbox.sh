#!/usr/bin/env bash
#
# create-ai-sandbox.sh -- create a per-project containerised environment for
# agentic coding, sharing one "brain" (global rules file) between Antigravity
# and Claude Code.
#
# Design notes:
#   * The canonical global-rules file is ~/.gemini/GEMINI.md. That is where
#     Antigravity looks for global rules; ~/.claude/CLAUDE.md is symlinked to it
#     so Claude Code reads the same bytes, on the host and in the container.
#   * The container does NOT get the host network, the host /dev, or the host X
#     display by default. It gets an isolated display, bridged networking, and
#     only the device nodes it needs. See --display and --with-docker below.
#   * Re-running this script is safe and non-interactive. Everything it writes
#     into files you own is delimited by BEGIN/END markers and replaced in place.
#
set -euo pipefail

readonly MARKER_BEGIN='<!-- BEGIN dev-tools:ai-sandbox-environment -->'
readonly MARKER_END='<!-- END dev-tools:ai-sandbox-environment -->'
readonly BASHRC_BEGIN='# >>> dev-tools ai-sandbox helpers >>>'
readonly BASHRC_END='# <<< dev-tools ai-sandbox helpers <<<'

# Pinned upstream versions. Bump deliberately; do not float.
readonly ANTIGRAVITY_CLI_VERSION='1.1.22-5711547746615296'
readonly ANTIGRAVITY_HUB_VERSION='2.8.1-6512087774658560'
readonly ANTIGRAVITY_IDE_VERSION='2.5.5-4923483625488384'
readonly COMBY_VERSION='1.8.1'
readonly EARTHLY_VERSION='v0.8.15'
readonly GOOGLE_CHROME_VERSION='152.0.7977.64-1'
readonly NODE_MAJOR='24'

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

DISPLAY_MODE="auto"     # auto | wayland | nested | host | none
DISPLAY_MODE_EXPLICIT="no"
WITH_DOCKER="no"        # rootless Docker + Earthly inside the sandbox
FORCE_REBUILD="no"
NO_START="no"
PROJECT_ARG=""

usage() {
    cat <<'USAGE'
Usage: create-ai-sandbox.sh [OPTIONS] [PROJECT_DIR]

Creates (or refreshes) an isolated container sandbox for PROJECT_DIR, defaulting
to the current directory. The project's git root is used, so it is safe to run
from a subdirectory.

Options:
  --display=MODE   How GUI apps in the sandbox reach a screen. Default: auto.
                     wayland  Mount only the host Wayland socket. The container
                              runs its own Xwayland for X11-only apps. Wayland's
                              client isolation means sandboxed apps cannot read
                              your keystrokes or screen. Safest; needs a Wayland
                              host session.
                     xpra     Dedicated Xvfb display plus an xpra server, with
                              its own auth cookie. Each sandboxed app appears as
                              an ordinary window on your desktop -- seamless like
                              host mode -- but it renders on the virtual display,
                              so it cannot read your keystrokes or screen. Needs
                              xpra and xvfb.
                     nested   Run a dedicated Xephyr X server on the host for
                              this sandbox, with its own auth cookie. Sandboxed
                              apps live inside that one window and cannot touch
                              your real display. Needs xserver-xephyr.
                     host     Legacy: share the real host X11 display. Anything
                              in the sandbox can keylog and screenshot your whole
                              session. Opt in explicitly.
                     none     No GUI at all. CLI agents only.
                     auto     wayland if available, else nested, else fail with
                              instructions. Never silently falls back to host.
  --with-docker    Install a rootless Docker daemon and Earthly inside the
                   sandbox. Requires relaxing seccomp/apparmor for the container,
                   which meaningfully weakens isolation. Off by default.
  --rebuild        Force a no-cache image rebuild.
  --no-start       Generate configuration but do not build or start anything.
  -h, --help       Show this message.

Shell helpers installed into ~/.bashrc:
  ai-sandbox            enter the sandbox for the current project
  ai-sandbox-stop       stop it (and its nested display, if any)
  ai-sandbox-restart    recreate the container, picking up new devices
  ai-sandbox-attach     expose a hot-plugged host device, e.g.
                        ai-sandbox-attach /dev/ttyUSB0
  ai-sandbox-rm         remove the container and all copied credentials
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --display=*)  DISPLAY_MODE="${arg#*=}"; DISPLAY_MODE_EXPLICIT="yes" ;;
        --with-docker) WITH_DOCKER="yes" ;;
        --rebuild)    FORCE_REBUILD="yes" ;;
        --no-start)   NO_START="yes" ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
        *)            PROJECT_ARG="$arg" ;;
    esac
done

case "$DISPLAY_MODE" in
    auto|wayland|xpra|nested|host|none) ;;
    *) echo "Invalid --display=$DISPLAY_MODE" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

log()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf '\n!! %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

require() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed.${2:+ $2}"
}

# rsync exits non-zero for benign partial conditions. Treat only those as OK so
# that a real failure is loud instead of silently falling back to a different,
# exclude-free copy strategy.
safe_rsync() {
    local rc=0
    rsync "$@" || rc=$?
    case "$rc" in
        0)      return 0 ;;
        23|24)  log "rsync reported vanished/partial files (code $rc); continuing." ; return 0 ;;
        *)      die "rsync failed with code $rc while copying ${*: -2:1} -> ${*: -1}" ;;
    esac
}

# ---------------------------------------------------------------------------
# Host prerequisites
# ---------------------------------------------------------------------------

step "Checking host prerequisites"
require git
require docker "Install Docker Engine and ensure your user can run it."
require rsync
require python3
docker compose version >/dev/null 2>&1 || die "'docker compose' (v2 plugin) is required."
log "ok"

# ---------------------------------------------------------------------------
# Resolve this script's own location, so we can find both the dev-tools repo
# it lives in and the identity library it shares with the ai-sandbox-* helpers.
# ---------------------------------------------------------------------------

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    link=$(readlink "$SCRIPT_PATH")
    case "$link" in
        /*) SCRIPT_PATH=$link ;;
        *)  SCRIPT_PATH="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)/$link" ;;
    esac
done
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)
DEV_TOOLS_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# Identity and path helpers, shared with the ai-sandbox-* commands so the two
# can never compute a different id for the same project.
# shellcheck source=bin/ai-sandbox-lib.sh
. "$SCRIPT_DIR/ai-sandbox-lib.sh"

# ---------------------------------------------------------------------------
# Resolve the project
# ---------------------------------------------------------------------------

PROJECT_ABS_DIR=$(ai_sandbox_project_root "${PROJECT_ARG:-.}") \
    || die "Cannot enter ${PROJECT_ARG:-.}"
cd "$PROJECT_ABS_DIR"

# Cosmetic only: hostname and log lines. Never used as a unique key, because
# two projects can share a basename.
PROJECT_NAME=$(ai_sandbox_slug "${PROJECT_ABS_DIR##*/}")
[ -n "$PROJECT_NAME" ] || PROJECT_NAME="project"

PROJECT_ID=$(ai_sandbox_project_id "$PROJECT_ABS_DIR")
CONTAINER_NAME="${PROJECT_ID}-agent"

SANDBOX_DIR="$AI_SANDBOX_ROOT/${CONTAINER_NAME}"
IMAGE_NAME="ai-sandbox-${PROJECT_ID}:latest"   # replaced by the shared tag in Task 6
BUILD_DIR="$SANDBOX_DIR/build"          # docker build context: Dockerfile + helpers only
ENV_FILE="$SANDBOX_DIR/.env"
COMPOSE_FILE="$SANDBOX_DIR/docker-compose.yml"
# The cookie lives in its own directory, and that DIRECTORY is what the container
# mounts. xauth rewrites the file by writing a temporary copy and renaming it, so
# a single-file bind mount would leave the container pinned to the old inode and
# reading a stale cookie after any regeneration.
XAUTH_DIR="$SANDBOX_DIR/x11auth"
XAUTH_FILE="$XAUTH_DIR/Xauthority"
CONTAINER_XAUTH="/run/sandbox-x11auth/Xauthority"

HOST_UID=$(id -u)
HOST_GID=$(id -g)
HOST_USER="${USER:-$(id -un)}"
CONTAINER_HOME="/home/${HOST_USER}"

step "Project: $PROJECT_NAME"
log "source    $PROJECT_ABS_DIR"
log "sandbox   $SANDBOX_DIR"
log "container $CONTAINER_NAME"

mkdir -p "$SANDBOX_DIR"
chmod 700 "$SANDBOX_DIR"                # holds OAuth tokens and API keys

# The authoritative record of which project this sandbox belongs to. Migration
# reads it to tell an already-migrated directory from a legacy one.
printf '%s\n' "$PROJECT_ABS_DIR" > "$SANDBOX_DIR/project-path"

mkdir -p "$BUILD_DIR" \
         "$XAUTH_DIR" \
         "$SANDBOX_DIR/antigravity-data" \
         "$SANDBOX_DIR/antigravity-ide-data" \
         "$SANDBOX_DIR/claude-data" \
         "$SANDBOX_DIR/gcloud" \
         "$SANDBOX_DIR/.claude" \
         "$SANDBOX_DIR/.gemini"

# ---------------------------------------------------------------------------
# Locate the host tools/ directory
# ---------------------------------------------------------------------------

if   [ -d "$DEV_TOOLS_DIR/tools" ];              then HOST_TOOLS_DIR="$DEV_TOOLS_DIR/tools"
elif [ -d "$HOME/dev/public/dev-tools/tools" ];  then HOST_TOOLS_DIR="$HOME/dev/public/dev-tools/tools"
elif [ -d "$HOME/tools" ];                       then HOST_TOOLS_DIR="$HOME/tools"
else die "Cannot locate the dev-tools 'tools' directory (looked next to this script, in ~/dev/public/dev-tools, and in ~/tools)."
fi
log "tools     $HOST_TOOLS_DIR"

# ---------------------------------------------------------------------------
# Display mode
# ---------------------------------------------------------------------------

step "Selecting display mode"

# A display mode chosen once stays chosen. Without this, re-running the script
# bare would silently fall back to 'auto' and undo a deliberate --display=host.
if [ "$DISPLAY_MODE_EXPLICIT" = "no" ] && [ -f "$ENV_FILE" ]; then
    STORED_MODE=$(sed -n 's/^SANDBOX_DISPLAY_MODE=//p' "$ENV_FILE" | tail -n 1)
    case "$STORED_MODE" in
        wayland|xpra|nested|host|none)
            DISPLAY_MODE="$STORED_MODE"
            log "keeping the display mode chosen previously (pass --display=... to change it)"
            ;;
    esac
fi

if [ "$DISPLAY_MODE" = "auto" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$HOST_UID}/${WAYLAND_DISPLAY}" ]; then
        DISPLAY_MODE="wayland"
    elif command -v xpra >/dev/null 2>&1 && command -v Xvfb >/dev/null 2>&1; then
        DISPLAY_MODE="xpra"
    elif command -v Xephyr >/dev/null 2>&1; then
        DISPLAY_MODE="nested"
    else
        die "No isolated display backend available.
  This host has no Wayland session, and neither xpra nor Xephyr is installed.
  Fix with one of:
    sudo apt install xpra xvfb           # then re-run (seamless windows, isolated)
    sudo apt install xserver-xephyr      # then re-run (one nested window, isolated)
    $0 --display=none                    # CLI agents only
    $0 --display=host                    # UNSAFE: shares your real X display"
    fi
fi
log "mode: $DISPLAY_MODE"

# NESTED_DISPLAY is derived from the project id so it is stable across runs
# and distinct per sandbox, even for two projects sharing a basename.
NESTED_DISPLAY_NUM=$(( 100 + $(printf '%s' "$PROJECT_ID" | cksum | cut -d' ' -f1) % 80 ))

# The container gets its own /tmp/.X11-unix containing exactly one socket: a hard
# link to this sandbox's Xephyr socket. A directory (rather than a single-socket
# bind) means a restarted Xephyr is picked up without recreating the container,
# and the sandbox never sees the host's other X sockets. It lives inside
# /tmp/.X11-unix so that the hard link is guaranteed to be on the same filesystem.
X11_SOCKET_DIR="/tmp/.X11-unix/.ai-sandbox-${CONTAINER_NAME}"

DISPLAY_ENV_LINES=""
DISPLAY_VOL_LINES=""

add_env() { DISPLAY_ENV_LINES="${DISPLAY_ENV_LINES}      - $1"$'\n'; }
add_vol() { DISPLAY_VOL_LINES="${DISPLAY_VOL_LINES}      - $1"$'\n'; }

case "$DISPLAY_MODE" in
  wayland)
      [ -n "${WAYLAND_DISPLAY:-}" ] || die "--display=wayland but WAYLAND_DISPLAY is not set."
      host_wl="${XDG_RUNTIME_DIR:-/run/user/$HOST_UID}/${WAYLAND_DISPLAY}"
      [ -S "$host_wl" ] || die "Wayland socket $host_wl not found."
      ctr_wl="/run/user/${HOST_UID}/${WAYLAND_DISPLAY}"
      add_env "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
      add_env "XDG_SESSION_TYPE=wayland"
      add_env "OZONE_PLATFORM=wayland"
      add_env "SANDBOX_START_XWAYLAND=1"
      add_env "SANDBOX_START_WM=1"
      add_env "DISPLAY=:99"
      add_vol "\"${host_wl}:${ctr_wl}\""
      log "Host Wayland socket only. X11-only apps get a container-private Xwayland on :99."
      ;;
  xpra)
      require xpra "Install with: sudo apt install xpra xvfb"
      require Xvfb "Install with: sudo apt install xvfb"
      require xauth
      require mcookie "Part of the 'util-linux' package."
      add_env "DISPLAY=:${NESTED_DISPLAY_NUM}"
      add_env "XAUTHORITY=${CONTAINER_XAUTH}"
      # xpra acts as the window manager on the virtual display and hands each
      # window to your real desktop, so a WM inside the container would fight it.
      add_env "SANDBOX_START_WM=0"
      add_vol "\"${X11_SOCKET_DIR}:/tmp/.X11-unix\""
      add_vol "\"${XAUTH_DIR}:/run/sandbox-x11auth:ro\""
      mkdir -p "$X11_SOCKET_DIR"
      chmod 700 "$X11_SOCKET_DIR"
      log "Private Xvfb display :${NESTED_DISPLAY_NUM}, forwarded window-by-window by xpra."
      ;;
  nested)
      require Xephyr "Install with: sudo apt install xserver-xephyr"
      require xauth
      require mcookie "Part of the 'util-linux' package."
      add_env "DISPLAY=:${NESTED_DISPLAY_NUM}"
      add_env "SANDBOX_START_WM=1"
      add_env "XAUTHORITY=${CONTAINER_XAUTH}"
      add_vol "\"${X11_SOCKET_DIR}:/tmp/.X11-unix\""
      add_vol "\"${XAUTH_DIR}:/run/sandbox-x11auth:ro\""
      mkdir -p "$X11_SOCKET_DIR"
      chmod 700 "$X11_SOCKET_DIR"
      log "Dedicated Xephyr server on :${NESTED_DISPLAY_NUM} with a private cookie."
      log "Run 'sandbox-desktop' inside the sandbox to start a window manager."
      ;;
  host)
      [ -n "${DISPLAY:-}" ] || die "--display=host but DISPLAY is not set."
      require xauth
      warn "--display=host shares your real X display. Anything running in this
   sandbox can read your keystrokes and capture your screen, in every
   application, for as long as the container is running."
      add_env "DISPLAY=${DISPLAY}"
      add_env "XAUTHORITY=${CONTAINER_XAUTH}"
      add_vol "\"/tmp/.X11-unix:/tmp/.X11-unix\""
      add_vol "\"${XAUTH_DIR}:/run/sandbox-x11auth:ro\""
      if [ -n "${WAYLAND_DISPLAY:-}" ]; then
          host_wl="${XDG_RUNTIME_DIR:-/run/user/$HOST_UID}/${WAYLAND_DISPLAY}"
          if [ -S "$host_wl" ]; then
              add_env "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
              add_vol "\"${host_wl}:/run/user/${HOST_UID}/${WAYLAND_DISPLAY}\""
          fi
      fi
      ;;
  none)
      log "No display will be shared. GUI applications will not start."
      ;;
esac

# X authority cookie, per sandbox, never world-readable.
if [ "$DISPLAY_MODE" = "nested" ] || [ "$DISPLAY_MODE" = "xpra" ]; then
    # Generate once and keep. Regenerating the cookie while an Xephyr that was
    # started with the old one is still running would silently break auth.
    if [ ! -s "$XAUTH_FILE" ] \
       || ! xauth -f "$XAUTH_FILE" list ":${NESTED_DISPLAY_NUM}" 2>/dev/null | grep -q .; then
        rm -f "$XAUTH_FILE"
        : > "$XAUTH_FILE"
        chmod 600 "$XAUTH_FILE"
        # Our own cookie for our own server; nothing is shared with the real display.
        xauth -f "$XAUTH_FILE" add ":${NESTED_DISPLAY_NUM}" MIT-MAGIC-COOKIE-1 "$(mcookie)"
        log "Generated a private X cookie for :${NESTED_DISPLAY_NUM}"
    else
        log "Reusing the existing X cookie for :${NESTED_DISPLAY_NUM}"
    fi
    # 'xauth add :N' keys the entry to THIS machine's hostname (FamilyLocal).
    # The container has a different hostname, so libX11 inside it would find no
    # matching entry and connect unauthenticated. Add a FamilyWild ('ffff')
    # duplicate carrying the same cookie, which matches from any host. Idempotent.
    # Read fully before writing: piping 'xauth -f F nlist' straight into
    # 'xauth -f F nmerge' deadlocks the second process against the first's lock
    # on F, which fails with "timeout in locking authority file".
    XAUTH_WILD=$(xauth -f "$XAUTH_FILE" nlist ":${NESTED_DISPLAY_NUM}" 2>/dev/null \
                 | grep -v '^ffff' | sed -e 's/^..../ffff/' || true)
    if [ -n "$XAUTH_WILD" ]; then
        printf '%s\n' "$XAUTH_WILD" | xauth -f "$XAUTH_FILE" nmerge -
    fi
    chmod 600 "$XAUTH_FILE"
elif [ "$DISPLAY_MODE" = "host" ]; then
    rm -f "$XAUTH_FILE"
    : > "$XAUTH_FILE"
    chmod 600 "$XAUTH_FILE"
    XAUTH_HOST=$(xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' | sort -u || true)
    if [ -n "$XAUTH_HOST" ]; then
        printf '%s\n' "$XAUTH_HOST" | xauth -f "$XAUTH_FILE" nmerge -
    fi
fi

# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------

PULSE_SOCKET_HOST="${XDG_RUNTIME_DIR:-/run/user/$HOST_UID}/pulse/native"
if [ -S "$PULSE_SOCKET_HOST" ]; then
    add_env "PULSE_SERVER=unix:/run/sandbox-pulse"
    add_vol "\"${PULSE_SOCKET_HOST}:/run/sandbox-pulse\""
    log "Audio: PulseAudio/PipeWire socket shared."
fi

# ---------------------------------------------------------------------------
# Devices
#
# The host /dev is deliberately NOT bind-mounted. Doing so would hand the
# container the host's devpts (every terminal in your session) and the host's
# virtual consoles. Instead each needed device node is passed through
# explicitly, and cgroup rules are added only for majors that are inherently
# per-device (USB serial, USB raw, ALSA) rather than blanket wildcards.
# ---------------------------------------------------------------------------

step "Enumerating devices"

DEVICE_LINES=""
CGROUP_LINES=""
declare -A SEEN_CGROUP=()

add_device() { DEVICE_LINES="${DEVICE_LINES}      - \"$1:$1\""$'\n'; }
add_cgroup() {
    [ -n "${SEEN_CGROUP[$1]:-}" ] && return 0
    SEEN_CGROUP[$1]=1
    CGROUP_LINES="${CGROUP_LINES}      - '$1'"$'\n'
}

pass_through_tty() {
    local dev=$1 major minor
    [ -c "$dev" ] || return 0
    major=$(stat -c '%t' "$dev"); minor=$(stat -c '%T' "$dev")
    major=$((16#$major));         minor=$((16#$minor))
    add_device "$dev"
    add_cgroup "c ${major}:${minor} rwm"
    log "serial: $dev (${major}:${minor})"
}

shopt -s nullglob
for dev in /dev/ttyUSB* /dev/ttyACM*; do
    pass_through_tty "$dev"
done
# Only real hardware UARTs. Every kernel registers 32 legacy ttyS slots whose
# /sys entries all exist regardless of hardware, so presence is not a usable
# test -- 'type' is what distinguishes them: 0 means PORT_UNKNOWN, i.e. the
# kernel probed that slot and found nothing behind it.
skipped_uarts=0
for dev in /dev/ttyS*; do
    node=${dev##*/}
    port_type=$(cat "/sys/class/tty/${node}/type" 2>/dev/null || true)
    if [ -z "$port_type" ]; then
        # 'type' unreadable: fall back to the weaker test rather than drop a
        # port that might be real.
        [ -e "/sys/class/tty/${node}/device" ] || continue
    elif [ "$port_type" = "0" ]; then
        skipped_uarts=$((skipped_uarts + 1))
        continue
    fi
    pass_through_tty "$dev"
done
if [ "$skipped_uarts" -gt 0 ]; then
    log "serial: skipped $skipped_uarts unpopulated legacy UART slot(s)"
fi
shopt -u nullglob

# Hot-plugged USB serial adapters get new minors. These majors are exclusively
# USB serial / USB raw, so wildcarding them exposes nothing else, and lets
# 'ai-sandbox-attach' create the node later without recreating the container.
add_cgroup 'c 188:* rwm'    # ttyUSB
add_cgroup 'c 166:* rwm'    # ttyACM

if [ -d /dev/bus/usb ]; then
    add_vol '"/dev/bus/usb:/dev/bus/usb"'
    add_cgroup 'c 189:* rwm'
    log "usb: /dev/bus/usb (libusb tools, hot-plug aware)"
fi

if [ -d /dev/snd ] && [ "$DISPLAY_MODE" != "none" ]; then
    add_vol '"/dev/snd:/dev/snd"'
    add_cgroup 'c 116:* rwm'
    log "audio: /dev/snd (ALSA)"
fi

SECURITY_OPT_BLOCK=""
if [ "$WITH_DOCKER" = "yes" ]; then
    [ -c /dev/fuse ]    && { add_device /dev/fuse;    add_cgroup 'c 10:229 rwm'; }
    [ -c /dev/net/tun ] && { add_device /dev/net/tun; add_cgroup 'c 10:200 rwm'; }
    SECURITY_OPT_BLOCK=$'    security_opt:\n      - seccomp:unconfined\n      - apparmor:unconfined\n'
    warn "--with-docker relaxes seccomp and AppArmor for this container so that a
   nested rootless daemon can run. That is a real reduction in isolation."
fi

# Virtual serial ports are created inside the container with socat against its
# own private devpts, so no host device is involved. Nothing to pass through.

# ---------------------------------------------------------------------------
# Shared brain
#
# Antigravity reads global rules from ~/.gemini/GEMINI.md and workspace rules
# from .agents/rules/. Claude Code reads ~/.claude/CLAUDE.md. Making the latter
# a symlink to the former is what actually gives both tools one brain, on the
# host as well as inside the container.
# ---------------------------------------------------------------------------

step "Wiring the shared brain"

mkdir -p "$HOME/.gemini" "$HOME/.claude/projects" "$HOME/.antigravity" \
         "$HOME/.config/Antigravity" "$HOME/.config/Antigravity IDE" "$HOME/.config/Claude" \
         "$HOME/.gemini/config" \
         "$HOME/.gemini/antigravity/brain" "$HOME/.gemini/antigravity/conversations" \
         "$HOME/.gemini/antigravity-ide/brain" "$HOME/.gemini/antigravity-ide/conversations"
touch "$HOME/.gitignore"

SHARED_BRAIN="$HOME/.gemini/GEMINI.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
touch "$SHARED_BRAIN"

# Fold any pre-existing Claude Code global memory into the shared file once,
# then make the Claude path a symlink so the two can never drift again.
if [ -e "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; then
    if [ -s "$CLAUDE_MD" ] && ! cmp -s "$CLAUDE_MD" "$SHARED_BRAIN"; then
        backup="${CLAUDE_MD}.pre-ai-sandbox.$(date +%Y%m%d%H%M%S)"
        cp -a "$CLAUDE_MD" "$backup"
        log "Backed up existing ~/.claude/CLAUDE.md -> ${backup##*/}"
        MERGE_SRC="$CLAUDE_MD" python3 - "$SHARED_BRAIN" <<'PYEOF'
import os, sys
target = sys.argv[1]
addition = open(os.environ["MERGE_SRC"], encoding="utf-8").read().strip()
existing = open(target, encoding="utf-8").read()
if addition and addition not in existing:
    sep = "\n\n" if existing.strip() else ""
    with open(target, "a", encoding="utf-8") as f:
        f.write(sep + addition + "\n")
    print("  Merged ~/.claude/CLAUDE.md into ~/.gemini/GEMINI.md")
PYEOF
    fi
    rm -f "$CLAUDE_MD"
fi
ln -sfn "$SHARED_BRAIN" "$CLAUDE_MD"
# shellcheck disable=SC2088  # literal text for display, not a path to expand
log "~/.claude/CLAUDE.md -> ~/.gemini/GEMINI.md"

# Retire the file the previous version of this script used, so the two brains
# do not silently compete.
LEGACY_BRAIN="$HOME/.gemini/antigravity-ide/brain/CLAUDE.md"
if [ -f "$LEGACY_BRAIN" ] && [ ! -L "$LEGACY_BRAIN" ]; then
    mv "$LEGACY_BRAIN" "${LEGACY_BRAIN}.superseded"
    log "Retired legacy brain file -> ${LEGACY_BRAIN##*/}.superseded (Antigravity never read it)"
fi

# Build the tooling notes from the feature set that is actually enabled, so the
# agents are never told about tools that were not installed.
TOOL_NOTES="- \`headroom\` -- token compression for tool output, logs and files
  (\`headroom wrap <tool>\`, \`headroom proxy --port 8787\`, \`headroom doctor\`, \`headroom mcp\`),
  or \`from headroom import compress\`. Use it to shrink large JSON payloads, logs or
  command output before they land in context.
- \`semantic-docs\` -- local vector search over docs, notes, PDFs and daily tasks.
- \`socat\` -- create virtual serial port pairs, e.g.
  \`socat -d -d pty,raw,echo=0 pty,raw,echo=0\`.
- \`parec\`/\`paplay\`, \`arecord\`/\`aplay\`, \`sox\`/\`ffmpeg\` -- audio capture, conversion, playback.
- ImageMagick 6."

if [ "$WITH_DOCKER" = "yes" ]; then
    TOOL_NOTES="${TOOL_NOTES}
- \`docker\` -- rootless Docker daemon running inside this container. Run
  \`sandbox-doctor\` if it is not responding.
- \`earthly\` -- Earthly builds, using that internal daemon."
fi

case "$DISPLAY_MODE" in
    wayland) DISPLAY_NOTE="GUI apps render through the host Wayland compositor; X11-only apps use a container-private Xwayland on :99." ;;
    xpra)    DISPLAY_NOTE="GUI apps render on a private virtual display and are forwarded to the user's desktop by xpra, one window each." ;;
    nested)  DISPLAY_NOTE="GUI apps render into a dedicated Xephyr window on the host; a window manager is started automatically." ;;
    host)    DISPLAY_NOTE="GUI apps render on the host's real X display." ;;
    none)    DISPLAY_NOTE="There is no display. Do not try to start GUI applications." ;;
esac

SANDBOX_BLOCK="${MARKER_BEGIN}
## AI sandbox environment (dev-tools/bin/create-ai-sandbox.sh)

This section applies only when you are running inside an ai-sandbox container
created by \`dev-tools/bin/create-ai-sandbox.sh\` (Ubuntu 22.04, full CLI access
and passwordless sudo). It does not apply when running natively on the host.
You can tell which you are in: inside the sandbox, \`/etc/ai-sandbox-release\` exists.

Available in addition to the usual tooling:

${TOOL_NOTES}

Environment notes:
- ${DISPLAY_NOTE}
- Networking is bridged, not host. The host's own services are reachable at
  \`host.docker.internal\`, not at \`localhost\`.
- The project is mounted read-write at its real host path, so edits are real
  edits to the user's working tree. The rest of the host filesystem is not mounted.
- Only explicitly passed-through serial/USB devices are visible under /dev.

Double-check what you are doing, and whether it addresses the request, before acting.
${MARKER_END}"

SANDBOX_BLOCK="$SANDBOX_BLOCK" python3 - "$SHARED_BRAIN" "$MARKER_BEGIN" "$MARKER_END" <<'PYEOF'
import os, re, sys
path, begin, end = sys.argv[1], sys.argv[2], sys.argv[3]
block = os.environ["SANDBOX_BLOCK"]
with open(path, encoding="utf-8") as f:
    content = f.read()
pattern = re.compile(r"\n*" + re.escape(begin) + r".*?" + re.escape(end) + r"\n*", re.DOTALL)
content = pattern.sub("\n", content).rstrip("\n")
with open(path, "w", encoding="utf-8") as f:
    f.write((content + "\n\n" if content else "") + block + "\n")
PYEOF
log "Updated the ai-sandbox block in ~/.gemini/GEMINI.md"

# The previous version generated a .agentrules file in every project. Neither
# Claude Code nor Antigravity reads that filename, and it claimed the agent was
# sandboxed even when read on the host. Move it aside rather than deleting it.
if [ -f "$PROJECT_ABS_DIR/.agentrules" ] \
   && head -n 1 "$PROJECT_ABS_DIR/.agentrules" | grep -q '^# Agent Environment Context$'; then
    mv "$PROJECT_ABS_DIR/.agentrules" "$PROJECT_ABS_DIR/.agentrules.superseded"
    log "Retired generated .agentrules -> .agentrules.superseded (no tool reads that path)"
fi

# ---------------------------------------------------------------------------
# Copy tool state into the sandbox
# ---------------------------------------------------------------------------

step "Copying tool state into the sandbox"

COMMON_EXCLUDES=(
    --exclude='*Cache*' --exclude='*cache*' --exclude='BrowserMetrics*'
    --exclude='Crashpad' --exclude='logs' --exclude='tmp'
)

if [ -d "$HOME/.gemini" ]; then
    safe_rsync -a --delete-excluded "${COMMON_EXCLUDES[@]}" \
        --exclude='brain' --exclude='conversations' --exclude='config' \
        --exclude='browser_recordings' --exclude='html_artifacts' \
        --exclude='history' --exclude='History*' \
        --exclude='IndexedDB' --exclude='Service Worker' --exclude='GEMINI.md' \
        "$HOME/.gemini/" "$SANDBOX_DIR/.gemini/"
    log ".gemini"
fi
if [ -d "$HOME/.antigravity" ]; then
    safe_rsync -a "${COMMON_EXCLUDES[@]}" "$HOME/.antigravity/" "$SANDBOX_DIR/.antigravity/"
    log ".antigravity"
fi
if [ -d "$HOME/.config/Antigravity" ]; then
    safe_rsync -a "${COMMON_EXCLUDES[@]}" "$HOME/.config/Antigravity/" "$SANDBOX_DIR/antigravity-data/"
    log "Antigravity"
fi
if [ -d "$HOME/.config/Antigravity IDE" ]; then
    safe_rsync -a "${COMMON_EXCLUDES[@]}" "$HOME/.config/Antigravity IDE/" "$SANDBOX_DIR/antigravity-ide-data/"
    log "Antigravity IDE"
fi
if [ -d "$HOME/.config/Claude" ]; then
    safe_rsync -a "${COMMON_EXCLUDES[@]}" "$HOME/.config/Claude/" "$SANDBOX_DIR/claude-data/"
    log "Claude Desktop"
fi
if [ -d "$HOME/.claude" ]; then
    # CLAUDE.md and projects/ are bind-mounted live further down, not copied.
    safe_rsync -a "${COMMON_EXCLUDES[@]}" --exclude='CLAUDE.md' --exclude='projects' \
        "$HOME/.claude/" "$SANDBOX_DIR/.claude/"
    log ".claude"
fi

# ~/.claude.json is the Claude Code CLI's account/session state and lives beside
# ~/.claude rather than inside it. It is copied, not shared, so the host and the
# sandbox keep separate sessions -- but that means sandbox-side changes are lost
# on the next run. Only refresh it when the host copy is newer.
if [ -f "$HOME/.claude.json" ]; then
    if [ ! -f "$SANDBOX_DIR/.claude.json" ] || [ "$HOME/.claude.json" -nt "$SANDBOX_DIR/.claude.json" ]; then
        cp -f "$HOME/.claude.json" "$SANDBOX_DIR/.claude.json"
        log ".claude.json (refreshed from host)"
    else
        log ".claude.json (sandbox copy is newer; left alone)"
    fi
elif [ ! -f "$SANDBOX_DIR/.claude.json" ]; then
    echo '{}' > "$SANDBOX_DIR/.claude.json"
fi
chmod 600 "$SANDBOX_DIR/.claude.json"

# gcloud: no host credentials are copied and no login is performed. The isolated
# config directory is mounted empty; run 'gcloud auth login' inside the sandbox
# if and when a project needs it.
log "gcloud: isolated empty config at $SANDBOX_DIR/gcloud (log in inside the sandbox if needed)"

# ---------------------------------------------------------------------------
# Build context
# ---------------------------------------------------------------------------

step "Generating build context"

cat > "$BUILD_DIR/entrypoint.sh" <<'ENTRYPOINT_EOF'
#!/bin/bash
# Sandbox entrypoint. Brings up optional per-container services, records the
# resulting environment for interactive shells, then hands off.
set -u

RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true
ENV_SNAPSHOT="$RUNTIME_DIR/sandbox-env.sh"
: > "$ENV_SNAPSHOT"

# --- D-Bus -----------------------------------------------------------------
if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
    echo "export DBUS_SESSION_BUS_ADDRESS='${DBUS_SESSION_BUS_ADDRESS}'" >> "$ENV_SNAPSHOT"
fi

# --- Xwayland --------------------------------------------------------------
# In wayland mode the container runs its own X server against the host
# compositor, so X11-only applications work without any host X access.
if [ "${SANDBOX_START_XWAYLAND:-0}" = "1" ] && command -v Xwayland >/dev/null 2>&1; then
    Xwayland :99 >/tmp/xwayland.log 2>&1 &
    for _ in $(seq 1 50); do
        [ -S /tmp/.X11-unix/X99 ] && break
        sleep 0.1
    done
    if [ -S /tmp/.X11-unix/X99 ]; then
        echo "export DISPLAY=:99" >> "$ENV_SNAPSHOT"
    else
        echo "sandbox: Xwayland failed to start; see /tmp/xwayland.log" >&2
    fi
fi

# --- Window manager --------------------------------------------------------
# Without a window manager, apps on a nested display appear undecorated, cannot
# be moved, and ignore the screen resizing when the Xephyr window is resized.
if [ "${SANDBOX_START_WM:-0}" = "1" ] && [ -n "${DISPLAY:-}" ] && command -v openbox >/dev/null 2>&1; then
    for _ in $(seq 1 100); do
        xdpyinfo >/dev/null 2>&1 && break
        sleep 0.1
    done
    if xdpyinfo >/dev/null 2>&1; then
        openbox >/tmp/openbox.log 2>&1 &
    else
        echo "sandbox: X display ${DISPLAY} not reachable; window manager not started" >&2
    fi
fi

# --- Rootless Docker -------------------------------------------------------
if [ "${SANDBOX_WITH_DOCKER:-0}" = "1" ]; then
    if command -v dockerd-rootless.sh >/dev/null 2>&1; then
        export XDG_RUNTIME_DIR="$RUNTIME_DIR"
        dockerd-rootless.sh >/tmp/dockerd-rootless.log 2>&1 &
        echo "export DOCKER_HOST=unix://${RUNTIME_DIR}/docker.sock" >> "$ENV_SNAPSHOT"
        for _ in $(seq 1 100); do
            [ -S "${RUNTIME_DIR}/docker.sock" ] && break
            sleep 0.2
        done
        if [ ! -S "${RUNTIME_DIR}/docker.sock" ]; then
            echo "sandbox: rootless dockerd did not come up; see /tmp/dockerd-rootless.log" >&2
        fi
    else
        # Never advertise a DOCKER_HOST that cannot exist.
        echo "sandbox: --with-docker was requested but dockerd-rootless.sh is missing" >&2
    fi
fi

exec "$@"
ENTRYPOINT_EOF

cat > "$BUILD_DIR/sandbox-doctor" <<'DOCTOR_EOF'
#!/bin/bash
# Report what is and is not working inside the sandbox.
status() { printf '%-22s %s\n' "$1" "$2"; }
echo "== ai-sandbox status =="
status "user"        "$(id -un) ($(id -u):$(id -g))"
status "workdir"     "$PWD"
status "hostname"    "$(hostname)"
status "display"     "${DISPLAY:-<none>}${WAYLAND_DISPLAY:+  wayland=$WAYLAND_DISPLAY}"
if [ -n "${DISPLAY:-}" ]; then
    _d=${DISPLAY#*:}; _d=${_d%%.*}
    _sock="/tmp/.X11-unix/X${_d}"
    status "X socket" "$( [ -S "$_sock" ] && echo "$_sock" || echo "$_sock MISSING (mount problem)" )"
    status "XAUTHORITY" "${XAUTHORITY:-<unset>}"
    if [ -n "${XAUTHORITY:-}" ] && [ -r "${XAUTHORITY}" ]; then
        # A FamilyWild ('#ffff#' / no hostname) entry is what lets this container
        # authenticate against a server started on the host.
        status "xauth entries" "$(xauth -f "$XAUTHORITY" list 2>&1 | awk '{print $1}' | paste -sd' ' -)"
    elif [ -n "${XAUTHORITY:-}" ]; then
        status "xauth entries" "cannot read ${XAUTHORITY}"
    fi
    if _err=$(xdpyinfo 2>&1 >/dev/null); then
        status "X server" "reachable"
    else
        status "X server" "NOT reachable -- $(printf '%s' "$_err" | head -1)"
    fi
fi
status "shared brain" "$( [ -f "$HOME/.claude/CLAUDE.md" ] && echo "$(wc -c < "$HOME/.claude/CLAUDE.md") bytes" || echo MISSING )"
status "audio"        "$( [ -n "${PULSE_SERVER:-}" ] && pactl info >/dev/null 2>&1 && echo ok || echo unavailable )"
serial=$(ls /dev/ttyUSB* /dev/ttyACM* /dev/ttyS* 2>/dev/null | tr '\n' ' ')
status "serial ports" "${serial:-<none passed through>}"
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then status "docker" "ok ($DOCKER_HOST)"
    else status "docker" "NOT running -- see /tmp/dockerd-rootless.log"; fi
else
    status "docker" "not installed (re-run with --with-docker)"
fi
status "host gateway"  "$(getent hosts host.docker.internal >/dev/null 2>&1 && echo ok || echo unavailable)"
DOCTOR_EOF

cat > "$BUILD_DIR/sandbox-desktop" <<'DESKTOP_EOF'
#!/bin/bash
# Start a minimal window manager on the sandbox display, so GUI apps get
# decorations and can be moved around inside the nested screen.
set -e
if [ -z "${DISPLAY:-}" ]; then
    echo "No DISPLAY set. This sandbox was created with --display=none." >&2
    exit 1
fi
if pgrep -u "$(id -u)" openbox >/dev/null 2>&1; then
    echo "Window manager already running on $DISPLAY."
    exit 0
fi
openbox >/tmp/openbox.log 2>&1 &
echo "Started openbox on $DISPLAY."
DESKTOP_EOF

cat > "$BUILD_DIR/xdg-open" <<'XDGOPEN_EOF'
#!/bin/bash
# Electron apps detach from the TTY before printing OAuth URLs. Surface the URL
# on this container's own terminals so it can be copied to a host browser.
url=$1
for term in /dev/pts/*; do
    [ -w "$term" ] || continue
    {
        echo
        echo "============================================================"
        echo "ACTION REQUIRED: open this link in your host browser:"
        echo "$url"
        echo "============================================================"
        echo
    } > "$term" 2>/dev/null || true
done
exit 0
XDGOPEN_EOF

# Interactive shell configuration, sourced from .bashrc. Written as a real file
# rather than a chain of echoes so that quoting is unambiguous.
cat > "$BUILD_DIR/sandbox-bashrc.sh" <<'BASHRC_EOF'
# shellcheck shell=bash
# ai-sandbox interactive shell setup.

# Environment recorded by the entrypoint (D-Bus, DISPLAY, DOCKER_HOST).
# shellcheck disable=SC1090
[ -r "/run/user/$(id -u)/sandbox-env.sh" ] && . "/run/user/$(id -u)/sandbox-env.sh"

export CI=true
export PLAYWRIGHT_HTML_REPORT=none
# PYTHONPATH is set by compose so that 'python3 -m tools.<name>' resolves the
# read-only tools mount; keep a fallback for shells started without it.
[ -n "${PYTHONPATH:-}" ] || export PYTHONPATH="$HOME"

# SDKMAN, mounted from the host.
# shellcheck disable=SC1091
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"

# Git identity is passed in from the host; only set it once.
if [ -n "${HOST_GIT_NAME:-}" ] && [ -z "$(git config --global user.name || true)" ]; then
    git config --global user.name "$HOST_GIT_NAME"
fi
if [ -n "${HOST_GIT_EMAIL:-}" ] && [ -z "$(git config --global user.email || true)" ]; then
    git config --global user.email "$HOST_GIT_EMAIL"
fi
git config --global core.excludesfile "$HOME/.gitignore"

_sandbox_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
export PS1='\[\033[01;33m\][sandbox]\[\033[00m\] \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;35m\]$(_sandbox_git_branch)\[\033[00m\]\$ '
BASHRC_EOF

# --- Dockerfile ------------------------------------------------------------

cat > "$BUILD_DIR/Dockerfile" <<DOCKERFILE_HEAD
# Generated by create-ai-sandbox.sh -- edits here are overwritten on the next run.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \\
    TERM=xterm-256color \\
    CI=true \\
    PLAYWRIGHT_HTML_REPORT=none

ARG NODE_MAJOR=${NODE_MAJOR}
ARG ANTIGRAVITY_CLI_VERSION=${ANTIGRAVITY_CLI_VERSION}
ARG ANTIGRAVITY_HUB_VERSION=${ANTIGRAVITY_HUB_VERSION}
ARG ANTIGRAVITY_IDE_VERSION=${ANTIGRAVITY_IDE_VERSION}
ARG COMBY_VERSION=${COMBY_VERSION}
ARG EARTHLY_VERSION=${EARTHLY_VERSION}
ARG GOOGLE_CHROME_VERSION=${GOOGLE_CHROME_VERSION}
DOCKERFILE_HEAD

cat >> "$BUILD_DIR/Dockerfile" <<'DOCKERFILE_EOF'

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl wget gnupg ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Third-party repositories.
RUN set -eux; \
    mkdir -p /etc/apt/keyrings /usr/share/keyrings; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc \
        https://downloads.claude.ai/claude-desktop/key.asc; \
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
        > /etc/apt/sources.list.d/claude-desktop.list; \
    curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg \
        | gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" \
        > /etc/apt/sources.list.d/antigravity.list; \
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list; \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        > /usr/share/keyrings/cloudflare-main.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main" \
        > /etc/apt/sources.list.d/cloudflared.list; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        > /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list

RUN apt-get update && apt-get install -y --no-install-recommends \
        git sudo less vim-tiny ca-certificates \
        python3 python3-pip python3-venv \
        socat usbutils \
        libwayland-client0 libwayland-egl1 libwayland-cursor0 xwayland \
        openbox xterm x11-utils \
        libnss3 libatk1.0-0 libatk-bridge2.0-0 libdrm2 libgtk-3-0 libgbm1 \
        libasound2 libasound2-plugins pulseaudio-utils alsa-utils \
        xdg-utils dbus-x11 xauth fonts-liberation \
        claude-desktop antigravity google-cloud-cli cloudflared gh nodejs \
        ffmpeg imagemagick sox libsox-fmt-all \
    && rm -rf /var/lib/apt/lists/* \
    && dbus-uuidgen > /etc/machine-id

# Google Chrome, in its own layer so the rest of the image caches independently.
RUN set -eux; \
    wget -q -O /tmp/chrome.deb "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${GOOGLE_CHROME_VERSION}_amd64.deb"; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/chrome.deb; \
    rm -rf /tmp/chrome.deb /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir lancedb fastembed pypdf tqdm "headroom-ai[all]"

RUN npm install -g --force \
        @anthropic-ai/claude-code firebase-tools @google/gemini-cli @ast-grep/cli \
    && npm cache clean --force

RUN set -eux; \
    wget -q "https://github.com/comby-tools/comby/releases/download/${COMBY_VERSION}/comby-${COMBY_VERSION}-x86_64-linux" -O /usr/local/bin/comby; \
    chmod +x /usr/local/bin/comby

RUN set -eux; \
    wget -q "https://storage.googleapis.com/antigravity-public/antigravity-cli/${ANTIGRAVITY_CLI_VERSION}/linux-x64/cli_linux_x64.tar.gz" -O /tmp/cli.tar.gz; \
    tar -xzf /tmp/cli.tar.gz -C /tmp; \
    mv /tmp/antigravity /usr/local/bin/agy; \
    chmod +x /usr/local/bin/agy; \
    rm -f /tmp/cli.tar.gz

RUN set -eux; \
    wget -q "https://storage.googleapis.com/antigravity-public/antigravity-hub/${ANTIGRAVITY_HUB_VERSION}/linux-x64/Antigravity.tar.gz" -O /tmp/hub.tar.gz; \
    tar -xzf /tmp/hub.tar.gz -C /usr/local/; \
    rm -f /tmp/hub.tar.gz

RUN set -eux; \
    wget -q "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${ANTIGRAVITY_IDE_VERSION}/linux-x64/Antigravity%20IDE.tar.gz" -O /tmp/ide.tar.gz; \
    tar -xzf /tmp/ide.tar.gz -C /usr/local/; \
    rm -f /tmp/ide.tar.gz

# Electron apps need --no-sandbox inside a container. These are real wrapper
# scripts on PATH rather than shell aliases, so they also work for one-shot
# invocations such as 'ai-sandbox antigravity2-ide' and from the IDE itself.
RUN set -eux; \
    gui_flags='--no-sandbox --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations'; \
    for spec in \
        'claude-desktop|/usr/bin/claude-desktop' \
        'antigravity|/usr/bin/antigravity' \
        'antigravity2|/usr/local/Antigravity-x64/antigravity' \
        'antigravity2-ide|/usr/local/Antigravity IDE/bin/antigravity-ide'; do \
        name="${spec%%|*}"; target="${spec#*|}"; \
        printf '#!/bin/bash\nexec "%s" %s "$@"\n' "$target" "$gui_flags" > "/usr/local/bin/${name}"; \
        chmod +x "/usr/local/bin/${name}"; \
    done

# Thin wrappers for the dev-tools Python utilities mounted at ~/tools.
RUN set -eux; \
    printf '#!/bin/bash\nexec python3 -m tools.semantic_docs.cli "$@"\n' > /usr/local/bin/semantic-docs; \
    printf '#!/bin/bash\nexec python3 -m tools.agent_log_trimmer "$@"\n' > /usr/local/bin/agent-log-trimmer; \
    chmod +x /usr/local/bin/semantic-docs /usr/local/bin/agent-log-trimmer

# Allow the agent to work with PDFs through ImageMagick.
RUN sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' \
        /etc/ImageMagick-6/policy.xml

# Chrome cannot use its own sandbox inside a container.
RUN mv /usr/bin/google-chrome /usr/bin/google-chrome-original \
    && printf '#!/bin/bash\nexec /usr/bin/google-chrome-original --no-sandbox --disable-dev-shm-usage "$@"\n' \
        > /usr/bin/google-chrome \
    && chmod +x /usr/bin/google-chrome

COPY entrypoint.sh    /usr/local/bin/entrypoint.sh
COPY sandbox-doctor   /usr/local/bin/sandbox-doctor
COPY sandbox-desktop  /usr/local/bin/sandbox-desktop
COPY sandbox-bashrc.sh /etc/ai-sandbox-bashrc.sh
COPY xdg-open         /usr/local/bin/xdg-open
RUN mv /usr/bin/xdg-open /usr/bin/xdg-open-original \
    && chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/sandbox-doctor \
                /usr/local/bin/sandbox-desktop /usr/local/bin/xdg-open \
    && install -d -m 1777 /tmp/.X11-unix \
    && echo "ai-sandbox" > /etc/ai-sandbox-release
DOCKERFILE_EOF

if [ "$WITH_DOCKER" = "yes" ]; then
cat >> "$BUILD_DIR/Dockerfile" <<'DOCKERFILE_DOCKER'

# Rootless Docker. Ubuntu's docker.io package does not ship dockerd-rootless.sh,
# so the upstream repository is used instead.
RUN set -eux; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; \
    chmod a+r /etc/apt/keyrings/docker.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" \
        > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
        docker-compose-plugin docker-ce-rootless-extras \
        rootlesskit slirp4netns fuse-overlayfs uidmap iptables dbus-user-session; \
    rm -rf /var/lib/apt/lists/*; \
    systemctl disable docker.service containerd.service 2>/dev/null || true

RUN wget -q "https://github.com/earthly/earthly/releases/download/${EARTHLY_VERSION}/earthly-linux-amd64" \
        -O /usr/local/bin/earthly \
    && chmod +x /usr/local/bin/earthly
DOCKERFILE_DOCKER
fi

cat >> "$BUILD_DIR/Dockerfile" <<'DOCKERFILE_TAIL'

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=developer

RUN set -eux; \
    if ! getent group "${GROUP_ID}" >/dev/null; then groupadd -g "${GROUP_ID}" "${USER_NAME}"; fi; \
    useradd -s /bin/bash -l -u "${USER_ID}" -g "${GROUP_ID}" -m "${USER_NAME}"; \
    usermod -aG sudo,dialout,plugdev,audio,video "${USER_NAME}"; \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ai-sandbox; \
    chmod 0440 /etc/sudoers.d/ai-sandbox; \
    echo "${USER_NAME}:100000:65536" >> /etc/subuid; \
    echo "${USER_NAME}:100000:65536" >> /etc/subgid; \
    mkdir -p "/home/${USER_NAME}/.config" "/home/${USER_NAME}/.antigravity" \
             "/home/${USER_NAME}/.gemini" "/home/${USER_NAME}/.claude" \
             "/home/${USER_NAME}/tools" "/run/user/${USER_ID}"; \
    chown -R "${USER_ID}:${GROUP_ID}" "/home/${USER_NAME}" "/run/user/${USER_ID}"; \
    chmod 700 "/run/user/${USER_ID}"; \
    echo '. /etc/ai-sandbox-bashrc.sh' >> "/home/${USER_NAME}/.bashrc"

USER ${USER_NAME}
WORKDIR /home/${USER_NAME}

# Antigravity IDE extensions. Claude Code and Red Hat Java come from Open VSX
# (the IDE's default registry); Microsoft-published extensions are not on Open
# VSX, so they are sideloaded from the Marketplace download endpoint. Extension
# registries are outside this script's control, so every install is best-effort.
RUN for ext in anthropic.claude-code redhat.java; do \
        antigravity2-ide --install-extension "$ext" \
            || echo "WARNING: could not install $ext; continuing"; \
    done

RUN set -u; \
    for pair in "ms-python:python" "dbaeumer:vscode-eslint" "esbenp:prettier-vscode"; do \
        publisher="${pair%%:*}"; name="${pair##*:}"; \
        if curl -fsSL --compressed -o "/tmp/${name}.vsix" \
             "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${name}/latest/vspackage"; then \
            antigravity2-ide --install-extension "/tmp/${name}.vsix" \
                || echo "WARNING: could not install ${publisher}.${name}; continuing"; \
        else \
            echo "WARNING: could not download ${publisher}.${name}; continuing"; \
        fi; \
    done; \
    rm -f /tmp/*.vsix

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
DOCKERFILE_TAIL

log "Dockerfile and helper scripts written to $BUILD_DIR"

# ---------------------------------------------------------------------------
# .env
# ---------------------------------------------------------------------------

if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<'ENVEOF'
# Secrets for this sandbox. Uncomment and fill in as needed.
# ANTHROPIC_API_KEY=
# GEMINI_API_KEY=
ENVEOF
fi
chmod 600 "$ENV_FILE"

HOST_GIT_NAME=$(git config user.name 2>/dev/null || true)
HOST_GIT_EMAIL=$(git config user.email 2>/dev/null || true)

HOST_UID="$HOST_UID" \
HOST_GID="$HOST_GID" \
HOST_USER="$HOST_USER" \
HOST_GIT_NAME="$HOST_GIT_NAME" \
HOST_GIT_EMAIL="$HOST_GIT_EMAIL" \
WITH_DOCKER="$WITH_DOCKER" \
DISPLAY_MODE="$DISPLAY_MODE" \
python3 - "$ENV_FILE" <<'PYEOF'
import os, sys
path = sys.argv[1]
managed = {
    "HOST_UID": os.environ.get("HOST_UID", ""),
    "HOST_GID": os.environ.get("HOST_GID", ""),
    "HOST_USER": os.environ.get("HOST_USER", ""),
    "HOST_GIT_NAME": os.environ.get("HOST_GIT_NAME", ""),
    "HOST_GIT_EMAIL": os.environ.get("HOST_GIT_EMAIL", ""),
    "SANDBOX_WITH_DOCKER": "1" if os.environ.get("WITH_DOCKER") == "yes" else "0",
    "SANDBOX_DISPLAY_MODE": os.environ.get("DISPLAY_MODE", ""),
}
MARKER = "# Managed by create-ai-sandbox.sh"
kept = [
    line for line in open(path, encoding="utf-8").read().splitlines()
    if line.split("=", 1)[0].strip() not in managed and line.strip() != MARKER
]
while kept and not kept[-1].strip():
    kept.pop()
lines = kept + ["", MARKER] + [
    f"{k}={v}" for k, v in managed.items() if v != ""
]
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PYEOF

# ---------------------------------------------------------------------------
# docker-compose.yml
# ---------------------------------------------------------------------------

step "Generating docker-compose.yml"

{
cat <<COMPOSE_HEAD
# Generated by create-ai-sandbox.sh -- edits here are overwritten on the next run.
services:
  ${CONTAINER_NAME}:
    build:
      context: "${BUILD_DIR}"
      dockerfile: Dockerfile
      args:
        USER_ID: "\${HOST_UID}"
        GROUP_ID: "\${HOST_GID}"
        USER_NAME: "\${HOST_USER}"
    image: "${IMAGE_NAME}"
    container_name: "${CONTAINER_NAME}"
    hostname: "${PROJECT_NAME}-sandbox"
    restart: "no"
    init: true
    shm_size: '4gb'
    # Bridged, not host, networking: the sandbox can reach the internet but not
    # every service bound to the host's loopback. The host itself is reachable
    # by name when deliberately needed.
    extra_hosts:
      - "host.docker.internal:host-gateway"
    # Matches the real host path so Claude Code's path-keyed state
    # (~/.claude/projects/<sanitised-path>) lines up between host and sandbox.
    working_dir: "${PROJECT_ABS_DIR}"
COMPOSE_HEAD

printf '%s' "$SECURITY_OPT_BLOCK"

if [ -n "$CGROUP_LINES" ]; then
    echo "    device_cgroup_rules:"
    printf '%s' "$CGROUP_LINES"
fi
if [ -n "$DEVICE_LINES" ]; then
    echo "    devices:"
    printf '%s' "$DEVICE_LINES"
fi

cat <<COMPOSE_ENV
    environment:
      - "XDG_RUNTIME_DIR=/run/user/\${HOST_UID}"
      - "TERM=xterm-256color"
      - "CI=true"
      - "PLAYWRIGHT_HTML_REPORT=none"
      - "PYTHONPATH=${CONTAINER_HOME}"
      - "SANDBOX_WITH_DOCKER=\${SANDBOX_WITH_DOCKER}"
COMPOSE_ENV
printf '%s' "$DISPLAY_ENV_LINES"

cat <<'COMPOSE_ENVFILE'
    env_file:
      - .env
COMPOSE_ENVFILE

cat <<COMPOSE_VOLS
    volumes:
      # The project, at its real host path, read-write.
      - "${PROJECT_ABS_DIR}:${PROJECT_ABS_DIR}"
      # dev-tools helpers, read-only.
      - "${HOST_TOOLS_DIR}:${CONTAINER_HOME}/tools:ro"
      # Toolchains managed by SDKMAN on the host, read-only.
      - "${HOME}/.sdkman:${CONTAINER_HOME}/.sdkman:ro"
      - "${HOME}/.gitignore:${CONTAINER_HOME}/.gitignore"
      # Sandbox-local copies of tool state (logins, settings, extensions).
      - "${SANDBOX_DIR}/.gemini:${CONTAINER_HOME}/.gemini"
      - "${SANDBOX_DIR}/.antigravity:${CONTAINER_HOME}/.antigravity"
      - "${SANDBOX_DIR}/.claude:${CONTAINER_HOME}/.claude"
      - "${SANDBOX_DIR}/.claude.json:${CONTAINER_HOME}/.claude.json"
      - "${SANDBOX_DIR}/antigravity-data:${CONTAINER_HOME}/.config/Antigravity"
      - "${SANDBOX_DIR}/antigravity-ide-data:${CONTAINER_HOME}/.config/Antigravity IDE"
      - "${SANDBOX_DIR}/claude-data:${CONTAINER_HOME}/.config/Claude"
      - "${SANDBOX_DIR}/gcloud:${CONTAINER_HOME}/.config/gcloud"
      # The shared brain: one file, read by Antigravity as GEMINI.md and by
      # Claude Code as CLAUDE.md, live on the host and in every sandbox.
      - "${HOME}/.gemini/GEMINI.md:${CONTAINER_HOME}/.gemini/GEMINI.md"
      - "${HOME}/.gemini/GEMINI.md:${CONTAINER_HOME}/.claude/CLAUDE.md"
      # Live-shared Antigravity brain, conversations and config.
      - "${HOME}/.gemini/config:${CONTAINER_HOME}/.gemini/config"
      - "${HOME}/.gemini/antigravity/brain:${CONTAINER_HOME}/.gemini/antigravity/brain"
      - "${HOME}/.gemini/antigravity/conversations:${CONTAINER_HOME}/.gemini/antigravity/conversations"
      - "${HOME}/.gemini/antigravity-ide/brain:${CONTAINER_HOME}/.gemini/antigravity-ide/brain"
      - "${HOME}/.gemini/antigravity-ide/conversations:${CONTAINER_HOME}/.gemini/antigravity-ide/conversations"
      # Live-shared Claude Code per-project history.
      - "${HOME}/.claude/projects:${CONTAINER_HOME}/.claude/projects"
COMPOSE_VOLS
printf '%s' "$DISPLAY_VOL_LINES"
} > "$COMPOSE_FILE"

log "$COMPOSE_FILE"

# ---------------------------------------------------------------------------
# Nested display launcher
# ---------------------------------------------------------------------------

cat > "$SANDBOX_DIR/start-display.sh" <<DISPLAYEOF
#!/usr/bin/env bash
# Start this sandbox's isolated display, if it needs one, and publish its socket
# into the directory the container mounts as /tmp/.X11-unix.
#
# This MUST run before 'docker compose up'. If it does not, Docker finds the
# mount source missing and creates it as a root-owned directory, after which the
# X server cannot bind its socket and reports "server already running".
set -euo pipefail
MODE="${DISPLAY_MODE}"
NUM="${NESTED_DISPLAY_NUM}"
XAUTH="${XAUTH_FILE}"
SOCK_DIR="${X11_SOCKET_DIR}"
LOG_DIR="${SANDBOX_DIR}"
TITLE="ai-sandbox: ${PROJECT_NAME}"
NAME="${CONTAINER_NAME}"
DISPLAYEOF

cat >> "$SANDBOX_DIR/start-display.sh" <<'DISPLAYEOF2'

case "$MODE" in
    nested|xpra) ;;
    *) exit 0 ;;
esac

HOST_XAUTHORITY="${XAUTHORITY:-}"
SOCK="/tmp/.X11-unix/X${NUM}"
export XAUTHORITY="$XAUTH"

# A leftover from a run where the container started first: Docker created the
# socket path as a root-owned directory. /tmp is sticky, so only root can remove it.
if [ -e "$SOCK" ] && [ ! -S "$SOCK" ]; then
    if ! rm -rf "$SOCK" 2>/dev/null; then
        echo "ERROR: $SOCK exists but is not a socket, and cannot be removed." >&2
        echo "       It was created by Docker and is owned by root. Remove it with:" >&2
        echo "           sudo rm -rf $SOCK" >&2
        exit 1
    fi
fi

mkdir -p "$SOCK_DIR"
chmod 700 "$SOCK_DIR"

screen_geometry() {
    local geom
    geom=$(DISPLAY="${HOST_DISPLAY:-${DISPLAY:-}}" xdpyinfo 2>/dev/null \
           | awk '/dimensions:/ {print $2; exit}')
    case "$geom" in
        [0-9]*x[0-9]*) printf '%s' "$geom" ;;
        *)             printf '1920x1080' ;;
    esac
}

x_server_running() {
    [ -S "$SOCK" ] && pgrep -f "$1 :${NUM}\b" >/dev/null 2>&1
}

wait_for_socket() {
    local _i
    for _i in $(seq 1 100); do
        [ -S "$SOCK" ] && return 0
        sleep 0.1
    done
    return 1
}

if [ "$MODE" = "nested" ]; then
    if ! x_server_running Xephyr; then
        GEOM=$(screen_geometry)
        echo "Starting Xephyr on :${NUM} (${GEOM}) for ${NAME}..."
        Xephyr ":${NUM}" -auth "$XAUTH" -screen "$GEOM" -resizeable \
            -title "$TITLE" >"${LOG_DIR}/xephyr.log" 2>&1 &
        if ! wait_for_socket; then
            echo "Xephyr did not start; see ${LOG_DIR}/xephyr.log" >&2
            exit 1
        fi
    fi
else
    # xpra: we start the X server ourselves so that it uses this sandbox's
    # private cookie, then point xpra at it with --use-display=yes. Letting xpra
    # spawn its own Xvfb would put the cookie somewhere we do not control.
    if ! x_server_running Xvfb; then
        echo "Starting Xvfb on :${NUM} for ${NAME}..."
        Xvfb ":${NUM}" -auth "$XAUTH" -screen 0 5760x2560x24+32 \
            +extension Composite +extension RANDR +extension GLX \
            -nolisten tcp -noreset -dpi 96 >"${LOG_DIR}/xvfb.log" 2>&1 &
        if ! wait_for_socket; then
            echo "Xvfb did not start; see ${LOG_DIR}/xvfb.log" >&2
            exit 1
        fi
    fi

    # 'xpra start' is the long-standing name for seamless mode; xpra 6 renamed it
    # to 'xpra seamless' and keeps 'start' as an alias. Try both, and drop the
    # optional flags if this xpra is too old to know them.
    xpra_server_running() {
        xpra list 2>/dev/null | grep -qE "(^|[^0-9]):${NUM}\b"
    }
    if ! xpra_server_running; then
        echo "Starting xpra server on :${NUM}..."
        started=no
        for subcmd in start seamless; do
            for extra in "--systemd-run=no --notifications=no --mdns=no --pulseaudio=no --dbus-launch=no" ""; do
                # shellcheck disable=SC2086
                if xpra "$subcmd" ":${NUM}" --use-display=yes --daemon=yes --start-child="" $extra \
                        >>"${LOG_DIR}/xpra.log" 2>&1; then
                    started=yes; break
                fi
            done
            [ "$started" = yes ] && break
        done
        if [ "$started" != yes ]; then
            echo "xpra server failed to start; see ${LOG_DIR}/xpra.log" >&2
            echo "The Xvfb display on :${NUM} is running, so you can fall back with:" >&2
            echo "    create-ai-sandbox.sh --display=nested" >&2
            exit 1
        fi
    fi

    # The viewer renders the forwarded windows on your real desktop, so it needs
    # your normal display and cookie -- not the sandbox's.
    if ! pgrep -f "xpra attach :${NUM}\b" >/dev/null 2>&1; then
        echo "Attaching the xpra viewer..."
        ( if [ -n "$HOST_XAUTHORITY" ]; then
              export XAUTHORITY="$HOST_XAUTHORITY"
          else
              unset XAUTHORITY
          fi
          exec xpra attach ":${NUM}" >>"${LOG_DIR}/xpra-attach.log" 2>&1 ) &
        sleep 1
    fi
fi

# Hard-link (not copy -- this is a socket) so the container sees exactly this one
# display. Re-linking on every call keeps it correct across server restarts.
if ! ln -f "$SOCK" "$SOCK_DIR/X${NUM}" 2>/dev/null; then
    echo "ERROR: could not hard-link $SOCK into $SOCK_DIR." >&2
    echo "       Re-run with --display=wayland or --display=host." >&2
    exit 1
fi
exit 0
DISPLAYEOF2
chmod +x "$SANDBOX_DIR/start-display.sh"

cat > "$SANDBOX_DIR/stop-display.sh" <<DISPLAYSTOPEOF
#!/usr/bin/env bash
set -euo pipefail
MODE="${DISPLAY_MODE}"
NUM="${NESTED_DISPLAY_NUM}"
export XAUTHORITY="${XAUTH_FILE}"
case "\$MODE" in
    nested)
        pkill -f "Xephyr :\${NUM}\\b" 2>/dev/null || true
        ;;
    xpra)
        pkill -f "xpra attach :\${NUM}\\b" 2>/dev/null || true
        xpra stop ":\${NUM}" >/dev/null 2>&1 || true
        pkill -f "Xvfb :\${NUM}\\b" 2>/dev/null || true
        ;;
    *) exit 0 ;;
esac
rm -f "${X11_SOCKET_DIR}/X${NESTED_DISPLAY_NUM}" 2>/dev/null || true
DISPLAYSTOPEOF
chmod +x "$SANDBOX_DIR/stop-display.sh"

# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------

step "Installing helper commands"

BASHRC_FILE="$HOME/.bashrc"
touch "$BASHRC_FILE"

mkdir -p "$AI_SANDBOX_ROOT/bin"
for helper in ai-sandbox-lib.sh ai-sandbox ai-sandbox-stop ai-sandbox-restart \
              ai-sandbox-attach ai-sandbox-rm; do
    install -m 0755 "$SCRIPT_DIR/$helper" "$AI_SANDBOX_ROOT/bin/$helper"
done
# ai-sandbox-lib.sh is sourced, not run.
chmod 0644 "$AI_SANDBOX_ROOT/bin/ai-sandbox-lib.sh"

# Recorded so ai-sandbox-migrate can refresh these copies without being told
# where the repository lives.
printf 'DEV_TOOLS_DIR=%s\n' "$DEV_TOOLS_DIR" > "$AI_SANDBOX_ROOT/config"
log "$AI_SANDBOX_ROOT/bin"

# The block below is deliberately trivial and stable: the helpers are real
# files now, so an open shell picks up a new version without re-sourcing
# anything, and this text should never need to change again.
HELPERS='# Helpers for dev-tools/bin/create-ai-sandbox.sh live in ~/.ai-sandbox/bin.
case ":$PATH:" in
    *":$HOME/.ai-sandbox/bin:"*) ;;
    *) PATH="$HOME/.ai-sandbox/bin:$PATH" ;;
esac'

SB_BEGIN="$BASHRC_BEGIN" SB_END="$BASHRC_END" SB_HELPERS="$HELPERS" \
python3 - "$BASHRC_FILE" <<'PYEOF'
import os, re, sys
path  = sys.argv[1]
begin = os.environ["SB_BEGIN"]
end   = os.environ["SB_END"]
block = begin + "\n" + os.environ["SB_HELPERS"] + "\n" + end

content = open(path, encoding="utf-8").read()
# Remove this script's marked block, and the unmarked block written by earlier
# versions of the script.
content = re.sub(r"\n*" + re.escape(begin) + r".*?" + re.escape(end) + r"\n*",
                 "\n", content, flags=re.DOTALL)
content = re.sub(r"\n*# Antigravity Sandbox Helper\n.*?\nfunction ai-sandbox-stop\(\)\s*\{.*?\n\}\n",
                 "\n", content, flags=re.DOTALL)
content = content.rstrip("\n")
open(path, "w", encoding="utf-8").write(content + "\n\n" + block + "\n")
PYEOF
log "~/.ai-sandbox/bin added to PATH in ~/.bashrc (run 'source ~/.bashrc' or open a new shell)"

# ---------------------------------------------------------------------------
# Build and start
# ---------------------------------------------------------------------------

if [ "$NO_START" = "yes" ]; then
    step "Done (--no-start)"
    log "Configuration written. Start it with: ai-sandbox"
    exit 0
fi

# The display must exist before the container starts: Docker creates any missing
# bind-mount source itself, as root, which would then block Xephyr from binding.
if [ "$DISPLAY_MODE" = "nested" ] || [ "$DISPLAY_MODE" = "xpra" ]; then
    step "Starting the isolated display"
    "$SANDBOX_DIR/start-display.sh"
fi

step "Building and starting $CONTAINER_NAME"
build_args=(-f "$COMPOSE_FILE" --env-file "$ENV_FILE")
if [ "$FORCE_REBUILD" = "yes" ]; then
    docker compose "${build_args[@]}" build --no-cache
fi
docker compose "${build_args[@]}" up -d --build

step "Ready"
cat <<SUMMARY
  Shell:              ai-sandbox           (run 'source ~/.bashrc' first, this once)
                      An interactive shell in the container. Run anything from it,
                      GUI apps included -- 'antigravity2-ide &'. Open as many as
                      you like; each 'ai-sandbox' is a separate shell.
  One-shot command:   ai-sandbox sandbox-doctor
  Shared brain:       ~/.gemini/GEMINI.md  (~/.claude/CLAUDE.md is a symlink to it)
  Sandbox files:      $SANDBOX_DIR
  Display mode:       $DISPLAY_MODE
  Rootless Docker:    $WITH_DOCKER
SUMMARY

case "$DISPLAY_MODE" in
  xpra)
cat <<'XPRA_HINT'

  GUI apps appear as ordinary windows on your desktop, forwarded one at a time
  by xpra, but they render on a private virtual display -- so nothing in the
  sandbox can read your keystrokes or capture your screen.
      ai-sandbox                 # shell; run 'antigravity2-ide &' from it
  If a window never appears, check xpra-attach.log in the sandbox directory.
XPRA_HINT
    ;;
  nested)
cat <<'NESTED_HINT'

  GUI apps appear inside the Xephyr window, not as separate host windows, and a
  window manager is started for you. If you would rather have them as ordinary
  host windows, as before:
      create-ai-sandbox.sh --display=host
  That shares your real X display, so the sandbox can see your whole session --
  but the network and device isolation stay in place either way. The choice is
  remembered; you do not need to pass --display again.
NESTED_HINT
    ;;
  host)
cat <<'HOST_HINT'

  GUI apps appear as ordinary host windows. Your real X display is shared with
  the sandbox, so anything in it can read your keystrokes and screen.
HOST_HINT
    ;;
esac
