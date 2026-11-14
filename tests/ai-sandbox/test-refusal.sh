#!/usr/bin/env bash
# C-INSTALL: every host entry point of bin/ai/MANIFEST refuses, first thing, to run from a
# directory a sandbox mounts read-write (the project paths the stamps under ~/.ai-sandbox
# name), with exit 3 and the install command; it writes nothing before it refuses.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

t=$(mktemp -d)
stubs="$REPO_ROOT/tests/ai-sandbox/stub"
# A HOME holding one stamp that names the repository's parent, so the repository is a
# directory a sandbox can write; and a HOME with no stamp.
stamped="$t/stamped"; plain="$t/plain"
mkdir -p "$stamped/.ai-sandbox/x-agent" "$plain"
printf '%s\n' "$(dirname "$REPO_ROOT")" > "$stamped/.ai-sandbox/x-agent/project-path"
stamp_only() { (cd "$1/.ai-sandbox" && find . | LC_ALL=C sort | tr '\n' ' '); }
before=$(stamp_only "$stamped")
entries=$(awk '$1 == "entry" {print $2}' "$REPO_ROOT/bin/ai/MANIFEST")
assert_ne "the manifest has entry lines" "$entries" ""

# run <home> <entry path> [args]: the entry, run from the repository, as the host user
run() {
    local home=$1 prog=$2; shift 2
    (cd "$REPO_ROOT" && env -u AI_SANDBOX_ROOT -u SUDO_USER HOME="$home" PATH="$stubs:$PATH" \
        bash "$REPO_ROOT/$prog" "$@" </dev/null >"$t/out" 2>"$t/err"); echo $?
}

for e in $entries; do
    rc=$(run "$stamped" "$e")
    assert_eq "$e from a sandbox-writable tree: exit 3" "$rc" 3
    assert_contains "$e names the install command and the tree" "$(cat "$t/err")" \
        "ai-sandbox-install --from $REPO_ROOT"
    assert_eq "$e wrote nothing under ~/.ai-sandbox" "$(stamp_only "$stamped")" "$before"
done

# The same programs under a HOME without a stamp go on: not exit 3. Each with arguments
# that make it stop early. verify-ai-sandbox-on-host.sh has none (it runs create and
# migrates a host), so it is covered by the refusal half only.
early_args() {
    case $1 in
        bin/ai/create-ai-sandbox.sh|bin/ai/ai-knowledge|bin/ai/update-antigravity-ide.sh) echo --help ;;
        bin/ai/handover-ready) echo --clear ;;
        *) echo ;;
    esac
}
for e in $entries; do
    case $e in verify-ai-sandbox-on-host.sh|tests/ai-sandbox/run-tests.sh) continue ;; esac
    # shellcheck disable=SC2046
    rc=$(run "$plain" "$e" $(early_args "$e"))
    assert_ne "$e under a HOME without stamps does not refuse" "$rc" 3
done
# run-tests.sh runs every test file; a copy whose directory holds one trivial file stands in.
rm -rf "$t/rt"; mkdir -p "$t/rt/tests/ai-sandbox" "$t/rt/bin/ai"
cp "$REPO_ROOT/tests/ai-sandbox/run-tests.sh" "$t/rt/tests/ai-sandbox/"
cp "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh" "$t/rt/bin/ai/"
printf '#!/usr/bin/env bash\necho trivial\n' > "$t/rt/tests/ai-sandbox/test-x.sh"
rc=$(cd "$t/rt" && env -u AI_SANDBOX_ROOT HOME="$plain" bash tests/ai-sandbox/run-tests.sh >/dev/null 2>&1; echo $?)
assert_eq "run-tests.sh under a HOME without stamps runs" "$rc" 0
printf '%s\n' "$t" > "$stamped/.ai-sandbox/x-agent/project-path"
rc=$(cd "$t/rt" && env -u AI_SANDBOX_ROOT HOME="$stamped" bash tests/ai-sandbox/run-tests.sh >/dev/null 2>&1; echo $?)
assert_eq "the copy of run-tests.sh refuses where its tree is stamped" "$rc" 3
printf '%s\n' "$(dirname "$REPO_ROOT")" > "$stamped/.ai-sandbox/x-agent/project-path"

# A test file run directly refuses before fake_home replaces HOME.
out=$(cd "$REPO_ROOT" && env -u AI_SANDBOX_ROOT HOME="$stamped" bash "$REPO_ROOT/tests/ai-sandbox/test-gc.sh" 2>&1 >/dev/null; echo "rc=$?")
assert_contains "a test file refuses under the stamped HOME" "$out" "ai-sandbox-install --from $REPO_ROOT"
assert_contains "with exit 3" "$out" "rc=3"

# The image's context-statusline sits in the build context with no lib beside it: no refusal,
# whatever the stamps say.
mkdir -p "$t/ctx"; cp "$REPO_ROOT/bin/ai/context-statusline" "$t/ctx/"
printf '%s\n' "$t" > "$stamped/.ai-sandbox/x-agent/project-path"
rc=$(cd "$t/ctx" && env -u AI_SANDBOX_ROOT HOME="$stamped" bash "$t/ctx/context-statusline" </dev/null >/dev/null 2>&1; echo $?)
assert_ne "context-statusline with no lib beside it does not refuse" "$rc" 3

# update-antigravity-ide.sh through sudo: HOME is root's, SUDO_USER names the invoking user,
# whose home the user lookup gives. A stub getent on PATH serves the lookup.
printf '%s\n' "$(dirname "$REPO_ROOT")" > "$stamped/.ai-sandbox/x-agent/project-path"
mkdir -p "$t/getent-stub"
cat > "$t/getent-stub/getent" <<'EOF'
#!/bin/sh
# getent passwd <user>: the home is the stamped one
printf '%s:x:1000:1000::%s:/bin/bash\n' "$2" "$STUB_USER_HOME"
EOF
chmod +x "$t/getent-stub/getent"
sudo_run() {   # [env assignments...]
    (cd "$REPO_ROOT" && env -u AI_SANDBOX_ROOT -u SUDO_USER HOME="$plain" STUB_USER_HOME="$stamped" \
        PATH="$t/getent-stub:$PATH" "$@" bash "$REPO_ROOT/bin/ai/update-antigravity-ide.sh" --help \
        </dev/null >"$t/out" 2>"$t/err"); echo $?
}
assert_eq "update-antigravity-ide.sh through sudo reads the invoking user's stamps: exit 3" "$(sudo_run SUDO_USER=agent)" 3
assert_contains "and names the install command" "$(cat "$t/err")" "ai-sandbox-install --from $REPO_ROOT"
assert_ne "without SUDO_USER and without stamps it does not refuse" "$(sudo_run)" 3

rm -rf "$t"
finish
