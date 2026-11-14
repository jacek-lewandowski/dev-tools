# create.d/project.sh -- prerequisites, project resolution, paths, the sandbox directory and the sync of shared stores.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

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

project_prerequisites() {
# ---------------------------------------------------------------------------
# Host prerequisites
# ---------------------------------------------------------------------------

step "Checking host prerequisites"
require git
require docker "Install Docker Engine and ensure your user can run it."
require rsync
require python3
docker compose version >/dev/null 2>&1 || die "'docker compose' (v2 plugin) is required."
docker buildx version >/dev/null 2>&1 || die "'docker buildx' (BuildKit) is required: the image build uses cache mounts. Install the docker-buildx-plugin package."
log "ok"
}

project_resolve() {
# ---------------------------------------------------------------------------
# Resolve the project
# ---------------------------------------------------------------------------

# The commands create runs are those beside it, so one run never mixes two revisions.
if [ -x "$SCRIPT_DIR/ai-sandbox-migrate" ]; then
    "$SCRIPT_DIR/ai-sandbox-migrate" || true
fi

PROJECT_ABS_DIR=$(ai_sandbox_create_root "${PROJECT_ARG:-.}") \
    || die "Cannot enter ${PROJECT_ARG:-.}"
cd "$PROJECT_ABS_DIR"

# Cosmetic only: hostname and log lines. Never used as a unique key, because
# two projects can share a basename.
PROJECT_NAME=$(ai_sandbox_slug "${PROJECT_ABS_DIR##*/}")
[ -n "$PROJECT_NAME" ] || PROJECT_NAME="project"

PROJECT_ID=$(ai_sandbox_project_id "$PROJECT_ABS_DIR")
CONTAINER_NAME="${PROJECT_ID}-agent"
# This project's entry under ~/.claude/projects; the only one the sandbox sees.
CLAUDE_PROJECT_DIR="$HOME/.claude/projects/$(ai_sandbox_claude_project_key "$PROJECT_ABS_DIR")"

SANDBOX_DIR="$AI_SANDBOX_ROOT/${CONTAINER_NAME}"

# I10: compose would recreate a running container inside 'up', with no gap in
# which to reset the build caches, so this script refuses before writing
# anything -- with or without --no-start (docs/superpowers/specs/
# 2026-10-02-ai-sandbox-build-caches-design.md).
if ai_sandbox_container_running "$CONTAINER_NAME"; then
    die "$CONTAINER_NAME is running. Stop it first: ai-sandbox-stop"
fi

# D9: the overlay driver_opts 'o' string separates fields with ',' and lower
# layers with ':', so a ',', ':' or whitespace in either path would generate a
# mount that fails at container start instead of failing here.
for _p in "$HOME" "$SANDBOX_DIR"; do
    case "$_p" in
        *[,:[:space:]]*) die "Cannot use '$_p' for build caches: it contains ',', ':' or whitespace." ;;
    esac
done
unset _p

# ONE build context and ONE image for every project: nothing in the generated
# Dockerfile is project-specific, so a per-project tag bought nothing but a
# duplicate of a very large image.
IMAGE_DIR="$AI_SANDBOX_ROOT/image"
BUILD_DIR="$IMAGE_DIR/build"
ENV_FILE="$SANDBOX_DIR/.env"
COMPOSE_FILE="$SANDBOX_DIR/docker-compose.yml"
# The cookie lives in its own directory, and that DIRECTORY is what the container
# mounts. xauth rewrites the file by writing a temporary copy and renaming it, so
# a single-file bind mount would leave the container pinned to the old inode and
# reading a stale cookie after any regeneration.
XAUTH_DIR="$SANDBOX_DIR/x11auth"
# Overrides for the two directives Ubuntu's xpra ships active and that cannot be
# undone from the command line. See the generator further down.
XPRA_CONF_DIR="$SANDBOX_DIR/xpra-conf"
XAUTH_FILE="$XAUTH_DIR/Xauthority"
CONTAINER_XAUTH="/run/sandbox-x11auth/Xauthority"

HOST_UID=$(id -u)
HOST_GID=$(id -g)
HOST_USER="${USER:-$(id -un)}"
# Matching the host home keeps absolute paths valid on both sides of the
# mount, which is what makes logs and path-keyed tool state line up.
CONTAINER_HOME="$HOME"

step "Project: $PROJECT_NAME"
log "source    $PROJECT_ABS_DIR"
log "sandbox   $SANDBOX_DIR"
log "container $CONTAINER_NAME"

mkdir -p "$SANDBOX_DIR"
chmod 700 "$SANDBOX_DIR"                # holds OAuth tokens and API keys

# The authoritative record of which project this sandbox belongs to. Migration
# reads it to tell an already-migrated directory from a legacy one.
printf '%s\n' "$PROJECT_ABS_DIR" > "$SANDBOX_DIR/project-path"

mkdir -p "$BUILD_DIR"

# Bulk assets every sandbox shares, read-only. The host is their only writer:
# its own copy is synced in on every run, so installing or updating an
# extension, plugin or CLI build on the host is what updates the sandboxes.
SHARED_DIR="$AI_SANDBOX_ROOT/shared"
while IFS='|' read -r _sub _ctr _sb; do
    [ -n "$_sub" ] || continue
    mkdir -p "$SHARED_DIR/$_sub"
    if [ -d "$HOME/$_ctr" ] && [ -n "$(ls -A "$HOME/$_ctr" 2>/dev/null)" ]; then
        safe_rsync -a "$HOME/$_ctr/" "$SHARED_DIR/$_sub/"
    fi
done < <(ai_sandbox_shared_mounts)
unset _sub _ctr _sb

# Every per-sandbox bind source, created here rather than left to Docker, which
# would make a missing one root-owned. The list is ai_sandbox_state_dirs in
# ai-sandbox-lib.sh, so that 'ai-sandbox-account reset' recreates the same set.
mkdir -p "$XAUTH_DIR"
while IFS= read -r _dir; do
    [ -n "$_dir" ] && mkdir -p "$SANDBOX_DIR/$_dir"
done < <(ai_sandbox_state_dirs)
unset _dir
# The clone's directory and the bare origin it fetches from (C-KNOW), made here for the
# same reason, before the sync step below, which may fail or find the lock busy.
if ai_knowledge_configured; then
    mkdir -p "$SANDBOX_DIR/knowledge"
    ai_sandbox_make_origin "$SANDBOX_DIR" || warn "cannot make the knowledge origin in $SANDBOX_DIR"
fi
}

project_extensions() {
# The image no longer carries extensions, so the shared store is their only
# source. Not fatal: the IDE simply starts without them until this succeeds.
# The IDE is only in the -gui images, so a sandbox with no display has nothing to install.
[ -n "$IMAGE_GUI" ] || return 0
if ! "$SCRIPT_DIR/ai-sandbox-extensions"; then
    warn "IDE extensions are not installed. Retry with: ai-sandbox-extensions refresh"
fi
}
