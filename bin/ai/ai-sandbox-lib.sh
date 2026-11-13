#!/usr/bin/env bash
# Shared definitions for create-ai-sandbox.sh and the ai-sandbox-* helpers.
# This file is SOURCED, never executed. It must not call 'set -e' or exit.
#
# Identity is defined here exactly once. create-ai-sandbox.sh and every helper
# must call these functions rather than recomputing a project id, because a
# divergence between two implementations silently orphans a sandbox directory.

AI_SANDBOX_ROOT="${AI_SANDBOX_ROOT:-$HOME/.ai-sandbox}"
AI_SANDBOX_SCHEMA_VERSION=2
# Host-wide settings, shell-style KEY=VALUE lines. create-ai-sandbox.sh writes
# DEV_TOOLS_DIR; AI_SANDBOX_MEMORY_BUDGET_GB, the RAM in GB that all running
# sandboxes together may use, is written by the user by hand (the file's only
# reader outside this repository is the user) and has no default.
AI_SANDBOX_CONFIG="$AI_SANDBOX_ROOT/config"     # defined once, in the lib

# The shared knowledge repository (see ai-knowledge). Configured when the config
# file exists; every knowledge feature is inert otherwise.
AI_KNOWLEDGE_ROOT="$AI_SANDBOX_ROOT/knowledge"
AI_KNOWLEDGE_CONFIG="$AI_KNOWLEDGE_ROOT/config"
AI_KNOWLEDGE_RENDER="$AI_SANDBOX_ROOT/shared/knowledge"
ai_knowledge_configured() { [ -f "$AI_KNOWLEDGE_CONFIG" ]; }

# Lowercase, replace every non-alphanumeric with '-', collapse runs, trim both
# ends. Trimming the trailing end matters: 'foo.' would otherwise yield 'foo-',
# and 'foo-' + '-' + hash is a double dash, which Docker rejects in a
# repository component.
ai_sandbox_slug() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed -e 's/[^a-z0-9]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-*//' -e 's/-*$//'
}

# <slug of basename>-<first 8 hex of sha256 of the absolute path>.
ai_sandbox_project_id() {
    local abs=$1 slug hash
    slug=$(ai_sandbox_slug "$(basename "$abs")")
    [ -n "$slug" ] || slug=project
    hash=$(printf '%s' "$abs" | sha256sum | cut -c1-8)
    printf '%s-%s' "$slug" "$hash"
}

# Claude Code keys its per-project state (~/.claude/projects/<key>) by the
# absolute project path with every character outside [A-Za-z0-9] turned into
# '-'. Reproducing that lets a sandbox mount only its own project's entry.
ai_sandbox_claude_project_key() {
    printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'
}

# C-STAMP. The project a directory belongs to is read from the stamps under
# AI_SANDBOX_ROOT, never from the tree: a sandbox can write the tree (a nested
# repository, a setting in the project's git configuration that names another
# directory), and no git process runs here.
# Whether <dir> is a project the host stamped: the sandbox directory filed
# under its id holds a project-path whose first line is <dir>.
ai_sandbox_stamped() {   # <dir>
    local f line=""
    f="$(ai_sandbox_dir_for "$1")/project-path"
    [ -f "$f" ] || return 1
    IFS= read -r line < "$f" || [ -n "$line" ]
    [ "$line" = "$1" ]
}

