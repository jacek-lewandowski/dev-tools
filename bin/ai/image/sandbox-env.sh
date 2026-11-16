# shellcheck shell=sh
# ai-sandbox environment, for interactive and non-interactive shells alike.
# Sourced via /etc/profile.d (login shells), BASH_ENV (non-interactive bash)
# and .bashrc (interactive shells). Keep it idempotent, silent and POSIX.

# Environment recorded by the entrypoint (D-Bus, DISPLAY, DOCKER_HOST).
# shellcheck disable=SC1090
[ -r "/run/user/$(id -u)/sandbox-env.sh" ] && . "/run/user/$(id -u)/sandbox-env.sh"

export CI=true
export PLAYWRIGHT_HTML_REPORT=none
# PYTHONPATH is set by compose so that 'python3 -m tools.<name>' resolves the
# read-only tools mount; keep a fallback for shells started without it.
[ -n "${PYTHONPATH:-}" ] || export PYTHONPATH="$HOME"

# SDKMAN: the sandbox's own farm of defaults (see create-ai-sandbox.sh). This
# is what sdkman-init.sh does to PATH, without the shell functions, so that
# 'java', 'gradle' and friends resolve in scripts and agent shells too.
export SDKMAN_DIR="${SDKMAN_DIR:-$HOME/.sdkman}"
if [ -d "$SDKMAN_DIR/candidates" ]; then
    for _sdk_bin in "$SDKMAN_DIR"/candidates/*/current/bin; do
        [ -d "$_sdk_bin" ] || continue
        case ":$PATH:" in
            *":$_sdk_bin:"*) ;;
            *) PATH="$_sdk_bin:$PATH" ;;
        esac
    done
    unset _sdk_bin
    export PATH
    if [ -d "$SDKMAN_DIR/candidates/java/current" ]; then
        export JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
    fi
fi
