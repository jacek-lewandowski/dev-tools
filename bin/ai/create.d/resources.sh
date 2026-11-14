# create.d/resources.sh -- memory, CPU set and timezone, and the host's memory-budget gate.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

# Resource limits for the container. Docker imposes none by default, so a
# runaway build or an Electron leak can take the whole host down with it.
#   MEMORY_GB         RAM the sandbox may use, in GB: --memory=GB, default 2,
#                     remembered per sandbox (SANDBOX_MEMORY_GB in .env).
#                     MEMORY_LIMIT is the same number in Docker's notation.
#   MEMORY_SWAP_LIMIT RAM+swap ceiling. Equal to MEMORY_LIMIT means the
#                     container gets no swap, so the limit is a real MEMORY_GB
#                     rather than that much RAM plus the 2x swap Docker would
#                     otherwise allow -- which on a host whose swap is already
#                     full would buy nothing but thrashing.
#   SHM_SIZE          /dev/shm is a tmpfs inside the container's own cgroup, so
#                     its pages count against MEMORY_LIMIT. Keeping it well
#                     under the limit stops one large shm allocation from
#                     OOM-killing the sandbox by itself.
#   CPU_LIMIT         Derived: half as many cores as GB of RAM, rounded up and
#                     never fewer than one, so the default 2 GB sandbox sees one and 6 GB sees three.
#                     Applied as a cpuset rather than a CPU quota,
#                     because a quota is invisible to nproc, make -j, cargo,
#                     Node and every other tool that sizes its parallelism by
#                     core count: they would see the host's cores and build
#                     straight into the memory cap. A cpuset changes what the
#                     container can see, so nproc and the cap agree. The cores
#                     themselves are chosen to spread sandboxes over the host
#                     (see "CPU set" below).
# The three memory values are set under "Memory" below, once the remembered
# size is known. How much RAM all running sandboxes may use together is
# AI_SANDBOX_MEMORY_BUDGET_GB in ~/.ai-sandbox/config, checked by
# ai_sandbox_check_capacity in ai-sandbox-lib.sh before every start.

readonly SHM_SIZE='1gb'

resources_budget_gate() {
# The host's memory budget gates every run, --no-start included, before
# anything is written: a host without one learns what to write first.
ai_sandbox_memory_budget_gb >/dev/null || exit 1
}

resources_limits() {
readonly MEMORY_GB
readonly MEMORY_LIMIT="${MEMORY_GB}g"
readonly MEMORY_SWAP_LIMIT=$MEMORY_LIMIT
CPU_LIMIT=$(( (MEMORY_GB + 1) / 2 ))
[ "$CPU_LIMIT" -ge 1 ] || CPU_LIMIT=1
readonly CPU_LIMIT
}

