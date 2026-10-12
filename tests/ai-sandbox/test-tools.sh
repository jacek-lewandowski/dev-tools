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
assert_contains "nano is installed"                      "$df" 'nano'
assert_contains "net-tools is installed"                 "$df" 'net-tools'
assert_contains "comby's shared libraries are installed" "$df" 'libev4 libpcre3 libsqlite3-0'
assert_contains "comby is smoke-tested at build time"    "$df" 'comby -version'
assert_contains "agy is installed from the antigravity tarball" \
    "$df" 'mv /tmp/antigravity /usr/local/bin/agy'
# Managed settings: the only place Claude Code accepts classifier (autoMode)
# rules from inside a sandbox, and root-owned so the sandbox user cannot edit it.
assert_contains "managed settings are installed for Claude Code" "$df" \
    'COPY claude-managed-settings.json /etc/claude-code/managed-settings.json'
ms=$(cat "$build/claude-managed-settings.json")
assert_contains "agy -p is allowed by permission rule"  "$ms" '"Bash(agy -p *)"'
assert_contains "agy models is allowed by permission rule" "$ms" '"Bash(agy models)"'
assert_contains "and made read-only to the sandbox user" "$df" 'chmod 0644 /etc/claude-code/managed-settings.json'
assert_contains "autoMode inherits the defaults"        "$ms" '"$defaults"'
assert_contains "autoMode authorises agy"               "$ms" 'agy (Antigravity CLI, Gemini) is a user-approved model provider'
assert_contains "ai-delegate is allowed by permission rule" "$ms" '"Bash(ai-delegate *)"'
assert_contains "autoMode authorises ai-delegate"        "$ms" '`agy -p` or `ai-delegate` is authorized'
assert_eq "managed settings JSON parses" "$(python3 -m json.tool "$build/claude-managed-settings.json" >/dev/null 2>&1; echo $?)" '0'
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
assert_contains "notes mention agy"                 "$brain" '`agy`'
assert_contains "notes mention codex"               "$brain" '`codex`'
assert_contains "notes mention nano"                "$brain" '`nano`'
assert_contains "notes say how to call agy"         "$brain" 'agy -p "<prompt>" --model'
assert_contains "notes mention ai-delegate"         "$brain" 'ai-delegate <role> <task-file>'
assert_contains "notes say when to fall back"       "$brain" 'only when it exits 3 (agy not'
assert_contains "notes forbid a second-reviewer subagent" "$brain" 'Never spawn `second-reviewer` as a Claude subagent.'
assert_contains "notes say only the lead delegates"  "$brain" 'Only the lead runs `ai-delegate`; subagents never call it.'
assert_contains "notes give the delegate timeout"   "$brain" 'timeout of at least 600000 ms'
assert_contains "notes say how to run it in the background" "$brain" 'or run it in the background'
assert_contains "notes name the conversation id line" "$brain" '`ai-delegate: conversation_id=<id>`'
assert_contains "notes say how round 2 resumes"     "$brain" '`--conversation <id>` to continue round 1'
assert_contains "ai-delegate is installed in the image" "$df" 'COPY ai-delegate       /usr/local/bin/ai-delegate'
assert_file     "ai-delegate is a host helper"  "$AI_SANDBOX_ROOT/bin/ai-delegate"
assert_contains "notes mention net-tools"           "$brain" '`net-tools`'

# --- entrypoint merges read_url(*) into the sandbox's own agy settings -----
ep="$build/entrypoint.sh"
merge="$tmp/merge.py"
sed -n "/^python3 - .*antigravity-cli\/settings.json/,/^PYEOF/p" "$ep" | sed '1d;$d' > "$merge"
assert_contains "entrypoint carries the merge" "$(cat "$ep")" 'read_url(*)'
mh="$tmp/merge-home"; mkdir -p "$mh/.gemini/antigravity-cli"
sf="$mh/.gemini/antigravity-cli/settings.json"
printf '{"colorScheme":"x","permissions":{"allow":["a"],"deny":["d"]}}' > "$sf"; chmod 0640 "$sf"
python3 "$merge" "$sf"
assert_eq "rule merged, other keys kept" \
    "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["colorScheme"],d["permissions"]["allow"],d["permissions"]["deny"])' "$sf")" "x ['a', 'read_url(*)'] ['d']"
assert_eq "mode kept" "$(stat -c %a "$sf")" '640'
python3 "$merge" "$sf"
assert_eq "merge is idempotent" "$(grep -c 'read_url' "$sf")" '1'
printf '{"colorScheme":"x"}' > "$sf"; python3 "$merge" "$sf"
assert_contains "allow list created when absent" "$(cat "$sf")" 'read_url(*)'
printf 'not json' > "$sf"; python3 "$merge" "$sf" 2>/dev/null
assert_eq "unparsable file left alone" "$(cat "$sf")" 'not json'
rm -f "$sf"; python3 "$merge" "$sf" 2>/dev/null
assert_no_file "missing file is never created" "$sf"
assert_contains "failure cannot fail the start" "$(cat "$ep")" "|| true"

rm -rf "$tmp"
finish
