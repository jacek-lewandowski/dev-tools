#!/usr/bin/env bash
# The container's resource ceiling, and 1:1 window forwarding under xpra.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"

bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
compose=$(cat "$dir/docker-compose.yml")

# Docker imposes no memory limit unless asked, so these must be present.
assert_contains "compose caps memory"        "$compose" 'mem_limit: "4g"'
assert_contains "compose forbids swap"       "$compose" 'memswap_limit: "4g"'
# /dev/shm is charged to the container's cgroup: at the old 4gb it could reach
# the whole limit on its own.
assert_contains "shm is well under the cap"  "$compose" "shm_size: '1gb'"
TESTS_RUN=$((TESTS_RUN + 1))
case "$compose" in
    *"shm_size: '4gb'"*) _fail "the old unbounded shm size is gone" "shm_size is still 4gb" ;;
    *)                   _pass "the old unbounded shm size is gone" ;;
esac

# The agents inside need to know the ceiling exists, or they parallelise into it.
assert_contains "the shared brain states the cap" "$(cat "$HOME/.gemini/GEMINI.md")" \
    "capped at 4g of RAM with no swap"

# --- CPUs: half the GB of RAM, as a cpuset so nproc inside agrees ------------
host_cpus=$(nproc)
want=2; [ "$want" -le "$host_cpus" ] || want=$host_cpus
expect_first=$(seq -s, 0 $((want - 1)))
assert_contains "compose pins a cpuset"            "$compose" "cpuset: \"$expect_first\""
assert_contains "the set is remembered in .env"    "$(cat "$dir/.env")" "SANDBOX_CPUSET=$expect_first"
assert_contains "the shared brain states the CPUs" "$(cat "$HOME/.gemini/GEMINI.md")" \
    "and $want CPU core(s)"
assert_contains "doctor reports cpus" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'status "cpus"'
# A second sandbox must not stack onto the same cores while others are idle.
proj2="$tmp/work/q"; mkdir -p "$proj2"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj2" >"$tmp/out.q" 2>&1 || true
dir2="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj2")-agent"
if [ "$host_cpus" -ge 4 ]; then
    assert_contains "a second sandbox gets the next idle cores" \
        "$(cat "$dir2/docker-compose.yml")" 'cpuset: "2,3"'
fi
# Re-running keeps the allocation; a stale or malformed one is replaced.
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out.re" 2>&1 || true
assert_contains "a re-run keeps the cpuset" "$(cat "$dir/docker-compose.yml")" "cpuset: \"$expect_first\""
sed -i 's/^SANDBOX_CPUSET=.*/SANDBOX_CPUSET=0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64/' "$dir/.env"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out.re2" 2>&1 || true
assert_contains "a set of the wrong size is re-allocated" "$(cat "$dir/docker-compose.yml")" "cpuset: \"$expect_first\""
rm -rf "$dir2"

doctor="$AI_SANDBOX_ROOT/image/build/sandbox-doctor"
assert_file "sandbox-doctor generated" "$doctor"
assert_contains "doctor reports memory" "$(cat "$doctor")" 'status "memory"'
TESTS_RUN=$((TESTS_RUN + 1))
if bash -n "$doctor" 2>"$tmp/doctor.err"; then _pass "doctor is valid bash"
else _fail "doctor is valid bash" "$(cat "$tmp/doctor.err")"; fi

# --- xpra: forwarded windows must not be rescaled ---------------------------
# The real backend is not installed in a test environment; these stubs exist
# only to get past the require/xauth calls so the launcher is generated.
stubs="$tmp/xstub"; mkdir -p "$stubs"
for t in xpra Xvfb; do printf '#!/bin/sh\nexit 0\n' > "$stubs/$t"; done
printf '#!/bin/sh\nexit 0\n'                       > "$stubs/xauth"
printf '#!/bin/sh\necho 0123456789abcdef0123456789abcdef\n' > "$stubs/mcookie"
chmod +x "$stubs"/*
PATH="$stubs:$PATH" bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" \
    --display=xpra --no-start "$proj" >"$tmp/out.xpra" 2>&1 || true

# The two offending directives ship ACTIVE in Ubuntu's xpra:
#   /etc/xpra/conf.d/60_server.conf: start = /etc/X11/Xsession true
#   /etc/xpra/conf.d/40_client.conf: desktop-scaling = auto
# Neither can be cleared from the command line (start/start-child append to the
# config value), so they are overridden through a private config directory.
conf="$dir/xpra-conf/xpra.conf"
assert_file "private xpra config generated" "$conf"
xconf=$(cat "$conf")
assert_contains "Xsession is replaced by a no-op" "$xconf" 'start = /bin/true'
assert_contains "so is start-child"               "$xconf" 'start-child = /bin/true'
assert_contains "an instant-exit child cannot kill the server" "$xconf" \
    'exit-with-children = no'
# '1' is in xpra's TRUE_OPTIONS: exactly 1:1, and no parse warning ('off' warns).
assert_contains "scaling pinned 1:1"              "$xconf" 'desktop-scaling = 1'
assert_contains "dpi pinned"                      "$xconf" 'dpi = 96'

launcher="$dir/start-display.sh"
assert_file "xpra launcher generated" "$launcher"
launch=$(cat "$launcher")
assert_contains "the launcher points xpra at that config" "$launch" \
    'export XPRA_USER_CONF_DIRS='
# Silently inert on an xpra that does not know the variable, so it is checked.
assert_contains "and verifies xpra honoured it" "$launch" 'xpra showsetting start'
assert_contains "viewer disables desktop scaling" "$launch" '--desktop-scaling=1'
assert_contains "viewer pins its DPI"             "$launch" '--dpi=96'
assert_contains "toolkit scaling is cleared"      "$launch" 'unset GDK_SCALE'
TESTS_RUN=$((TESTS_RUN + 1))
case "$launch" in
    # This cancelled the wrong option and never had any effect.
    *'--start-child=""'*) _fail "the no-op --start-child flag is gone" \
        "the launcher still passes --start-child=\"\"" ;;
    *) _pass "the no-op --start-child flag is gone" ;;
esac
# An xpra that rejects a flag exits at once; no windows at all is the worse bug.
assert_contains "unsupported flags are probed"    "$launch" 'attach_help='
assert_contains "the viewer retries bare"         "$launch" 'retrying without it'
TESTS_RUN=$((TESTS_RUN + 1))
if bash -n "$launcher" 2>"$tmp/launch.err"; then _pass "launcher is valid bash"
else _fail "launcher is valid bash" "$(cat "$tmp/launch.err")"; fi

rm -rf "/tmp/.X11-unix/.ai-sandbox-$(ai_sandbox_project_id "$proj")-agent" 2>/dev/null

finish
