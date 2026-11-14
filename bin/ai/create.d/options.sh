# create.d/options.sh -- usage, option parsing, and the options remembered in .env.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

usage() {
    cat <<'USAGE'
Usage: create-ai-sandbox.sh [OPTIONS] [PROJECT_DIR]

Creates or refreshes an isolated container sandbox for PROJECT_DIR, defaulting
to the current directory. Running from a subdirectory is safe: the nearer of the
directory's sandboxed ancestor and its ancestor holding a .git entry is used,
else the directory itself. Sandboxes are keyed on the project's full path, so two
projects whose directories share a name do not collide.

Options:
  --display=MODE   How GUI apps reach a screen. Default: none. Remembered.
                     wayland  Mount only the host Wayland socket. The container
                              runs its own Xwayland for X11-only apps. Wayland's
                              client isolation means sandboxed apps cannot read
                              your keystrokes or screen. Safest; needs a Wayland
                              host session.
                     xpra     Dedicated Xvfb display plus an xpra server with
                              its own auth cookie. Each app appears as an
                              ordinary window on your desktop, but renders on
                              the virtual display, so it cannot read your
                              keystrokes or screen. Needs xpra and xvfb.
                     nested   Dedicated Xephyr server with its own cookie.
                              Sandboxed apps live inside that one window and
                              cannot touch your real display. Needs
                              xserver-xephyr.
                     host     Legacy: share the real host X11 display. Anything
                              in the sandbox can keylog and screenshot your
                              whole session, in every application. Opt in
                              explicitly.
                     none     No GUI at all. CLI agents only, and an image without the GUI
                              applications (headless Chromium for Playwright and
                              Puppeteer is in every image).
                     auto     wayland if available, else xpra, else nested, else
                              fail with instructions. Never silently falls back
                              to host.
  --with-docker    Install a rootless Docker daemon and Earthly inside the
                   sandbox. Off by default. Remembered. This sets
                   seccomp:unconfined and apparmor:unconfined for the container,
                   which meaningfully weakens isolation, and the nested daemon
                   keeps its own image store inside the container, costing disk
                   per sandbox.
  --no-docker      Undo a remembered --with-docker.
  --audio          Share the host's sound socket and sound devices with the
                   sandbox, microphone included. Off by default. The socket
                   carries capture as well as playback, so anything in the
                   sandbox can record from your microphone, and a program in
                   the sandbox can make the host's sound server, which runs as
                   you, act on its requests: a sandbox with --audio is outside
                   the promise that a sandbox is
                   given no host daemon's socket but its display's.
                   Remembered until --no-audio.
  --no-audio       Drop a remembered --audio: the host's sound stays out of the
                   sandbox.
  --memory=GB      RAM the sandbox may use, a whole number of GB. Default: 2 (one CPU core).
                   Remembered. The sandbox gets half as many CPU cores as GB,
                   rounded up (see Resources below).
  --rebuild        Force a no-cache rebuild of the image. That image is
                   shared by every project, so other sandboxes pick up the new
                   one on their next start.
  --no-start       Generate configuration but do not build or start anything.
  -h, --help       Show this message.

Options marked "Remembered" persist per project: re-running with no flags keeps
the last choice, and passing the option again changes it.

Commands on the host (installed into ~/.ai-sandbox/bin, put on your PATH):
  ai-sandbox            enter the sandbox for the current project; with
                        arguments, run a command inside it
  ai-sandbox-stop       stop it, and its private display if it has one
  ai-sandbox-restart    recreate the container, picking up new devices
  ai-sandbox-attach     expose a hot-plugged device, e.g.
                        ai-sandbox-attach /dev/ttyUSB0
  ai-sandbox-account    status | refresh | reset -- which AI account this
                        project uses, and re-seeding it from the host
  ai-sandbox-extensions refresh -- reinstall the shared IDE extensions
  ai-sandbox-gc         reclaim duplicated state and unused images; confirms
                        before removing anything
  ai-sandbox-migrate    bring ~/.ai-sandbox up to the current layout; runs
                        automatically before every start
  ai-sandbox-rm         remove this project's sandbox and its credentials
  ai-knowledge          init <url> [--integrator DIR] | sync | render | status |
                        proposals -- the shared knowledge repository (global
                        rules, roles, own skills), read-only in every sandbox,
                        proposed to through the sandbox's clone at ~/knowledge

Commands inside the sandbox:
  sandbox-doctor        report what is and is not working
  sandbox-desktop       start a window manager on the private display

Layout under ~/.ai-sandbox:
  <project>-<hash>-agent/   per project: credentials, tool state, compose file.
                            Seeded from the host once, then never overwritten,
                            so each project can hold a different Claude, Codex
                            or Gemini account.
  shared/                   IDE extensions, plugins, CLI builds and the agent
                            skills under ~/.agents, synced from the host and
                            read-only in every sandbox.
  image/                    build context and stamps of the images (one per
                            kind: with or without GUI applications), each
                            shared by every project.
  bin/                      the ai-sandbox-* commands listed above.
  <project>-<hash>-agent/build-caches/  per-sandbox upper/work layers for the
                            Gradle and Maven overlay mounts (see "Build caches"
                            below); emptied on every start, never shared.

Mounted live from the host into every sandbox: ~/.gemini/GEMINI.md (the shared
brain, also read as ~/.claude/CLAUDE.md), the Antigravity brain and
conversations, and this project's own ~/.claude/projects/<key> entry only, so a
sandbox cannot read or write another project's Claude Code history or memory.
Edits there are real edits on the host.

Shared knowledge (optional): after 'ai-knowledge init <private-git-url>
--integrator <dev-tools dir>' the global rules and roles come from that
repository instead, rendered read-only into every sandbox as GEMINI.md,
CLAUDE.md, ~/.codex/AGENTS.md and the tools' agents directories. Each sandbox
gets its own clone at ~/knowledge with main checked out, made and kept current
inside the sandbox from a read-only origin the host maintains; the 'propose-rule'
skill commits one file on a proposal/<date>-<slug>-<hex> branch, and the host
pushes it on the next 'ai-knowledge sync' (or 'sync --all', or a re-run of this script), reading the clone
without running git in it. A 'process-report' report travels the same way as a ref
refs/reports/<name>. A sandbox created before this setup (its SANDBOX_KNOWLEDGE
stamp is not the one knowledge needs, 2) is refused at start until it is
re-created: run this script for its project again.

IntelliJ IDEA: if /opt/idea-IU exists on the host it is mounted read-only and
runnable inside the sandbox as 'idea'. Settings and the licence are copied from
the host once, per project; plugins are shared between projects; indexes are per
project. Being read-only, the IDE cannot update itself -- update it on the host.
For a different install path, set IDEA_HOST_DIR in the environment.

SDKMAN: the host's ~/.sdkman is mounted read-only, so its toolchains are shared
and never duplicated, but each sandbox keeps its OWN default versions, taken
from the host's when the sandbox is first created. Change one from inside with
'sdk default java <version>'; to re-snapshot the host's, delete the sandbox's
sdkman/candidates/<candidate>/current and re-run. The candidates are on PATH and
JAVA_HOME is set in every shell, interactive or not, and 'sdk' works from
scripts too (/usr/local/bin/sdk stands in for the shell function).

Build caches: the host's ~/.gradle/caches, ~/.gradle/wrapper/dists and
~/.m2/repository are each the read-only lower layer of an overlay mount, so
'./gradlew --offline' can use what the host has already downloaded. Writes
inside the sandbox land in build-caches/<key>/upper under the sandbox
directory and are discarded on every start; nothing is ever written back to
the host. 'sandbox-doctor' reports each mount; 'ai-sandbox-gc' reclaims
leftovers from a reset it could not delete outright.

Resources: the container is capped at --memory GB of RAM (default 2, one CPU core) with no
swap, and /dev/shm at 1 GB, which counts against that cap; a changed size
applies from the next start. CPUs follow the memory: half as many cores as GB,
rounded up and never more than the host has, pinned as a cpuset so that
'nproc' inside reports the same number. The cores are chosen to spread the
sandboxes over the host and remembered in the sandbox's .env. All running
sandboxes together may use at most AI_SANDBOX_MEMORY_BUDGET_GB, which you write
by hand into ~/.ai-sandbox/config (no default; nothing is created or started
until it is set): a start that would exceed it is refused, with the running
sandboxes and their sizes listed, until one is stopped or the budget is raised.
A sandbox also yields to the host: lower CPU shares, a higher OOM score so it
is killed first under host memory pressure, and at most 4096 processes.
USAGE
}

