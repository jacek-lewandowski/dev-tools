#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"

run() { bash "$REPO_ROOT/bin/create-ai-sandbox.sh" "$@" >"$tmp/out" 2>&1 || true; }
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

# Contradictory flags are a usage error, not last-one-wins.
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --with-docker --no-docker "$proj" \
    >"$tmp/both" 2>&1 && rc=0 || rc=$?
assert_eq       "both flags exit 2"    "$rc" '2'
assert_contains "both flags explained" "$(cat "$tmp/both")" 'not both'

help=$(bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --help 2>&1)
assert_contains "help documents xpra in auto"   "$help" 'else xpra'
assert_contains "help documents --no-docker"    "$help" '--no-docker'
assert_contains "help says rebuild is shared"   "$help" 'shared by every project'
assert_contains "help lists ai-sandbox-account" "$help" 'ai-sandbox-account'
assert_contains "help lists ai-sandbox-gc"      "$help" 'ai-sandbox-gc'
assert_contains "help lists sandbox-doctor"     "$help" 'sandbox-doctor'
assert_contains "help explains the layout"      "$help" '~/.ai-sandbox'
assert_contains "help notes stickiness"         "$help" 'Remembered'

# The Dockerfile must not append a subuid range unconditionally: useradd on
# Ubuntu 22.04 already allocates one, leaving a duplicate line in each file.
df="$AI_SANDBOX_ROOT/image/build/Dockerfile"
[ -f "$df" ] || df="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent/build/Dockerfile"
assert_contains "subuid append is guarded" "$(cat "$df")" 'grep -q "^${USER_NAME}:" /etc/subuid'

rm -rf "$tmp"
finish
