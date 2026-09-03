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
touch "$HOME/.bashrc"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 \
    || { echo "script failed:"; cat "$tmp/out"; }

for h in ai-sandbox ai-sandbox-stop ai-sandbox-restart ai-sandbox-attach ai-sandbox-rm; do
    assert_file "installed $h" "$AI_SANDBOX_ROOT/bin/$h"
done
assert_file "installed the library" "$AI_SANDBOX_ROOT/bin/ai-sandbox-lib.sh"
assert_file "recorded the source dir" "$AI_SANDBOX_ROOT/config"
assert_contains "config points at the repo" "$(cat "$AI_SANDBOX_ROOT/config")" \
                "DEV_TOOLS_DIR=$REPO_ROOT"

# The bashrc block must be the stable one-liner, not a pile of functions.
block=$(sed -n '/>>> dev-tools ai-sandbox helpers >>>/,/<<< dev-tools ai-sandbox helpers <<</p' "$HOME/.bashrc")
assert_contains "bashrc adds bin to PATH" "$block" '.ai-sandbox/bin'
# Match any function definition, not one remembered name: the point is that the
# block stays a stable PATH stub, whatever a future helper might be called.
case "$block" in
    *'() {'*) TESTS_RUN=$((TESTS_RUN+1)); _fail "bashrc defines no functions" "block still defines a function" ;;
    *)        TESTS_RUN=$((TESTS_RUN+1)); _pass "bashrc defines no functions" ;;
esac

# The helper must resolve the same project the script did.
id=$(ai_sandbox_project_id "$proj")
out=$( cd "$proj" && AI_SANDBOX_ROOT="$AI_SANDBOX_ROOT" \
       bash "$AI_SANDBOX_ROOT/bin/ai-sandbox" --print-context 2>&1 )
assert_contains "helper resolves the same sandbox" "$out" "${id}-agent"

# Re-running create refreshes stale installed copies.
echo '# stale' > "$AI_SANDBOX_ROOT/bin/ai-sandbox-stop"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >>"$tmp/out" 2>&1 || true
assert_contains "stale helper refreshed" "$(cat "$AI_SANDBOX_ROOT/bin/ai-sandbox-stop")" 'compose stop'

rm -rf "$tmp"
finish
