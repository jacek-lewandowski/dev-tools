#!/usr/bin/env bash
# The tools agents kept "fixing" by hand: comby's shared libraries, pnpm/yarn
# shims, and SDKMAN's java in the non-interactive shells agents actually get.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"

# A host SDKMAN, so the SDKMAN tooling notes are generated.
SD="$HOME/.sdkman"
mkdir -p "$SD/bin" "$SD/etc" "$SD/candidates/java/21.0.8-tem/bin"
echo 'init' > "$SD/bin/sdkman-init.sh"
ln -s 21.0.8-tem "$SD/candidates/java/current"

bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
build="$AI_SANDBOX_ROOT/image/build"
df=$(cat "$build/Dockerfile")

# --- image -----------------------------------------------------------------
assert_contains "comby's shared libraries are installed" "$df" 'libev4 libpcre3 libsqlite3-0'
assert_contains "comby is smoke-tested at build time"    "$df" 'comby -version'
assert_contains "corepack shims are enabled"             "$df" 'corepack enable'
assert_contains "pnpm and yarn are pre-warmed"           "$df" 'corepack prepare pnpm@latest yarn@stable --activate'
assert_contains "corepack cache is shared, not root's"   "$df" 'COREPACK_HOME=/usr/local/share/corepack'
assert_contains "and handed to the sandbox user"         "$df" '"${COREPACK_HOME}"'
assert_contains "env file reaches non-interactive bash"  "$df" 'ENV BASH_ENV=/etc/ai-sandbox-env.sh'
assert_contains "env file reaches login shells"          "$df" 'ln -s /etc/ai-sandbox-env.sh /etc/profile.d/ai-sandbox.sh'
assert_contains "sdk wrapper is installed"               "$df" 'COPY sandbox-sdk      /usr/local/bin/sdk'
assert_file     "env file is in the build context"       "$build/sandbox-env.sh"
assert_file     "sdk wrapper is in the build context"    "$build/sandbox-sdk"
assert_contains "interactive shells use the same env file" \
    "$(cat "$build/sandbox-bashrc.sh")" '. /etc/ai-sandbox-env.sh'

# --- the env file, sourced for real ----------------------------------------
# Simulates the container: a farm at ~/.sdkman with java and gradle defaults.
ch="$tmp/container-home"
mkdir -p "$ch/.sdkman/candidates/java/17.0.16-tem/bin" \
         "$ch/.sdkman/candidates/gradle/9.6.1/bin" \
         "$ch/.sdkman/candidates/maven"            # installed, no default
ln -s 17.0.16-tem "$ch/.sdkman/candidates/java/current"
ln -s 9.6.1       "$ch/.sdkman/candidates/gradle/current"
env_out=$(HOME="$ch" PATH=/usr/bin:/bin bash -c '
    unset JAVA_HOME PYTHONPATH SDKMAN_DIR
    . "'"$build/sandbox-env.sh"'"
    p1=$PATH
    . "'"$build/sandbox-env.sh"'"      # a second time, as profile.d + .bashrc would
    echo "PATH=$PATH"
    echo "SAME=$([ "$p1" = "$PATH" ] && echo yes || echo no)"
    echo "JAVA_HOME=$JAVA_HOME"
    echo "SDKMAN_DIR=$SDKMAN_DIR"
    echo "PYTHONPATH=$PYTHONPATH"
    echo "CI=$CI"' 2>&1)
assert_contains "java's bin dir is on PATH"   "$env_out" "$ch/.sdkman/candidates/java/current/bin:"
assert_contains "gradle's bin dir is on PATH" "$env_out" "$ch/.sdkman/candidates/gradle/current/bin:"
assert_contains "sourcing twice adds nothing" "$env_out" 'SAME=yes'
assert_contains "JAVA_HOME points at the default" "$env_out" "JAVA_HOME=$ch/.sdkman/candidates/java/current"
assert_contains "SDKMAN_DIR is exported"      "$env_out" "SDKMAN_DIR=$ch/.sdkman"
assert_contains "PYTHONPATH falls back to HOME" "$env_out" "PYTHONPATH=$ch"
assert_contains "CI is set"                   "$env_out" 'CI=true'
TESTS_RUN=$((TESTS_RUN + 1))
case "$env_out" in
    *maven*) _fail "a candidate without a default is skipped" "$env_out" ;;
    *)       _pass "a candidate without a default is skipped" ;;
esac
# Without SDKMAN on the host nothing must break or be invented.
no_sdk=$(HOME="$tmp/empty-home" PATH=/usr/bin:/bin bash -c '
    unset JAVA_HOME SDKMAN_DIR; . "'"$build/sandbox-env.sh"'"; echo "rc=$? JAVA_HOME=${JAVA_HOME:-unset}"' 2>&1)
assert_eq "no SDKMAN: silent, JAVA_HOME left unset" "$no_sdk" 'rc=0 JAVA_HOME=unset'
# It is sourced by /etc/profile through dash, so it has to be POSIX.
if command -v dash >/dev/null 2>&1; then
    dash_out=$(HOME="$ch" dash -c 'unset SDKMAN_DIR; . "'"$build/sandbox-env.sh"'" && echo "JAVA_HOME=$JAVA_HOME"' 2>&1)
    assert_eq "POSIX sh can source it" "$dash_out" "JAVA_HOME=$ch/.sdkman/candidates/java/current"
fi

# --- the sdk wrapper -------------------------------------------------------
chmod +x "$build/sandbox-sdk"
mkdir -p "$ch/.sdkman/bin"
printf 'sdk() { echo "sdk function got: $*"; }\n' > "$ch/.sdkman/bin/sdkman-init.sh"
unset SDKMAN_DIR                                        # the host's must not leak in
assert_eq "sdk works from a non-interactive shell" \
    "$(HOME="$ch" bash -c '"'"$build/sandbox-sdk"'" default java 17.0.16-tem' 2>&1)" \
    'sdk function got: default java 17.0.16-tem'
use_out=$(HOME="$ch" "$build/sandbox-sdk" use java 17.0.16-tem 2>&1); use_rc=$?
assert_eq       "sdk use is refused: it cannot work here" "$use_rc" '1'
assert_contains "and points at sdk default"   "$use_out" 'sdk default java 17.0.16-tem'
assert_contains "sdk env install still works" \
    "$(HOME="$ch" "$build/sandbox-sdk" env install 2>&1)" 'sdk function got: env install'
none_out=$(HOME="$tmp/empty-home" "$build/sandbox-sdk" default java 17 2>&1); none_rc=$?
assert_eq       "no SDKMAN: sdk fails cleanly" "$none_rc" '1'
assert_contains "and says why"                 "$none_out" 'not available'

# --- what the agents are told ----------------------------------------------
brain=$(cat "$HOME/.gemini/GEMINI.md")
assert_contains "notes forbid apt-installing a JDK" "$brain" 'never apt-get install a JDK'
assert_contains "notes mention comby and ast-grep"  "$brain" '`comby`'
assert_contains "notes mention pnpm via corepack"   "$brain" 'corepack'

rm -rf "$tmp"
finish
