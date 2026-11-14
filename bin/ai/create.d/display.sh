# create.d/display.sh -- display mode, X authority, start-display.sh, stop-display.sh and xpra.conf.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

display_resolve() {
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

# The container gets its own /tmp/.X11-unix containing exactly one socket: a hard
# link to this sandbox's Xephyr socket. A directory (rather than a single-socket
# bind) means a restarted Xephyr is picked up without recreating the container,
# and the sandbox never sees the host's other X sockets. It lives inside
# /tmp/.X11-unix so that the hard link is guaranteed to be on the same filesystem.
X11_SOCKET_DIR="/tmp/.X11-unix/.ai-sandbox-${CONTAINER_NAME}"

# The display number is allocated once and remembered in .env. The first
# candidate is derived from the project id, but that formula has only 80 slots,
# and two sandboxes on one number do not share a display: the second finds a
# server it cannot authenticate to, because each has its own cookie. So skip
# every number another sandbox has recorded (or, for one created before numbers
# were recorded, would derive) and every socket some other X server holds.
display_num_default() {
    printf '%s' "$(( 100 + $(printf '%s' "$1" | cksum | cut -d' ' -f1) % 80 ))"
}
NESTED_DISPLAY_NUM=""
if [ -f "$ENV_FILE" ]; then
    NESTED_DISPLAY_NUM=$(sed -n 's/^SANDBOX_DISPLAY_NUM=//p' "$ENV_FILE" | tail -n 1)
    case "$NESTED_DISPLAY_NUM" in *[!0-9]*) NESTED_DISPLAY_NUM="" ;; esac
fi
if [ -z "$NESTED_DISPLAY_NUM" ]; then
    declare -gA CLAIMED_DISPLAY=()
    for other_env in "$AI_SANDBOX_ROOT"/*-agent/.env; do
        other_dir=${other_env%/.env}
        [ -f "$other_env" ] && [ "$other_dir" != "$SANDBOX_DIR" ] || continue
        n=$(sed -n 's/^SANDBOX_DISPLAY_NUM=//p' "$other_env" | tail -n 1)
        other_id=${other_dir##*/}; other_id=${other_id%-agent}
        case "$n" in ""|*[!0-9]*) n=$(display_num_default "$other_id") ;; esac
        CLAIMED_DISPLAY[$n]=1
    done
    first=$(display_num_default "$PROJECT_ID")
    for (( n = first; n < first + 900; n++ )); do
        [ -n "${CLAIMED_DISPLAY[$n]:-}" ] && continue
        if [ -e "/tmp/.X11-unix/X$n" ] && ! [ "/tmp/.X11-unix/X$n" -ef "$X11_SOCKET_DIR/X$n" ]; then
            continue
        fi
        NESTED_DISPLAY_NUM=$n; break
    done
    [ -n "$NESTED_DISPLAY_NUM" ] || die "No free X display number between :$first and :$((first + 899))."
    unset CLAIMED_DISPLAY other_env other_dir other_id n first
fi
}

# W9: /tmp/.X11-unix is written by a sandbox started with --display=host, so the socket directory
# below it is made, with its mode, without following a link (D20); a refusal stops create.
make_socket_dir() {
    mkdir -p /tmp/.X11-unix
    ai_sandbox_nofollow mkdir /tmp/.X11-unix "${X11_SOCKET_DIR#/tmp/.X11-unix/}" 700 \
        || die "cannot make $X11_SOCKET_DIR: a link or a file is in the way; remove it, then re-run."
}

display_environment() {
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
      make_socket_dir
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
      make_socket_dir
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
}

