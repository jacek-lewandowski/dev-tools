#!/usr/bin/env bash
# What a re-creation does to a sandbox's container, and that the generated environment
# block tells agents so. The compose calls are read from the stub docker's log.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
export DOCKER_STUB_IMAGES="ai-sandbox:base-u$(id -u) ai-sandbox:base-gui-u$(id -u) ai-sandbox:docker-u$(id -u) ai-sandbox:docker-gui-u$(id -u)"
proj="$tmp/work/p"; mkdir -p "$proj"
touch "$HOME/.bashrc"
name="$(ai_sandbox_project_id "$proj")-agent"
helper="$AI_SANDBOX_ROOT/bin"

# --- the environment block says what survives -------------------------------
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || cat "$tmp/out"
block=$(tr '\n' ' ' < "$HOME/.gemini/GEMINI.md" | tr -s ' ')
[ -f "$AI_KNOWLEDGE_ROOT/sandbox-environment.md" ] && block=$(tr '\n' ' ' < "$AI_KNOWLEDGE_ROOT/sandbox-environment.md" | tr -s ' ')
want="- Only the project directory and the sandbox's own mounted state directories (~/.claude, ~/.cache, ~/.npm, ~/.codex, ~/.gemini, ~/.config/Claude, ~/.config/gcloud, ~/.config/Antigravity*, ~/knowledge) keep what you write. Files written anywhere else in the container can vanish at any start or re-creation: ai-sandbox-restart always replaces the container, and ai-sandbox or create-ai-sandbox.sh do when its image or configuration changed (another project's create can rebuild the shared image); until then they fill the host's disk. Write large or lasting output only under the project or those directories. The Gradle and Maven build caches are the exception: writes to them are discarded at every start."
assert_contains "block: the full re-creation bullet" "$block" "$want"

# --- a re-create of the existing sandbox ends in 'compose up -d' ------------
# Compose itself decides whether 'up' replaces the container (changed configuration or
# image); the script never passes --force-recreate and never calls 'down' on this path.
: > "$DOCKER_STUB_LOG"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none "$proj" >"$tmp/out2" 2>&1 || cat "$tmp/out2"
log=$(stub_docker_log)
assert_contains "re-create: compose up -d" "$log" " up -d"
case "$log" in
    *--force-recreate*|*" down"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "re-create: no forced recreate and no down" "$log" ;;
    *) TESTS_RUN=$((TESTS_RUN+1)); _pass "re-create: no forced recreate and no down" ;;
esac

# --- a plain start of the stopped sandbox also issues 'compose up -d' -------
: > "$DOCKER_STUB_LOG"
(cd "$proj" && bash "$helper/ai-sandbox" true >/dev/null 2>&1)
log=$(stub_docker_log)
assert_contains "ai-sandbox start: compose up -d, like create" "$log" " up -d"
case "$log" in
    *--force-recreate*|*" down"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "ai-sandbox start: no forced recreate and no down" "$log" ;;
    *) TESTS_RUN=$((TESTS_RUN+1)); _pass "ai-sandbox start: no forced recreate and no down" ;;
esac

# --- the helpers: stop keeps the container, restart and rm remove it --------
: > "$DOCKER_STUB_LOG"
(cd "$proj" && bash "$helper/ai-sandbox-stop" >/dev/null 2>&1)
log=$(stub_docker_log)
assert_contains "stop: compose stop" "$log" " stop"
case "$log" in
    *" down"*|*" rm"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "stop removes nothing" "$log" ;;
    *) TESTS_RUN=$((TESTS_RUN+1)); _pass "stop removes nothing" ;;
esac

: > "$DOCKER_STUB_LOG"
(cd "$proj" && bash "$helper/ai-sandbox-restart" >/dev/null 2>&1)
log=$(stub_docker_log)
assert_contains "restart: compose down removes the container" "$log" " down"
assert_contains "restart: then compose up -d" "$log" " up -d"

: > "$DOCKER_STUB_LOG"
(cd "$proj" && printf "y\n" | bash "$helper/ai-sandbox-rm" >/dev/null 2>&1)
assert_contains "rm: compose down -v" "$(stub_docker_log)" " down -v"

rm -rf "$tmp"
finish
