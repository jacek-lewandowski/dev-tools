#!/usr/bin/env bash
# Per-sandbox SDKMAN defaults, snapshotted from the host and then owned locally.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"

# A host SDKMAN: two java versions with 21 as the default, one gradle with no
# default set at all, and the machinery directories.
SD="$HOME/.sdkman"
mkdir -p "$SD/bin" "$SD/libexec" "$SD/src" "$SD/etc" "$SD/var" \
         "$SD/candidates/java/21.0.8-tem/bin" "$SD/candidates/java/17.0.16-tem/bin" \
         "$SD/candidates/gradle/9.6.1/bin"
echo 'init' > "$SD/bin/sdkman-init.sh"
echo 'sdkman_auto_answer=false' > "$SD/etc/config"
echo '5.20.0' > "$SD/var/version"
ln -s 21.0.8-tem "$SD/candidates/java/current"

bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
farm="$dir/sdkman"

# --- the farm --------------------------------------------------------------
assert_file "farm created"          "$farm/candidates/java"
assert_eq   "default snapshotted from the host" \
    "$(readlink "$farm/candidates/java/current")" '21.0.8-tem'
# 'current' must be a real, rewritable symlink -- that is the whole point.
TESTS_RUN=$((TESTS_RUN + 1))
if [ -L "$farm/candidates/java/current" ] && [ -w "$farm/candidates/java" ]; then
    _pass "the default is a writable symlink"
else _fail "the default is a writable symlink" "not a symlink, or the dir is read-only"; fi

# Every host version is reachable, via a link into the read-only host mount.
for v in 21.0.8-tem 17.0.16-tem; do
    assert_link "java $v links to the host mount" \
        "$farm/candidates/java/$v" "$HOME/.sdkman-host/candidates/java/$v"
done
# A candidate with no host default must not get an invented one.
TESTS_RUN=$((TESTS_RUN + 1))
if [ ! -L "$farm/candidates/gradle/current" ]; then _pass "no default invented for gradle"
else _fail "no default invented for gradle" "current -> $(readlink "$farm/candidates/gradle/current")"; fi

# Machinery is linked, not copied: no second copy of libexec per sandbox.
for part in bin libexec src; do
    assert_link "$part is linked to the host" "$farm/$part" "$HOME/.sdkman-host/$part"
done
# Writable state is real and seeded.
assert_eq "etc/config seeded" "$(cat "$farm/etc/config")" 'sdkman_auto_answer=false'
assert_eq "var seeded"        "$(cat "$farm/var/version")" '5.20.0'
assert_file "tmp is sandbox-local" "$farm/tmp"

# The sandbox dir must stay small -- the toolchains are not duplicated into it.
TESTS_RUN=$((TESTS_RUN + 1))
_kb=$(du -s --exclude=.git "$farm" | cut -f1)
if [ "$_kb" -lt 512 ]; then _pass "farm is a symlink tree, not a copy (${_kb}kB)"
else _fail "farm is a symlink tree, not a copy" "${_kb}kB is too big"; fi

# --- mounts ----------------------------------------------------------------
compose=$(cat "$dir/docker-compose.yml")
assert_contains "host sdkman mounted read-only" "$compose" \
    "\"$SD:$HOME/.sdkman-host:ro\""
assert_contains "farm mounted writable at ~/.sdkman" "$compose" \
    "\"$farm:$HOME/.sdkman\""
TESTS_RUN=$((TESTS_RUN + 1))
case "$compose" in
    *"$SD:$HOME/.sdkman:ro"*) _fail "the old read-only ~/.sdkman mount is gone" \
        "the host tree is still mounted straight onto ~/.sdkman" ;;
    *) _pass "the old read-only ~/.sdkman mount is gone" ;;
esac

# --- second run: the sandbox's own default survives, versions re-sync -------
ln -sfn 17.0.16-tem "$farm/candidates/java/current"     # as 'sdk default java 17' would
mkdir -p "$SD/candidates/java/25.0.3-tem"               # host installs a new JDK
rm -rf "$SD/candidates/java/21.0.8-tem"                 # and removes an old one
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out2" 2>&1 || true

assert_eq "the sandbox default is not reset by a re-run" \
    "$(readlink "$farm/candidates/java/current")" '17.0.16-tem'
assert_link "a newly installed host version appears" \
    "$farm/candidates/java/25.0.3-tem" "$HOME/.sdkman-host/candidates/java/25.0.3-tem"
assert_no_link "a removed host version is unlinked" "$farm/candidates/java/21.0.8-tem"

# --- a default the host has deleted ----------------------------------------
ln -sfn 25.0.3-tem "$farm/candidates/java/current"
rm -rf "$SD/candidates/java/25.0.3-tem"
ln -sfn 17.0.16-tem "$SD/candidates/java/current"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out3" 2>&1 || true
assert_eq "a dangling default is repointed, not left broken" \
    "$(readlink "$farm/candidates/java/current")" '17.0.16-tem'
assert_contains "and it says so" "$(cat "$tmp/out3")" "no longer installed on the host"

# --- a sandbox-installed version is never touched --------------------------
mkdir -p "$farm/candidates/java/99-local/bin"           # as 'sdk install' would
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out4" 2>&1 || true
assert_file "a sandbox-installed version survives" "$farm/candidates/java/99-local/bin"

finish