display_launchers() {
# ---------------------------------------------------------------------------
# Nested display launcher
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# xpra overrides
#
# xpra reads config from the application defaults, then /etc/xpra, then the
# "user" config dirs, merging each DIRECTORY over the previous one with a whole
# dict update. So a key set in a later directory REPLACES the earlier value --
# which is the only way to undo a list-typed option, because --start and
# --start-child APPEND to the config value on the command line instead of
# replacing it. XPRA_USER_CONF_DIRS moves that last directory here, so this
# sandbox gets the overrides without touching the user's own ~/.xpra.
# ---------------------------------------------------------------------------

if [ "$DISPLAY_MODE" = "xpra" ]; then
    mkdir -p "$XPRA_CONF_DIR"
    cat > "$XPRA_CONF_DIR/xpra.conf" <<'XPRACONF_EOF'
# Generated by create-ai-sandbox.sh -- edits here are overwritten on the next run.
# Read by xpra via XPRA_USER_CONF_DIRS, last and therefore winning.

# Ubuntu's xpra ships /etc/xpra/conf.d/60_server.conf with
#     start = /etc/X11/Xsession true
# uncommented. Debian's Xsession treats its argument as the session program to
# run; "true" is not a registered session, so it pops an xmessage error dialog
# on the sandbox's display and then falls back to starting the host's DEFAULT X
# session there -- a second window manager competing with xpra, plus its whole
# process tree. /bin/true replaces it with a no-op.
start = /bin/true
start-child = /bin/true
# start-child exits immediately by design, so make sure that cannot take the
# server with it. (/etc/xpra already sets this; pinned because we rely on it.)
exit-with-children = no

# /etc/xpra/conf.d/40_client.conf ships 'desktop-scaling = auto'. auto scales by
# PIXEL COUNT, not by DPI: its buckets are 3960x2160 -> 1.0 and 7680x4320 ->
# 1.25, and the 5760x2560 virtual screen the launcher asks Xvfb for is
# 14.7 Mpx, which lands in the second one. That is the 125%.
# '1' is in xpra's TRUE_OPTIONS so it parses as exactly 1:1; 'off' also ends up
# 1:1 but logs 'failed to parse scaling value' on the way.
desktop-scaling = 1
dpi = 96
# The viewer runs on the host GPU, and on Intel xpra prints "vendor 'Intel' is
# greylisted, you may want to turn off OpenGL if you encounter bugs". With GL
# on, a forwarded window flickers, leaves artefacts and disturbs other
# GPU-composited windows (Chrome) on a two-monitor GNOME session. Software
# rendering is plenty for IDE and terminal windows.
opengl = no
XPRACONF_EOF
    log "xpra overrides: $XPRA_CONF_DIR/xpra.conf"
fi

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
XPRA_CONF="${XPRA_CONF_DIR}"
SOCK_DIR="${X11_SOCKET_DIR}"
# I6: the function comes from the installed revision at run time, so a script generated by one
# revision keeps working after a later install; each call sources it in a subshell, leaving this
# script's variables alone.
NOFOLLOW_LIB="${AI_SANDBOX_INSTALLED}/current/bin/ai/ai-sandbox-lib.sh"
LOG_DIR="${SANDBOX_DIR}"
TITLE="ai-sandbox: ${PROJECT_NAME}"
NAME="${CONTAINER_NAME}"
DISPLAYEOF

cat >> "$SANDBOX_DIR/start-display.sh" <<'DISPLAYEOF2'

case "$MODE" in
    nested|xpra) ;;
    *) exit 0 ;;
esac

SOCK_ROOT=/tmp/.X11-unix
SOCK_REL="${SOCK_DIR#"$SOCK_ROOT"/}"
# W9: /tmp/.X11-unix may be written by a --display=host sandbox, so the socket directory is made
# and the socket published through ai_sandbox_nofollow (rooted at /tmp/.X11-unix), never by path.
nofollow() {
    [ -r "$NOFOLLOW_LIB" ] || { echo "ERROR: $NOFOLLOW_LIB is missing; run ai-sandbox-install." >&2; return 1; }
    ( . "$NOFOLLOW_LIB" && ai_sandbox_nofollow "$@" )
}

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

