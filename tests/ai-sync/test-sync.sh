#!/usr/bin/env bash
# ai-sync must be additive unless told otherwise, must never lose symlinked
# skills, must not upload credentials, and must not hide rclone failures.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../ai-sandbox/harness.sh"

tmp=$(mktemp -d)
export HOME="$tmp/home"
export RCLONE_STUB_LOG="$tmp/rclone.log"
export PATH="$REPO_ROOT/tests/ai-sync/stub:$PATH"
unset RCLONE_STUB_INDEX AI_SYNC_ALLOW_SECRETS

# A home with one of everything the script syncs, plus the things it must skip.
mkdir -p "$HOME/.gemini/config/skills" "$HOME/.agents/skills/real" "$HOME/.claude/skills" \
         "$HOME/.claude/plugins/cache" "$HOME/.claude/todos" "$HOME/.claude/projects/p/memory"
echo rules > "$HOME/.gemini/GEMINI.md"
echo '{}'  > "$HOME/.gemini/config/mcp_config.json"
echo '{}'  > "$HOME/.claude/settings.json"
echo '{}'  > "$HOME/.claude/plugins/installed_plugins.json"
echo '{}'  > "$HOME/.claude/plugins/known_marketplaces.json"
echo x     > "$HOME/.claude/plugins/cache/big"
echo x     > "$HOME/.claude/todos/session.json"
echo mem   > "$HOME/.claude/projects/p/memory/MEMORY.md"

run() { : > "$RCLONE_STUB_LOG"; bash "$REPO_ROOT/bin/ai/ai-sync" "$@" >"$tmp/out" 2>&1; echo $?; }
log() { cat "$RCLONE_STUB_LOG"; }
transfers() { grep -E '^(copy|sync) ' "$RCLONE_STUB_LOG"; }

# --- push, additive by default
rc=$(run push)
assert_eq "push succeeds" "$rc" 0
assert_eq "no sync verb without --delete" "$(transfers | grep -c '^sync ')" 0
assert_eq "every transfer passes --links" "$(transfers | grep -vc -- '--links')" 0
assert_eq "todos are not synced" "$(log | grep -c todos)" 0
assert_eq "plugin caches are not synced" "$(log | grep -c 'plugins/cache')" 0
assert_contains "plugin manifests are synced" "$(log)" "installed_plugins.json"
assert_contains "memory filter excludes chat logs" "$(log)" "--filter + **/memory/** --filter - *"
assert_eq "no --backup-dir without --delete" "$(log | grep -c -- '--backup-dir')" 0

# --- push --delete mirrors directories into a remote trash, never the filtered copies
rc=$(run push -D)
assert_eq "push -D succeeds" "$rc" 0
assert_contains "directories are mirrored" "$(transfers)" "sync --links --backup-dir gdrive:AI_Sync/.trash/"
assert_eq "single files stay copies" "$(transfers | grep GEMINI.md | grep -c '^copy ')" 1
assert_eq "filtered subsets stay copies" "$(transfers | grep projects | grep -c '^copy ')" 1

# --- status previews without transferring
rc=$(run status)
assert_eq "status defaults to push" "$(grep -c Pushing "$tmp/out")" 1
assert_eq "status is a dry run everywhere" "$(transfers | grep -vc -- '--dry-run')" 0
export RCLONE_STUB_INDEX="$tmp/index"; printf 'shared-brain/\nshared-brain/GEMINI.md\n' > "$RCLONE_STUB_INDEX"
rc=$(run status pull)
assert_eq "status pull previews the pull direction" "$(grep -c Pulling "$tmp/out")" 1
assert_eq "status pull is a dry run" "$(transfers | grep -vc -- '--dry-run')" 0

# --- pull only touches what the remote has, and does not hide a missing remote
printf 'shared-brain/\nshared-brain/GEMINI.md\nskills/\nskills/claude-skills/\n' > "$RCLONE_STUB_INDEX"
rc=$(run pull)
assert_eq "pull succeeds" "$rc" 0
assert_eq "present components are pulled" "$(transfers | grep -c -e GEMINI.md -e claude-skills)" 2
assert_eq "absent components are not requested" "$(transfers | grep -c -e semantic_docs_db -e brain-artifacts)" 0
assert_contains "absent components are reported" "$(cat "$tmp/out")" "not on remote: semantic_docs_db"
assert_eq "pull is additive by default" "$(transfers | grep -c '^sync ')" 0
assert_link "CLAUDE.md links to the shared rules" "$HOME/.claude/CLAUDE.md" "$HOME/.gemini/GEMINI.md"
rc=$(run pull -D)
assert_contains "pull -D trashes locally" "$(transfers)" "sync --links --backup-dir $HOME/.ai-sync-trash/"
unset RCLONE_STUB_INDEX
rc=$(run pull)
assert_eq "an unlistable remote fails the pull" "$rc" 1
assert_eq "nothing is transferred from an unlistable remote" "$(transfers | wc -l)" 0

# --- credentials never leave the machine
echo '{"env":{"GITHUB_TOKEN":"ghp_abcdefghijklmnopqrstuvwxyz0123"}}' > "$HOME/.gemini/config/mcp_config.json"
rc=$(run push)
assert_eq "a token-like value aborts the push" "$rc" 1
assert_eq "nothing is uploaded after a hit" "$(transfers | wc -l)" 0
assert_eq "the value itself is not echoed" "$(grep -c ghp_abcdefghijklmnopqrstuvwxyz0123 "$tmp/out")" 0
assert_contains "the location is reported" "$(cat "$tmp/out")" "mcp_config.json"
rc=$(AI_SYNC_ALLOW_SECRETS=1 run push)
assert_eq "the override lets the push through" "$rc" 0

rm -rf "$tmp"
finish
