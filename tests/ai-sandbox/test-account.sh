#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"
mkdir -p "$HOME/.claude" "$HOME/.codex"
echo 'host-token'   > "$HOME/.claude/.credentials.json"
echo '{"a":"host"}' > "$HOME/.claude.json"
echo 'host-codex'   > "$HOME/.codex/auth.json"

create() { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >>"$tmp/out" 2>&1 || true; }
create
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"

assert_file "seed marker written" "$dir/.seeded"
assert_eq   "claude creds seeded" "$(cat "$dir/.claude/.credentials.json")" 'host-token'
assert_eq   "codex creds seeded"  "$(cat "$dir/.codex/auth.json")"          'host-codex'

# Log in to a different account inside the sandbox, then re-run the script.
echo 'project-token' > "$dir/.claude/.credentials.json"
echo 'project-codex' > "$dir/.codex/auth.json"
echo '{"a":"proj"}'  > "$dir/.claude.json"
create
assert_eq "claude login survives re-run" "$(cat "$dir/.claude/.credentials.json")" 'project-token'
assert_eq "codex login survives re-run"  "$(cat "$dir/.codex/auth.json")"          'project-codex'
assert_eq "claude.json survives re-run"  "$(cat "$dir/.claude.json")"              '{"a":"proj"}'

# ...even after the host re-authenticates to a different account.
echo 'host-token-2' > "$HOME/.claude/.credentials.json"
create
assert_eq "host re-auth does not leak in" "$(cat "$dir/.claude/.credentials.json")" 'project-token'

assert_contains "compose mounts .codex" "$(cat "$dir/docker-compose.yml")" \
    "$dir/.codex:$HOME/.codex"
assert_contains "image installs the codex CLI" \
    "$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")" '@openai/codex'

acct() { ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" "$@" 2>&1 ); }
assert_contains "status names the sandbox" "$(acct status)" "$(ai_sandbox_project_id "$proj")"
assert_contains "status reports seeding"   "$(acct status)" 'seeded'

# What the seed leaves out, refresh must leave out too: live-mounted paths,
# caches, and the bulk that lives in shared/.
mkdir -p "$HOME/.claude/projects/-home-other" "$HOME/.claude/downloads" "$HOME/.gemini/antigravity/brain"
echo host-rules > "$HOME/.claude/CLAUDE.md"
echo other      > "$HOME/.claude/projects/-home-other/x.jsonl"
echo bulk       > "$HOME/.claude/downloads/bin"
echo brain      > "$HOME/.gemini/antigravity/brain/CLAUDE.md"
mkdir -p "$dir/.claude/projects/mine" "$dir/.claude/downloads"
echo mine > "$dir/.claude/projects/mine/keep"
acct refresh --yes >/dev/null
assert_no_file "refresh excludes CLAUDE.md"        "$dir/.claude/CLAUDE.md"
assert_no_file "refresh excludes other projects"   "$dir/.claude/projects/-home-other"
assert_no_file "refresh excludes shared downloads" "$dir/.claude/downloads/bin"
assert_no_file "refresh excludes the brain"        "$dir/.gemini/antigravity/brain"
assert_file    "refresh keeps the projects mount"  "$dir/.claude/projects/mine/keep"
assert_file    "refresh keeps the downloads mount" "$dir/.claude/downloads"
assert_eq   "refresh pulls the host token" "$(cat "$dir/.claude/.credentials.json")" 'host-token-2'
assert_file "refresh leaves a backup"      "$dir/.credentials-backup"
assert_eq   "backup holds the replaced login" \
            "$(cat "$dir/.credentials-backup/.claude/.credentials.json")" 'project-token'

acct reset --yes >/dev/null
assert_no_file "reset cleared claude creds" "$dir/.claude/.credentials.json"
assert_file    "reset kept the sandbox"     "$dir/docker-compose.yml"
# Bind sources must survive reset, or compose recreates them root-owned.
while IFS='|' read -r _ sb_rel; do
    [ -n "$sb_rel" ] && assert_file "reset kept bind source $sb_rel" "$dir/$sb_rel"
done < <(ai_sandbox_seed_paths)
# The nested ~/.claude/projects/<key> mount needs its parent to exist too, or
# Docker creates projects/ and projects/<key> root-owned on the next start and
# rm -rf of .claude fails ever after.
assert_file "reset kept .claude/projects for the nested mount" "$dir/.claude/projects"
create
assert_no_file "reset is not undone by a re-run" "$dir/.claude/.credentials.json"

rm -rf "$tmp"
finish
