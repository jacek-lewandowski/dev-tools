#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
a="$tmp/work/a"; b="$tmp/work/b"; mkdir -p "$a" "$b"
uid=$(id -u)
tag="ai-sandbox:base-u${uid}"

bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$a" >"$tmp/o1" 2>&1 || true
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$b" >"$tmp/o2" 2>&1 || true

ca="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$a")-agent/docker-compose.yml"
cb="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$b")-agent/docker-compose.yml"

assert_contains "project A uses the shared tag" "$(cat "$ca")" "image: \"$tag\""
assert_contains "project B uses the same tag"   "$(cat "$cb")" "image: \"$tag\""
case "$(cat "$ca")" in
    *"build:"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "compose has no build: block" "found one" ;;
    *)          TESTS_RUN=$((TESTS_RUN+1)); _pass "compose has no build: block" ;;
esac
assert_file    "shared build context" "$AI_SANDBOX_ROOT/image/build/Dockerfile"
assert_no_file "no per-project build" "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$a")-agent/build"

# Container home must match the host home, so paths line up on both sides.
assert_contains "USER_HOME build arg" "$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")" 'ARG USER_HOME'
assert_contains "container home matches the host home" "$(cat "$ca")" ":$HOME/tools:ro"

# The hash must be stable across runs, and change when any input changes.
h1=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev base)
h2=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev base)
assert_eq "build hash is stable" "$h1" "$h2"
assert_eq "build hash is a sha256" "$(printf '%s' "$h1" | wc -c | tr -d ' ')" '64'
h3=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1001 1000 dev /home/dev base)
if [ "$h1" = "$h3" ]; then TESTS_RUN=$((TESTS_RUN+1)); _fail "build hash covers build args" "unchanged"
else TESTS_RUN=$((TESTS_RUN+1)); _pass "build hash covers build args"; fi
echo '# poke' >> "$AI_SANDBOX_ROOT/image/build/Dockerfile"
h4=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev base)
if [ "$h1" = "$h4" ]; then TESTS_RUN=$((TESTS_RUN+1)); _fail "build hash covers file contents" "unchanged"
else TESTS_RUN=$((TESTS_RUN+1)); _pass "build hash covers file contents"; fi

# The docker variant is a separate tag, so the two never overwrite each other.
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start --with-docker "$a" >>"$tmp/o1" 2>&1 || true
assert_contains "docker variant tag" "$(cat "$ca")" "ai-sandbox:docker-u${uid}"
# A bare re-run keeps the docker tag: the sticky flag must be read from .env
# before the tag is derived, or the docker Dockerfile lands under the base tag.
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$a" >>"$tmp/o1" 2>&1 || true
assert_contains "docker tag survives a bare re-run" "$(cat "$ca")" "ai-sandbox:docker-u${uid}"

rm -rf "$tmp"
finish