options_parse() {
for arg in "$@"; do
    case "$arg" in
        --display=*)  DISPLAY_MODE="${arg#*=}"; DISPLAY_MODE_EXPLICIT="yes" ;;
        --with-docker) WITH_DOCKER="yes"; WITH_DOCKER_EXPLICIT="yes" ;;
        --no-docker)   WITH_DOCKER="no";  WITH_DOCKER_EXPLICIT="yes" ;;
        --audio)       WITH_AUDIO="yes"; WITH_AUDIO_EXPLICIT="yes" ;;
        --no-audio)    WITH_AUDIO="no";  WITH_AUDIO_EXPLICIT="yes" ;;
        --memory=*)   MEMORY_GB="${arg#*=}"; MEMORY_GB_EXPLICIT="yes" ;;
        --rebuild)    FORCE_REBUILD="yes" ;;
        --no-start)   NO_START="yes" ;;
        -h|--help)    usage; exit 0 ;;
        -*)           echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
        *)            PROJECT_ARG="$arg" ;;
    esac
done

# Last-one-wins would silently pick a Docker setting the user did not intend.
seen_with="no"; seen_without="no"; seen_audio="no"; seen_noaudio="no"
for arg in "$@"; do
    case "$arg" in
        --with-docker) seen_with="yes" ;;
        --no-docker)   seen_without="yes" ;;
        --audio)       seen_audio="yes" ;;
        --no-audio)    seen_noaudio="yes" ;;
    esac