resources_cpuset() {
# --- CPU set ---------------------------------------------------------------
# Which CPU_LIMIT cores this sandbox is pinned to, remembered in .env like the
# display number. Pinning to the same cores everywhere would stack every
# sandbox onto 0-1 while the rest of the host idles, so each new one takes the
# cores the fewest other sandboxes have claimed, lowest numbers first: two
# sandboxes on a 16-core host share nothing, and on an oversubscribed host the
# doubling-up is even. Re-allocated when the count no longer matches CPU_LIMIT
# or the host has fewer cores than the recorded set names.
HOST_CPUS=$(nproc 2>/dev/null || echo 1)
CPUSET_WANT=$CPU_LIMIT
[ "$CPUSET_WANT" -le "$HOST_CPUS" ] || CPUSET_WANT=$HOST_CPUS
cpuset_valid() {
    local set=$1 c count=0
    case "$set" in ''|*[!0-9,]*|,*|*,|*,,*) return 1 ;; esac
    IFS=, read -ra _ids <<< "$set"
    for c in "${_ids[@]}"; do
        [ "$c" -lt "$HOST_CPUS" ] || return 1
        count=$((count + 1))
    done
    [ "$count" -eq "$CPUSET_WANT" ]
}
CPUSET=""
[ -f "$ENV_FILE" ] && CPUSET=$(sed -n 's/^SANDBOX_CPUSET=//p' "$ENV_FILE" | tail -n 1)
if ! cpuset_valid "$CPUSET"; then
    declare -ga CPU_LOAD=()
    for (( c = 0; c < HOST_CPUS; c++ )); do CPU_LOAD[c]=0; done
    for other_env in "$AI_SANDBOX_ROOT"/*-agent/.env; do
        other_dir=${other_env%/.env}
        [ -f "$other_env" ] && [ "$other_dir" != "$SANDBOX_DIR" ] || continue
        IFS=, read -ra _ids <<< "$(sed -n 's/^SANDBOX_CPUSET=//p' "$other_env" | tail -n 1)"
        for c in "${_ids[@]}"; do
            case "$c" in ''|*[!0-9]*) continue ;; esac
            [ "$c" -lt "$HOST_CPUS" ] && CPU_LOAD[c]=$((CPU_LOAD[c] + 1))
        done
    done
    chosen=()
    for (( k = 0; k < CPUSET_WANT; k++ )); do
        best=-1
        for (( c = 0; c < HOST_CPUS; c++ )); do
            [ "${CPU_LOAD[c]}" -ge 0 ] || continue          # already chosen
            if [ "$best" -lt 0 ] || [ "${CPU_LOAD[c]}" -lt "${CPU_LOAD[best]}" ]; then best=$c; fi
        done
        CPU_LOAD[best]=-1
        chosen+=("$best")
    done
    CPUSET=$(printf '%s\n' "${chosen[@]}" | sort -n | paste -sd, -)
    log "CPU set: cores $CPUSET of the host's $HOST_CPUS (${CPUSET_WANT} for ${MEMORY_GB} GB: half the GB, rounded up)"
    unset CPU_LOAD chosen other_env other_dir best c k
fi
unset _ids
}

resources_timezone() {
# ---------------------------------------------------------------------------
# Timezone
# ---------------------------------------------------------------------------

# The sandbox keeps the host's clock zone: TZ by name for everything that
# reads it (tzdata in the image resolves it), and the entrypoint points
# /etc/localtime and /etc/timezone at the same zone for everything that does
# not. Nothing is bind-mounted over a zoneinfo path: Docker follows the image's
# /etc/localtime symlink and would overwrite /usr/share/zoneinfo/Etc/UTC with
# the host's file, so UTC by name would show the host's zone. Never remembered in .env: a
# host that changes zones is followed on the next create. The name comes from
# timedatectl, else /etc/timezone, else the /etc/localtime symlink, else UTC.
HOST_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || true)
if [ -z "$HOST_TZ" ] && [ -f "$HOST_ETC_DIR/timezone" ]; then
    HOST_TZ=$(sed -n '1{s/[[:space:]]//g;p}' "$HOST_ETC_DIR/timezone")
fi
if [ -z "$HOST_TZ" ] && [ -L "$HOST_ETC_DIR/localtime" ]; then
    tz_target=$(readlink -f "$HOST_ETC_DIR/localtime" 2>/dev/null || readlink "$HOST_ETC_DIR/localtime")
    case "$tz_target" in /usr/share/zoneinfo/*) HOST_TZ=${tz_target#/usr/share/zoneinfo/} ;; esac
    unset tz_target
fi
if [ -z "$HOST_TZ" ]; then
    HOST_TZ=UTC
    warn "Could not determine the host's timezone (timedatectl, $HOST_ETC_DIR/timezone, $HOST_ETC_DIR/localtime); the sandbox uses UTC."
fi
readonly HOST_TZ
add_env "TZ=${HOST_TZ}"
log "Timezone: $HOST_TZ (TZ), /etc/localtime and /etc/timezone set by the entrypoint"
TZ_SUMMARY="$HOST_TZ (the host's, by TZ; the entrypoint links /etc/localtime and writes /etc/timezone at start, warning in docker logs if it cannot)"
}
