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
assert_contains "compose caps memory"        "$compose" 'mem_limit: "6g"'
assert_contains "compose forbids swap"       "$compose" 'memswap_limit: "6g"'
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
    "capped at 6g of RAM with no swap"

# The sandbox must lose to the host under contention and cannot exhaust its process table.
assert_contains "compose lowers CPU shares"   "$compose" 'cpu_shares: 256'
# blkio_weight is rejected or ignored on some hosts, so it must stay out.
TESTS_RUN=$((TESTS_RUN + 1))
case "$compose" in
    *blkio_weight*) _fail "compose has no blkio_weight" "blkio_weight is present" ;;
    *)              _pass "compose has no blkio_weight" ;;
esac
assert_contains "compose raises the OOM score" "$compose" 'oom_score_adj: 500'
assert_contains "compose limits processes"    "$compose" 'pids_limit: 4096'

# --- CPUs: half the GB of RAM, as a cpuset so nproc inside agrees ------------
host_cpus=$(nproc)
want=3; [ "$want" -le "$host_cpus" ] || want=$host_cpus
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
if [ "$host_cpus" -ge 6 ]; then
    assert_contains "a second sandbox gets the next idle cores" \
        "$(cat "$dir2/docker-compose.yml")" 'cpuset: "3,4,5"'
fi
# Re-running keeps the allocation; a stale or malformed one is replaced.
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out.re" 2>&1 || true
assert_contains "a re-run keeps the cpuset" "$(cat "$dir/docker-compose.yml")" "cpuset: \"$expect_first\""
sed -i 's/^SANDBOX_CPUSET=.*/SANDBOX_CPUSET=0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64/' "$dir/.env"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out.re2" 2>&1 || true
assert_contains "a set of the wrong size is re-allocated" "$(cat "$dir/docker-compose.yml")" "cpuset: \"$expect_first\""
rm -rf "$dir2"

# --- --memory=GB: the limit, the cores and the rules text follow the option --
assert_contains "the default size is remembered in .env" "$(cat "$dir/.env")" 'SANDBOX_MEMORY_GB=6'
mem_create() {   # <gb>: re-create proj with --memory=<gb>, reload compose
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start --memory="$1" "$proj" >"$tmp/out.m$1" 2>&1 || true
    compose=$(cat "$dir/docker-compose.yml")
}
mem_create 8
want8=4; [ "$want8" -le "$host_cpus" ] || want8=$host_cpus
expect8=$(seq -s, 0 $((want8 - 1)))
assert_contains "--memory=8 caps memory at 8g"        "$compose" 'mem_limit: "8g"'
assert_contains "--memory=8 forbids swap at 8g"       "$compose" 'memswap_limit: "8g"'
assert_contains "the set recorded for 6 is re-allocated to ceil(8/2) cores" "$compose" "cpuset: \"$expect8\""
assert_contains "--memory=8 is remembered in .env"    "$(cat "$dir/.env")" 'SANDBOX_MEMORY_GB=8'
assert_contains "the shared brain states the new cap" "$(cat "$HOME/.gemini/GEMINI.md")" \
    "capped at 8g of RAM with no swap and $want8 CPU core(s)"
mem_create 5
assert_contains "--memory=5 caps memory at 5g"        "$compose" 'mem_limit: "5g"'
assert_contains "--memory=5 gets ceil(5/2) cores"     "$compose" "cpuset: \"$expect_first\""
assert_contains "--memory=5 is remembered in .env"    "$(cat "$dir/.env")" 'SANDBOX_MEMORY_GB=5'
mem_create 1
assert_contains "--memory=1 caps memory at 1g"        "$compose" 'mem_limit: "1g"'
assert_contains "--memory=1 gets one core"            "$compose" 'cpuset: "0"'
assert_contains "--memory=1 is remembered in .env"    "$(cat "$dir/.env")" 'SANDBOX_MEMORY_GB=1'
assert_contains "the shared brain states one core"    "$(cat "$HOME/.gemini/GEMINI.md")" \
    "capped at 1g of RAM with no swap and 1 CPU core(s)"
# Back to the default for the sections below.
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start --memory=6 "$proj" >"$tmp/out.m6" 2>&1 || true

doctor="$AI_SANDBOX_ROOT/image/build/sandbox-doctor"
assert_file "sandbox-doctor generated" "$doctor"
assert_contains "doctor reports memory" "$(cat "$doctor")" 'status "memory"'
TESTS_RUN=$((TESTS_RUN + 1))
if bash -n "$doctor" 2>"$tmp/doctor.err"; then _pass "doctor is valid bash"
else _fail "doctor is valid bash" "$(cat "$tmp/doctor.err")"; fi

