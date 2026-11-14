#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

# Called directly, not via $(), so the exports inside fake_home actually
# reach this shell (and thus the create-ai-sandbox.sh child processes below).
# See the comment on fake_home in harness.sh.
fake_home >/dev/null
tmp="$FAKE_HOME_DIR"
proj="$tmp/work/proj"; mkdir -p "$proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 \
    || { echo "script failed:"; cat "$tmp/out"; }

# create installs nothing: the commands, their library and the PATH entry belong to the
# installed revision (ai-sandbox-install), and the config keeps only what the user wrote.
for h in ai-sandbox ai-sandbox-stop ai-sandbox-restart ai-sandbox-attach ai-sandbox-rm ai-sandbox-lib.sh; do
    assert_file "the installed revision holds $h" "$AI_SANDBOX_ROOT/bin/$h"
done
config_lines() { grep -c "^$1=" "$AI_SANDBOX_ROOT/config"; }
assert_eq "create leaves the budget line alone, once" "$(config_lines AI_SANDBOX_MEMORY_BUDGET_GB)" 1
assert_eq "create records no checkout location in the config" "$(config_lines DEV_TOOLS_DIR)" 0
assert_eq "the budget still reads as a whole number" \
    "$(AI_SANDBOX_ROOT="$AI_SANDBOX_ROOT" bash -c '. "$1/bin/ai/ai-sandbox-lib.sh" && ai_sandbox_memory_budget_gb' _ "$REPO_ROOT" 2>&1)" 18
# A hand-written config may lack its final newline: a create leaves it byte for byte.
printf 'AI_SANDBOX_MEMORY_BUDGET_GB=18' > "$AI_SANDBOX_ROOT/config"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out3" 2>&1 \
    || { echo "script failed:"; cat "$tmp/out3"; }
assert_eq "a config without a final newline is left as it is" "$(cat "$AI_SANDBOX_ROOT/config")" "AI_SANDBOX_MEMORY_BUDGET_GB=18"
assert_no_file "create wrote no ~/.bashrc" "$HOME/.bashrc"

# The helper must resolve the same project the script did.
id=$(ai_sandbox_project_id "$proj")
out=$( cd "$proj" && AI_SANDBOX_ROOT="$AI_SANDBOX_ROOT" \
       bash "$AI_SANDBOX_ROOT/bin/ai-sandbox" --print-context 2>&1 )
assert_contains "helper resolves the same sandbox" "$out" "${id}-agent"

# O22: ai-delegate and sandbox-knowledge-sync run in the image only, so neither is a host entry point.
entries=$(awk '$1 == "entry" {print $2}' "$REPO_ROOT/bin/ai/MANIFEST")
assert_eq "ai-delegate is not an entry point"            "$(printf '%s\n' "$entries" | grep -c 'ai-delegate')" 0
assert_eq "sandbox-knowledge-sync is not an entry point" "$(printf '%s\n' "$entries" | grep -c 'sandbox-knowledge-sync')" 0
assert_no_file "create puts no ai-delegate on the host" "$AI_SANDBOX_ROOT/bin/ai-delegate"
assert_eq "and says nothing about one" "$(grep -c 'ai-delegate' "$tmp/out")" 0

rm -rf "$tmp"
finish
