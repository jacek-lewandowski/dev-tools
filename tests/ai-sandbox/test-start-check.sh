#!/usr/bin/env bash
# C-INSTALL: a sandbox whose compose file does not mount the installed revision's tools (one
# created before the install root existed) is not current: refused at start and restart with
# its re-create command, entered with a notice while running, and current once re-created.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
# after fake_home: the lib derives its paths from HOME when sourced
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
proj="$tmp/work/proj"; mkdir -p "$proj"
create() { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/create.out" 2>&1; }
create || { echo "create failed:"; cat "$tmp/create.out"; }
dir=$(ai_sandbox_dir_for "$proj"); name=$(basename "$dir")
compose="$dir/docker-compose.yml"
assert_contains "a sandbox created under the install mounts its tools" "$(cat "$compose")" "\"$AI_SANDBOX_ROOT/installed/current/tools:"
assert_eq "it is current" "$(ai_sandbox_stale_reason "$dir")" ""

# as the base's create wrote it: tools from the checkout
cp "$compose" "$tmp/compose.current"
sed -i "s|\"$AI_SANDBOX_ROOT/installed/current/tools:|\"/old/checkout/tools:|" "$compose"
assert_ne "an old compose file is not current" "$(ai_sandbox_stale_reason "$dir")" ""

: > "$DOCKER_STUB_LOG"
msg=$(cd "$proj" && DOCKER_STUB_RUNNING=false bash "$AI_SANDBOX_ROOT/bin/ai-sandbox" true 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox refuses to start it" "$r" 1
assert_contains "and names the re-create command" "$msg" "create-ai-sandbox.sh $proj"
assert_eq "no compose up" "$(grep -c ' up' "$DOCKER_STUB_LOG")" 0
: > "$DOCKER_STUB_LOG"
msg=$(cd "$proj" && DOCKER_STUB_PS="$name" DOCKER_STUB_RUNNING=false bash "$AI_SANDBOX_ROOT/bin/ai-sandbox-restart" 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox-restart refuses it" "$r" 1
assert_contains "and names the re-create command" "$msg" "create-ai-sandbox.sh $proj"
assert_eq "no compose up" "$(grep -c ' up' "$DOCKER_STUB_LOG")" 0
assert_eq "no compose down" "$(grep -c 'compose.*down' "$DOCKER_STUB_LOG")" 0

# a running one is entered, with the notice
: > "$DOCKER_STUB_LOG"
msg=$(cd "$proj" && DOCKER_STUB_RUNNING=true bash "$AI_SANDBOX_ROOT/bin/ai-sandbox" true 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox enters it while it runs" "$r" 0
assert_contains "and says to re-create it" "$msg" "create-ai-sandbox.sh $proj"
assert_contains "it goes through compose exec" "$(stub_docker_log)" "exec"

# re-created under an install: it starts
create || { echo "create failed:"; cat "$tmp/create.out"; }
assert_eq "after a create it is current" "$(ai_sandbox_stale_reason "$dir")" ""
: > "$DOCKER_STUB_LOG"
(cd "$proj" && DOCKER_STUB_IMAGES="$(sed -n 's/^    image: "\(.*\)"$/\1/p' "$compose")" DOCKER_STUB_RUNNING=false bash "$AI_SANDBOX_ROOT/bin/ai-sandbox" true >"$tmp/start.out" 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox starts it" "$r" 0
assert_contains "through compose up" "$(stub_docker_log)" " up"

# E5: a stopped sandbox whose image does not exist locally is refused before compose up
# (which would try a registry pull of a name no registry has), with the build command.
image=$(sed -n 's/^    image: "\(.*\)"$/\1/p' "$compose")
assert_contains "the compose file names the image" "$image" "ai-sandbox:"
: > "$DOCKER_STUB_LOG"
msg=$(cd "$proj" && DOCKER_STUB_RUNNING=false bash "$AI_SANDBOX_ROOT/bin/ai-sandbox" true 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox refuses a missing image" "$r" 1
assert_contains "says which image" "$msg" "$image"
assert_contains "and names the build command" "$msg" "create-ai-sandbox.sh $proj"
assert_eq "no compose up for a missing image" "$(grep -c ' up' "$DOCKER_STUB_LOG")" 0
: > "$DOCKER_STUB_LOG"
msg=$(cd "$proj" && DOCKER_STUB_PS="$name" DOCKER_STUB_RUNNING=false bash "$AI_SANDBOX_ROOT/bin/ai-sandbox-restart" 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox-restart refuses a missing image" "$r" 1
assert_contains "restart names the build command" "$msg" "create-ai-sandbox.sh $proj"
assert_eq "restart: no compose up" "$(grep -c ' up' "$DOCKER_STUB_LOG")" 0
assert_eq "restart: no compose down" "$(grep -c 'compose.*down' "$DOCKER_STUB_LOG")" 0
# a running container is entered whatever its image
msg=$(cd "$proj" && DOCKER_STUB_RUNNING=true bash "$AI_SANDBOX_ROOT/bin/ai-sandbox" true 2>&1) && r=0 || r=$?
assert_eq "a running sandbox is entered with its image gone" "$r" 0

rm -rf "$tmp"
finish