# --- timezone: the host's zone, by name (TZ); the entrypoint links /etc/localtime ---
# Every source is faked: a timedatectl stub on PATH, and HOST_ETC_DIR pointed at
# a directory standing in for the host's /etc (this test host may have none).
tzstubs="$tmp/tzstub"; mkdir -p "$tzstubs"
etc="$tmp/etc"; zi="$tmp/zoneinfo/Europe"; mkdir -p "$etc" "$zi"
printf 'TZif2 fake\n' > "$zi/Warsaw"
tz_create() {   # the stub's timedatectl script on stdin
    cat > "$tzstubs/timedatectl"; chmod +x "$tzstubs/timedatectl"
    PATH="$tzstubs:$PATH" HOST_ETC_DIR="$etc" bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" \
        --display=none --no-start "$proj" >"$tmp/out.tz" 2>&1 || true
    compose=$(cat "$dir/docker-compose.yml")
}
# 1. timedatectl names the zone; /etc/localtime is a symlink to a zoneinfo file.
ln -s "$zi/Warsaw" "$etc/localtime"
tz_create <<'STUB'
#!/bin/sh
echo Europe/Warsaw
STUB
assert_contains "TZ follows timedatectl"                    "$compose" '- TZ=Europe/Warsaw'
# A bind mount at /etc/localtime follows the image's symlink and lands on
# /usr/share/zoneinfo/Etc/UTC, so UTC by name shows the host's zone: no mount.
assert_eq       "no volume targets /etc/localtime or zoneinfo" "$(grep -cE '/etc/localtime|/usr/share/zoneinfo' "$dir/docker-compose.yml")" '0'
assert_contains "the shared brain states the zone"          "$(cat "$HOME/.gemini/GEMINI.md")" "host's timezone (TZ=Europe/Warsaw)"
assert_contains "the image installs tzdata"                 "$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")" ' tzdata'
# The "Ready" summary (with its Timezone line) is printed only after a build
# and start, which --no-start never reaches; the log line of the timezone step
# is what a --no-start run shows.
assert_contains "the log names the zone and the file"       "$(cat "$tmp/out.tz")" "Timezone: Europe/Warsaw (TZ), /etc/localtime and /etc/timezone set by the entrypoint"
assert_eq       "the zone is not remembered in .env"        "$(grep -c 'TZ=' "$dir/.env")" '0'
# 2. timedatectl fails (no systemd): /etc/timezone names the zone.
printf 'America/Lima\n' > "$etc/timezone"
tz_create <<'STUB'
#!/bin/sh
echo "Failed to connect to bus" >&2; exit 1
STUB
assert_contains "TZ falls back to /etc/timezone" "$compose" '- TZ=America/Lima'
# 3. timedatectl prints nothing and there is no /etc/timezone: the symlink's
#    target names the zone; a target with no file behind it means no mount.
rm "$etc/timezone" "$etc/localtime"; ln -s /usr/share/zoneinfo/Asia/Tokyo "$etc/localtime"
tz_create <<'STUB'
#!/bin/sh
echo
STUB
assert_contains "TZ falls back to the localtime symlink"   "$compose" '- TZ=Asia/Tokyo'
# 4. No source at all: UTC, with a warning, and still no mount.
rm "$etc/localtime"
tz_create <<'STUB'
#!/bin/sh
exit 1
STUB
assert_contains "no source means UTC"                       "$compose" '- TZ=UTC'
assert_contains "and a warning about the zone"              "$(cat "$tmp/out.tz")" 'Could not determine the host'"'"'s timezone'
assert_eq       "nothing is mounted at /etc/localtime"      "$(grep -c '/etc/localtime' "$dir/docker-compose.yml")" '0'

# 5. The entrypoint makes /etc/localtime and /etc/timezone follow TZ, against a
#    fake /etc and zoneinfo tree (it must never touch the real ones here).
ep="$AI_SANDBOX_ROOT/image/build/entrypoint.sh"
fz="$tmp/fake-zi"; fe="$tmp/fake-etc"; mkdir -p "$fz/Europe" "$fz/Etc" "$fe" "$tmp/epstub"
# Stub dbus-launch, and no plugin list: the other sections stay inert.
printf '#!/bin/sh\n' > "$tmp/epstub/dbus-launch"; chmod +x "$tmp/epstub/dbus-launch"
printf 'warsaw\n' > "$fz/Europe/Warsaw"; printf 'utc\n' > "$fz/Etc/UTC"
ln -s "$fz/Etc/UTC" "$fe/localtime"; echo Etc/UTC > "$fe/timezone"
run_ep() {   # TZ value
    TZ="$1" SANDBOX_ETC_DIR="$fe" SANDBOX_ZONEINFO_DIR="$fz" SANDBOX_RUNTIME_DIR="$tmp/ep-run" \
        CLAUDE_PLUGINS_LIST=/nonexistent CLAUDE_PLUGINS_LOG="$tmp/ep-plugins.log" \
        PATH="$tmp/epstub:$PATH" bash "$ep" true >"$tmp/ep.out" 2>&1
}
run_ep Europe/Warsaw
assert_eq       "entrypoint links /etc/localtime to the zone"  "$(readlink "$fe/localtime")" "$fz/Europe/Warsaw"
assert_eq       "entrypoint writes the zone to /etc/timezone"  "$(cat "$fe/timezone")" 'Europe/Warsaw'
assert_eq       "the zoneinfo files are left untouched"        "$(cat "$fz/Etc/UTC")" 'utc'
run_ep Nowhere/Land
assert_eq       "an unknown zone keeps the previous link"      "$(readlink "$fe/localtime")" "$fz/Europe/Warsaw"
assert_contains "and the entrypoint warns about it"            "$(cat "$tmp/ep.out")" 'Nowhere/Land'

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
