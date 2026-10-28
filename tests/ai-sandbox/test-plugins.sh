#!/usr/bin/env bash
# The entrypoint installs the standard Claude Code plugins at every start, only
# the ones absent from `claude plugin list`, and never fails the start.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
build="$AI_SANDBOX_ROOT/image/build"
ids='superpowers frontend-design code-simplifier playwright claude-md-management'

# --- P2: the list is rendered once, and the doctor reports it ---------------
for id in $ids; do
    assert_eq "$id@claude-plugins-official appears once in the build context" \
        "$(grep -rhoF "$id@claude-plugins-official" "$build" | wc -l)" 1
done
assert_contains "the list is copied into the image" "$(cat "$build/Dockerfile")" 'COPY claude-plugins.list /usr/local/share/claude-plugins.list'
assert_contains "the doctor has a plugins line" "$(cat "$build/sandbox-doctor")" 'status "claude plugins"'

# --- P1: entrypoint against a stub claude ------------------------------------
stub="$tmp/stub"; mkdir -p "$stub"
cat > "$stub/claude" <<'STUB'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
[ -n "${STUB_FAIL:-}" ] && { echo boom >&2; exit 1; }
case "$*" in
    "plugin marketplace list --json") cat "$STUB_MARKETPLACES" ;;
    "plugin list --json")             cat "$STUB_PLUGINS" ;;
esac
exit 0
STUB
chmod +x "$stub/claude"
# The entrypoint's other sections must not touch the live sandbox: a runtime-dir
# override, a stub dbus-launch, and none of the optional services requested.
cat > "$stub/dbus-launch" <<'STUB'
#!/bin/bash
echo called >> "$STUB_DBUS_LOG"
echo "DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent';"
STUB
chmod +x "$stub/dbus-launch"
export STUB_DBUS_LOG="$tmp/dbus.log" SANDBOX_RUNTIME_DIR="$tmp/run"
unset SANDBOX_START_XWAYLAND SANDBOX_START_WM SANDBOX_WITH_DOCKER
real_env="/run/user/$(id -u)/sandbox-env.sh"
real_before=$(stat -c '%y %s' "$real_env" 2>&1)
count_dbus() { ps -eo comm= | grep -cx dbus-daemon; }
dbus_before=$(count_dbus)
export STUB_LOG="$tmp/stub.log" STUB_MARKETPLACES="$tmp/mk.json" STUB_PLUGINS="$tmp/pl.json"
export CLAUDE_PLUGINS_LIST="$build/claude-plugins.list" CLAUDE_PLUGINS_LOG="$tmp/plugins.log"

# Runs the entrypoint with `exec true`, then waits for the background section.
run_ep() {
    : > "$STUB_LOG"; : > "$CLAUDE_PLUGINS_LOG"
    PATH="$stub:$PATH" bash "$build/entrypoint.sh" true; echo $? > "$tmp/ep.rc"
    local i; for i in $(seq 1 100); do grep -qE '^(done|plugin list)' "$CLAUDE_PLUGINS_LOG" && break; sleep 0.1; done
    # STUB_FAIL runs never print "done"; give the background section a moment.
    [ -n "${STUB_FAIL:-}" ] && sleep 1
    cat "$tmp/ep.rc"
}
installs() { grep -c '^plugin install ' "$STUB_LOG"; }

echo '[]' > "$STUB_MARKETPLACES"; echo '[]' > "$STUB_PLUGINS"
assert_eq "empty list: the start succeeds" "$(run_ep)" 0
log=$(cat "$STUB_LOG")
assert_contains "the marketplace is added" "$log" 'plugin marketplace add anthropics/claude-plugins-official'
assert_contains "the marketplace is updated" "$log" 'plugin marketplace update claude-plugins-official'
assert_eq "all five plugins are installed" "$(installs)" 5
for id in $ids; do
    assert_contains "$id is installed with -y" "$log" "plugin install $id@claude-plugins-official -y"
done

echo '[{"name":"claude-plugins-official"}]' > "$STUB_MARKETPLACES"
echo '[{"id":"superpowers@claude-plugins-official","enabled":true},{"id":"playwright@claude-plugins-official","enabled":false}]' > "$STUB_PLUGINS"
assert_eq "partial list: the start succeeds" "$(run_ep)" 0
log=$(cat "$STUB_LOG")
assert_eq "only the three missing are installed" "$(installs)" 3
assert_eq "an installed plugin is not reinstalled" "$(grep -c 'install superpowers' "$STUB_LOG")" 0
assert_eq "a disabled plugin is left disabled" "$(grep -c 'install playwright' "$STUB_LOG")" 0
assert_eq "a known marketplace is not added again" "$(grep -c 'marketplace add' "$STUB_LOG")" 0
assert_contains "the marketplace is updated before installing" "$log" 'plugin marketplace update'

echo '[]' > "$STUB_PLUGINS"
printf '[%s]' "$(for id in $ids; do printf '{"id":"%s@claude-plugins-official","enabled":true},' "$id"; done | sed 's/,$//')" > "$STUB_PLUGINS"
assert_eq "everything present: the start succeeds" "$(run_ep)" 0
assert_eq "everything present: nothing is installed" "$(installs)" 0
assert_eq "everything present: no network update" "$(grep -c 'marketplace update' "$STUB_LOG")" 0

assert_eq "a stub that fails every command does not fail the start" "$(STUB_FAIL=1 run_ep)" 0
assert_eq "nothing is installed when the list cannot be read" "$(installs)" 0

# The start is not delayed: with everything present, entrypoint returns quickly.
t0=$(date +%s%N); PATH="$stub:$PATH" bash "$build/entrypoint.sh" true; t1=$(date +%s%N)
assert_eq "the entrypoint hands off in under a second" "$(( (t1 - t0) / 1000000 < 1000 ))" 1

assert_eq "the live sandbox-env.sh is untouched" "$(stat -c '%y %s' "$real_env" 2>&1)" "$real_before"
assert_eq "no dbus-daemon was started" "$(count_dbus)" "$dbus_before"
assert_contains "the stub dbus-launch was the one called" "$(cat "$STUB_DBUS_LOG")" called
assert_file "the snapshot went to the overridden runtime dir" "$tmp/run/sandbox-env.sh"

# --- the tool notes follow CLAUDE_PLUGINS (via claude-plugins.list) ---------
want=$(sed 's/@.*//' "$build/claude-plugins.list" | paste -sd, | sed 's/,/, /g')
line=$(grep -- '- Claude Code plugins ' "$HOME/.gemini/GEMINI.md")
got=$(printf '%s' "$line" | sed -e 's/^- Claude Code plugins //' -e 's/ are installed.*//' -e 's/`//g')
assert_eq "the notes line lists exactly the configured plugins" "$got" "$want"

rm -rf "$tmp"
finish
