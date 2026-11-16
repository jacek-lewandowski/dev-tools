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

# --- "knowledge" names the ai-knowledge repository; the Antigravity store is named apart
help=$(bash "$REPO_ROOT/bin/ai/ai-sync" --help 2>&1)
assert_contains "help names the Antigravity knowledge items" "$help" "Antigravity knowledge items"
assert_eq "help no longer says Knowledge Items" "$(printf '%s\n' "$help" | grep -c 'Knowledge Items')" 0

# --- once the knowledge repository owns GEMINI.md, ai-sync leaves it alone
echo '{}' > "$HOME/.gemini/config/mcp_config.json"   # back to a secret-free home
export RCLONE_STUB_INDEX="$tmp/index"
mkdir -p "$HOME/.ai-sandbox/knowledge"; echo 'REMOTE=x' > "$HOME/.ai-sandbox/knowledge/config"
rc=$(run push)
assert_eq "push still succeeds with knowledge configured" "$rc" 0
assert_eq "GEMINI.md not pushed when git owns it" "$(transfers | grep -c GEMINI.md)" 0
assert_contains "the skip is announced" "$(cat "$tmp/out")" "knowledge repository"
printf 'shared-brain/\nshared-brain/GEMINI.md\n' > "$RCLONE_STUB_INDEX"
rc=$(run pull)
assert_eq "pull still succeeds with knowledge configured" "$rc" 0
assert_eq "GEMINI.md not pulled when git owns it" "$(transfers | grep -c GEMINI.md)" 0
rm "$HOME/.ai-sandbox/knowledge/config"

# --- O15: the pull writes nothing through a link a sandbox placed below a directory it can write
# A remote holding a project's memory (a directory with a file), another file, and one brain entry each.
export HOME_KEEP="$HOME"
snapd() { ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; elif [ -f "$f" ]; then printf '%s %s\n' "$f" "$(sha256sum < "$f")"; else printf '%s\n' "$f"; fi; done ); }
export RCLONE_STUB_TREE="$tmp/remote-tree"
mkdir -p "$RCLONE_STUB_TREE/claude/projects/key/memory" "$RCLONE_STUB_TREE/brain-artifacts/ide/conv" "$RCLONE_STUB_TREE/brain-artifacts/agy/conv"
echo remote-mem > "$RCLONE_STUB_TREE/claude/projects/key/memory/MEMORY.md"; echo remote-top > "$RCLONE_STUB_TREE/claude/projects/key/top.md"
echo ide > "$RCLONE_STUB_TREE/brain-artifacts/ide/conv/note"; echo agy > "$RCLONE_STUB_TREE/brain-artifacts/agy/conv/note"
export RCLONE_STUB_INDEX="$tmp/index2"; printf 'claude/\nclaude/projects/\nbrain-artifacts/\nbrain-artifacts/ide/\nbrain-artifacts/agy/\n' > "$RCLONE_STUB_INDEX"
new_home() { export HOME="$tmp/h$1"; mkdir -p "$HOME"; trap_dir="$tmp/trap$1"; mkdir -p "$trap_dir/dir"; echo trap > "$trap_dir/file"; echo trap > "$trap_dir/dir/inner"; }
pulled() { rc=$(run pull); }

new_home 1; mkdir -p "$HOME/.claude/projects/key" "$HOME/.gemini/antigravity/brain"; echo local-only > "$HOME/.claude/projects/key/keep.md"
pulled
assert_eq "O15: pull succeeds" "$rc" 0
assert_eq "O15: the fixture's memory file arrives" "$(cat "$HOME/.claude/projects/key/memory/MEMORY.md" 2>/dev/null)" remote-mem
assert_eq "O15: the fixture's other file arrives" "$(cat "$HOME/.claude/projects/key/top.md" 2>/dev/null)" remote-top
assert_eq "O15: a destination file the fixture lacks is kept" "$(cat "$HOME/.claude/projects/key/keep.md")" local-only
assert_eq "O15: the ide brain entry arrives" "$(cat "$HOME/.gemini/antigravity-ide/brain/conv/note" 2>/dev/null)" ide
assert_eq "O15: the agy brain entry arrives" "$(cat "$HOME/.gemini/antigravity/brain/conv/note" 2>/dev/null)" agy
# dry run: every destination byte-identical
before=$(snapd "$HOME"); rc=$(run pull --dry-run); after=$(snapd "$HOME")
assert_eq "O15: --dry-run succeeds" "$rc" 0
assert_eq "O15: --dry-run changes no destination" "$after" "$before"
rm -rf "$HOME/.claude/projects/key/memory" "$HOME/.claude/projects/key/top.md" "$HOME/.gemini/antigravity/brain/conv"
rc=$(run pull --dry-run)
assert_eq "O15: --dry-run puts no fixture file in place" "$([ -e "$HOME/.claude/projects/key/memory" ] && echo yes || echo no)" no

# a link at a name the fixture holds as a directory, one it holds as a file, a brain entry
link_case() {   # <label> <path under HOME> <dir|file> <what to check after: path under HOME> <expected content or DIR>
    new_home "$1"
    mkdir -p "$HOME/.claude/projects/key/memory" "$HOME/.gemini/antigravity/brain"
    local full="$HOME/$2" target
    if [ "$3" = dir ]; then target="$trap_dir/dir"; else target="$trap_dir/file"; fi
    rm -rf "$full"; mkdir -p "$(dirname "$full")"; ln -s "$target" "$full"
    local t0; t0=$(snapd "$trap_dir")
    pulled
    assert_eq "O15 $1: pull exits 0" "$rc" 0
    assert_eq "O15 $1: the trap is unchanged" "$(snapd "$trap_dir")" "$t0"
    assert_eq "O15 $1: the link is replaced by the fixture's entry" "$([ ! -L "$HOME/$4" ] && cat "$HOME/$4" 2>/dev/null)" "$5"
}
link_case memory-dir .claude/projects/key/memory dir .claude/projects/key/memory/MEMORY.md remote-mem
link_case memory-file .claude/projects/key/memory/MEMORY.md file .claude/projects/key/memory/MEMORY.md remote-mem
link_case brain-entry .gemini/antigravity/brain/conv dir .gemini/antigravity/brain/conv/note agy

# a host whose ~/.claude is a link to a directory elsewhere (a dotfiles layout) still receives the files
new_home 9; mkdir -p "$tmp/dotfiles/claude"; ln -s "$tmp/dotfiles/claude" "$HOME/.claude"
pulled
assert_eq "O15 D27: pull exits 0 with ~/.claude a link" "$rc" 0
assert_eq "O15 D27: the fixture's file is below the linked directory" "$(cat "$tmp/dotfiles/claude/projects/key/memory/MEMORY.md" 2>/dev/null)" remote-mem
export HOME="$HOME_KEEP"; unset RCLONE_STUB_TREE

rm -rf "$tmp"
finish
