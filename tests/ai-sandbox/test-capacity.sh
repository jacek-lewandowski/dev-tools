#!/usr/bin/env bash
# Starting a sandbox is refused when its memory plus that of every running
# sandbox would exceed the host's budget (AI_SANDBOX_MEMORY_BUDGET_GB in
# $AI_SANDBOX_ROOT/config), whichever helper starts it. fake_home seeds 18 GB.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"
touch "$HOME/.bashrc"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
name="$(ai_sandbox_project_id "$proj")-agent"
helper="$AI_SANDBOX_ROOT/bin"
config="$AI_SANDBOX_ROOT/config"
# Four other sandboxes exist on this host. Whether they run is up to the stub;
# the stub reports 6 GiB for each unless DOCKER_STUB_MEMORY says otherwise.
for o in aaa-agent bbb-agent ccc-agent ddd-agent; do mkdir -p "$AI_SANDBOX_ROOT/$o"; done

assert_contains "the budget is seeded for the suite" "$(cat "$config")" 'AI_SANDBOX_MEMORY_BUDGET_GB=18'

# --- ai-sandbox: 12 + 6 = 18 fits the budget; 18 + 6 does not ---------------
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_eq       "ai-sandbox starts when the budget is exactly filled" "$rc" 0
assert_contains "the start reaches compose up"                       "$(stub_docker_log)" ' up -d'

: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_ne       "ai-sandbox refuses when the budget would be exceeded" "$rc" 0
assert_contains "the refusal names the sandbox and its memory"        "$out" "Cannot start $name (6 GB): 18 GB of the 18 GB memory budget is in use."
assert_contains "the refusal lists the first running sandbox"         "$out" 'aaa-agent (6 GB)'
assert_contains "the refusal lists the last running sandbox"          "$out" 'ccc-agent (6 GB)'
assert_contains "the list is comma-separated in docker ps order"      "$out" 'Running: aaa-agent (6 GB), bbb-agent (6 GB), ccc-agent (6 GB)'
assert_contains "the refusal says how to make room"                   "$out" 'ai-sandbox-stop'
assert_contains "the refusal says where the budget lives"             "$out" "raise AI_SANDBOX_MEMORY_BUDGET_GB in $config"
TESTS_RUN=$((TESTS_RUN + 1))
case "$(stub_docker_log)" in
    *' up -d'*) _fail "a refused start does not reach compose up" "$(stub_docker_log)" ;;
    *)          _pass "a refused start does not reach compose up" ;;
esac

# A running container that is not a sandbox of this host does not count, nor
# does a sandbox that exists but is not running (ddd-agent is not in docker ps).
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nstranger-agent' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_eq       "unrelated and stopped containers are not counted" "$rc" 0
assert_contains "the sandbox starts beside them"                   "$(stub_docker_log)" ' up -d'

# --- memory read from Docker: bytes are rounded up to whole GB ---------------
# bbb-agent runs at 8 GiB, ccc-agent with no limit at all (0, counted 0 GB),
# aaa-agent one byte over 6 GiB: 7 + 8 + 0 = 15, and 15 + 6 > 18.
: > "$DOCKER_STUB_LOG"
mem=$'aaa-agent=6442450945\nbbb-agent=8589934592\nccc-agent=0'
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' DOCKER_STUB_MEMORY="$mem" \
      bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_ne       "a larger running sandbox counts its own size" "$rc" 0
assert_contains "bytes are summed as GB"                       "$out" "Cannot start $name (6 GB): 15 GB of the 18 GB memory budget is in use."
assert_contains "8 GiB is listed as 8 GB"                      "$out" 'bbb-agent (8 GB)'
assert_contains "a partial GB rounds up"                       "$out" 'aaa-agent (7 GB)'
assert_contains "no limit is listed as such"                   "$out" 'ccc-agent (no limit)'
TESTS_RUN=$((TESTS_RUN + 1))
case "$(stub_docker_log)" in
    *' up -d'*) _fail "the over-budget start does not reach compose up" "$(stub_docker_log)" ;;
    *)          _pass "the over-budget start does not reach compose up" ;;
