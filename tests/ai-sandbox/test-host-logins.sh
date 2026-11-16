#!/usr/bin/env bash
# The logins mode (phase 7, T02, O2): create-ai-sandbox.sh --host-logins and the managed
# SANDBOX_HOST_LOGINS key of .env with its three states. What the seed copies in each mode is
# tested where the seed is (T03); here only the record, the messages and the option.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
mkdir -p "$HOME/.claude"; echo host-token > "$HOME/.claude/.credentials.json"

create() {   # <project> [options]  -- output in $tmp/out
    local p=$1; shift
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$@" "$p" >"$tmp/out" 2>&1; echo $?
}
mode() { ai_sandbox_env_value "$1" SANDBOX_HOST_LOGINS; }
keyline() { grep -c '^SANDBOX_HOST_LOGINS=' "$1/.env"; }
dir_of() { echo "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$1")-agent"; }

a="$tmp/work/a"; mkdir -p "$a"; da=$(dir_of "$a")
assert_eq "create without options exits 0" "$(create "$a")" 0
assert_eq "a new sandbox records the inside mode" "$(mode "$da")" 0
assert_eq "once" "$(keyline "$da")" 1
assert_eq "no host-logins message without the option" "$(grep -c 'I1 does not hold' "$tmp/out")" 0
create "$a" >/dev/null
assert_eq "a second create keeps 0" "$(mode "$da")" 0
# L-2: a first create that stops after the seed (here: the build context cannot be written) has
# already recorded its mode, so the sandbox is not counted as an unrecorded legacy one afterwards
for want in 0 1; do
    e="$tmp/work/e$want"; mkdir -p "$e"; de=$(dir_of "$e")
    rm -rf "$AI_SANDBOX_ROOT/image/build/entrypoint.sh"; mkdir -p "$AI_SANDBOX_ROOT/image/build/entrypoint.sh"
    if [ "$want" = 1 ]; then opt=--host-logins; else opt=; fi
    rc=$(create "$e" $opt)
    assert_ne "L-2 the interrupted first create (mode $want) did stop" "$rc" 0
    assert_file "L-2 the seed ran (.seeded present, mode $want)" "$de/.seeded"
    assert_eq "L-2 the mode $want is recorded although the create stopped" "$(mode "$de")" "$want"
done
rm -rf "$AI_SANDBOX_ROOT/image/build/entrypoint.sh"
# R2-L1: the rerun of that interrupted first create (no --memory) is still a new sandbox: 2 GB
f="$tmp/work/f"; mkdir -p "$f"; df=$(dir_of "$f")
rm -rf "$AI_SANDBOX_ROOT/image/build/entrypoint.sh"; mkdir -p "$AI_SANDBOX_ROOT/image/build/entrypoint.sh"
assert_ne "R2-L1 the interrupted first create did stop" "$(create "$f")" 0
rm -rf "$AI_SANDBOX_ROOT/image/build/entrypoint.sh"
assert_eq "R2-L1 the rerun of an interrupted first create succeeds" "$(create "$f")" 0
assert_eq "R2-L1 the rerun keeps the new sandbox's 2 GB" "$(ai_sandbox_env_value "$df" SANDBOX_MEMORY_GB)" 2

b="$tmp/work/b"; mkdir -p "$b"; db=$(dir_of "$b")
assert_eq "create --host-logins exits 0" "$(create "$b" --host-logins)" 0
assert_eq "records the host mode" "$(mode "$db")" 1
assert_contains "says that I1 does not hold" "$(cat "$tmp/out")" 'I1 does not hold'
assert_contains "names the command that renews them" "$(cat "$tmp/out")" 'ai-sandbox-account refresh'
create "$b" >/dev/null
assert_eq "a re-create without the option keeps 1" "$(mode "$db")" 1
assert_contains "and says it again" "$(cat "$tmp/out")" 'I1 does not hold'
assert_eq "once, in .env" "$(keyline "$db")" 1

# --host-logins on a sandbox recorded 0: records 1, copies nothing, names refresh (D4)
create "$a" --host-logins >/dev/null; cat "$tmp/out" > "$tmp/out.a"
assert_eq "records 1 on a sandbox recorded 0" "$(mode "$da")" 1
assert_contains "names refresh" "$(cat "$tmp/out.a")" 'ai-sandbox-account refresh'
assert_no_file "copies nothing itself" "$da/.claude/.credentials.json"

# an unrecorded sandbox (.seeded present, no key): stays unrecorded, unless the option is given (D22)
c="$tmp/work/c"; mkdir -p "$c"; dc=$(dir_of "$c"); create "$c" >/dev/null
sed -i '/^SANDBOX_HOST_LOGINS=/d' "$dc/.env"
assert_eq "an unrecorded sandbox stays unrecorded" "$(create "$c"; keyline "$dc")" "0
0"
assert_eq "no key written" "$(mode "$dc")" ""
create "$c" --host-logins >/dev/null
assert_eq "--host-logins records 1 on an unrecorded sandbox" "$(mode "$dc")" 1
assert_contains "and names refresh" "$(cat "$tmp/out")" 'ai-sandbox-account refresh'
assert_no_file "and copies nothing itself" "$dc/.claude/.credentials.json"