mkdir -p "$SOCK_ROOT"
nofollow mkdir "$SOCK_ROOT" "$SOCK_REL" 700 || {
    echo "ERROR: could not make $SOCK_DIR: a link or a file is in the way." >&2
    exit 1
}

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
    # Everything below reads this sandbox's own xpra config, which is what
    # neutralises '/etc/X11/Xsession true' and 'desktop-scaling = auto'.
    export XPRA_USER_CONF_DIRS="$XPRA_CONF"
    # Those overrides are silently inert on an xpra that does not know the
    # variable, so confirm it really is reading the directory. 'showsetting'
    # lists the config dirs it consults, on stderr.
    if xpra showsetting start >"${LOG_DIR}/xpra-showsetting.log" 2>&1 \
       && ! grep -qF "$XPRA_CONF" "${LOG_DIR}/xpra-showsetting.log"; then
        echo "WARNING: this xpra ignored XPRA_USER_CONF_DIRS, so the Xsession error" >&2
        echo "         dialog and the 125% scaling will come back. Comment out" >&2
        echo "         'start = /etc/X11/Xsession true' in /etc/xpra/conf.d/60_server.conf" >&2
        echo "         and 'desktop-scaling = auto' in /etc/xpra/conf.d/40_client.conf." >&2
    fi

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
            # No --start/--start-child here: they append to the config value
            # rather than replace it, so a command line cannot cancel what
            # /etc/xpra sets. That is done in this sandbox's xpra.conf instead.
            for extra in "--systemd-run=no --notifications=no --mdns=no --pulseaudio=no --dbus-launch=no" ""; do
                # shellcheck disable=SC2086
                if xpra "$subcmd" ":${NUM}" --use-display=yes --daemon=yes $extra \
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

    # Belt and braces over the xpra.conf above: these are ordinary scalar
    # options, so the command line beats any config file on any xpra version,
    # whether or not XPRA_USER_CONF_DIRS was understood. Probed rather than
    # assumed, because an xpra that does not recognise a flag refuses to attach.
    attach_opts=()
    attach_help=$( { xpra attach --help || true; xpra --help || true; } 2>&1 )
    for opt in --desktop-scaling=1 --dpi=96 --opengl=no; do
        case "$attach_help" in
            *"${opt%%=*}"*) attach_opts+=("$opt") ;;
        esac
    done

    attach_viewer() {
        # The viewer renders the forwarded windows on your real desktop, so it
        # needs your normal display and cookie -- not the sandbox's.
        ( if [ -n "$HOST_XAUTHORITY" ]; then
              export XAUTHORITY="$HOST_XAUTHORITY"
          else
              unset XAUTHORITY
          fi
          # Toolkit scaling in the host session would re-enlarge the viewer's own
          # idea of the screen after desktop-scaling has been turned off.
          unset GDK_SCALE GDK_DPI_SCALE QT_SCALE_FACTOR QT_AUTO_SCREEN_SCALE_FACTOR
          exec xpra attach ":${NUM}" "$@" >>"${LOG_DIR}/xpra-attach.log" 2>&1 ) &
        sleep 1
    }

    if ! pgrep -f "xpra attach :${NUM}\b" >/dev/null 2>&1; then
        echo "Attaching the xpra viewer..."
        attach_viewer "${attach_opts[@]+"${attach_opts[@]}"}"
        # A flag this xpra dislikes makes the viewer exit at once, and a sandbox
        # with no windows at all is a worse failure than one at the wrong scale.
        if [ "${#attach_opts[@]}" -gt 0 ] \
           && ! pgrep -f "xpra attach :${NUM}\b" >/dev/null 2>&1; then
            echo "The viewer rejected ${attach_opts[*]}; retrying without it." >&2
            attach_viewer
        fi
    fi
fi

# Hard-link (not copy -- this is a socket) so the container sees exactly this one
# display. Re-linking on every call keeps it correct across server restarts.
if ! nofollow hardlink "$SOCK_ROOT" "$SOCK_REL/X${NUM}" "$SOCK"; then
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
export XPRA_USER_CONF_DIRS="${XPRA_CONF_DIR}"
NOFOLLOW_LIB="${AI_SANDBOX_INSTALLED}/current/bin/ai/ai-sandbox-lib.sh"
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
# W9, D26: removed through the function rooted at /tmp/.X11-unix (a link at the directory is not followed);
# an installed revision that lacks it leaves the socket, which the next start publishes over.
if [ -r "\$NOFOLLOW_LIB" ]; then
    ( . "\$NOFOLLOW_LIB" && ai_sandbox_nofollow remove /tmp/.X11-unix "${X11_SOCKET_DIR#/tmp/.X11-unix/}/X${NESTED_DISPLAY_NUM}" ) 2>/dev/null || true
fi
DISPLAYSTOPEOF
chmod +x "$SANDBOX_DIR/stop-display.sh"
}
