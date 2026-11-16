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
assert_eq "no host-logins message without the option" "$(grep -c 'I1' "$tmp/out")" 0
create "$a" >/dev/null
assert_eq "a second create keeps 0" "$(mode "$da")" 0

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

# the option's help text, and no --no-host-logins (D3)
assert_contains "--help describes the option" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)" '--host-logins'
assert_contains "--help names the way back" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)" 'ai-sandbox-account reset'
assert_eq "--no-host-logins does not exist: exit 2" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --no-host-logins "$a" >/dev/null 2>&1; echo $?)" 2

rm -rf "$tmp"
finish