# T04 (O4): a sandbox without a recorded mode is reported at every start; a recorded one is not
# by ai-sandbox or ai-sandbox-restart (create says it itself for 1, above).
d="$tmp/work/d"; mkdir -p "$d"; dd_=$(dir_of "$d"); create "$d" >/dev/null
ename=$(basename "$dd_"); eimage=$(sed -n 's/^    image: "\(.*\)"$/\1/p' "$dd_/docker-compose.yml")
start() {   # <project> <ai-sandbox|ai-sandbox-restart> <running true|false>; stderr+stdout in $tmp/start.out, prints the exit code
    (cd "$1" && DOCKER_STUB_IMAGES="$eimage" DOCKER_STUB_PS="$ename" DOCKER_STUB_RUNNING="$3" \
        bash "$AI_SANDBOX_ROOT/bin/$2" true >"$tmp/start.out" 2>&1; echo $?)
}
sed -i '/^SANDBOX_HOST_LOGINS=/d' "$dd_/.env"
for cmd in ai-sandbox ai-sandbox-restart; do
    for running in true false; do
        assert_eq "$cmd (running=$running) exits as before on an unrecorded sandbox" "$(start "$d" "$cmd" "$running")" 0
        assert_contains "$cmd (running=$running) says that I1 does not hold" "$(cat "$tmp/start.out")" 'I1 does not hold'
        assert_contains "$cmd (running=$running) names reset" "$(cat "$tmp/start.out")" 'ai-sandbox-account reset'
    done
done
assert_eq "the sandbox is still unrecorded" "$(mode "$dd_")" ""
create "$d" >/dev/null
assert_contains "create --no-start says it for an unrecorded sandbox" "$(cat "$tmp/out")" 'ai-sandbox-account reset'
assert_contains "and that I1 does not hold" "$(cat "$tmp/out")" 'I1 does not hold'
sed -i '/^SANDBOX_HOST_LOGINS=/d' "$dd_/.env"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none "$d" >"$tmp/out" 2>&1; r=$?
assert_eq "a full create of an unrecorded sandbox exits 0" "$r" 0
assert_contains "and says it after the summary" "$(sed -n '/^== Ready/,$p' "$tmp/out")" 'ai-sandbox-account reset'
for m in 0 1; do
    sed -i '/^SANDBOX_HOST_LOGINS=/d' "$dd_/.env"; echo "SANDBOX_HOST_LOGINS=$m" >> "$dd_/.env"
    for cmd in ai-sandbox ai-sandbox-restart; do
        start "$d" "$cmd" true >/dev/null
        assert_eq "$cmd prints no legacy line for a sandbox recorded $m" "$(grep -c 'I1 does not hold' "$tmp/start.out")" 0
    done
done

# the option's help text, and no --no-host-logins (D3)
assert_contains "--help describes the option" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)" '--host-logins'
assert_contains "--help names the way back" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)" 'ai-sandbox-account reset'
# T08 (O11): the usage and the generated environment block say what the phase made true
help=$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)
assert_contains "--help names the Codex default" "$help" 'Approve for me'
assert_contains "--help says the brain and conversations are the sandbox's own" "$help" "conversations are the sandbox's own"
assert_contains "--help says ai-sandbox-rm removes the brain" "$help" "remove this project's sandbox, its logins"
assert_eq "--help no longer says the Antigravity brain is mounted live" "$(printf '%s\n' "$help" | tr '\n' ' ' | grep -c 'conversations, and this project')" 0
assert_contains "--help: the licence only with --host-logins" "$help" 'the licence only with --host-logins'
block=$(cat "$HOME/.gemini/GEMINI.md" 2>/dev/null)
assert_contains "the generated environment block lists the project entry" "$block" "this project's Claude Code history and memory"
assert_eq "and no longer lists the Antigravity brain among the host paths" "$(printf '%s\n' "$block" | grep -c 'Antigravity brain and conversations')" 0
# the coupling register has the Codex default's row, and the markers it names exist
# PROJECT_MAP.md is outside the suite's roots: not in a git archive export of bin/ai, tools and tests
if [ -f "$REPO_ROOT/PROJECT_MAP.md" ]; then
    assert_contains "PROJECT_MAP.md's coupling register names the Codex default" "$(cat "$REPO_ROOT/PROJECT_MAP.md")" 'ai_sandbox_codex_default'
else
    echo "skip - PROJECT_MAP.md's coupling register names the Codex default (no PROJECT_MAP.md: an export of the suite's roots)"
fi
assert_eq "the two reads-outside markers of the default exist" "$(grep -n -A12 'reads-outside:' "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh" | grep -c -e 'ai_sandbox_codex_default()' -e 'ai_sandbox_seed_agy_trust()')" 2
assert_eq "--no-host-logins does not exist: exit 2" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --no-host-logins "$a" >/dev/null 2>&1; echo $?)" 2

rm -rf "$tmp"
finish
