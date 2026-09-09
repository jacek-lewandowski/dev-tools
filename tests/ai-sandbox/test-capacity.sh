#!/usr/bin/env bash
# No more than AI_SANDBOX_MAX_RUNNING sandboxes run at once, whichever helper
# starts them. Three 6 GB sandboxes are what a host can carry.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"
touch "$HOME/.bashrc"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
name="$(ai_sandbox_project_id "$proj")-agent"
helper="$AI_SANDBOX_ROOT/bin"
# Three other sandboxes exist on this host. Whether they run is up to the stub.
for o in aaa-agent bbb-agent ccc-agent; do mkdir -p "$AI_SANDBOX_ROOT/$o"; done

assert_eq "the cap is three" "${AI_SANDBOX_MAX_RUNNING:-unset}" 3

# --- ai-sandbox -------------------------------------------------------------
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_ne       "ai-sandbox refuses a fourth sandbox"   "$rc" 0
assert_contains "the refusal names the running ones"    "$out" 'aaa-agent bbb-agent ccc-agent'
assert_contains "the refusal says how to make room"     "$out" 'ai-sandbox-stop'
TESTS_RUN=$((TESTS_RUN + 1))
case "$(stub_docker_log)" in
    *' up -d'*) _fail "a refused start does not reach compose up" "$(stub_docker_log)" ;;
    *)          _pass "a refused start does not reach compose up" ;;
esac

# A running container that is not a sandbox of this host does not count.
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nstranger-agent' bash "$helper/ai-sandbox" true 2>&1); rc=$?
assert_eq       "unrelated containers are not counted"  "$rc" 0
assert_contains "the third sandbox starts"              "$(stub_docker_log)" ' up -d'

# --- ai-sandbox-restart -----------------------------------------------------
# The sandbox being restarted is one of the three: it must not count against itself.
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS="$name"$'\naaa-agent\nbbb-agent' DOCKER_STUB_RUNNING=true \
      bash "$helper/ai-sandbox-restart" 2>&1); rc=$?
assert_eq       "restart does not count the sandbox itself" "$rc" 0
assert_contains "restart takes the sandbox down"            "$(stub_docker_log)" ' down'
assert_contains "restart brings the sandbox up"             "$(stub_docker_log)" ' up -d'

# A refused restart leaves the sandbox as it was: the check runs before 'down'.
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' bash "$helper/ai-sandbox-restart" 2>&1); rc=$?
assert_ne "restart refuses when the host is full" "$rc" 0
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
assert_ne       "create refuses to start a fourth sandbox" "$rc" 0
assert_contains "create's refusal names the running ones"  "$out" 'aaa-agent bbb-agent ccc-agent'
TESTS_RUN=$((TESTS_RUN + 1))
case "$(stub_docker_log)" in
    *build*|*' up -d'*) _fail "a refused create neither builds nor starts" "$(stub_docker_log)" ;;
    *)                  _pass "a refused create neither builds nor starts" ;;
esac

# --no-start starts nothing, so a full host is no reason to refuse it.
out=$(DOCKER_STUB_PS=$'aaa-agent\nbbb-agent\nccc-agent' \
      bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" 2>&1); rc=$?
assert_eq "--no-start ignores the cap" "$rc" 0

rm -rf "$tmp"
finish
