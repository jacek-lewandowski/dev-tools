#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"

run() { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" "$@" >"$tmp/out" 2>&1 || true; }
envfile() { cat "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent/.env"; }

run --display=none --no-start --with-docker "$proj"
assert_contains "docker recorded" "$(envfile)" 'SANDBOX_WITH_DOCKER=1'

# The bug this fixes: a bare re-run used to silently turn Docker back off.
run --display=none --no-start "$proj"
assert_contains "docker is sticky" "$(envfile)" 'SANDBOX_WITH_DOCKER=1'

run --display=none --no-start --no-docker "$proj"
assert_contains "--no-docker turns it off" "$(envfile)" 'SANDBOX_WITH_DOCKER=0'
run --display=none --no-start "$proj"
assert_contains "off is sticky too" "$(envfile)" 'SANDBOX_WITH_DOCKER=0'

# The memory size is remembered the same way, and a bare re-run says so.
run --display=none --no-start --memory=8 "$proj"
assert_contains "memory recorded" "$(envfile)" 'SANDBOX_MEMORY_GB=8'
run --display=none --no-start "$proj"
assert_contains "memory is sticky"               "$(envfile)" 'SANDBOX_MEMORY_GB=8'
assert_contains "a bare re-run says what it kept" "$(cat "$tmp/out")" 'keeping 8 GB of memory (pass --memory=... to change it)'
run --display=none --no-start --memory=6 "$proj"
assert_contains "--memory=6 changes it" "$(envfile)" 'SANDBOX_MEMORY_GB=6'
for bad in 0 '' 6g; do
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start --memory="$bad" "$proj" \
        >"$tmp/bad" 2>&1 && rc=0 || rc=$?
    assert_eq       "--memory=$bad exits 2"      "$rc" '2'
    assert_contains "--memory=$bad is explained" "$(cat "$tmp/bad")" "Invalid --memory=$bad: a whole number of GB"
done

# Contradictory flags are a usage error, not last-one-wins.
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --with-docker --no-docker "$proj" \
    >"$tmp/both" 2>&1 && rc=0 || rc=$?
assert_eq       "both flags exit 2"    "$rc" '2'
assert_contains "both flags explained" "$(cat "$tmp/both")" 'not both'

help=$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)
assert_contains "help documents xpra in auto"   "$help" 'else xpra'
assert_contains "help documents --no-docker"    "$help" '--no-docker'
assert_contains "help says rebuild is shared"   "$help" 'shared by every project'
assert_contains "help lists ai-sandbox-account" "$help" 'ai-sandbox-account'
assert_contains "help lists ai-sandbox-gc"      "$help" 'ai-sandbox-gc'
assert_contains "help lists sandbox-doctor"     "$help" 'sandbox-doctor'
assert_contains "help explains the layout"      "$help" '~/.ai-sandbox'
assert_contains "help notes stickiness"         "$help" 'Remembered'
assert_contains "help documents --memory"       "$help" '--memory=GB'
assert_contains "help names the budget key"     "$help" 'AI_SANDBOX_MEMORY_BUDGET_GB'

# The Dockerfile must not append a subuid range unconditionally: useradd on
# Ubuntu 22.04 already allocates one, leaving a duplicate line in each file.
df="$AI_SANDBOX_ROOT/image/build/Dockerfile"
[ -f "$df" ] || df="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent/build/Dockerfile"
assert_contains "subuid append is guarded" "$(cat "$df")" 'grep -q "^${USER_NAME}:" /etc/subuid'

rm -rf "$tmp"
finish
