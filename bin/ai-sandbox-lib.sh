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

# The git toplevel when there is one, so running from a subdirectory is safe.
ai_sandbox_project_root() {
    local dir=${1:-$PWD}
    (
        cd "$dir" 2>/dev/null || exit 1
        if git rev-parse --show-toplevel >/dev/null 2>&1; then
            git rev-parse --show-toplevel
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

# Bulk, read-mostly data that is identical across projects, so every sandbox
# mounts one shared copy instead of carrying its own.
#
# Each row is three fields:
#   <subdirectory of shared/>|<path in the container>|<path in the sandbox dir>
#
# The second and third differ, and that difference is load-bearing. The
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
ide-cacheddata|.config/Antigravity IDE/CachedData|antigravity-ide-data/CachedData
cache|.cache|
npm|.npm|
SHARED
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
