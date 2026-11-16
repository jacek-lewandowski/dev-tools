#!/usr/bin/env bash
# Brain and conversations per sandbox (phase 7, T06, O7): the four Antigravity stores are bound from
# the sandbox's own directory, never from the host's; create and reset make them; rm's question names them.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
for d in antigravity/brain antigravity/conversations antigravity-ide/brain antigravity-ide/conversations; do
    mkdir -p "$HOME/.gemini/$d"; echo "HOST-$(echo "$d" | tr '/' '-')" > "$HOME/.gemini/$d/marker"
done
proj="$tmp/work/p"; mkdir -p "$proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 </dev/null
dir=$(ai_sandbox_dir_for "$proj")
compose=$(cat "$dir/docker-compose.yml")
pairs="antigravity-brain:.gemini/antigravity/brain antigravity-conversations:.gemini/antigravity/conversations antigravity-ide-brain:.gemini/antigravity-ide/brain antigravity-ide-conversations:.gemini/antigravity-ide/conversations"
for p in $pairs; do
    assert_contains "O7 binds ${p%%:*} from the sandbox directory" "$compose" "\"$dir/${p%%:*}:$HOME/${p#*:}\""
    assert_file "O7 create made ${p%%:*}" "$dir/${p%%:*}"
done
assert_eq "O7 binds nothing from the host's .gemini/antigravity" "$(grep -cF -- "- \"$HOME/.gemini/antigravity" "$dir/docker-compose.yml")" 0
assert_file "O7 create made the parent .gemini/antigravity" "$dir/.gemini/antigravity"
assert_file "O7 create made the parent .gemini/antigravity-ide" "$dir/.gemini/antigravity-ide"
assert_eq "O7 no host brain marker in the sandbox" "$(grep -rlF HOST-antigravity "$dir" 2>/dev/null | wc -l)" 0
assert_contains "O7 CLAUDE_PROJECT_DIR is bound as before" "$compose" "$HOME/.claude/projects/"

# reset keeps what the sandbox holds in them, and makes them when they are gone
for p in $pairs; do echo "INSIDE-${p%%:*}" > "$dir/${p%%:*}/note"; done
( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" reset --yes >"$tmp/reset.out" 2>&1 )
for p in $pairs; do assert_eq "O7 reset keeps a file of ${p%%:*}" "$(cat "$dir/${p%%:*}/note" 2>/dev/null)" "INSIDE-${p%%:*}"; done
rm -rf "$dir/.gemini/antigravity" "$dir/.gemini/antigravity-ide"; for p in $pairs; do rm -rf "$dir/${p%%:*}"; done
( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" reset --yes >"$tmp/reset.out" 2>&1 )
for p in $pairs; do assert_file "O7 reset makes ${p%%:*}" "$dir/${p%%:*}"; done
assert_file "O7 reset makes .gemini/antigravity" "$dir/.gemini/antigravity"
assert_file "O7 reset makes .gemini/antigravity-ide" "$dir/.gemini/antigravity-ide"

# ai-sandbox-rm's question names them
out=$(printf 'n\n' | ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-rm" 2>&1 )); r=$?
assert_eq "O7 rm answered n exits 1" "$r" 1
assert_contains "O7 rm's question names the brain" "$out" 'brain'
assert_contains "O7 and the conversations" "$out" 'conversations'
assert_file "O7 and removed nothing" "$dir/docker-compose.yml"

# D10: ai-sync is untouched since the base
assert_eq "D10 bin/ai/ai-sync is unchanged since 3468d50" "$(git -C "$REPO_ROOT" diff 3468d50 HEAD -- bin/ai/ai-sync | wc -l)" 0

rm -rf "$tmp"
finish
