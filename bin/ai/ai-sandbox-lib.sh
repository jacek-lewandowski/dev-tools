#!/usr/bin/env bash
# Shared definitions for create-ai-sandbox.sh and the ai-sandbox-* helpers.
# This file is SOURCED, never executed. It must not call 'set -e' or exit.
#
# Identity is defined here exactly once. create-ai-sandbox.sh and every helper
# must call these functions rather than recomputing a project id, because a
# divergence between two implementations silently orphans a sandbox directory.

AI_SANDBOX_ROOT="${AI_SANDBOX_ROOT:-$HOME/.ai-sandbox}"
AI_SANDBOX_SCHEMA_VERSION=2

# Lowercase, replace every non-alphanumeric with '-', collapse runs, trim both
# ends. Trimming the trailing end matters: 'foo.' would otherwise yield 'foo-',
# and 'foo-' + '-' + hash is a double dash, which Docker rejects in a
# repository component.
ai_sandbox_slug() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed -e 's/[^a-z0-9]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-*//' -e 's/-*$//'
}

# <slug of basename>-<first 8 hex of sha256 of the absolute path>.
ai_sandbox_project_id() {
    local abs=$1 slug hash
    slug=$(ai_sandbox_slug "$(basename "$abs")")
    [ -n "$slug" ] || slug=project
    hash=$(printf '%s' "$abs" | sha256sum | cut -c1-8)
    printf '%s-%s' "$slug" "$hash"
}

# Claude Code keys its per-project state (~/.claude/projects/<key>) by the
# absolute project path with every character outside [A-Za-z0-9] turned into
# '-'. Reproducing that lets a sandbox mount only its own project's entry.
ai_sandbox_claude_project_key() {
    printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'
}

# The git toplevel when there is one, so running from a subdirectory is safe.
ai_sandbox_project_root() {
    local dir=${1:-$PWD}
    (
        cd "$dir" 2>/dev/null || exit 1
        local top
        if top=$(git rev-parse --show-toplevel 2>/dev/null); then
            printf '%s\n' "$top"
        else
            pwd
        fi
    )
}

ai_sandbox_dir_for() {
    printf '%s/%s-agent' "$AI_SANDBOX_ROOT" "$(ai_sandbox_project_id "$1")"
}

# Resolve the sandbox for the current directory. Sets AI_SANDBOX_DIR,
# AI_SANDBOX_NAME and AI_SANDBOX_PROJECT, or returns 1 with a message.
ai_sandbox_require_ctx() {
    AI_SANDBOX_PROJECT=$(ai_sandbox_project_root) || return 1
    AI_SANDBOX_DIR=$(ai_sandbox_dir_for "$AI_SANDBOX_PROJECT")
    AI_SANDBOX_NAME=$(basename "$AI_SANDBOX_DIR")
    if [ ! -f "$AI_SANDBOX_DIR/docker-compose.yml" ]; then
        echo "No sandbox configured for this project ($AI_SANDBOX_DIR)." >&2
        echo "Create one with: create-ai-sandbox.sh" >&2
        return 1
    fi
}

ai_sandbox_compose() {
    docker compose -f "$AI_SANDBOX_DIR/docker-compose.yml" \
                   --env-file "$AI_SANDBOX_DIR/.env" "$@"
}

# Deterministic hash over a build context and the build args that go with it.
# Sorting the paths under a fixed locale is what makes it reproducible across
# machines; hashing contents rather than mtimes is what stops a rebuild being
# triggered by a rewrite that changed nothing.
ai_sandbox_build_hash() {
    local dir=$1; shift
    {
        ( cd "$dir" && find . -type f -print0 | LC_ALL=C sort -z \
            | while IFS= read -r -d '' f; do
                  printf '%s\0%s\0' "${f#./}" "$(sha256sum "$f" | cut -d' ' -f1)"
              done )
        printf '%s\0' "$@"
    } | sha256sum | cut -d' ' -f1
}

