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

# The host's IntelliJ IDEA installation. Mounted read-only when it exists, so
# the sandbox can run the IDE without being able to modify or update it, and
# skipped entirely when it does not. Override for a different install path:
#   IDEA_HOST_DIR=/opt/idea-2025.1 create-ai-sandbox.sh
readonly IDEA_HOST_DIR="${IDEA_HOST_DIR:-/opt/idea-IU}"
# Where the host keeps /etc/timezone and /etc/localtime, read to give the
# sandbox the host's timezone. Overridable so the tests can stand in a fake.
readonly HOST_ETC_DIR="${HOST_ETC_DIR:-/etc}"
# Where the host keeps its sound devices, tested for and mounted (at /dev/snd in
# the sandbox) only for a sandbox created with --audio. Overridable so the
# tests can stand in a fake.
readonly HOST_SND_DIR="${HOST_SND_DIR:-/dev/snd}"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

DISPLAY_MODE="none"     # auto | wayland | nested | host | none; none unless one is remembered or passed
DISPLAY_MODE_EXPLICIT="no"
WITH_DOCKER="no"        # rootless Docker + Earthly inside the sandbox
WITH_DOCKER_EXPLICIT="no"
WITH_AUDIO="no"         # host sound socket and devices, microphone included; off unless asked for
WITH_AUDIO_EXPLICIT="no"
AUDIO_OLD_VALUE="no"    # the stored value was the one the old default wrote
AUDIO_STORED_OFF="no"   # the stored value was 0: audio was switched off before
HOST_LOGINS_EXPLICIT="no"   # --host-logins: copy the login rows too (see options_remembered_logins)
LOGINS_MODE=""          # the SANDBOX_HOST_LOGINS value to record: 0, 1 or empty (unrecorded)
LOGINS_SEED="no"        # yes when the first seed copies the login rows
MEMORY_GB=""            # --memory=GB; the remembered size, else 2, when empty
MEMORY_GB_EXPLICIT="no"
FORCE_REBUILD="no"
NO_START="no"
PROJECT_ARG=""

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
# Physical: a directory reached through a link names the tree its files are in, so one
# run never mixes two revisions.
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)

# Identity and path helpers, shared with the ai-sandbox-* commands so the two
# can never compute a different id for the same project. Sourced first because the
# refusal to run from a tree a sandbox can write comes before anything else.
# shellcheck source=bin/ai/ai-sandbox-lib.sh
. "$SCRIPT_DIR/ai-sandbox-lib.sh"
ai_sandbox_refuse_writable_self "${BASH_SOURCE[0]}" || exit 3

. "$SCRIPT_DIR/create.d/options.sh"
. "$SCRIPT_DIR/create.d/project.sh"
. "$SCRIPT_DIR/create.d/display.sh"
. "$SCRIPT_DIR/create.d/resources.sh"
. "$SCRIPT_DIR/create.d/devices.sh"
. "$SCRIPT_DIR/create.d/rules.sh"
. "$SCRIPT_DIR/create.d/seed.sh"
. "$SCRIPT_DIR/create.d/image.sh"
. "$SCRIPT_DIR/create.d/compose.sh"
. "$SCRIPT_DIR/create.d/install.sh"
. "$SCRIPT_DIR/create.d/start.sh"

# The modules define; the stages run here, in this order.
options_parse "$@"
install_require_revision
project_prerequisites
options_check_memory
resources_budget_gate
project_resolve
options_remembered
options_remembered_memory
options_remembered_logins
resources_limits
options_remembered_display
display_resolve
image_name
resources_cpuset
display_environment
devices_audio
resources_timezone
devices_enumerate
rules_shared_brain
seed_tool_state
seed_idea
seed_sdkman
image_context
compose_env
compose_file
display_launchers
start_gate
image_build
project_extensions
start_run