# The parent of an absolute path; nothing for "/".
ai_sandbox_parent_dir() {
    case $1 in
        /|"") ;;
        */*)  local p=${1%/*}; printf '%s' "${p:-/}" ;;
    esac
}

# The nearest stamped ancestor of <dir>, else (second argument "git") the
# nearest ancestor holding a .git entry, else <dir> with links resolved.
# Today's stamps hold two path forms: git's resolved toplevel for a repository,
# the path as given for anything else. So both chains of ancestors are walked,
# the path as given and the resolved one, nearest first, the given form first
# on a tie; a stamp is found whichever form it holds. A .git entry is looked
# for in the resolved chain, the form a repository's stamp has always had.
# Return: 0 found a stamp or a .git, 3 found neither (printed the fallback),
# 1 no such directory.
ai_sandbox_root_scan() {   # <dir> [git]
    local a b fallback
    a=$(cd -- "$1" 2>/dev/null && pwd) || return 1
    b=$(cd -- "$1" 2>/dev/null && pwd -P) || return 1
    fallback=$b
    while [ -n "$a" ] || [ -n "$b" ]; do
        if [ -n "$a" ] && ai_sandbox_stamped "$a"; then printf '%s\n' "$a"; return 0; fi
        if [ -n "$b" ] && [ "$b" != "$a" ] && ai_sandbox_stamped "$b"; then printf '%s\n' "$b"; return 0; fi
        if [ "${2:-}" = git ] && [ -n "$b" ] && [ -e "$b/.git" ]; then printf '%s\n' "$b"; return 0; fi
        a=$(ai_sandbox_parent_dir "$a"); b=$(ai_sandbox_parent_dir "$b")
    done
    printf '%s\n' "$fallback"; return 3
}

# The project of <dir> for every command but create: the nearest stamped
# ancestor, else <dir> itself with links resolved. 1: no such directory.
ai_sandbox_project_root() {   # [dir]
    local rc=0
    ai_sandbox_root_scan "${1:-$PWD}" || rc=$?
    [ "$rc" -ne 1 ]
}

# create-ai-sandbox.sh only: the nearer of the stamped ancestor and the
# ancestor holding a .git entry (tested for existence), else <dir> itself.
ai_sandbox_create_root() {   # [dir]
    local rc=0
    ai_sandbox_root_scan "${1:-$PWD}" git || rc=$?
    [ "$rc" -ne 1 ]
}

ai_sandbox_dir_for() {
    printf '%s/%s-agent' "$AI_SANDBOX_ROOT" "$(ai_sandbox_project_id "$1")"
}

# One value from a sandbox's managed .env; empty when absent.
ai_sandbox_env_value() {   # <sandbox dir> <key>
    sed -n "s/^$2=//p" "$1/.env" 2>/dev/null | tail -1
}

# Every sandbox directory that has a compose file, as "<sandbox dir>\t<project
# dir>". The project column is empty for a sandbox created before the stamp.
ai_sandbox_list() {
    local d
    for d in "$AI_SANDBOX_ROOT"/*-agent; do
        [ -f "$d/docker-compose.yml" ] || continue
        printf '%s\t%s\n' "$d" "$(ai_sandbox_env_value "$d" SANDBOX_PROJECT_DIR)"
    done
}

# The knowledge stamp create-ai-sandbox.sh writes: 1 when the compose file
# carries the knowledge mounts, 0 when it carries the live GEMINI.md mount,
# nothing for a sandbox created before stamps existed.
ai_sandbox_knowledge_stamp() { ai_sandbox_env_value "$1" SANDBOX_KNOWLEDGE; }

# current | stale | unstamped: whether the sandbox's compose file matches the
# host's knowledge configuration. A stale sandbox with knowledge configured
# mounts the live GEMINI.md, which now resolves to the render, read-write.
ai_sandbox_knowledge_state() {
    local stamp want=0
    stamp=$(ai_sandbox_knowledge_stamp "$1")
    ai_knowledge_configured && want=1
    if [ -z "$stamp" ]; then echo unstamped
    elif [ "$stamp" = "$want" ]; then echo current
    else echo stale
    fi
}

# The start path only checks; it never rewrites a sandbox. The repair is a
# plain create-ai-sandbox.sh run for this sandbox; the disposable migration
# script from the dev-tools checkout is the shortcut for every sandbox at once.
ai_sandbox_require_current() {   # <sandbox dir>
    local state dev_tools="" project
    state=$(ai_sandbox_knowledge_state "$1")
    [ "$state" = current ] && return 0
    [ -f "$AI_SANDBOX_CONFIG" ] && dev_tools=$(sed -n 's/^DEV_TOOLS_DIR=//p' "$AI_SANDBOX_CONFIG" | head -1)
    project=$(ai_sandbox_env_value "$1" SANDBOX_PROJECT_DIR)
    if [ -z "$project" ] && [ -f "$1/project-path" ]; then project=$(head -1 "$1/project-path"); fi
    {
        if [ "$state" = stale ]; then
            echo "Sandbox $(basename "$1") is stale: its compose file disagrees with the host's knowledge configuration."
        else
            echo "Sandbox $(basename "$1") is unstamped: it was created before the knowledge stamp existed."
        fi
        echo "It cannot be started until it has been recreated. Run on the host:"
        echo "    create-ai-sandbox.sh ${project:-<project dir>}"
        echo "To recreate every stale or unstamped sandbox at once instead:"
        echo "    ${dev_tools:-<dev-tools checkout>}/bin/ai/ai-sandbox-migrate-knowledge"
    } >&2
    return 1
}
# Resolve the sandbox for the current directory. Sets AI_SANDBOX_DIR,
# AI_SANDBOX_NAME and AI_SANDBOX_PROJECT, or returns 1 with a message.
ai_sandbox_require_ctx() {
    AI_SANDBOX_PROJECT=$(ai_sandbox_project_root) || return 1
    AI_SANDBOX_DIR=$(ai_sandbox_dir_for "$AI_SANDBOX_PROJECT")
    AI_SANDBOX_NAME=$(basename "$AI_SANDBOX_DIR")
    if [ ! -f "$AI_SANDBOX_DIR/docker-compose.yml" ]; then
        echo "No sandbox configured for this project ($AI_SANDBOX_DIR)." >&2
        echo "Create one with: create-ai-sandbox.sh" >&2
        return 1
    fi
}

ai_sandbox_compose() {
    docker compose -f "$AI_SANDBOX_DIR/docker-compose.yml" \
                   --env-file "$AI_SANDBOX_DIR/.env" "$@"
}

# Deterministic hash over a build context and the build args that go with it.
# Sorting the paths under a fixed locale is what makes it reproducible across
# machines; hashing contents rather than mtimes is what stops a rebuild being
# triggered by a rewrite that changed nothing.
ai_sandbox_build_hash() {
    local dir=$1; shift
    {
        ( cd "$dir" && find . -type f -print0 | LC_ALL=C sort -z \
            | while IFS= read -r -d '' f; do
                  printf '%s\0%s\0' "${f#./}" "$(sha256sum "$f" | cut -d' ' -f1)"
              done )
        printf '%s\0' "$@"
    } | sha256sum | cut -d' ' -f1
}

# Bulk data that is identical across projects, so every sandbox mounts one
# shared copy instead of carrying its own.
#
# Sandboxes are NOT one trust domain. Everything here is executable code -- IDE
# extensions, JetBrains plugins, Claude Code and Claude Desktop binaries, the
# agent skills every agent loads and follows -- so
# it is mounted READ-ONLY into every sandbox and written only by the host:
# create-ai-sandbox.sh syncs the host's own copy in on every run, and
# ai-sandbox-extensions installs what the host does not have. A compromised
# sandbox therefore cannot plant code that another sandbox runs. Whatever a
# sandbox must write at run time (~/.cache, ~/.npm, the IDE's CachedData) is
# per sandbox and deliberately absent from this table.
#
# Each row is three fields:
#   <subdirectory of shared/>|<path in the container>|<path in the sandbox dir>
#
# The second field is also the path under $HOME on the host that the store is
# populated from. The second and third differ, and that difference is load-bearing. The
# container sees ~/.config/Claude, but the sandbox directory holds the same data
# under claude-data/ (and antigravity-data/, antigravity-ide-data/). An empty
# third field means the data exists ONLY in the container's writable layer and
# has no per-project copy on disk -- migration and gc skip those rows rather
# than hunting for a directory that never existed.
#
# Most of these are nested bind mounts inside the per-project mounts. Docker
# orders mounts by destination depth, which is what makes the nesting work;
# ~/.claude/projects has relied on that since before this change.
#
# agent-skills is ~/.agents, where the skills CLI keeps the one real copy of
# every shared skill; ~/.claude/skills/<name>, ~/.codex/skills/<name> and the
# like are relative symlinks into it. The seed copies those symlinks as
# symlinks, so without this mount every shared skill dangles in the sandbox.
ai_sandbox_shared_mounts() {
    cat <<'SHARED'
agent-skills|.agents|
antigravity-extensions|.antigravity/extensions|.antigravity/extensions
antigravity-ide-extensions|.antigravity-ide/extensions|
claude-downloads|.claude/downloads|.claude/downloads
claude-desktop-versions|.config/Claude/claude-code|claude-data/claude-code
ide-vsix|.config/Antigravity IDE/CachedExtensionVSIXs|antigravity-ide-data/CachedExtensionVSIXs
jetbrains-plugins|.local/share/JetBrains|
SHARED
}

# Every helper installed into $AI_SANDBOX_ROOT/bin. create-ai-sandbox.sh
# installs from this list and ai-sandbox-migrate refreshes from it, so a helper
# added here is picked up by both without either being edited. Programs that
# run only inside the image (ai-delegate) are deliberately not listed: the host
# has no use for them and a host copy is one more file to keep current.
ai_sandbox_helpers() {
    cat <<'HELPERS'
ai-sandbox-lib.sh
ai-sandbox
ai-sandbox-stop
ai-sandbox-restart
ai-sandbox-attach
ai-sandbox-rm
ai-sandbox-migrate
ai-sandbox-account
ai-sandbox-gc
ai-knowledge
ai-sandbox-extensions
HELPERS
}

# The image tag of one variant. The uid suffix keeps two host users sharing one
# Docker daemon from fighting over a single tag, since the image bakes in USER_ID.
ai_sandbox_image_name() {   # <base|docker>
    printf 'ai-sandbox:%s-u%s' "$1" "$(id -u)"
}

# C-GIT, host side. Whether PATH, a bind source a sandbox's compose file mounts
# read-write, or a project directory a stamp names holds the path (links
# resolved): then a sandbox can write the repository's configuration and refs.
# 0 when it does, 1 when it does not. A path that cannot be resolved counts as
# writable: the caller refuses, which is the safe side.
ai_sandbox_writable_path() {   # <path>
    local real d line f src
    local -a srcs=() resolved=()
    real=$(readlink -m -- "$1" 2>/dev/null) && [ -n "$real" ] || return 0
    for d in "$AI_SANDBOX_ROOT"/*-agent; do
        [ -d "$d" ] || continue
        # the project directories the stamps name
        if [ -f "$d/project-path" ] && IFS= read -r line < "$d/project-path" && [ -n "$line" ]; then srcs+=("$line"); fi
        line=$(ai_sandbox_env_value "$d" SANDBOX_PROJECT_DIR)
        [ -z "$line" ] || srcs+=("$line")
        # the bind sources of the compose file that carry no :ro; only quoted
        # list items under the service's volumes: key, as create-ai-sandbox.sh
        # writes them (src:dst or src:dst:options; named volumes do not start
        # with a slash and a relative source is relative to the compose file)
        [ -f "$d/docker-compose.yml" ] || continue
        while IFS= read -r src; do
            case $src in /*) srcs+=("$src") ;; ./*|../*) srcs+=("$d/$src") ;; esac
        done < <(awk '
            /^    volumes:[[:space:]]*$/ { inv = 1; next }
            inv && $0 !~ /^[[:space:]]*(#.*)?$/ { match($0, /^ */); if (RLENGTH <= 4) inv = 0 }
            inv && /^[[:space:]]+-[[:space:]]+"[^"]*"[[:space:]]*$/ {
                item = $0; sub(/^[[:space:]]+-[[:space:]]+"/, "", item); sub(/"[[:space:]]*$/, "", item)
                n = split(item, f, ":")
                if (n >= 2 && f[1] !~ /\$/) {
                    if (n >= 3 && f[n] ~ /(^|,)ro(,|$)/) next
                    print f[1]
                }
            }' "$d/docker-compose.yml")
    done
    [ ${#srcs[@]} -gt 0 ] || return 1
    mapfile -t resolved < <(readlink -m -- "${srcs[@]}" 2>/dev/null)
    for src in "${resolved[@]}"; do
        [ -n "$src" ] || continue
        case $real in "$src"|"$src"/*) return 0 ;; esac
    done
    return 1
}

# C-GIT, host side: the only way the host runs git against a repository, apart
# from ai_sandbox_confined_git. <repository> is a host-owned directory (status
# 3, without starting git, when a sandbox can write it); '-' discovers no
# repository, for commands given a URL alone, because a git started inside a
# repository reads that repository's configuration even then. The working
# directory is / in that form and the repository's own path, links resolved,
# in the other. Variables set for the call (GIT_SSH_COMMAND and the like) reach
# git; GIT_DIR and GIT_WORK_TREE never do, since they would override the
# repository this function has just vetted. AI_SANDBOX_GIT_TIMEOUT=<seconds>
# bounds the run (exit 124).
ai_sandbox_host_git() {   # <repository|-> <git args...>
    local repo=$1 real=""
    shift
    if [ "$repo" != - ]; then
        real=$(readlink -m -- "$repo" 2>/dev/null) || real=$repo
        if ai_sandbox_writable_path "$real"; then
            echo "ai_sandbox_host_git: refusing to run git in $repo: a sandbox can write it" >&2
            return 3
        fi
    fi
    (
        unset GIT_DIR GIT_WORK_TREE
        if [ -n "$real" ]; then
            cd -- "$real" 2>/dev/null || { echo "ai_sandbox_host_git: cannot enter $repo" >&2; exit 128; }
        else
            cd / || exit 128
        fi
        if [ -n "${AI_SANDBOX_GIT_TIMEOUT:-}" ]; then exec timeout "$AI_SANDBOX_GIT_TIMEOUT" git "$@"; fi
        exec git "$@"
    )
}

# True when the sandbox container NAME is running. Without docker on PATH
# nothing can be running, so the answer is no rather than an error.
ai_sandbox_container_running() {
    command -v docker >/dev/null 2>&1 || return 1
    [ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

# The one rule for every memory size: a whole number of GB, at least 1, no
# sign, no unit, no leading zero (bash would read 010 as octal). The budget,
# the remembered SANDBOX_MEMORY_GB and --memory all go through it.
ai_sandbox_whole_gb() {   # <value>
    case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac
}

# The host's memory budget from AI_SANDBOX_CONFIG, last line wins. The file is
# the user's, so it is read with sed, never sourced. A value that is not a
# whole number of GB counts as unset and is quoted in the refusal.
ai_sandbox_memory_budget_gb() {   # prints the budget; 1 + refusal on stderr when unset/invalid
    local gb=""
    [ -f "$AI_SANDBOX_CONFIG" ] && gb=$(sed -n 's/^AI_SANDBOX_MEMORY_BUDGET_GB=//p' "$AI_SANDBOX_CONFIG" | tail -1)
    if ! ai_sandbox_whole_gb "$gb"; then
        {
            if [ -z "$gb" ]; then
                echo "No memory budget is configured for this host: AI_SANDBOX_MEMORY_BUDGET_GB is not set in $AI_SANDBOX_CONFIG."
            else
                echo "No memory budget is configured for this host: AI_SANDBOX_MEMORY_BUDGET_GB is '$gb' in $AI_SANDBOX_CONFIG, not a whole number of GB."
            fi
            echo "Write the RAM, in GB, that all running sandboxes together may use, for example:"
            echo "    echo 'AI_SANDBOX_MEMORY_BUDGET_GB=18' >> $AI_SANDBOX_CONFIG"
        } >&2
        return 1
    fi
    printf '%s\n' "$gb"
}

# The memory a sandbox is created with. A sandbox created before the key
# existed has a compose file saying 'mem_limit: "6g"', so 6 is what Docker
# applies to it. A hand-edited value that is not a whole number of GB is also
# 6, with one warning naming the file: a start must never do arithmetic on it.
ai_sandbox_memory_gb() {   # <sandbox dir>: SANDBOX_MEMORY_GB from .env, or 6 when the key is absent
    local gb
    gb=$(ai_sandbox_env_value "$1" SANDBOX_MEMORY_GB)
    if [ -n "$gb" ] && ! ai_sandbox_whole_gb "$gb"; then
        echo "SANDBOX_MEMORY_GB is '$gb' in $1/.env, not a whole number of GB; counting 6 GB." >&2
        gb=""
    fi
    printf '%s\n' "${gb:-6}"
}

# False, with the refusal on stderr, when starting NAME at GB would put the
# running sandboxes' memory plus GB over the host's budget. Each running
# sandbox counts what Docker enforces on it (HostConfig.Memory, bytes rounded
# up to whole GB; 0, no limit, counts 0 and is listed as such). NAME itself
# never counts, so a restart can always reclaim its own share; nor does any
# container without a sandbox directory under AI_SANDBOX_ROOT, because the
# budget is about sandboxes, not about Docker at large. Every path that runs
# 'compose up' must call this first, and a restart must call it before
# 'compose down'.
ai_sandbox_check_capacity() {   # <name> <gb>: 0, or 1 + the over-budget refusal on stderr
    local self=$1 gb=$2 budget n bytes ngb used=0 running=() list
    budget=$(ai_sandbox_memory_budget_gb) || return 1
    command -v docker >/dev/null 2>&1 || return 0
    while IFS= read -r n; do
        [ -n "$n" ] && [ "$n" != "$self" ] && [ -d "$AI_SANDBOX_ROOT/$n" ] || continue
        bytes=$(docker container inspect -f '{{.HostConfig.Memory}}' "$n" 2>/dev/null)
        case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
        if [ "$bytes" -eq 0 ]; then
            ngb=0; running+=("$n (no limit)")
        else
            ngb=$(( (bytes + 1073741823) / 1073741824 )); running+=("$n ($ngb GB)")
        fi
        used=$((used + ngb))
    done < <(docker ps --format '{{.Names}}' 2>/dev/null)
    [ $((used + gb)) -le "$budget" ] && return 0
    list=$(printf '%s, ' "${running[@]}"); list=${list%, }
    {
        echo "Cannot start $self ($gb GB): $used GB of the $budget GB memory budget is in use."
        echo "Running: ${list:-none}"
        echo "Stop one first, with 'ai-sandbox-stop' from its project directory, or raise AI_SANDBOX_MEMORY_BUDGET_GB in $AI_SANDBOX_CONFIG."
    } >&2
    return 1
}

# rsync '--exclude=' arguments for copying the host's <path under $HOME> into
# a sandbox, one per line. Used by the one-time seed in create-ai-sandbox.sh
# and by 'ai-sandbox-account refresh', so a refresh can never drag in what the
# seed deliberately left out: caches, the bulk that now lives in shared/, host
# state a single-project sandbox has no use for, and the paths that are
# bind-mounted live instead of copied (the shared brain and conversations,
# ~/.claude/CLAUDE.md and this project's ~/.claude/projects entry).
ai_sandbox_seed_excludes() {
    cat <<'EX'
--exclude=*Cache*
--exclude=*cache*
--exclude=BrowserMetrics*
--exclude=Crashpad
--exclude=logs
--exclude=tmp
--exclude=extensions
--exclude=downloads
--exclude=claude-code
--exclude=CachedExtensionVSIXs
--exclude=CachedData
--exclude=WebStorage
--exclude=workspaceStorage
--exclude=Safe Browsing
--exclude=optimization_guide_model_store
--exclude=WasmTtsEngine
--exclude=OnDeviceHeadSuggestModel
--exclude=CertificateRevocation
EX
    case $1 in
        .gemini) cat <<'EX'
--exclude=brain
--exclude=conversations
--exclude=browser_recordings
--exclude=html_artifacts
--exclude=history
--exclude=History*
--exclude=IndexedDB
--exclude=Service Worker
--exclude=GEMINI.md
EX
        ;;
        .claude) printf '%s\n' --exclude=CLAUDE.md --exclude=projects ;;
    esac
}

# Every directory under a sandbox directory that the compose file binds into
# the container, plus the parents of nested mount targets. All of them must
# exist before 'compose up': Docker creates a missing bind source -- or a
# missing parent for a nested target -- as root, and the container user can
# then neither write to it nor, later, remove it. create-ai-sandbox.sh makes
# them before generating the compose file; 'ai-sandbox-account reset' remakes
# them after wiping the credential directories.
#
# .claude/projects is the parent of the ~/.claude/projects/<key> mount. Without
# it Docker creates projects/ and projects/<key> root-owned inside .claude, and
# 'rm -rf .claude' fails on <key> ever after.
# cache/ and npm/ are per sandbox on purpose: both hold code the sandbox writes
# at run time (wheels, npm tarballs), so sharing them would let one sandbox
# feed code to another.
ai_sandbox_state_dirs() {
    cat <<'DIRS'
.gemini
.antigravity
.antigravity-ide
.claude
.claude/projects
.codex
antigravity-data
antigravity-ide-data
claude-data
gcloud
cache
npm
DIRS
}

# Host build-cache overlay volumes (docs/superpowers/specs/2026-10-02-ai-sandbox-build-caches-design.md).
# Each row is '<key>|<path under $HOME>', the same path on the host (the
# overlay lower) and in the container (host and container $HOME are equal).
ai_sandbox_build_caches() {
    cat <<'CACHES'
gradle-caches|.gradle/caches
gradle-wrapper-dists|.gradle/wrapper/dists
m2-repository|.m2/repository
CACHES
}

# <container name> <key> -> the Docker volume name for that cache.
ai_sandbox_caches_volume() {
    printf '%s-%s' "$1" "$2"
}

# <sandbox dir> <key> <host lower path> -> the overlay driver_opts 'o' string.
ai_sandbox_caches_opts() {
    printf 'lowerdir=%s,upperdir=%s/build-caches/%s/upper,workdir=%s/build-caches/%s/work' \
        "$3" "$1" "$2" "$1" "$2"
}

# <sandbox dir> -> 0 when this sandbox was created with the build-caches
# stamp (D7). Every other caches function is a no-op otherwise (I8).
ai_sandbox_caches_enabled() {
    [ "$(ai_sandbox_env_value "$1" SANDBOX_BUILD_CACHES)" = "1" ]
}

# <sandbox dir> -> mkdir -p the three lowers (under the real $HOME) and every
# upper/work directory. Idempotent: an existing upper or work is never
# touched, only created when absent.
ai_sandbox_caches_prepare() {
    local sandbox=$1 key path
    ai_sandbox_caches_enabled "$sandbox" || return 0
    while IFS='|' read -r key path; do
        mkdir -p "$HOME/$path"
        mkdir -p "$sandbox/build-caches/$key/upper" "$sandbox/build-caches/$key/work"
    done < <(ai_sandbox_build_caches)
}

# Internal: the 'type|device|o' triple Docker currently has stored for a
# build-cache volume, as the compose file's driver_opts carries them (D2
# compares all three). The real shape ('Options' as {device, o, type}) was
# confirmed against the host in the phase 1 smoke test (Run 4). Return status
# is 1 only when the volume itself does not exist (fine, not a difference --
# compose creates it on 'up'); a volume that exists but whose Options is null
# or missing a field still returns 0, with empty stdout, so the caller counts
# it as a difference rather than silently skipping it like a missing volume.
ai_sandbox_caches_current_triple() {   # <volume name>
    local out
    out=$(docker volume inspect "$1" 2>/dev/null) || return 1
    printf '%s' "$out" | python3 -c '
import json, sys
try:
    opts = json.load(sys.stdin)[0]["Options"]
    t, d, o = opts["type"], opts["device"], opts["o"]
    if t is None or d is None or o is None:
        raise ValueError
    sys.stdout.write("%s|%s|%s" % (t, d, o))
except Exception:
    pass
'
    return 0
}

# <sandbox dir> <container name> -> 0, or 1 with the D2 message on stderr.
# Diffs each build-cache volume's stored type, device and o options against
# what the compose file now generates (type and device are always the literal
# "overlay" the compose block writes); a missing volume is not a difference
# (compose creates it on 'up'), but a volume that exists and cannot be read as
# that triple -- Options null, or a field missing, e.g. a plain local volume
# reusing the name -- counts as a difference rather than being skipped as if
# it were missing. Every other script (ai-sandbox, ai-sandbox-restart) only
# checks and stops with this message; only create-ai-sandbox.sh repairs (I9).
ai_sandbox_caches_check() {   # <sandbox dir> <container name>
    local sandbox=$1 container=$2 key path lower have want project rc=0
    ai_sandbox_caches_enabled "$sandbox" || return 0
    project=$(ai_sandbox_env_value "$sandbox" SANDBOX_PROJECT_DIR)
    while IFS='|' read -r key path; do
        lower="$HOME/$path"
        have=$(ai_sandbox_caches_current_triple "$(ai_sandbox_caches_volume "$container" "$key")") || continue
        want="overlay|overlay|$(ai_sandbox_caches_opts "$sandbox" "$key" "$lower")"
        if [ "$have" != "$want" ]; then
            {
                echo "Build-cache volume $(ai_sandbox_caches_volume "$container" "$key") has different options than the sandbox now expects."
                echo "If it is running, run: ai-sandbox-stop"
                echo "Then run: create-ai-sandbox.sh ${project:-<project dir>}"
            } >&2
            rc=1
        fi
    done < <(ai_sandbox_build_caches)
    return "$rc"
}

# <sandbox dir> <container name> -> D2 repair. Precondition: the container is
# already stopped (I10 guarantees this before create-ai-sandbox.sh calls it;
# used only there, never by ai-sandbox or ai-sandbox-restart, I9). Removes the
# stopped container (no '-v', so the lower is never touched) and exactly the
# volumes whose type, device or o options differ, logging each one; the
# following 'compose up' recreates them.
ai_sandbox_caches_repair() {   # <sandbox dir> <container name>
    local sandbox=$1 container=$2 key path lower have want vol diffs=()
    ai_sandbox_caches_enabled "$sandbox" || return 0
    while IFS='|' read -r key path; do
        lower="$HOME/$path"
        vol=$(ai_sandbox_caches_volume "$container" "$key")
        have=$(ai_sandbox_caches_current_triple "$vol") || continue
        want="overlay|overlay|$(ai_sandbox_caches_opts "$sandbox" "$key" "$lower")"
        [ "$have" = "$want" ] || diffs+=("$vol")
    done < <(ai_sandbox_build_caches)
    [ "${#diffs[@]}" -gt 0 ] || return 0
    docker compose -f "$sandbox/docker-compose.yml" --env-file "$sandbox/.env" down
    for vol in "${diffs[@]}"; do
        echo "Repairing build-cache volume $vol: removing it (options changed) so the next start recreates it." >&2
        docker volume rm "$vol"
    done
}

# <sandbox dir> -> D4 reset. Caller holds the '.lock' and has seen the
# container not running. Renames each 'build-caches/<key>' aside into
# '.trash' (a rename always succeeds for the host user, even when sudo inside
# the container left root-owned entries behind), makes a fresh empty
# upper/work, then deletes the trashed copy. A failed deletion only warns;
# ai-sandbox-gc collects what is left (phase 3).
ai_sandbox_caches_reset() {   # <sandbox dir>
    local sandbox=$1 base key path trash
    ai_sandbox_caches_enabled "$sandbox" || return 0
    base="$sandbox/build-caches"
    mkdir -p "$base/.trash"
    while IFS='|' read -r key path; do
        trash=""
        if [ -d "$base/$key" ]; then
            trash="$base/.trash/$key-$(date +%s%N 2>/dev/null || date +%s)-$$-$RANDOM"
            mv "$base/$key" "$trash"
        fi
        mkdir -p "$base/$key/upper" "$base/$key/work"
        if [ -n "$trash" ]; then
            rm -rf "$trash" 2>/dev/null || echo "Warning: could not remove $trash; finish with: sudo rm -rf $trash" >&2
        fi
    done < <(ai_sandbox_build_caches)
    return 0
}

# '<path under $HOME on the host>|<path under the sandbox directory>'.
# Everything here is identity-bearing -- OAuth tokens, account records, the
# Electron profiles that hold a logged-in session -- so it is seeded from the
# host exactly once and never overwritten afterwards. That is what lets one
# project hold a different Claude, Codex or Gemini account from another.
ai_sandbox_seed_paths() {
    cat <<'SEED'
.gemini|.gemini
.antigravity|.antigravity
.antigravity-ide|.antigravity-ide
.claude|.claude
.codex|.codex
.config/Antigravity|antigravity-data
.config/Antigravity IDE|antigravity-ide-data
.config/Claude|claude-data
SEED
}