done
if [ "$seen_with" = "yes" ] && [ "$seen_without" = "yes" ]; then
    echo "Pass --with-docker or --no-docker, not both." >&2
    exit 2
fi
if [ "$seen_audio" = "yes" ] && [ "$seen_noaudio" = "yes" ]; then
    echo "Pass --audio or --no-audio, not both." >&2
    exit 2
fi
unset seen_with seen_without seen_audio seen_noaudio

case "$DISPLAY_MODE" in
    auto|wayland|xpra|nested|host|none) ;;
    *) echo "Invalid --display=$DISPLAY_MODE" >&2; exit 2 ;;
esac
}

options_check_memory() {
# Checked here, not with the other options above, because the rule for a
# memory size lives in the lib.
if [ "$MEMORY_GB_EXPLICIT" = "yes" ] && ! ai_sandbox_whole_gb "$MEMORY_GB"; then
    echo "Invalid --memory=$MEMORY_GB: a whole number of GB" >&2; exit 2
fi
}

options_remembered() {
# ---------------------------------------------------------------------------
# Display mode
# ---------------------------------------------------------------------------

step "Selecting display mode"

# A display mode chosen once stays chosen. Without this, re-running the script
# bare would silently fall back to 'none' and undo a deliberate --display=host.
# A Docker choice made once stays chosen. Without this, re-running the script
# bare silently regenerates the sandbox without the daemon: the Dockerfile loses
# it, security_opt disappears from the compose file, SANDBOX_WITH_DOCKER flips to
# 0, and the next start has no daemon and no explanation.
if [ "$WITH_DOCKER_EXPLICIT" = "no" ] && [ -f "$ENV_FILE" ]; then
    STORED_DOCKER=$(sed -n 's/^SANDBOX_WITH_DOCKER=//p' "$ENV_FILE" | tail -n 1)
    case "$STORED_DOCKER" in
        1) WITH_DOCKER="yes"; log "keeping rootless Docker (pass --no-docker to drop it)" ;;
        0) WITH_DOCKER="no" ;;
    esac
fi
if [ "$WITH_AUDIO_EXPLICIT" = "no" ] && [ -f "$ENV_FILE" ]; then
    STORED_AUDIO=$(sed -n 's/^SANDBOX_WITH_AUDIO=//p' "$ENV_FILE" | tail -n 1)
    # 2 is a request (--audio, remembered). 1 is the old shape: every run
    # before audio became opt-in wrote it, for the old default and for --audio
    # alike, so it is no request. 0 and anything else read as off.
    case "$STORED_AUDIO" in
        2) WITH_AUDIO="yes" ;;
        1) AUDIO_OLD_VALUE="yes" ;;
        0) AUDIO_STORED_OFF="yes" ;;
    esac
fi
}

options_remembered_memory() {
# ---------------------------------------------------------------------------
# Memory
# ---------------------------------------------------------------------------

# The size chosen once stays chosen, like the options above; a sandbox created
# before the key existed, or one whose hand-edited size the lib rejects (it
# warns, like the start scripts do), gets the lib's 6 GB from
# ai_sandbox_memory_gb; only a sandbox with no .env gets the default 2 GB. See
# the comment on the resource limits at the top of this script.
if [ "$MEMORY_GB_EXPLICIT" = "no" ]; then
    MEMORY_GB=2
    if [ -f "$ENV_FILE" ]; then
        STORED_MEMORY=$(ai_sandbox_env_value "$SANDBOX_DIR" SANDBOX_MEMORY_GB)
        MEMORY_GB=$(ai_sandbox_memory_gb "$SANDBOX_DIR")
        [ "$STORED_MEMORY" != "$MEMORY_GB" ] || log "keeping $MEMORY_GB GB of memory (pass --memory=... to change it)"
        unset STORED_MEMORY
    fi
fi
}

options_remembered_display() {
if [ "$DISPLAY_MODE_EXPLICIT" = "no" ] && [ -f "$ENV_FILE" ]; then
    STORED_MODE=$(sed -n 's/^SANDBOX_DISPLAY_MODE=//p' "$ENV_FILE" | tail -n 1)
    case "$STORED_MODE" in
        wayland|xpra|nested|host|none)
            DISPLAY_MODE="$STORED_MODE"
            log "keeping the display mode chosen previously (pass --display=... to change it)"
            ;;
    esac
fi
}
