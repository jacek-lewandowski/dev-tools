#!/usr/bin/env bash
# Build-cache overlay volumes (docs/superpowers/specs/2026-10-02-ai-sandbox-build-caches-design.md).
# Each task's new assertions are added here as its own section.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
docker_stub() { "$REPO_ROOT/tests/ai-sandbox/stub/docker" "$@"; }

# =============================================================================
# Task 1: docker stub -- volume inspect, and real stop/start container state
# =============================================================================

# --- a seeded volume's options round-trip through 'volume inspect' ----------
opts='lowerdir=/home/u/.gradle/caches,upperdir=/sb/build-caches/gradle-caches/upper,workdir=/sb/build-caches/gradle-caches/work'
out=$(DOCKER_STUB_VOLUMES="proj-agent-gradle-caches=$opts" docker_stub volume inspect proj-agent-gradle-caches 2>/dev/null); rc=$?
assert_eq "seeded volume inspect succeeds" "$rc" 0
assert_contains "seeded volume's Options.o round-trips" "$out" "\"o\": \"$opts\""
assert_contains "seeded volume still types as overlay" "$out" '"type": "overlay"'
assert_contains "seeded volume carries compose labels for the caller to ignore" "$out" 'com.docker.compose.project'

# A second, differently-seeded volume is unaffected by the first.
other_opts='lowerdir=/home/u/.m2/repository,upperdir=/sb/build-caches/m2-repository/upper,workdir=/sb/build-caches/m2-repository/work'
out=$(DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$opts"$'\nproj-agent-m2-repository='"$other_opts" \
      docker_stub volume inspect proj-agent-m2-repository 2>/dev/null); rc=$?
assert_eq "a second seeded volume also round-trips" "$rc" 0
assert_contains "the second volume carries its own options" "$out" "\"o\": \"$other_opts\""

# --- an unseeded name reads as missing ---------------------------------------
out=$(DOCKER_STUB_VOLUMES="proj-agent-gradle-caches=$opts" docker_stub volume inspect unseeded-name 2>/dev/null); rc=$?
assert_ne "an unseeded name is refused" "$rc" 0
assert_eq "an unseeded name prints nothing on stdout" "$out" ""

out=$(docker_stub volume inspect proj-agent-gradle-caches 2>/dev/null); rc=$?
assert_ne "no DOCKER_STUB_VOLUMES at all: missing" "$rc" 0

# --- a stubbed 'compose down' then 'container inspect' reports not-running --
: > "$DOCKER_STUB_LOG"
cfile="$tmp/probe-compose.yml"; efile="$tmp/probe.env"
printf 'services:\n  x:\n    container_name: "probe-agent"\n' > "$cfile"; : > "$efile"

r=$(DOCKER_STUB_RUNNING=true docker_stub container inspect -f '{{.State.Running}}' probe-agent 2>/dev/null)
assert_eq "before any compose call, DOCKER_STUB_RUNNING is honoured" "$r" true

DOCKER_STUB_RUNNING=true docker_stub compose -f "$cfile" --env-file "$efile" down >/dev/null
r=$(DOCKER_STUB_RUNNING=true docker_stub container inspect -f '{{.State.Running}}' probe-agent 2>/dev/null)
assert_eq "a stubbed compose down makes the container report not-running" "$r" false

# An unrelated name is unaffected by another container's stopped state.
r=$(DOCKER_STUB_RUNNING=true docker_stub container inspect -f '{{.State.Running}}' other-agent 2>/dev/null)
assert_eq "an unrelated name still answers DOCKER_STUB_RUNNING" "$r" true

DOCKER_STUB_RUNNING=true docker_stub compose -f "$cfile" --env-file "$efile" up -d >/dev/null
r=$(DOCKER_STUB_RUNNING=true docker_stub container inspect -f '{{.State.Running}}' probe-agent 2>/dev/null)
assert_eq "a stubbed compose up clears the stopped state" "$r" true

# 'stop' and 'rm' record stopped the same way 'down' does; 'start' clears it.
DOCKER_STUB_RUNNING=true docker_stub compose -f "$cfile" --env-file "$efile" stop >/dev/null
r=$(docker_stub container inspect -f '{{.State.Running}}' probe-agent 2>/dev/null)
assert_eq "a stubbed compose stop also records not-running" "$r" false
DOCKER_STUB_RUNNING=true docker_stub compose -f "$cfile" --env-file "$efile" start >/dev/null
r=$(DOCKER_STUB_RUNNING=true docker_stub container inspect -f '{{.State.Running}}' probe-agent 2>/dev/null)
assert_eq "a stubbed compose start clears it again" "$r" true

# =============================================================================
# Task 2: lib -- pure cache functions
# =============================================================================

# --- the table has exactly the three rows and paths --------------------------
table=$(ai_sandbox_build_caches)
assert_eq "the table has exactly three rows" "$(printf '%s\n' "$table" | wc -l | tr -d ' ')" 3
assert_contains "gradle-caches row" "$table" 'gradle-caches|.gradle/caches'
assert_contains "gradle-wrapper-dists row" "$table" 'gradle-wrapper-dists|.gradle/wrapper/dists'
assert_contains "m2-repository row" "$table" 'm2-repository|.m2/repository'

# --- caches_volume / caches_opts format strings match the contract exactly --
assert_eq "caches_volume formats '<container>-<key>'" \
    "$(ai_sandbox_caches_volume proj-agent gradle-caches)" "proj-agent-gradle-caches"
assert_eq "caches_opts formats the overlay options exactly" \
    "$(ai_sandbox_caches_opts /sb gradle-caches /home/u/.gradle/caches)" \
    "lowerdir=/home/u/.gradle/caches,upperdir=/sb/build-caches/gradle-caches/upper,workdir=/sb/build-caches/gradle-caches/work"

# --- caches_enabled is true only with SANDBOX_BUILD_CACHES=1 in .env --------
sb="$tmp/sb-enabled"; mkdir -p "$sb"
printf 'SANDBOX_PROJECT_DIR=%s\n' "$tmp/work/p" > "$sb/.env"
ai_sandbox_caches_enabled "$sb"; assert_eq "no stamp: disabled" "$?" 1
printf 'SANDBOX_BUILD_CACHES=1\n' >> "$sb/.env"
ai_sandbox_caches_enabled "$sb"; assert_eq "SANDBOX_BUILD_CACHES=1: enabled" "$?" 0
printf 'SANDBOX_BUILD_CACHES=0\n' > "$sb/.env"
ai_sandbox_caches_enabled "$sb"; assert_eq "SANDBOX_BUILD_CACHES=0: disabled" "$?" 1

# --- caches_prepare creates the three lowers and every upper/work, idempotently
sb="$tmp/sb-prepare"; mkdir -p "$sb"
printf 'SANDBOX_BUILD_CACHES=1\n' > "$sb/.env"
ai_sandbox_caches_prepare "$sb"
assert_file "gradle-caches lower created under HOME" "$HOME/.gradle/caches"
assert_file "gradle-wrapper-dists lower created under HOME" "$HOME/.gradle/wrapper/dists"
assert_file "m2-repository lower created under HOME" "$HOME/.m2/repository"
assert_file "gradle-caches upper created" "$sb/build-caches/gradle-caches/upper"
assert_file "gradle-caches work created" "$sb/build-caches/gradle-caches/work"
assert_file "m2-repository upper created" "$sb/build-caches/m2-repository/upper"
assert_file "m2-repository work created" "$sb/build-caches/m2-repository/work"
# idempotent: a marker in an existing upper survives a second prepare
echo mark > "$sb/build-caches/gradle-caches/upper/marker"
ai_sandbox_caches_prepare "$sb"
assert_file "prepare never empties an existing upper" "$sb/build-caches/gradle-caches/upper/marker"

# --- a no-op on an unstamped sandbox: never creates build-caches/ -----------
sb="$tmp/sb-unstamped-prepare"; mkdir -p "$sb"
: > "$sb/.env"
ai_sandbox_caches_prepare "$sb"
assert_no_file "prepare is a no-op without the stamp" "$sb/build-caches"

# =============================================================================
# Task 3: lib -- check and repair (D2)
# =============================================================================

sb="$tmp/sb-check"; mkdir -p "$sb"
container="proj-agent"
printf 'SANDBOX_BUILD_CACHES=1\nSANDBOX_PROJECT_DIR=%s\n' "$tmp/work/p" > "$sb/.env"
printf 'services:\n  x:\n    container_name: "%s"\n' "$container" > "$sb/docker-compose.yml"

gc_lower="$HOME/.gradle/caches"; wd_lower="$HOME/.gradle/wrapper/dists"; m2_lower="$HOME/.m2/repository"
gc_opts=$(ai_sandbox_caches_opts "$sb" gradle-caches "$gc_lower")
wd_opts=$(ai_sandbox_caches_opts "$sb" gradle-wrapper-dists "$wd_lower")
m2_opts=$(ai_sandbox_caches_opts "$sb" m2-repository "$m2_lower")

# --- a matching stubbed volume: check passes, nothing mutating logged ------
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$gc_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
    ai_sandbox_caches_check "$sb" "$container" 2>"$tmp/check.err"; rc=$?
assert_eq "check passes when every volume matches" "$rc" 0
assert_eq "a matching check prints nothing on stderr" "$(cat "$tmp/check.err")" ""
mutating=$(grep -v '^volume inspect' "$DOCKER_STUB_LOG" || true)
assert_eq "a matching check issues no down/rm/up" "$mutating" ""

# --- a stubbed difference: check fails naming the volume and the repair ----
bad_opts="lowerdir=/somewhere/else,upperdir=$sb/build-caches/gradle-caches/upper,workdir=$sb/build-caches/gradle-caches/work"
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$bad_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
    ai_sandbox_caches_check "$sb" "$container" 2>"$tmp/check.err"; rc=$?
assert_ne "check fails on a differing volume" "$rc" 0
assert_contains "the message names the differing volume" "$(cat "$tmp/check.err")" "proj-agent-gradle-caches"
assert_contains "the message names ai-sandbox-stop" "$(cat "$tmp/check.err")" "ai-sandbox-stop"
assert_contains "the message names create-ai-sandbox.sh" "$(cat "$tmp/check.err")" "create-ai-sandbox.sh"

# --- repair: 'down' (no -v), then 'volume rm' of exactly the differing name -
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$bad_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
    ai_sandbox_caches_repair "$sb" "$container"
mutating=$(grep -v '^volume inspect' "$DOCKER_STUB_LOG" || true)
assert_eq "repair logs 'down' then 'volume rm' of exactly the differing volume, nothing else" "$mutating" \
"compose -f $sb/docker-compose.yml --env-file $sb/.env down
volume rm proj-agent-gradle-caches"

# --- on an unstamped sandbox both are no-ops, no docker calls at all -------
sb2="$tmp/sb-unstamped-check"; mkdir -p "$sb2"
: > "$sb2/.env"
: > "$DOCKER_STUB_LOG"
ai_sandbox_caches_check "$sb2" "$container"; assert_eq "check is a no-op without the stamp" "$?" 0
ai_sandbox_caches_repair "$sb2" "$container"; assert_eq "repair is a no-op without the stamp" "$?" 0
assert_eq "no docker calls logged for an unstamped sandbox" "$(cat "$DOCKER_STUB_LOG")" ""

# --- D2 compares type, device and o, not just o -----------------------------
# A differing 'type' (everything else matches) is a difference.
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$gc_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
DOCKER_STUB_VOLUME_TYPE="proj-agent-gradle-caches=btrfs" \
    ai_sandbox_caches_check "$sb" "$container" 2>"$tmp/check.err"; rc=$?
assert_ne "a differing type fails check" "$rc" 0
assert_contains "the message names the volume with the differing type" "$(cat "$tmp/check.err")" "proj-agent-gradle-caches"
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$gc_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
DOCKER_STUB_VOLUME_TYPE="proj-agent-gradle-caches=btrfs" \
    ai_sandbox_caches_repair "$sb" "$container"
mutating=$(grep -v '^volume inspect' "$DOCKER_STUB_LOG" || true)
assert_eq "repair removes exactly the volume with the differing type" "$mutating" \
"compose -f $sb/docker-compose.yml --env-file $sb/.env down
volume rm proj-agent-gradle-caches"

# A differing 'device' (everything else matches) is a difference.
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$gc_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
DOCKER_STUB_VOLUME_DEVICE="proj-agent-gradle-caches=none" \
    ai_sandbox_caches_check "$sb" "$container" 2>"$tmp/check.err"; rc=$?
assert_ne "a differing device fails check" "$rc" 0
assert_contains "the message names the volume with the differing device" "$(cat "$tmp/check.err")" "proj-agent-gradle-caches"
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$gc_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
DOCKER_STUB_VOLUME_DEVICE="proj-agent-gradle-caches=none" \
    ai_sandbox_caches_repair "$sb" "$container"
mutating=$(grep -v '^volume inspect' "$DOCKER_STUB_LOG" || true)
assert_eq "repair removes exactly the volume with the differing device" "$mutating" \
"compose -f $sb/docker-compose.yml --env-file $sb/.env down
volume rm proj-agent-gradle-caches"

# An existing but unparseable volume (Options: null, e.g. a plain local volume
# reusing the name) is a difference, not treated as missing.
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$gc_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
DOCKER_STUB_VOLUME_NULL_OPTIONS="proj-agent-gradle-caches" \
    ai_sandbox_caches_check "$sb" "$container" 2>"$tmp/check.err"; rc=$?
assert_ne "an existing unparseable volume fails check" "$rc" 0
assert_contains "the message names the unparseable volume" "$(cat "$tmp/check.err")" "proj-agent-gradle-caches"
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES=$'proj-agent-gradle-caches='"$gc_opts"$'\nproj-agent-gradle-wrapper-dists='"$wd_opts"$'\nproj-agent-m2-repository='"$m2_opts" \
DOCKER_STUB_VOLUME_NULL_OPTIONS="proj-agent-gradle-caches" \
    ai_sandbox_caches_repair "$sb" "$container"
mutating=$(grep -v '^volume inspect' "$DOCKER_STUB_LOG" || true)
assert_eq "repair removes exactly the unparseable volume" "$mutating" \
"compose -f $sb/docker-compose.yml --env-file $sb/.env down
volume rm proj-agent-gradle-caches"

# =============================================================================
# Task 4: lib -- reset (D4)
# =============================================================================

sb="$tmp/sb-reset"; mkdir -p "$sb"
printf 'SANDBOX_BUILD_CACHES=1\n' > "$sb/.env"
ai_sandbox_caches_prepare "$sb"
echo probe > "$sb/build-caches/gradle-caches/upper/probe"
ai_sandbox_caches_reset "$sb"; rc=$?
assert_eq "reset returns 0" "$rc" 0
assert_no_file "the probe file is gone after reset" "$sb/build-caches/gradle-caches/upper/probe"
assert_file "upper exists after reset" "$sb/build-caches/gradle-caches/upper"
assert_file "work exists after reset" "$sb/build-caches/gradle-caches/work"
assert_file "m2-repository upper is also recreated" "$sb/build-caches/m2-repository/upper"

# --- an undeletable leftover only warns; reset still returns 0 --------------
sb="$tmp/sb-reset-leftover"; mkdir -p "$sb"
printf 'SANDBOX_BUILD_CACHES=1\n' > "$sb/.env"
ai_sandbox_caches_prepare "$sb"
if [ "$(id -u)" != 0 ]; then
    mkdir -p "$sb/build-caches/gradle-caches/upper/locked/inner"
    echo stuck > "$sb/build-caches/gradle-caches/upper/locked/inner/file"
    chmod 000 "$sb/build-caches/gradle-caches/upper/locked"
    ai_sandbox_caches_reset "$sb" 2>"$tmp/reset.err"; rc=$?
    assert_eq "reset still returns 0 when a leftover cannot be deleted" "$rc" 0
    assert_contains "reset warns about the undeletable leftover" "$(cat "$tmp/reset.err")" "sudo rm -rf"
    assert_file "a fresh upper exists despite the leftover" "$sb/build-caches/gradle-caches/upper"
    # restore permissions so the final cleanup below can remove the tree
    chmod 700 "$sb"/build-caches/.trash/*/upper/locked 2>/dev/null || true
fi

# --- a no-op on an unstamped sandbox ----------------------------------------
sb="$tmp/sb-reset-unstamped"; mkdir -p "$sb"
: > "$sb/.env"
ai_sandbox_caches_reset "$sb"; rc=$?
assert_eq "reset on an unstamped sandbox returns 0" "$rc" 0
assert_no_file "reset creates no build-caches/ without the stamp" "$sb/build-caches"

# =============================================================================
# Task 5: create-ai-sandbox.sh -- I10 refusal and the D9 path check
# =============================================================================

i10proj="$tmp/work/i10"; mkdir -p "$i10proj"
i10dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$i10proj")-agent"

: > "$DOCKER_STUB_LOG"
out=$(DOCKER_STUB_RUNNING=true bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none "$i10proj" 2>&1); rc=$?
assert_ne "a running container is refused (full start)" "$rc" 0
assert_contains "the refusal names ai-sandbox-stop" "$out" "ai-sandbox-stop"
assert_no_file "no sandbox directory is written for a refused run" "$i10dir"

: > "$DOCKER_STUB_LOG"
out=$(DOCKER_STUB_RUNNING=true bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$i10proj" 2>&1); rc=$?
assert_ne "a running container is refused (--no-start)" "$rc" 0
assert_contains "the --no-start refusal also names ai-sandbox-stop" "$out" "ai-sandbox-stop"
assert_no_file "no sandbox directory is written for a refused --no-start run" "$i10dir"

# --- a ',' in a faked $HOME is refused before any directory is created ------
d9tmp=$(mktemp -d)
old_home=$HOME; old_root=$AI_SANDBOX_ROOT
export HOME="$d9tmp/ho,me"; mkdir -p "$HOME"
export AI_SANDBOX_ROOT="$HOME/.ai-sandbox"; mkdir -p "$AI_SANDBOX_ROOT"
d9proj="$d9tmp/proj"; mkdir -p "$d9proj"
: > "$DOCKER_STUB_LOG"
out=$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$d9proj" 2>&1); rc=$?
assert_ne "a ',' in \$HOME is refused" "$rc" 0
assert_contains "the D9 refusal names the comma" "$out" ","
assert_no_file "no sandbox directory created for the refused path" "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$d9proj")-agent"
export HOME="$old_home" AI_SANDBOX_ROOT="$old_root"
rm -rf "$d9tmp"

# =============================================================================
# Task 6: create-ai-sandbox.sh -- Dockerfile D6 and the .env stamp D7
# =============================================================================

t6proj="$tmp/work/t6"; mkdir -p "$t6proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t6proj" >"$tmp/t6.out" 2>&1 || cat "$tmp/t6.out"
t6dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t6proj")-agent"
dockerfile=$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")
assert_contains "Dockerfile creates \${USER_HOME}/.gradle" "$dockerfile" '${USER_HOME}/.gradle"'
assert_contains "Dockerfile creates \${USER_HOME}/.gradle/wrapper" "$dockerfile" '${USER_HOME}/.gradle/wrapper"'
assert_contains "Dockerfile creates \${USER_HOME}/.m2" "$dockerfile" '${USER_HOME}/.m2"'
assert_contains "a fresh sandbox's .env is stamped" "$(cat "$t6dir/.env")" "SANDBOX_BUILD_CACHES=1"

# =============================================================================
# Task 7: create-ai-sandbox.sh -- compose volumes
# =============================================================================

t7proj="$tmp/work/t7"; mkdir -p "$t7proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t7proj" >"$tmp/t7.out" 2>&1 || cat "$tmp/t7.out"
t7dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t7proj")-agent"
t7container=$(basename "$t7dir")
compose=$(cat "$t7dir/docker-compose.yml")

assert_contains "service mounts the gradle-caches volume" "$compose" \
    "- \"gradle-caches:$HOME/.gradle/caches\""
assert_contains "service mounts the gradle-wrapper-dists volume" "$compose" \
    "- \"gradle-wrapper-dists:$HOME/.gradle/wrapper/dists\""
assert_contains "service mounts the m2-repository volume" "$compose" \
    "- \"m2-repository:$HOME/.m2/repository\""

assert_contains "top-level volumes: carries the gradle-caches name" "$compose" \
    "name: \"$t7container-gradle-caches\""
assert_contains "top-level volumes: carries the gradle-wrapper-dists name" "$compose" \
    "name: \"$t7container-gradle-wrapper-dists\""
assert_contains "top-level volumes: carries the m2-repository name" "$compose" \
    "name: \"$t7container-m2-repository\""
assert_contains "gradle-caches driver_opts o string" "$compose" \
    "o: \"$(ai_sandbox_caches_opts "$t7dir" gradle-caches "$HOME/.gradle/caches")\""
assert_contains "gradle-wrapper-dists driver_opts o string" "$compose" \
    "o: \"$(ai_sandbox_caches_opts "$t7dir" gradle-wrapper-dists "$HOME/.gradle/wrapper/dists")\""
assert_contains "m2-repository driver_opts o string" "$compose" \
    "o: \"$(ai_sandbox_caches_opts "$t7dir" m2-repository "$HOME/.m2/repository")\""
assert_eq "exactly three build-cache volumes declared" \
    "$(printf '%s\n' "$compose" | grep -c '^    driver_opts:$')" 3

case "$compose" in
    *gradle.properties*|*"init.d"*|*settings.xml*|*settings-security.xml*|*"/jdks"*|*"/daemon"*)
        TESTS_RUN=$((TESTS_RUN+1)); _fail "nothing else under ~/.gradle or ~/.m2 is mounted" "found a forbidden entry" ;;
    *) TESTS_RUN=$((TESTS_RUN+1)); _pass "nothing else under ~/.gradle or ~/.m2 is mounted" ;;
esac

# =============================================================================
# Task 8: create-ai-sandbox.sh -- start-section wiring
# =============================================================================

t8proj="$tmp/work/t8"; mkdir -p "$t8proj"
t8dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t8proj")-agent"
t8container=$(basename "$t8dir")

: > "$DOCKER_STUB_LOG"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t8proj" >"$tmp/t8.out" 2>&1 || cat "$tmp/t8.out"
assert_file "--no-start creates gradle-caches upper" "$t8dir/build-caches/gradle-caches/upper"
assert_file "--no-start creates gradle-caches work" "$t8dir/build-caches/gradle-caches/work"
assert_file "--no-start creates gradle-wrapper-dists upper" "$t8dir/build-caches/gradle-wrapper-dists/upper"
assert_file "--no-start creates m2-repository upper" "$t8dir/build-caches/m2-repository/upper"
assert_eq "--no-start issues no volume query" "$(grep -c '^volume inspect' "$DOCKER_STUB_LOG")" 0

# An actual start: a stubbed differing volume triggers 'down' (no -v), then
# 'volume rm' of exactly that volume, then 'up'.
wd_opts=$(ai_sandbox_caches_opts "$t8dir" gradle-wrapper-dists "$HOME/.gradle/wrapper/dists")
m2_opts=$(ai_sandbox_caches_opts "$t8dir" m2-repository "$HOME/.m2/repository")
bad_opts="lowerdir=/somewhere/else,upperdir=$t8dir/build-caches/gradle-caches/upper,workdir=$t8dir/build-caches/gradle-caches/work"
echo probe > "$t8dir/build-caches/gradle-caches/upper/probe"
: > "$DOCKER_STUB_LOG"
DOCKER_STUB_VOLUMES="$t8container-gradle-caches=$bad_opts"$'\n'"$t8container-gradle-wrapper-dists=$wd_opts"$'\n'"$t8container-m2-repository=$m2_opts" \
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none "$t8proj" >"$tmp/t8b.out" 2>&1 || cat "$tmp/t8b.out"
assert_eq "a start with a differing volume logs down, volume rm, then up, contiguously and last" \
    "$(tail -3 "$DOCKER_STUB_LOG")" \
"compose -f $t8dir/docker-compose.yml --env-file $t8dir/.env down
volume rm $t8container-gradle-caches
compose -f $t8dir/docker-compose.yml --env-file $t8dir/.env up -d"
assert_eq "volume rm is logged exactly once, for exactly the differing volume" \
    "$(grep -c '^volume rm ' "$DOCKER_STUB_LOG")" 1
assert_no_file "the reset under the repair also emptied the probe" "$t8dir/build-caches/gradle-caches/upper/probe"

# =============================================================================
# Task 9: ai-sandbox and ai-sandbox-restart -- D5 wiring
# =============================================================================

t9proj="$tmp/work/t9"; mkdir -p "$t9proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t9proj" >"$tmp/t9.out" 2>&1 || cat "$tmp/t9.out"
t9dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t9proj")-agent"
t9container=$(basename "$t9dir")

gc_opts=$(ai_sandbox_caches_opts "$t9dir" gradle-caches "$HOME/.gradle/caches")
wd_opts=$(ai_sandbox_caches_opts "$t9dir" gradle-wrapper-dists "$HOME/.gradle/wrapper/dists")
m2_opts=$(ai_sandbox_caches_opts "$t9dir" m2-repository "$HOME/.m2/repository")
bad_opts="lowerdir=/somewhere/else,upperdir=$t9dir/build-caches/gradle-caches/upper,workdir=$t9dir/build-caches/gradle-caches/work"
matching_vols="$t9container-gradle-caches=$gc_opts"$'\n'"$t9container-gradle-wrapper-dists=$wd_opts"$'\n'"$t9container-m2-repository=$m2_opts"
diffing_vols="$t9container-gradle-caches=$bad_opts"$'\n'"$t9container-gradle-wrapper-dists=$wd_opts"$'\n'"$t9container-m2-repository=$m2_opts"

# --- a stubbed difference: both exit non-zero naming create-ai-sandbox.sh, --
# --- logging no down/up/volume rm -------------------------------------------
: > "$DOCKER_STUB_LOG"
out=$(cd "$t9proj" && DOCKER_STUB_VOLUMES="$diffing_vols" bash "$REPO_ROOT/bin/ai/ai-sandbox" true 2>&1); rc=$?
assert_ne "ai-sandbox refuses on a differing cache volume" "$rc" 0
assert_contains "the refusal names create-ai-sandbox.sh" "$out" "create-ai-sandbox.sh"
log=$(cat "$DOCKER_STUB_LOG")
TESTS_RUN=$((TESTS_RUN+1))
case "$log" in
    *' down'*|*' up -d'*|*'volume rm'*) _fail "a refused ai-sandbox logs no down/up/volume rm" "$log" ;;
    *) _pass "a refused ai-sandbox logs no down/up/volume rm" ;;
esac

: > "$DOCKER_STUB_LOG"
out=$(cd "$t9proj" && DOCKER_STUB_RUNNING=true DOCKER_STUB_VOLUMES="$diffing_vols" \
      bash "$REPO_ROOT/bin/ai/ai-sandbox-restart" 2>&1); rc=$?
assert_ne "ai-sandbox-restart refuses on a differing cache volume" "$rc" 0
assert_contains "the restart refusal names create-ai-sandbox.sh" "$out" "create-ai-sandbox.sh"
log=$(cat "$DOCKER_STUB_LOG")
TESTS_RUN=$((TESTS_RUN+1))
case "$log" in
    *' down'*|*' up -d'*|*'volume rm'*) _fail "a refused ai-sandbox-restart logs no down/up/volume rm" "$log" ;;
    *) _pass "a refused ai-sandbox-restart logs no down/up/volume rm" ;;
esac

# --- a stopped container's ai-sandbox start empties a probe in upper -------
echo probe > "$t9dir/build-caches/gradle-caches/upper/probe"
: > "$DOCKER_STUB_LOG"
out=$(cd "$t9proj" && DOCKER_STUB_VOLUMES="$matching_vols" bash "$REPO_ROOT/bin/ai/ai-sandbox" true 2>&1); rc=$?
assert_eq "a stopped ai-sandbox start succeeds" "$rc" 0
assert_no_file "a stopped ai-sandbox start empties the probe" "$t9dir/build-caches/gradle-caches/upper/probe"
assert_file "upper still exists after the reset" "$t9dir/build-caches/gradle-caches/upper"

# --- a running container's ai-sandbox entry leaves the probe alone ---------
echo probe > "$t9dir/build-caches/gradle-caches/upper/probe"
: > "$DOCKER_STUB_LOG"
out=$(cd "$t9proj" && DOCKER_STUB_RUNNING=true DOCKER_STUB_VOLUMES="$matching_vols" \
      bash "$REPO_ROOT/bin/ai/ai-sandbox" true 2>&1); rc=$?
assert_eq "entering a running sandbox succeeds" "$rc" 0
assert_file "entering a running sandbox leaves the probe" "$t9dir/build-caches/gradle-caches/upper/probe"
log=$(cat "$DOCKER_STUB_LOG")
TESTS_RUN=$((TESTS_RUN+1))
case "$log" in
    *'volume inspect'*) _fail "entering a running sandbox issues no volume query" "$log" ;;
    *) _pass "entering a running sandbox issues no volume query" ;;
esac

# --- ai-sandbox-restart empties the probe -----------------------------------
: > "$DOCKER_STUB_LOG"
out=$(cd "$t9proj" && DOCKER_STUB_RUNNING=true DOCKER_STUB_VOLUMES="$matching_vols" \
      bash "$REPO_ROOT/bin/ai/ai-sandbox-restart" 2>&1); rc=$?
assert_eq "ai-sandbox-restart succeeds" "$rc" 0
assert_no_file "ai-sandbox-restart empties the probe" "$t9dir/build-caches/gradle-caches/upper/probe"
assert_file "upper still exists after ai-sandbox-restart's reset" "$t9dir/build-caches/gradle-caches/upper"

# =============================================================================
# Review round 1: hold the lock across the whole check->(down->)reset->up
# sequence, re-checking "not running" first thing under it (Finding 1); mkdir
# -p the build-caches dir before opening the lock (Finding 3).
# =============================================================================

# --- create-ai-sandbox.sh: I10's check (the 1st 'container inspect' call)
# --- passes, but the container is found running by the re-check under the
# --- lock (the 2nd call) -- simulating a concurrent 'ai-sandbox' start that
# --- landed in between. Refused naming ai-sandbox-stop; no reset (the probe
# --- survives) and no 'down' logged -----------------------------------------
t10proj="$tmp/work/t10"; mkdir -p "$t10proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t10proj" >"$tmp/t10.out" 2>&1 || cat "$tmp/t10.out"
t10dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t10proj")-agent"
echo probe > "$t10dir/build-caches/gradle-caches/upper/probe"
: > "$DOCKER_STUB_LOG"; rm -f "$DOCKER_STUB_LOG.inspect_count"
out=$(DOCKER_STUB_RUNNING_FROM_CALL=2 bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none "$t10proj" 2>&1); rc=$?
assert_ne "create-ai-sandbox.sh refuses a container found running under the lock" "$rc" 0
assert_contains "the refusal names ai-sandbox-stop" "$out" "ai-sandbox-stop"
assert_file "no reset: the probe survives" "$t10dir/build-caches/gradle-caches/upper/probe"
log=$(cat "$DOCKER_STUB_LOG")
TESTS_RUN=$((TESTS_RUN+1))
case "$log" in
    *' down'*) _fail "no 'down' is logged against a container found running under the lock" "$log" ;;
    *) _pass "no 'down' is logged against a container found running under the lock" ;;
esac

# --- ai-sandbox: the outer check (1st call) passes, but the re-check under
# --- the lock (2nd call) finds it running -- entered with no check, reset or
# --- 'up', and the probe survives -------------------------------------------
t11proj="$tmp/work/t11"; mkdir -p "$t11proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t11proj" >"$tmp/t11.out" 2>&1 || cat "$tmp/t11.out"
t11dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t11proj")-agent"
echo probe > "$t11dir/build-caches/gradle-caches/upper/probe"
: > "$DOCKER_STUB_LOG"; rm -f "$DOCKER_STUB_LOG.inspect_count"
out=$(cd "$t11proj" && DOCKER_STUB_RUNNING_FROM_CALL=2 bash "$REPO_ROOT/bin/ai/ai-sandbox" true 2>&1); rc=$?
assert_eq "ai-sandbox succeeds when the lock's recheck finds it running" "$rc" 0
assert_file "no reset: the probe survives the race" "$t11dir/build-caches/gradle-caches/upper/probe"
log=$(cat "$DOCKER_STUB_LOG")
TESTS_RUN=$((TESTS_RUN+1))
case "$log" in
    *'volume inspect'*|*' up -d'*) _fail "no check or 'up' against a container found running under the lock" "$log" ;;
    *) _pass "no check or 'up' against a container found running under the lock" ;;
esac

# --- Finding 3: a stamped sandbox whose build-caches/ directory is missing
# --- (e.g. a hand cleanup) must not crash 'exec {FD}>.../build-caches/.lock'
# --- under 'set -e' -- the directory is made first, in all three scripts ---
t12proj="$tmp/work/t12"; mkdir -p "$t12proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t12proj" >"$tmp/t12.out" 2>&1 || cat "$tmp/t12.out"
t12dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t12proj")-agent"
rm -rf "$t12dir/build-caches"
: > "$DOCKER_STUB_LOG"
out=$(cd "$t12proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox" true 2>&1); rc=$?
assert_eq "ai-sandbox does not crash when build-caches/ is missing" "$rc" 0
assert_file "ai-sandbox recreates gradle-caches upper" "$t12dir/build-caches/gradle-caches/upper"

t13proj="$tmp/work/t13"; mkdir -p "$t13proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t13proj" >"$tmp/t13.out" 2>&1 || cat "$tmp/t13.out"
t13dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t13proj")-agent"
rm -rf "$t13dir/build-caches"
: > "$DOCKER_STUB_LOG"
out=$(cd "$t13proj" && DOCKER_STUB_RUNNING=true bash "$REPO_ROOT/bin/ai/ai-sandbox-restart" 2>&1); rc=$?
assert_eq "ai-sandbox-restart does not crash when build-caches/ is missing" "$rc" 0
assert_file "ai-sandbox-restart recreates gradle-caches upper" "$t13dir/build-caches/gradle-caches/upper"

t14proj="$tmp/work/t14"; mkdir -p "$t14proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t14proj" >"$tmp/t14.out" 2>&1 || cat "$tmp/t14.out"
t14dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t14proj")-agent"
rm -rf "$t14dir/build-caches"
: > "$DOCKER_STUB_LOG"
out=$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none "$t14proj" 2>&1); rc=$?
assert_eq "create-ai-sandbox.sh does not crash when build-caches/ is missing" "$rc" 0
assert_file "create-ai-sandbox.sh recreates gradle-caches upper" "$t14dir/build-caches/gradle-caches/upper"

# =============================================================================
# Review round 2: knowledge sync and start-display.sh must run before the
# build-caches lock in ai-sandbox-restart too (as ai-sandbox already does).
# start-display.sh can background a long-lived process (Xephyr, Xvfb, the xpra
# viewer); run under the lock, that process would inherit CACHES_LOCK_FD and
# keep the flock held long after this script closes its own copy, hanging
# every later 'ai-sandbox-restart'/'ai-sandbox' start.
# =============================================================================

t15proj="$tmp/work/t15"; mkdir -p "$t15proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t15proj" >"$tmp/t15.out" 2>&1 || cat "$tmp/t15.out"
t15dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t15proj")-agent"
sleep_pidfile="$tmp/t15-sleep.pid"
# A stand-in for the real, generated start-display.sh: it backgrounds a
# long-lived process (a stand-in for Xephyr/Xvfb/xpra) and records its pid so
# the test can confirm, afterward, that nothing of this script's is still
# alive holding the lock's file descriptor open.
cat > "$t15dir/start-display.sh" <<EOF
#!/usr/bin/env bash
(exec sleep 600) >/dev/null 2>&1 &
echo \$! > "$sleep_pidfile"
EOF
chmod +x "$t15dir/start-display.sh"

: > "$DOCKER_STUB_LOG"
out=$(cd "$t15proj" && DOCKER_STUB_RUNNING=true bash "$REPO_ROOT/bin/ai/ai-sandbox-restart" 2>&1); rc=$?
assert_eq "ai-sandbox-restart succeeds with a backgrounding start-display.sh" "$rc" 0

# The background process is a grandchild forked well before the script
# returned, so it is already running by now; no sleep/poll needed.
TESTS_RUN=$((TESTS_RUN+1))
if flock -n "$t15dir/build-caches/.lock" true 2>/dev/null; then
    _pass "the build-caches lock is free after ai-sandbox-restart returns"
else
    _fail "the build-caches lock is free after ai-sandbox-restart returns" \
          "flock -n failed: a lingering process (start-display.sh's child) still holds it"
fi

# Cleanup: the leftover background process must not survive the test file,
# whichever way the assertion above went.
leftover_pid=$(cat "$sleep_pidfile" 2>/dev/null || true)
[ -n "$leftover_pid" ] && kill "$leftover_pid" 2>/dev/null || true

# =============================================================================
# Task 16: tool notes -- Gradle/Maven named in the mounted-paths sentence, and
# the unconditional Gradle bullet (A1)
# =============================================================================

t16proj="$tmp/work/t16"; mkdir -p "$t16proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t16proj" >"$tmp/t16.out" 2>&1 || cat "$tmp/t16.out"
brain16=$(cat "$HOME/.gemini/GEMINI.md")
assert_contains "the mounted-paths sentence substring survives" "$brain16" \
    "The only other host paths mounted are the"
assert_contains "the mounted-paths sentence now names Gradle" "$brain16" "Gradle"
assert_contains "the mounted-paths sentence now names Maven" "$brain16" "Maven"
assert_contains "the Gradle bullet mentions --offline" "$brain16" "--offline"
assert_contains "the Gradle bullet says writes are discarded" "$brain16" "discarded"
assert_contains "the Gradle bullet names gradle.properties" "$brain16" "gradle.properties"
assert_contains "the Gradle bullet points at sandbox-doctor" "$brain16" "sandbox-doctor"

# =============================================================================
# Task 17: sandbox-doctor -- one status row per build-cache mount (A2)
# =============================================================================

t17proj="$tmp/work/t17"; mkdir -p "$t17proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t17proj" >"$tmp/t17.out" 2>&1 || cat "$tmp/t17.out"
doctor17=$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")
assert_contains "sandbox-doctor has a gradle-caches row" "$doctor17" "gradle-caches"
assert_contains "sandbox-doctor has a gradle-wrapper-dists row" "$doctor17" "gradle-wrapper-dists"
assert_contains "sandbox-doctor has a m2-repository row" "$doctor17" "m2-repository"
assert_contains "sandbox-doctor can report 'overlay'" "$doctor17" "overlay"
assert_contains "sandbox-doctor can report the not-mounted wording" "$doctor17" \
    "not mounted -- re-run create-ai-sandbox.sh"

# =============================================================================
# Task 18: usage() -- a Build caches paragraph, and build-caches/ in the
# "Layout under ~/.ai-sandbox" list (A3)
# =============================================================================

help18=$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)
assert_contains "--help shows a Build caches paragraph" "$help18" "Build caches"
assert_contains "--help lists build-caches/ in the layout" "$help18" "build-caches/"

# =============================================================================
# Task 19: create-ai-sandbox.sh -- the D2 repair call site does not leak the
# check's own "ai-sandbox-stop" message (user's decision, 2026-10-02): this
# script is already past I10 and about to repair the volume itself, so that
# message is misleading here. The repair step instead names the volume and
# says it is repairing/recreating it. Reuses Task 8's differing-volume start
# ($tmp/t8b.out), rather than re-running that scenario.
# =============================================================================

t19out=$(cat "$tmp/t8b.out")
TESTS_RUN=$((TESTS_RUN+1))
case "$t19out" in
    *"ai-sandbox-stop"*)
        _fail "create-ai-sandbox.sh's own output does not name ai-sandbox-stop at the repair site" "$t19out" ;;
    *) _pass "create-ai-sandbox.sh's own output does not name ai-sandbox-stop at the repair site" ;;
esac
assert_contains "create-ai-sandbox.sh's own output names the differing volume" "$t19out" \
    "$t8container-gradle-caches"
TESTS_RUN=$((TESTS_RUN+1))
case "$t19out" in
    *epair*|*ecreat*) _pass "create-ai-sandbox.sh's own output names repairing/recreating the volume" ;;
    *) _fail "create-ai-sandbox.sh's own output names repairing/recreating the volume" "$t19out" ;;
esac

# =============================================================================
# Task 20: ai-sandbox-rm -- report a leftover instead of aborting (A5)
# =============================================================================

t20proj="$tmp/work/t20"; mkdir -p "$t20proj"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t20proj" >"$tmp/t20.out" 2>&1 || cat "$tmp/t20.out"
t20dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t20proj")-agent"

# --- happy path: 'y' removes the directory, logging 'down -v' --------------
: > "$DOCKER_STUB_LOG"
out=$(cd "$t20proj" && printf 'y\n' | bash "$REPO_ROOT/bin/ai/ai-sandbox-rm" 2>&1); rc=$?
assert_eq "ai-sandbox-rm with no leftovers exits 0" "$rc" 0
assert_contains "ai-sandbox-rm logs compose down -v" "$(cat "$DOCKER_STUB_LOG")" "down -v"
assert_no_file "the sandbox directory is gone" "$t20dir"
assert_contains "it still reports the host's caches as untouched" "$out" "not touched"

# --- an undeletable leftover (same chmod-000 fixture style as the reset
# --- test): named, with the fix-up command, instead of aborting mid-way ----
if [ "$(id -u)" != 0 ]; then
    t20bproj="$tmp/work/t20b"; mkdir -p "$t20bproj"
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$t20bproj" >"$tmp/t20b.out" 2>&1 || cat "$tmp/t20b.out"
    t20bdir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$t20bproj")-agent"
    mkdir -p "$t20bdir/build-caches/gradle-caches/upper/locked/inner"
    echo stuck > "$t20bdir/build-caches/gradle-caches/upper/locked/inner/file"
    chmod 000 "$t20bdir/build-caches/gradle-caches/upper/locked"
    : > "$DOCKER_STUB_LOG"
    out=$(cd "$t20bproj" && printf 'y\n' | bash "$REPO_ROOT/bin/ai/ai-sandbox-rm" 2>&1); rc=$?
    assert_ne "ai-sandbox-rm exits non-zero when a leftover remains" "$rc" 0
    assert_contains "the leftover's path is named" "$out" "locked"
    assert_contains "the fix-up command is given" "$out" "sudo rm -rf"
    assert_contains "shared assets are still reported as left in place" "$out" "Shared assets"
    assert_contains "the host's caches are still reported as untouched" "$out" "not touched"
    # restore permissions so the final cleanup below can remove the tree
    chmod 700 "$t20bdir/build-caches/gradle-caches/upper/locked" 2>/dev/null || true
    rm -rf "$t20bdir" 2>/dev/null || true
fi

rm -rf "$tmp"
finish