esac
# The sandbox's own size comes from SANDBOX_MEMORY_GB in its .env: at 3 GB,
# 15 + 3 = 18 fits.
: > "$DOCKER_STUB_LOG"
printf 'SANDBOX_MEMORY_GB=3\n' >> "$AI_SANDBOX_ROOT/$name/.env"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' DOCKER_STUB_MEMORY="$mem" \
      bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_eq       "the sandbox's own .env size is what counts" "$rc" 0
assert_contains "a smaller sandbox fits beside them"         "$(stub_docker_log)" ' up -d'
# A hand-edited size that is not a whole number of GB counts as the default,
# with one warning naming the file, rather than breaking the arithmetic.
: > "$DOCKER_STUB_LOG"
sed -i '/^SANDBOX_MEMORY_GB=/d' "$AI_SANDBOX_ROOT/$name/.env"
printf 'SANDBOX_MEMORY_GB=abc\n' >> "$AI_SANDBOX_ROOT/$name/.env"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' DOCKER_STUB_MEMORY="$mem" \
      bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_ne       "an invalid SANDBOX_MEMORY_GB counts as 6 GB"     "$rc" 0
assert_contains "the invalid size is named with its file"         "$out" "SANDBOX_MEMORY_GB is 'abc' in $AI_SANDBOX_ROOT/$name/.env, not a whole number of GB; counting 6 GB."
assert_contains "and the refusal counts 6 GB"                     "$out" "Cannot start $name (6 GB): 15 GB of the 18 GB memory budget is in use."
TESTS_RUN=$((TESTS_RUN + 1))
case "$out" in
    *'arithmetic'*|*'syntax error'*) _fail "no arithmetic error on an invalid size" "$out" ;;
    *)                               _pass "no arithmetic error on an invalid size" ;;
esac
# A sandbox created before the key existed is what its compose file says: 6 GB.
: > "$DOCKER_STUB_LOG"
sed -i '/^SANDBOX_MEMORY_GB=/d' "$AI_SANDBOX_ROOT/$name/.env"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' DOCKER_STUB_MEMORY="$mem" \
      bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_ne       "a sandbox without SANDBOX_MEMORY_GB counts 6 GB" "$rc" 0
assert_contains "and the refusal says 6 GB"                       "$out" "Cannot start $name (6 GB)"

# --- ai-sandbox-restart -----------------------------------------------------
# The sandbox being restarted is running: it must not count against itself.
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS="$name"$'\naaa-agent\nbbb-agent' DOCKER_STUB_RUNNING=true \
      bash "$helper/ai-sandbox-restart" 2>&1); rc=$?
assert_eq       "restart does not count the sandbox itself" "$rc" 0
assert_contains "restart takes the sandbox down"            "$(stub_docker_log)" ' down'
assert_contains "restart brings the sandbox up"             "$(stub_docker_log)" ' up -d'

# A refused restart leaves the sandbox as it was: the check runs before 'down'.
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS="$name"$'\naaa-agent\nbbb-agent\nccc-agent' DOCKER_STUB_RUNNING=true \
      bash "$helper/ai-sandbox-restart" 2>&1); rc=$?
assert_ne       "restart refuses when the budget is full" "$rc" 0
assert_contains "restart's refusal lists the others"      "$out" 'Running: aaa-agent (6 GB), bbb-agent (6 GB), ccc-agent (6 GB)'
TESTS_RUN=$((TESTS_RUN + 1))
case "$(stub_docker_log)" in
    *' down'*) _fail "a refused restart never takes the sandbox down" "$(stub_docker_log)" ;;
    *)         _pass "a refused restart never takes the sandbox down" ;;
esac

