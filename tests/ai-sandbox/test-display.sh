#!/usr/bin/env bash
# Two sandboxes must never share an X display number: the second one cannot
# authenticate to a server started with the first one's cookie.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"

run()  { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$1" >"$tmp/out" 2>&1 || true; }
dir()  { printf '%s' "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$1")-agent"; }
num()  { sed -n 's/^SANDBOX_DISPLAY_NUM=//p' "$(dir "$1")/.env" | tail -n 1; }
# The historical formula: 80 slots, so collisions are easy to manufacture.
slot() { printf '%s' "$(( $(printf '%s' "$(ai_sandbox_project_id "$1")" | cksum | cut -d' ' -f1) % 80 ))"; }

a="$tmp/work/a"; mkdir -p "$a"
i=0
while b="$tmp/work/b$i"; [ "$(slot "$b")" != "$(slot "$a")" ]; do i=$((i + 1)); done
mkdir -p "$b"

run "$a"; run "$b"
assert_eq "first sandbox keeps the hash-derived number" "$(num "$a")" "$(( 100 + $(slot "$a") ))"
assert_ne "colliding sandbox gets a different number"   "$(num "$b")" "$(num "$a")"
assert_contains "start-display.sh uses the allocated number" \
    "$(cat "$(dir "$b")/start-display.sh")" "NUM=\"$(num "$b")\""

before=$(num "$b")
run "$b"
assert_eq "the number is sticky across re-runs" "$(num "$b")" "$before"

# A sandbox created before numbers were recorded still occupies its implicit slot.
sed -i '/^SANDBOX_DISPLAY_NUM=/d' "$(dir "$b")/.env"
rm -rf "$(dir "$a")"
run "$a"
assert_ne "a legacy sandbox's implicit number is avoided" "$(num "$a")" "$(( 100 + $(slot "$a") ))"

rm -rf "$tmp"
finish