# Bulk data that is identical across projects, so every sandbox mounts one
# shared copy instead of carrying its own.
#
# Sandboxes are NOT one trust domain. Everything here is executable code -- IDE
# extensions, JetBrains plugins, Claude Code and Claude Desktop binaries -- so
# it is mounted READ-ONLY into every sandbox and written only by the host:
# create-ai-sandbox.sh syncs the host's own copy in on every run, and
# ai-sandbox-extensions installs what the host does not have. A compromised
# sandbox therefore cannot plant code that another sandbox runs. Whatever a
# sandbox must write at run time (~/.cache, ~/.npm, the IDE's CachedData) is
# per sandbox and deliberately absent from this table.
#
# Each row is three fields:
#   <subdirectory of shared/>|<path in the container>|<path in the sandbox dir>
#
# The second field is also the path under $HOME on the host that the store is
# populated from. The second and third differ, and that difference is load-bearing. The
# container sees ~/.config/Claude, but the sandbox directory holds the same data
# under claude-data/ (and antigravity-data/, antigravity-ide-data/). An empty
# third field means the data exists ONLY in the container's writable layer and
# has no per-project copy on disk -- migration and gc skip those rows rather
# than hunting for a directory that never existed.
#
# These are nested bind mounts inside the per-project mounts. Docker orders
# mounts by destination depth, which is what makes the nesting work;
# ~/.claude/projects has relied on that since before this change.
ai_sandbox_shared_mounts() {
    cat <<'SHARED'
antigravity-extensions|.antigravity/extensions|.antigravity/extensions
antigravity-ide-extensions|.antigravity-ide/extensions|
claude-downloads|.claude/downloads|.claude/downloads
claude-desktop-versions|.config/Claude/claude-code|claude-data/claude-code
ide-vsix|.config/Antigravity IDE/CachedExtensionVSIXs|antigravity-ide-data/CachedExtensionVSIXs
jetbrains-plugins|.local/share/JetBrains|
SHARED
}

# Every helper installed into $AI_SANDBOX_ROOT/bin. create-ai-sandbox.sh
# installs from this list and ai-sandbox-migrate refreshes from it, so a helper
# added here is picked up by both without either being edited.
ai_sandbox_helpers() {
    cat <<'HELPERS'
ai-sandbox-lib.sh
ai-sandbox
ai-sandbox-stop
ai-sandbox-restart
ai-sandbox-attach
ai-sandbox-rm
ai-sandbox-migrate
ai-sandbox-account
ai-sandbox-gc
ai-sandbox-extensions
HELPERS
}

# True when the sandbox container NAME is running. Without docker on PATH
# nothing can be running, so the answer is no rather than an error.
ai_sandbox_container_running() {
    command -v docker >/dev/null 2>&1 || return 1
    [ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

# rsync '--exclude=' arguments for copying the host's <path under $HOME> into
# a sandbox, one per line. Used by the one-time seed in create-ai-sandbox.sh
# and by 'ai-sandbox-account refresh', so a refresh can never drag in what the
# seed deliberately left out: caches, the bulk that now lives in shared/, host
# state a single-project sandbox has no use for, and the paths that are
# bind-mounted live instead of copied (the shared brain and conversations,
# ~/.claude/CLAUDE.md and this project's ~/.claude/projects entry).
ai_sandbox_seed_excludes() {
    cat <<'EX'
--exclude=*Cache*
--exclude=*cache*
--exclude=BrowserMetrics*
--exclude=Crashpad
--exclude=logs
--exclude=tmp
--exclude=extensions
--exclude=downloads
--exclude=claude-code
--exclude=CachedExtensionVSIXs
--exclude=CachedData
--exclude=WebStorage
--exclude=workspaceStorage
--exclude=Safe Browsing
--exclude=optimization_guide_model_store
--exclude=WasmTtsEngine
--exclude=OnDeviceHeadSuggestModel
--exclude=CertificateRevocation
EX
    case $1 in
        .gemini) cat <<'EX'
--exclude=brain
--exclude=conversations
--exclude=browser_recordings
--exclude=html_artifacts
--exclude=history
--exclude=History*
--exclude=IndexedDB
--exclude=Service Worker
--exclude=GEMINI.md
EX
        ;;
        .claude) printf '%s\n' --exclude=CLAUDE.md --exclude=projects ;;
    esac
}

# '<path under $HOME on the host>|<path under the sandbox directory>'.
# Everything here is identity-bearing -- OAuth tokens, account records, the
# Electron profiles that hold a logged-in session -- so it is seeded from the
# host exactly once and never overwritten afterwards. That is what lets one
# project hold a different Claude, Codex or Gemini account from another.
ai_sandbox_seed_paths() {
    cat <<'SEED'
.gemini|.gemini
.antigravity|.antigravity
.claude|.claude
.codex|.codex
.config/Antigravity|antigravity-data
.config/Antigravity IDE|antigravity-ide-data
.config/Claude|claude-data
SEED
}