# --- create-ai-sandbox.sh ---------------------------------------------------
# Refused before the image is built, so a full host costs no build time.
: > "$DOCKER_STUB_LOG"
out=$(DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' \
      bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none "$proj" 2>&1); rc=$?
assert_ne       "create refuses to start over the budget"  "$rc" 0
assert_contains "create's refusal names the running ones"  "$out" 'Running: aaa-agent (6 GB), bbb-agent (6 GB), ccc-agent (6 GB)'
TESTS_RUN=$((TESTS_RUN + 1))
case "$(stub_docker_log)" in
    *build*|*' up -d'*) _fail "a refused create neither builds nor starts" "$(stub_docker_log)" ;;
    *)                  _pass "a refused create neither builds nor starts" ;;
esac

# --no-start starts nothing, so a full host is no reason to refuse it.
out=$(DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' \
      bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" 2>&1); rc=$?
assert_eq "--no-start ignores the budget" "$rc" 0

# --- no budget configured: nothing starts, nothing is written ---------------
missing="AI_SANDBOX_MEMORY_BUDGET_GB is not set in $config"
howto="echo 'AI_SANDBOX_MEMORY_BUDGET_GB=18' >> $config"
sed -i '/^AI_SANDBOX_MEMORY_BUDGET_GB=/d' "$config"
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS='' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_ne       "ai-sandbox refuses without a budget"   "$rc" 0
assert_contains "ai-sandbox names the missing key"      "$out" "No memory budget is configured for this host: $missing"
assert_contains "ai-sandbox says what the value means"  "$out" 'Write the RAM, in GB, that all running sandboxes together may use, for example:'
assert_contains "ai-sandbox says what to write where"   "$out" "$howto"
TESTS_RUN=$((TESTS_RUN + 1))
case "$(stub_docker_log)" in
    *' up -d'*) _fail "no budget: ai-sandbox does not reach compose up" "$(stub_docker_log)" ;;
    *)          _pass "no budget: ai-sandbox does not reach compose up" ;;
esac
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS="$name" DOCKER_STUB_RUNNING=true bash "$helper/ai-sandbox-restart" 2>&1); rc=$?
assert_ne       "ai-sandbox-restart refuses without a budget" "$rc" 0
assert_contains "restart names the missing key"               "$out" "$missing"
TESTS_RUN=$((TESTS_RUN + 1))
case "$(stub_docker_log)" in
    *' down'*) _fail "no budget: restart never takes the sandbox down" "$(stub_docker_log)" ;;
    *)         _pass "no budget: restart never takes the sandbox down" ;;
esac
proj2="$tmp/work/q"; mkdir -p "$proj2"
dir2="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj2")-agent"
out=$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj2" 2>&1); rc=$?
assert_ne       "create refuses without a budget, --no-start included" "$rc" 0
assert_contains "create names the missing key"                        "$out" "$missing"
assert_contains "create says what to write where"                     "$out" "$howto"
assert_no_file  "a refused create writes no .env"                     "$dir2/.env"
assert_contains "a refused create leaves the config alone"            "$(cat "$config")" "DEV_TOOLS_DIR=$REPO_ROOT"

# A value that is not a whole number of GB is as good as none, and is quoted.
printf 'AI_SANDBOX_MEMORY_BUDGET_GB=abc\n' >> "$config"
out=$(cd "$proj" && DOCKER_STUB_PS='' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_ne       "an invalid budget refuses the start" "$rc" 0
assert_contains "the invalid value is quoted"         "$out" "AI_SANDBOX_MEMORY_BUDGET_GB is 'abc' in $config, not a whole number of GB."
printf 'AI_SANDBOX_MEMORY_BUDGET_GB=0\n' >> "$config"
out=$(cd "$proj" && DOCKER_STUB_PS='' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_ne       "zero is not a budget"                "$rc" 0
assert_contains "zero is quoted too"                  "$out" "is '0' in $config"
# The last line wins, so a corrected value appended afterwards takes effect.
printf 'AI_SANDBOX_MEMORY_BUDGET_GB=18\n' >> "$config"
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS='' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_eq       "an appended budget takes effect"     "$rc" 0
assert_contains "and the sandbox starts"              "$(stub_docker_log)" ' up -d'

rm -rf "$tmp"
finish
