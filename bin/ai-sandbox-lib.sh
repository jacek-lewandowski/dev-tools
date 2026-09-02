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
