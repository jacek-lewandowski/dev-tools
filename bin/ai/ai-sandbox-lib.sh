#!/usr/bin/env bash
# Shared definitions for create-ai-sandbox.sh and the ai-sandbox-* helpers.
# This file is SOURCED, never executed. It must not call 'set -e' or exit.
#
# Identity is defined here exactly once. create-ai-sandbox.sh and every helper
# must call these functions rather than recomputing a project id, because a
# divergence between two implementations silently orphans a sandbox directory.

AI_SANDBOX_ROOT="${AI_SANDBOX_ROOT:-$HOME/.ai-sandbox}"
AI_SANDBOX_SCHEMA_VERSION=2
# C-INSTALL's root: the revisions the host runs (rev/<commit>), `current` naming one.
# Defined once, here; everything that names it uses this.
# reads-outside: ~/.ai-sandbox/bin (a link to installed/current/bin/ai) and
# ~/.ai-sandbox/installed/current: the user's ~/.bashrc block puts the first on PATH, the host's
# Claude Code statusLine setting names context-statusline there, and every sandbox's compose
# file mounts installed/current/tools; change them only with ai-sandbox-install.
AI_SANDBOX_INSTALLED="$AI_SANDBOX_ROOT/installed"   # C-INSTALL's root, defined once
# Host-wide settings, shell-style KEY=VALUE lines. AI_SANDBOX_MEMORY_BUDGET_GB, the RAM
# in GB that all running sandboxes together may use, is written by the user by hand (the
# file's only reader outside this repository is the user) and has no default.
AI_SANDBOX_CONFIG="$AI_SANDBOX_ROOT/config"     # defined once, in the lib

# The shared knowledge repository (see ai-knowledge). Configured when the config
# file exists; every knowledge feature is inert otherwise.
AI_KNOWLEDGE_ROOT="$AI_SANDBOX_ROOT/knowledge"
AI_KNOWLEDGE_CONFIG="$AI_KNOWLEDGE_ROOT/config"
AI_KNOWLEDGE_RENDER="$AI_SANDBOX_ROOT/shared/knowledge"
# C-STATUS: where a sandbox sees <sandbox dir>/status, read-only. Defined once here;
# the compose file binds it and passes it on as SANDBOX_STATUS_DIR.
AI_SANDBOX_STATUS_MOUNT=/run/ai-sandbox/status
# C-KNOW: the bare origin <sandbox dir>/knowledge-origin.git, written by the host only
# and bound read-only at this path; the in-sandbox clone fetches from it. Defined once
# here; create binds it, ai-knowledge refreshes it.
AI_SANDBOX_ORIGIN_MOUNT=/run/ai-sandbox/knowledge-origin.git
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

# The nearest stamped ancestor of <dir>, else (second argument "dotgit") the
# nearest ancestor holding a .git entry, else <dir> with links resolved.
# Today's stamps hold two path forms: git's resolved toplevel for a repository,
# the path as given for anything else. So both chains of ancestors are walked,
# the path as given and the resolved one, nearest first, the given form first
# on a tie; a stamp is found whichever form it holds. A .git entry is looked
# for in the resolved chain, the form a repository's stamp has always had.
# Return: 0 found a stamp or a .git, 3 found neither (printed the fallback),
# 1 no such directory.
ai_sandbox_root_scan() {   # <dir> [dotgit]
    local a b fallback
    a=$(cd -- "$1" 2>/dev/null && pwd) || return 1
    b=$(cd -- "$1" 2>/dev/null && pwd -P) || return 1
    fallback=$b
    while [ -n "$a" ] || [ -n "$b" ]; do
        if [ -n "$a" ] && ai_sandbox_stamped "$a"; then printf '%s\n' "$a"; return 0; fi
        if [ -n "$b" ] && [ "$b" != "$a" ] && ai_sandbox_stamped "$b"; then printf '%s\n' "$b"; return 0; fi
        if [ "${2:-}" = dotgit ] && [ -n "$b" ] && [ -e "$b/.git" ]; then printf '%s\n' "$b"; return 0; fi
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
    ai_sandbox_root_scan "${1:-$PWD}" dotgit || rc=$?
    [ "$rc" -ne 1 ]
}

# The origin's path in a sandbox directory, and its creation: empty and bare, HEAD on
# main, made by the host before any start (a missing bind source would be created
# root-owned by Docker). Nothing is fetched here; ai-knowledge fills it.
ai_sandbox_origin_dir() {   # <sandbox dir>
    printf '%s/knowledge-origin.git' "$1"
}
ai_sandbox_make_origin() {   # <sandbox dir>
    local o
    o=$(ai_sandbox_origin_dir "$1")
    mkdir -p -- "$o" || return 1
    [ -f "$o/HEAD" ] && return 0
    ai_sandbox_host_git "$o" init -q --bare >/dev/null && ai_sandbox_host_git "$o" symbolic-ref HEAD refs/heads/main
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

# The knowledge stamp create-ai-sandbox.sh writes: AI_SANDBOX_KNOWLEDGE_STAMP
# when the sandbox runs the in-sandbox knowledge sync (knowledge configured),
# 0 when it carries the live GEMINI.md mount, nothing for a sandbox created
# before stamps existed. Stamp 1 (the host-written clone) is no longer current:
# such a sandbox has to be re-created. The generated entrypoint and doctor
# compare the same value as a literal; a test keeps the three equal.
AI_SANDBOX_KNOWLEDGE_STAMP=2
ai_sandbox_knowledge_stamp() { ai_sandbox_env_value "$1" SANDBOX_KNOWLEDGE; }

# current | stale | unstamped: whether the sandbox's compose file matches the
# host's knowledge configuration. A stale sandbox with knowledge configured
# mounts the live GEMINI.md, which now resolves to the render, read-write, or
# predates the in-sandbox sync.
ai_sandbox_knowledge_state() {
    local stamp want=0
    stamp=$(ai_sandbox_knowledge_stamp "$1")
    ai_knowledge_configured && want=$AI_SANDBOX_KNOWLEDGE_STAMP
    if [ -z "$stamp" ]; then echo unstamped
    elif [ "$stamp" = "$want" ]; then echo current
    else echo stale
    fi
}

# The one repair, told with the project dir: the stamped one, else the path
# file of a sandbox from before stamps.
ai_sandbox_recreate_command() {   # <sandbox dir>
    local project
    project=$(ai_sandbox_env_value "$1" SANDBOX_PROJECT_DIR)
    if [ -z "$project" ] && [ -f "$1/project-path" ]; then project=$(head -1 "$1/project-path"); fi
    echo "create-ai-sandbox.sh ${project:-<project dir>}"
}

# What makes a sandbox not current, said once: the knowledge stamp disagrees with the host's
# knowledge configuration (stale, unstamped), or its compose file mounts a tools directory
# that is not the installed revision's (C-INSTALL: a sandbox created before the install
# root existed, or from another tree). Prints nothing for a current sandbox.
ai_sandbox_stale_reason() {   # <sandbox dir>
    local state
    state=$(ai_sandbox_knowledge_state "$1")
    case $state in
        stale)     echo "stale: its compose file disagrees with the host's knowledge configuration" ;;
        unstamped) echo "unstamped: it was created before the knowledge stamp existed" ;;
        *) ai_sandbox_mounts_install_root "$1" || echo "stale: its compose file does not mount the installed revision's tools ($AI_SANDBOX_INSTALLED/current/tools)" ;;
    esac
}

# The start path only checks; it never rewrites a sandbox. The repair is a
# plain create-ai-sandbox.sh run for this sandbox.
ai_sandbox_require_current() {   # <sandbox dir>
    local why
    why=$(ai_sandbox_stale_reason "$1")
    [ -n "$why" ] || return 0
    {
        echo "Sandbox $(basename "$1") is $why."
        echo "It cannot be started until it has been recreated. Run on the host:"
        echo "    $(ai_sandbox_recreate_command "$1")"
    } >&2
    return 1
}

# 'compose up' pulls an image it does not find locally, and the image name of a sandbox
# ('ai-sandbox:<family>-u<uid>') exists in no registry: the start would end in a pull error
# that names no repair. Only create-ai-sandbox.sh (without --no-start) builds the image, so
# a start or restart that would need it is refused here with that command (I6, E5).
ai_sandbox_require_image() {   # <sandbox dir>
    local image
    image=$(sed -n 's/^    image: "\(.*\)"$/\1/p' "$1/docker-compose.yml" 2>/dev/null | head -1)
    [ -n "$image" ] || return 0
    docker image inspect "$image" >/dev/null 2>&1 && return 0
    # an unreachable daemon also fails the inspect: the image is not what is wrong then, and
    # 'compose up' reports the real error
    docker info >/dev/null 2>&1 || return 0
    {
        # the name is read from a file under the sandbox's directory: shown through the display rule
        echo "Sandbox $(basename "$1") needs the image $(printf '%s' "$image" | ai_sandbox_display_clean), which does not exist on this host."
        echo "It cannot be started until the image has been built. Run on the host (without --no-start):"
        echo "    $(ai_sandbox_recreate_command "$1")"
    } >&2
    return 1
}

# A running sandbox is entered whatever its stamp; this is what the host says
# about one that is not current (nothing is executed in it).
ai_sandbox_say_recreate() {   # <sandbox dir>
    local why
    why=$(ai_sandbox_stale_reason "$1")
    [ -n "$why" ] || return 0
    {
        echo "Sandbox $(basename "$1") is running and ${why%%:*}: it keeps working, but it predates the host's current setup (${why#*: }) and the host runs nothing in it."
        echo "It must be re-created (this restarts it). Run on the host when it suits you:"
        echo "    $(ai_sandbox_recreate_command "$1")"
    } >&2
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

# Kept as an empty list on purpose. A host that still has the pre-install ai-sandbox-migrate
# runs it with its own lib sourced first, then this one, and copies every file this list names
# over its installed helpers; the name must stay defined (empty) so that nothing is copied until
# the host has installed a revision. Removable once every host has (spec's deferred list).
ai_sandbox_helpers() { :; }

# The image tag of one variant. The uid suffix keeps two host users sharing one
# Docker daemon from fighting over a single tag, since the image bakes in USER_ID.
# The image family: '-gui' (the GUI applications, for a sandbox with a display) when the second argument is 'gui'.
ai_sandbox_image_name() {   # <base|docker> [gui]
    printf 'ai-sandbox:%s%s-u%s' "$1" "${2:+-$2}" "$(id -u)"
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

# C-GIT's display rule, the one filter for text that came from a place a sandbox can write
# (a branch name, a path, a commit subject, a status file) before it reaches a terminal or a
# status line: standard input to standard output, every code point of category Cc except
# newline and tab, the bidi marks (U+200E, U+200F, U+061C), embeddings, overrides and
# isolates (U+202A to U+202E, U+2066 to U+2069), and every byte that is not UTF-8, dropped.
ai_sandbox_display_clean() {
    python3 -I -c '
import sys, unicodedata
text = sys.stdin.buffer.read().decode("utf-8", "ignore")
keep = "".join(c for c in text if c in "\n\t" or (unicodedata.category(c) != "Cc"
        and c not in "\u200e\u200f\u061c" and not "\u202a" <= c <= "\u202e"
        and not "\u2066" <= c <= "\u2069"))
sys.stdout.buffer.write(keep.encode("utf-8"))' \
        || LC_ALL=C tr -cd '\11\12\40-\176'   # no usable python3: only printable ASCII, never the raw text
}

# U12 (confirm_main in ai-knowledge): standard input to standard output, every code point that draws as nothing or moves the
# cursor (categories Cc except newline and tab, Cf, Co, Cn, and the bytes that are not UTF-8)
# written as visible text, so the user sees that the pushed text holds it. Runs before
# ai_sandbox_display_clean, which would drop them unseen; its own contract stays as it is.
ai_sandbox_show_invisible() {
    python3 -I -c '
import sys, unicodedata
# Default_Ignorable_Code_Point of DerivedCoreProperties.txt, Unicode 18.0.0 (https://www.unicode.org/Public/UCD/latest/ucd/DerivedCoreProperties.txt, fetched 2026-11-14, ranges merged by script)
IGNORABLE = ((0xAD, 0xAD), (0x34F, 0x34F), (0x61C, 0x61C), (0x115F, 0x1160), (0x17B4, 0x17B5), (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x206F), (0x3164, 0x3164), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF), (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF))
text = sys.stdin.buffer.read().decode("utf-8", "surrogateescape")
out = []
for c in text:
    n = ord(c)
    if 0xDC80 <= n <= 0xDCFF:
        out.append("<0x%02X>" % (n - 0xDC00))
    elif c not in "\n\t" and (unicodedata.category(c) in ("Cc", "Cf", "Co", "Cn", "Cs") or n in (0x2028, 0x2029)
                              or any(lo <= n <= hi for lo, hi in IGNORABLE)):
        out.append("<U+%04X>" % n)
    else:
        out.append(c)
sys.stdout.buffer.write("".join(out).encode("utf-8", "surrogateescape"))' || cat
}
# I3c: a host write below a directory a sandbox can write, made without following a link
# the sandbox may have placed there (the contract is in the phase 9 plan: ops mkdir, write,
# link, hardlink, remove, copy). <root> is absolute and cannot be renamed from inside (a bind
# source, or a host directory none contains), given resolved; every component of <path> is
# entered with O_NOFOLLOW through its parent's descriptor and the last is acted on through
# its parent, a file or link by creating a temporary name and renaming over it. Exit 0 done,
# 1 refused or failed (one stderr line per refusal), 2 usage. The program is a python3 -I -c
# argument, not standard input: standard input carries what write stores.
ai_sandbox_nofollow() {   # <op> <root> <path> [<arg>...]
    local prog
    prog=$(cat <<'PY'
import fnmatch, os, re, stat, sys

PROG = "ai_sandbox_nofollow"
DIRFLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
OPS = ("mkdir", "write", "link", "hardlink", "remove", "copy")
RC = 0
SEQ = 0


def usage(msg):
    sys.stderr.write("%s: %s\n" % (PROG, msg))
    sys.exit(2)


args = sys.argv[1:]
if len(args) < 3:
    usage("usage: <op> <root> <path> [<arg>...]")
op, root, path, rest = args[0], args[1], args[2], args[3:]
if op not in OPS:
    usage("unknown op %s" % op)
if not root.startswith("/"):
    usage("root must be absolute")
comps = path.split("/")
if any(c in ("", ".", "..") for c in comps):
    usage("path must be relative, with no empty, . or .. component")
for a in args:
    if "\0" in a:
        usage("an argument holds a NUL")

mode = None
target = None
copy_src = None
delete = ignore_existing = False
excludes = []
if op in ("mkdir", "write"):
    if len(rest) > 1:
        usage("too many arguments")
    if rest:
        if not re.fullmatch("[0-7]{1,4}", rest[0]):
            usage("mode must be octal")
        mode = int(rest[0], 8)
elif op in ("link", "hardlink"):
    if len(rest) != 1 or not rest[0]:
        usage("%s takes one argument" % op)
    target = rest[0]
    if op == "hardlink" and not target.startswith("/"):
        usage("hardlink takes an absolute file")
elif op == "remove":
    if rest:
        usage("remove takes no argument")
else:
    if not rest or not rest[0]:
        usage("copy takes a directory")
    copy_src = rest[0]
    for o in rest[1:]:
        if o == "--delete":
            delete = True
        elif o == "--ignore-existing":
            ignore_existing = True
        elif o.startswith("--exclude="):
            excludes.append(o[len("--exclude="):])
        else:
            usage("unknown option %s" % o)
    if delete and ignore_existing:
        usage("--delete and --ignore-existing exclude each other")
    if excludes and not delete:
        usage("--exclude belongs to --delete")
    if any(p == "" or "/" in p for p in excludes):
        usage("an --exclude holds no slash and is not empty")


def refuse(where, why):
    global RC
    RC = 1
    sys.stderr.write("%s: refused %s %s: %s\n" % (PROG, root, where, why))


def why(e):
    return e.strerror or str(e)


def lstat(name, fd):
    try:
        return os.stat(name, dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        return None


def excluded(name):
    return any(fnmatch.fnmatchcase(name, p) for p in excludes)


def tmpname():
    global SEQ
    SEQ += 1
    return ".ai-sandbox-nofollow.%d.%d" % (os.getpid(), SEQ)


def walk(rootfd, parts, create):
    """The directory descriptor of the parent: every component entered without following a
    link. None after a refusal; "absent" when a component is missing and may stay so."""
    fd = os.dup(rootfd)
    for i, c in enumerate(parts):
        where = "/".join(parts[: i + 1])
        try:
            nfd = os.open(c, DIRFLAGS, dir_fd=fd)
        except FileNotFoundError:
            if not create:
                os.close(fd)
                return "absent"
            try:
                os.mkdir(c, 0o777, dir_fd=fd)
                nfd = os.open(c, DIRFLAGS, dir_fd=fd)
            except OSError as e:
                refuse(where, why(e))
                os.close(fd)
                return None
        except OSError:
            refuse(where, "not a directory or a link")
            os.close(fd)
            return None
        os.close(fd)
        fd = nfd
    return fd


def place(pfd, name, make, where):
    """Replace a file or link at name by what make(tmp) creates there: never a write
    through the old entry. A real directory is left alone and refused."""
    st = lstat(name, pfd)
    if st is not None and stat.S_ISDIR(st.st_mode):
        refuse(where, "a directory is there")
        return False
    tmp = tmpname()
    try:
        make(tmp)
        os.rename(tmp, name, src_dir_fd=pfd, dst_dir_fd=pfd)
    except OSError as e:
        refuse(where, why(e))
        return False
    finally:
        # rename leaves the temporary name when both names are links to one file
        try:
            os.unlink(tmp, dir_fd=pfd)
        except OSError:
            pass
    return True


def rmtree(pfd, name):
    """Remove a directory below pfd without following a link, sparing excluded names: a
    directory still holding one stays (rsync's --delete without --delete-excluded)."""
    fd = os.open(name, DIRFLAGS, dir_fd=pfd)
    spared = False
    try:
        for e in list(os.scandir(fd)):
            if excluded(e.name):
                spared = True
            elif e.is_dir(follow_symlinks=False):
                spared = rmtree(fd, e.name) or spared
            else:
                os.unlink(e.name, dir_fd=fd)
    finally:
        os.close(fd)
    if not spared:
        os.rmdir(name, dir_fd=pfd)
    return spared


def remove_any(pfd, name):
    st = lstat(name, pfd)
    if st is None:
        return
    if stat.S_ISDIR(st.st_mode):
        rmtree(pfd, name)
    else:
        os.unlink(name, dir_fd=pfd)


def set_attrs(fd, st):
    os.fchmod(fd, stat.S_IMODE(st.st_mode) & 0o777)
    os.utime(fd, ns=(st.st_atime_ns, st.st_mtime_ns))


def copy_file(srcpath, st, pfd, name, where):
    def make(tmp):
        sfd = os.open(srcpath, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            dfd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=pfd)
            try:
                while True:
                    buf = os.read(sfd, 1 << 20)
                    if not buf:
                        break
                    view = memoryview(buf)
                    while view:
                        view = view[os.write(dfd, view):]
                set_attrs(dfd, st)
            finally:
                os.close(dfd)
        finally:
            os.close(sfd)
    return place(pfd, name, make, where)


def copy_link(srcpath, pfd, name, where):
    link_target = os.readlink(srcpath)
    return place(pfd, name, lambda tmp: os.symlink(link_target, tmp, dir_fd=pfd), where)


def copy_tree(srcdir, dfd, rel):
    try:
        entries = sorted(os.scandir(srcdir), key=lambda e: e.name)
    except OSError as e:
        refuse(rel, "cannot read the source: " + why(e))
        return
    held = set()
    for e in entries:
        n = e.name
        if n.startswith(".ai-sandbox-nofollow."):
            continue
        if excluded(n):
            continue
        held.add(n)
        where = rel + "/" + n
        try:
            sst = e.stat(follow_symlinks=False)
            is_dir = stat.S_ISDIR(sst.st_mode)
            is_reg = stat.S_ISREG(sst.st_mode)
            is_lnk = stat.S_ISLNK(sst.st_mode)
            if not (is_dir or is_reg or is_lnk):
                continue
            dst = lstat(n, dfd)
            dst_dir = dst is not None and stat.S_ISDIR(dst.st_mode)
            if ignore_existing and dst is not None and not (is_dir and dst_dir):
                continue
            if is_dir:
                created = False
                if not dst_dir:
                    if dst is not None:
                        os.unlink(n, dir_fd=dfd)
                    os.mkdir(n, 0o700, dir_fd=dfd)
                    created = True
                sub = os.open(n, DIRFLAGS, dir_fd=dfd)
                try:
                    copy_tree(e.path, sub, where)
                    if created or not ignore_existing:
                        set_attrs(sub, sst)
                finally:
                    os.close(sub)
            else:
                if dst_dir:
                    if not delete:
                        refuse(where, "a directory is there")
                        continue
                    if rmtree(dfd, n):
                        refuse(where, "a directory holding an excluded entry is there")
                        continue
                if is_reg:
                    copy_file(e.path, sst, dfd, n, where)
                else:
                    copy_link(e.path, dfd, n, where)
        except OSError as err:
            refuse(where, why(err))
    if delete:
        try:
            stale = [d.name for d in os.scandir(dfd)]
        except OSError as err:
            refuse(rel, why(err))
            return
        for n in sorted(stale):
            if n in held or excluded(n):
                continue
            try:
                remove_any(dfd, n)
            except OSError as err:
                refuse(rel + "/" + n, why(err))


def main():
    try:
        rootfd = os.open(root, DIRFLAGS)
    except OSError as e:
        refuse(path, "the root is not a directory or is a link: " + why(e))
        return
    parent_parts, last = comps[:-1], comps[-1]
    if op == "write":
        data = sys.stdin.buffer.read()
    pfd = walk(rootfd, parent_parts, create=(op == "mkdir"))
    if pfd == "absent":
        if op == "remove":
            return
        refuse(path, "a directory on the way is missing")
        return
    if pfd is None:
        return
    try:
        if op == "mkdir":
            st = lstat(last, pfd)
            if st is None:
                os.mkdir(last, 0o777, dir_fd=pfd)
            elif not stat.S_ISDIR(st.st_mode):
                refuse(path, "not a directory (a link or a file)")
                return
            fd = os.open(last, DIRFLAGS, dir_fd=pfd)
            try:
                if mode is not None:
                    os.fchmod(fd, mode)
            finally:
                os.close(fd)
        elif op == "write":
            def make(tmp):
                fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                             0o666 if mode is None else 0o600, dir_fd=pfd)
                try:
                    view = memoryview(data)
                    while view:
                        view = view[os.write(fd, view):]
                    if mode is not None:
                        os.fchmod(fd, mode)
                finally:
                    os.close(fd)
            place(pfd, last, make, path)
        elif op == "link":
            place(pfd, last, lambda tmp: os.symlink(target, tmp, dir_fd=pfd), path)
        elif op == "hardlink":
            place(pfd, last, lambda tmp: os.link(target, tmp, dst_dir_fd=pfd, follow_symlinks=False), path)
        elif op == "remove":
            st = lstat(last, pfd)
            if st is None:
                return
            if stat.S_ISDIR(st.st_mode):
                refuse(path, "a directory is there")
                return
            os.unlink(last, dir_fd=pfd)
        else:
            st = lstat(last, pfd)
            if ignore_existing and st is not None and not stat.S_ISDIR(st.st_mode):
                return
            sst = os.stat(copy_src)
            created = False
            if st is None or not stat.S_ISDIR(st.st_mode):
                if st is not None:
                    os.unlink(last, dir_fd=pfd)
                os.mkdir(last, 0o700, dir_fd=pfd)
                created = True
            fd = os.open(last, DIRFLAGS, dir_fd=pfd)
            try:
                copy_tree(copy_src, fd, path)
                if created or not ignore_existing:
                    set_attrs(fd, sst)
            finally:
                os.close(fd)
    except OSError as e:
        refuse(path, why(e))


try:
    main()
except BrokenPipeError:
    RC = 1
sys.exit(RC)
PY
)
    python3 -I -c "$prog" "$@"
}

# C-INSTALL: a host entry point calls this first, with its own path. 0 when the directory
# holding it, links resolved, is not one a sandbox can write (ai_sandbox_writable_path);
# else says so with the install command and returns 3, the status ai_sandbox_host_git gives
# for the same reason. <top> is the directory holding bin/ai, where --from points.
ai_sandbox_refuse_writable_self() {   # <own path>
    local own dir top
    own=$(readlink -f -- "$1" 2>/dev/null) && [ -n "$own" ] || own=$1
    dir=${own%/*}; [ -n "$dir" ] || dir=/
    ai_sandbox_writable_path "$dir" || return 0
    top=$dir
    while [ "$top" != / ] && [ ! -d "$top/bin/ai" ]; do
        case $top in */*) top=${top%/*}; [ -n "$top" ] || top=/ ;; *) break ;; esac
    done
    [ -d "$top/bin/ai" ] || top=$dir
    {
        echo "$(basename "$own"): refusing to run from $dir: a sandbox can write it"
        echo "Install a revision and run it from ~/.ai-sandbox/bin: ai-sandbox-install --from $top"
    } >&2
    return 3
}

# Whether <sandbox dir>'s compose file mounts the installed revision's tools, as
# create-ai-sandbox.sh writes it: C-INSTALL's `current`, not a path of any one tree.
ai_sandbox_mounts_install_root() {   # <sandbox dir>
    grep -qF -- "\"$AI_SANDBOX_INSTALLED/current/tools:" "$1/docker-compose.yml" 2>/dev/null
}

# The user's ~/.bashrc block that puts ~/.ai-sandbox/bin on PATH. Its markers and text
# are fixed on purpose (an existing block is left exactly as it is, wherever it sits in
# the file); written by ai-sandbox-install, the one writer. An older block of another
# text, and the unmarked block of earlier versions, are replaced by this one at the end.
AI_SANDBOX_BASHRC_BEGIN='# >>> dev-tools ai-sandbox helpers >>>'
AI_SANDBOX_BASHRC_END='# <<< dev-tools ai-sandbox helpers <<<'
# Whether the writer below can read and rewrite <bashrc file>, or create it.
ai_sandbox_bashrc_usable() {   # <bashrc file>
    if [ -e "$1" ]; then [ -r "$1" ] && [ -w "$1" ]; else [ -w "$(dirname -- "$1")" ]; fi
}
ai_sandbox_write_bashrc_block() {   # <bashrc file>
    local helpers='# Helpers for dev-tools/bin/ai/create-ai-sandbox.sh live in ~/.ai-sandbox/bin.
case ":$PATH:" in
    *":$HOME/.ai-sandbox/bin:"*) ;;
    *) PATH="$HOME/.ai-sandbox/bin:$PATH" ;;
esac'
    touch -- "$1"
    SB_BEGIN="$AI_SANDBOX_BASHRC_BEGIN" SB_END="$AI_SANDBOX_BASHRC_END" SB_HELPERS="$helpers" \
    python3 -I - "$1" <<'PYEOF'
import os, re, sys
path  = sys.argv[1]
begin = os.environ["SB_BEGIN"]
end   = os.environ["SB_END"]
block = begin + "\n" + os.environ["SB_HELPERS"] + "\n" + end

# surrogateescape: a byte that is not UTF-8 outside the block is read and written back as it was
content = open(path, encoding="utf-8", errors="surrogateescape").read()
if block in content:
    sys.exit(0)
# Remove this script's marked block, and the unmarked block written by earlier
# versions of the script.
content = re.sub(r"\n*" + re.escape(begin) + r".*?" + re.escape(end) + r"\n*",
                 "\n", content, flags=re.DOTALL)
content = re.sub(r"\n*# Antigravity Sandbox Helper\n.*?\nfunction ai-sandbox-stop\(\)\s*\{.*?\n\}\n",
                 "\n", content, flags=re.DOTALL)
content = content.rstrip("\n")
open(path, "w", encoding="utf-8", errors="surrogateescape").write(content + "\n\n" + block + "\n")
PYEOF
}

# C-GIT, confined side: git run on a tree a sandbox can write, inside a
# throwaway container of the sandbox image: no network, no entrypoint, the
# host's uid, <root> (resolved) the only mount, read-only and at its own path,
# no variable of the caller or of any .env reaches it, nothing is pulled.
# <subdirectory> of <root> is the working directory. Standard input and output
# are git's; so is the exit status, except 125 (no image, or docker could not
# start the container) and 124 (AI_SANDBOX_GIT_TIMEOUT expired, and the named
# container is removed so that nothing keeps running).
# A caller that serves a fetch (--upload-pack) gets exit 128 from git when this
# fails, not 125: it has to find out about a missing image by itself.
ai_sandbox_confined_git() {   # <root> <subdirectory> <git args...>
    local root sub=$2 variant gui tag="" name rc=0
    root=$(readlink -m -- "$1" 2>/dev/null) && [ -n "$root" ] || { echo "ai_sandbox_confined_git: no such root: $1" >&2; return 125; }
    shift 2
    command -v docker >/dev/null 2>&1 || { echo "ai_sandbox_confined_git: docker is not available" >&2; return 125; }
    for variant in base docker; do
        for gui in "" gui; do
            if docker image inspect "$(ai_sandbox_image_name "$variant" $gui)" >/dev/null 2>&1; then
                tag=$(ai_sandbox_image_name "$variant" $gui); break 2
            fi
        done
    done
    [ -n "$tag" ] || { echo "ai_sandbox_confined_git: no sandbox image exists yet (create-ai-sandbox.sh builds it)" >&2; return 125; }
    name="ai-sandbox-git-$$-$RANDOM"
    set -- docker run --rm -i --pull never --network none --user "$(id -u):$(id -g)" \
        --name "$name" -v "$root:$root:ro" -w "$root/$sub" --entrypoint git "$tag" "$@"
    if [ -n "${AI_SANDBOX_GIT_TIMEOUT:-}" ]; then
        timeout -k 5 "$AI_SANDBOX_GIT_TIMEOUT" "$@" || rc=$?
        if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
            docker rm -f "$name" >/dev/null 2>&1 || true
            return 124
        fi
        return "$rc"
    fi
    "$@"
}

# C-GIT, every fetch from a tree a sandbox can write. The host-owned <repository> is
# an ordinary git client of an untrusted server: the remote program of the fetch is
# ai_sandbox_confined_git (upload-pack, in the throwaway container), the URL is
# <root>/<subdirectory>, and no tag is followed, so the fetch changes refs of
# <repository> only at the destinations of its refspecs: each <ref pattern>
# refs/<name>/* lands as <prefix>/<name>/*, pruned below it. <prefix> is a full ref
# name below refs/, outside refs/heads/ and refs/tags/, and holds refs of this one
# tree only. Exit: ai_sandbox_host_git's (3 for a sandbox-writable <repository>), 125
# when no sandbox image exists or the container cannot start, 124 when
# AI_SANDBOX_GIT_TIMEOUT expires, 2 for arguments that do not fit the contract.
# git answers 128 when its remote program fails, whatever that program's own status
# was, so the program records its status in a file this function reads afterwards.
ai_sandbox_confined_fetch() {   # <repository> <prefix> <root> <subdirectory> <ref pattern>...
    local repo=$1 prefix=$2 root=$3 sub=$4 pat name real tmpd stat prog rc=0 crc outer lib
    local -a specs=()
    shift 4
    case $prefix in
        refs/heads|refs/heads/*|refs/tags|refs/tags/*|refs/|"") echo "ai_sandbox_confined_fetch: bad prefix: $prefix" >&2; return 2 ;;
        refs/*) ai_sandbox_host_git - check-ref-format "$prefix" 2>/dev/null || { echo "ai_sandbox_confined_fetch: bad prefix: $prefix" >&2; return 2; } ;;
        *) echo "ai_sandbox_confined_fetch: bad prefix: $prefix" >&2; return 2 ;;
    esac
    case $sub in ""|/*|..|../*|*/..|*/../*) echo "ai_sandbox_confined_fetch: bad subdirectory: $sub" >&2; return 2 ;; esac
    [ $# -gt 0 ] || { echo "ai_sandbox_confined_fetch: no ref pattern" >&2; return 2; }
    for pat in "$@"; do
        name=${pat#refs/}; name=${name%/\*}
        case $pat in
            refs/*/\*) ;;
            *) echo "ai_sandbox_confined_fetch: bad ref pattern: $pat" >&2; return 2 ;;
        esac
        case $name in ""|*[!A-Za-z0-9._-]*|.*) echo "ai_sandbox_confined_fetch: bad ref pattern: $pat" >&2; return 2 ;; esac
        specs+=("+refs/$name/*:$prefix/$name/*")
    done
    real=$(readlink -m -- "$root" 2>/dev/null) && [ -n "$real" ] || { echo "ai_sandbox_confined_fetch: no such root: $root" >&2; return 125; }
    lib=$(readlink -f -- "${BASH_SOURCE[0]}")
    tmpd=$(mktemp -d) || return 125
    stat="$tmpd/status"
    prog="AI_SANDBOX_FETCH_STATUS=$(printf '%q' "$stat")"
    outer=${AI_SANDBOX_GIT_TIMEOUT:-}
    if [ -n "$outer" ]; then
        prog="$prog AI_SANDBOX_GIT_TIMEOUT=$(printf '%q' "$outer")"
        # a backstop only: the container's own limit fires first and is the one reported
        case $outer in *[!0-9]*) ;; *) outer=$((outer + 10)) ;; esac
    fi
    prog="$prog bash -c $(printf '%q' '. "$0"; ai_sandbox_confined_git "$@"; rc=$?; printf %s "$rc" > "$AI_SANDBOX_FETCH_STATUS"; exit "$rc"')"
    prog="$prog $(printf '%q %q %q upload-pack' "$lib" "$real" "$sub")"
    AI_SANDBOX_GIT_TIMEOUT=$outer ai_sandbox_host_git "$repo" fetch -q --no-tags --prune \
        --upload-pack="$prog" "$real/$sub" "${specs[@]}" || rc=$?
    if [ "$rc" -ne 0 ] && [ -s "$stat" ]; then
        crc=$(cat "$stat")
        case $crc in 124|125) rc=$crc ;; esac
    fi
    rm -rf -- "$tmpd"
    return "$rc"
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
status
antigravity-data
antigravity-ide-data
claude-data
gcloud
cache
npm
DIRS
}

# One entry of ai_sandbox_state_dirs, made in a sandbox directory: a top-level entry is a bind
# source itself; a nested one (.claude/projects) lies below one, where a sandbox may have put a
# link, so it is made without following it (a refusal is one stderr line and exit 1).
ai_sandbox_make_state_dir() {   # <sandbox dir> <entry>
    case $2 in
        */*) mkdir -p "$1/${2%%/*}" && ai_sandbox_nofollow mkdir "$(readlink -f "$1")/${2%%/*}" "${2#*/}" ;;
        *) mkdir -p "$1/$2" ;;
    esac
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
    printf '%s' "$out" | python3 -I -c '
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

# ai_sandbox_seed_table (the phase 7 plan's contract, as reviewed)
#   The seed's allow list (replaces ai_sandbox_seed_paths and ai_sandbox_seed_excludes).
#   One row per line, nothing else printed:
#     <class>|<path under $HOME on the host>|<path under the sandbox directory>|<how>
#   class  settings  copied by the first seed of every sandbox and by 'ai-sandbox-account reset'
#          login     copied in addition only for a sandbox in the host mode: by its first seed
#                    and by 'ai-sandbox-account refresh'; removed by 'ai-sandbox-account reset'
#   paths  relative; no empty, '.' or '..' component; a component may hold '*', matched as a
#          shell glob against the names at that level on the host, the same names used in the
#          sandbox directory. A row whose host path is absent copies nothing. Nothing that no
#          row names is copied.
#   how    whole  the file, or the directory with everything below it, links as links
#          links  only the symbolic links directly in the directory, as links; nothing else in it
#          json   a JSON file (comments and trailing commas accepted) written with the root's type
#                 and only the key paths ai_sandbox_seed_keys lists for the row; {} or [] when
#                 none is present
#          xml    an XML file written with its root element and only those children whose name
#                 attribute ai_sandbox_seed_keys lists for the row
#          A json or xml file that does not parse is not written: one stderr line naming the
#          row, and the copy goes on.
#   .claude.json is the login row 'login|.claude.json|.claude.json|json'. Without that row the
#   sandbox's .claude.json is {}.
# reads-outside: the layouts of the host's tool stores, as the user's tools write them: Claude Code
# (~/.claude, ~/.claude.json), Codex (~/.codex), Gemini CLI and Antigravity CLI (~/.gemini),
# Claude Desktop (~/.config/Claude), Antigravity and Antigravity IDE (~/.config/Antigravity,
# ~/.config/Antigravity IDE) and JetBrains (~/.config/JetBrains/<product>); a tool that renames a
# file here silently stops it arriving, so change a row only with a look at that tool's layout.
ai_sandbox_seed_table() {
    cat <<'SEED'
settings|.claude/settings.json|.claude/settings.json|json
settings|.gemini/settings.json|.gemini/settings.json|json
settings|.gemini/antigravity-cli/settings.json|.gemini/antigravity-cli/settings.json|json
settings|.claude/skills|.claude/skills|links
settings|.codex/skills|.codex/skills|links
settings|.gemini/skills|.gemini/skills|links
settings|.codex/AGENTS.md|.codex/AGENTS.md|whole
settings|.gemini/config/AGENTS.md|.gemini/config/AGENTS.md|whole
settings|.config/Antigravity/User/settings.json|antigravity-data/User/settings.json|json
settings|.config/Antigravity/User/keybindings.json|antigravity-data/User/keybindings.json|json
settings|.config/Antigravity IDE/User/settings.json|antigravity-ide-data/User/settings.json|json
settings|.config/Antigravity IDE/User/keybindings.json|antigravity-ide-data/User/keybindings.json|json
settings|.config/JetBrains/*/codestyles|jetbrains-config/*/codestyles|whole
settings|.config/JetBrains/*/colors|jetbrains-config/*/colors|whole
settings|.config/JetBrains/*/keymaps|jetbrains-config/*/keymaps|whole
settings|.config/JetBrains/*/disabled_plugins.txt|jetbrains-config/*/disabled_plugins.txt|whole
settings|.config/JetBrains/*/options/editor.xml|jetbrains-config/*/options/editor.xml|xml
settings|.config/JetBrains/*/options/editor-font.xml|jetbrains-config/*/options/editor-font.xml|xml
settings|.config/JetBrains/*/options/console-font.xml|jetbrains-config/*/options/console-font.xml|xml
settings|.config/JetBrains/*/options/terminal-font.xml|jetbrains-config/*/options/terminal-font.xml|xml
settings|.config/JetBrains/*/options/laf.xml|jetbrains-config/*/options/laf.xml|xml
settings|.config/JetBrains/*/options/ui.lnf.xml|jetbrains-config/*/options/ui.lnf.xml|xml
settings|.config/JetBrains/*/options/colors.scheme.xml|jetbrains-config/*/options/colors.scheme.xml|xml
settings|.config/JetBrains/*/options/keymapFlags.xml|jetbrains-config/*/options/keymapFlags.xml|xml
login|.claude/.credentials.json|.claude/.credentials.json|whole
login|.claude.json|.claude.json|json
login|.codex/auth.json|.codex/auth.json|whole
login|.gemini/oauth_creds.json|.gemini/oauth_creds.json|whole
login|.gemini/google_accounts.json|.gemini/google_accounts.json|whole
login|.gemini/antigravity-cli/antigravity-oauth-token|.gemini/antigravity-cli/antigravity-oauth-token|whole
login|.config/Claude/Cookies|claude-data/Cookies|whole
login|.config/Claude/Local Storage|claude-data/Local Storage|whole
login|.config/Claude/IndexedDB|claude-data/IndexedDB|whole
login|.config/Claude/Session Storage|claude-data/Session Storage|whole
login|.config/Claude/Local State|claude-data/Local State|whole
login|.config/Claude/Trust Tokens|claude-data/Trust Tokens|whole
login|.config/Claude/config.json|claude-data/config.json|whole
login|.config/Antigravity/Cookies|antigravity-data/Cookies|whole
login|.config/Antigravity/Local Storage|antigravity-data/Local Storage|whole
login|.config/Antigravity/Session Storage|antigravity-data/Session Storage|whole
login|.config/Antigravity/Trust Tokens|antigravity-data/Trust Tokens|whole
login|.config/Antigravity/User/globalStorage/state.vscdb|antigravity-data/User/globalStorage/state.vscdb|whole
login|.config/Antigravity IDE/Cookies|antigravity-ide-data/Cookies|whole
login|.config/Antigravity IDE/Local Storage|antigravity-ide-data/Local Storage|whole
login|.config/Antigravity IDE/Session Storage|antigravity-ide-data/Session Storage|whole
login|.config/Antigravity IDE/Trust Tokens|antigravity-ide-data/Trust Tokens|whole
login|.config/Antigravity IDE/User/globalStorage/state.vscdb|antigravity-ide-data/User/globalStorage/state.vscdb|whole
login|.gemini/config/mcp_config.json|.gemini/config/mcp_config.json|whole
login|.gemini/antigravity/mcp_config.json|.gemini/antigravity/mcp_config.json|whole
login|.gemini/antigravity-ide/mcp_config.json|.gemini/antigravity-ide/mcp_config.json|whole
login|.config/Claude/claude_desktop_config.json|claude-data/claude_desktop_config.json|whole
login|.config/JetBrains/*/*.key|jetbrains-config/*/*.key|whole
login|.config/JetBrains/*/*.license|jetbrains-config/*/*.license|whole
SEED
}

# ai_sandbox_seed_keys <host path of a json or xml row, as the table writes it>
#   (the phase 7 plan's contract, as reviewed)
#   The row's key allow-list, one entry per line, nothing else printed. A key no entry reaches
#   is dropped.
#   json  a key path: components separated by '/'; a component is a key name, a shell glob over
#         key names ('editor.*' matches the top-level key 'editor.fontSize'), or '[]' for every
#         element of an array. The value at the path is kept whole.
#   xml   the name attribute of a child of the root element (a JetBrains 'component').
# An entry is added only with the user's word.
# reads-outside: the key names of the tools' settings files (Claude Code settings.json, Gemini CLI
# settings.json, agy settings.json, the editors' settings.json and keybindings.json, the JetBrains
# options/*.xml components): a tool that renames a key stops it arriving.
ai_sandbox_seed_keys() {   # <host path of a json or xml row, as the table writes it>
    case $1 in
        .claude/settings.json) cat <<'K'
model
modelSettings
language
theme
editorMode
autoCompactEnabled
idleCompaction
autoContinueAtUsageLimit
agentPushNotifEnabled
inputNeededNotifEnabled
remoteControlAtStartup
voice
voiceEnabled
K
        ;;
        .gemini/settings.json) cat <<'K'
general/enablePromptCompletion
general/previewFeatures
security/auth/selectedType
K
        ;;
        .gemini/antigravity-cli/settings.json) echo colorScheme ;;
        '.config/Antigravity/User/settings.json'|'.config/Antigravity IDE/User/settings.json') cat <<'K'
editor.*
diffEditor.*
workbench.colorTheme
workbench.iconTheme
files.autoSave
terminal.integrated.fontSize
debug.console.fontSize
scm.inputFontSize
git.autofetch
git.confirmSync
json.schemaDownload.enable
redhat.telemetry.enabled
extensions.ignoreRecommendations
markdown-preview-enhanced.previewTheme
python.languageServer
playwright.reuseBrowser
playwright.showTrace
claudeCode.preferredLocation
K
        ;;
        '.config/Antigravity/User/keybindings.json'|'.config/Antigravity IDE/User/keybindings.json') printf '%s\n' '[]/key' '[]/command' '[]/when' ;;
        .config/JetBrains/\*/options/editor.xml) printf '%s\n' EditorSettings CodeInsightSettings ;;
        .config/JetBrains/\*/options/editor-font.xml) echo DefaultFont ;;
        .config/JetBrains/\*/options/console-font.xml) echo ConsoleFont ;;
        .config/JetBrains/\*/options/terminal-font.xml) echo TerminalFontOptions ;;
        .config/JetBrains/\*/options/laf.xml) echo LafManager ;;
        .config/JetBrains/\*/options/ui.lnf.xml) echo UISettings ;;
        .config/JetBrains/\*/options/colors.scheme.xml) echo EditorColorsManagerImpl ;;
        .config/JetBrains/\*/options/keymapFlags.xml) echo KeymapFlagsStorage ;;
        .claude.json) printf '%s\n' oauthAccount userID hasCompletedOnboarding ;;
    esac
}

# Expands the globs of a table row under <base>: NUL-separated pairs <primary path> <secondary
# path>, one pair per match that exists, the k-th '*' component of the secondary path taking the
# name the k-th one of the primary matched. Run on the host side with the host path first, on the
# sandbox side with the sandbox path first.
ai_sandbox_seed_expand() {   # <base dir> <primary path> <secondary path>
    python3 -I -c '
import fnmatch, os, sys
base, prim, sec = sys.argv[1:4]
pc, sc = prim.split("/"), sec.split("/")
wild = lambda c: any(ch in c for ch in "*?[")
nsec = [i for i, c in enumerate(sc) if wild(c)]
res = [("", [])]
for c in pc:
    nxt = []
    for path, caps in res:
        here = os.path.join(base, path) if path else base
        if wild(c):
            try:
                names = sorted(os.listdir(here))
            except OSError:
                continue
            for n in names:
                if (n.startswith(".") and not c.startswith(".")) or not fnmatch.fnmatchcase(n, c):
                    continue
                nxt.append((path + "/" + n if path else n, caps + [n]))
        else:
            nxt.append((path + "/" + c if path else c, caps))
    res = nxt
for path, caps in res:
    if not os.path.lexists(os.path.join(base, path)):
        continue
    out = list(sc)
    for i, k in zip(nsec, range(len(caps))):
        out[i] = caps[k]
    sys.stdout.write(path + "\0" + "/".join(out) + "\0")
' "$@"
}

# The existing sandbox-side paths of the rows of a class (NUL-separated), for the callers that back
# up or remove them; a glob is expanded against the sandbox directory, as it is there.
ai_sandbox_seed_sandbox_paths() {   # <sandbox dir> <class> [tools|idea]
    local c host sb how h s
    while IFS='|' read -r c host sb how; do
        [ "$c" = "$2" ] || continue
        ai_sandbox_seed_in_scope "$sb" "${3:-all}" || continue
        while IFS= read -r -d '' s && IFS= read -r -d '' h; do
            printf '%s\0' "$s"
        done < <(ai_sandbox_seed_expand "$1" "$sb" "$host")
    done < <(ai_sandbox_seed_table)
}

# 0 when a sandbox path belongs to the scope: tools (everything but the IDE's settings), idea
# (only jetbrains-config) or all.
ai_sandbox_seed_in_scope() {   # <sandbox path> <scope>
    case $2 in
        idea) case $1 in jetbrains-config/*) return 0 ;; *) return 1 ;; esac ;;
        tools) case $1 in jetbrains-config/*) return 1 ;; *) return 0 ;; esac ;;
        *) return 0 ;;
    esac
}

# A json or xml file cut to its allowed keys, on standard output; 1 when it does not parse.
# JSON may hold comments and trailing commas (the editors' files do).
ai_sandbox_seed_filter() {   # <json|xml> <file> <key>...
    python3 -I -c '
import fnmatch, json, re, sys
kind, path, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
MISSING = object()
try:
    if kind == "xml":
        import xml.etree.ElementTree as ET
        root = ET.parse(path).getroot()
        for ch in list(root):
            if ch.get("name") not in keys:
                root.remove(ch)
        out = ET.tostring(root, encoding="unicode") + "\n"
        doc = None
    else:
        S = r"(\"(?:\\.|[^\"\\])*\")"
        t = re.sub(S + r"|//[^\n]*|/\*.*?\*/", lambda m: m.group(1) or "", open(path, encoding="utf-8-sig").read(), flags=re.S)
        doc = json.loads(re.sub(S + r"|,(\s*[}\]])", lambda m: m.group(1) or m.group(2), t))
        if not isinstance(doc, (dict, list)):
            raise ValueError("root")
except Exception:
    sys.exit(1)

def keep(v, paths):
    if any(not p for p in paths):
        return v
    if isinstance(v, dict):
        out = {}
        for k, x in v.items():
            sub = [p[1:] for p in paths if p[0] != "[]" and fnmatch.fnmatchcase(k, p[0])]
            if sub:
                r = keep(x, sub)
                if r is not MISSING:
                    out[k] = r
        return out if out else MISSING
    if isinstance(v, list):
        sub = [p[1:] for p in paths if p[0] == "[]"]
        out = []
        if sub:
            for x in v:
                r = keep(x, sub)
                if r is not MISSING:
                    out.append(r)
        return out if out else MISSING
    return MISSING

if doc is None:
    sys.stdout.write(out)
else:
    r = keep(doc, [tuple(k.split("/")) for k in keys])
    if r is MISSING:
        r = {} if isinstance(doc, dict) else []
    sys.stdout.write(json.dumps(r, indent=2, ensure_ascii=False) + "\n")
' "$@"
}

# Copies the rows of one class from $HOME into a sandbox directory, every write below it through
# ai_sandbox_nofollow (a refusal is one stderr line and the copy goes on). Prints, one per line,
# the sandbox path of each row written, so a caller can log the logins; a directory row that
# copy refused in part (it writes the other entries) is printed as '<path><TAB>partial', because
# what it did write is a copied login all the same (the log must not understate). scope: tools (all but the
# IDE's settings), idea (only those) or all. A json or xml file that does not parse is not
# written: one stderr line naming it.
ai_sandbox_seed_copy() {   # <sandbox dir> <settings|login> [tools|idea]
    local root c host sb how h s mode parent name target out
    local -a keys
    root=$(readlink -f "$1") || return 1
    while IFS='|' read -r c host sb how; do
        [ "$c" = "$2" ] || continue
        ai_sandbox_seed_in_scope "$sb" "${3:-all}" || continue
        mapfile -t keys < <(ai_sandbox_seed_keys "$host")
        while IFS= read -r -d '' h && IFS= read -r -d '' s; do
            parent=${s%/*}
            if [ "$parent" != "$s" ]; then ai_sandbox_nofollow mkdir "$root" "$parent" || continue; fi
            case $how in
                json|xml)
                    if ! out=$(ai_sandbox_seed_filter "$how" "$HOME/$h" "${keys[@]}"); then
                        echo "ai-sandbox: $h is not copied: it does not parse as $how" >&2
                        continue
                    fi
                    mode=$(stat -c %a "$HOME/$h" 2>/dev/null || echo 600)
                    printf '%s\n' "$out" | ai_sandbox_nofollow write "$root" "$s" "$mode" || continue ;;
                links)
                    [ -d "$HOME/$h" ] || continue
                    ai_sandbox_nofollow mkdir "$root" "$s" || continue
                    while IFS= read -r -d '' target; do
                        name=${target##*/}
                        ai_sandbox_nofollow link "$root" "$s/$name" "$(readlink "$target")" || true
                    done < <(find "$HOME/$h" -mindepth 1 -maxdepth 1 -type l -print0) ;;
                *)
                    if [ -d "$HOME/$h" ]; then
                        ai_sandbox_nofollow copy "$root" "$s" "$HOME/$h" --delete || { printf '%s\tpartial\n' "$s"; continue; }
                    elif [ -f "$HOME/$h" ]; then
                        mode=$(stat -c %a "$HOME/$h" 2>/dev/null || echo 600)
                        ai_sandbox_nofollow write "$root" "$s" "$mode" < "$HOME/$h" || continue
                    else
                        continue
                    fi ;;
            esac
            printf '%s\n' "$s"
        done < <(ai_sandbox_seed_expand "$HOME" "$host" "$sb")
    done < <(ai_sandbox_seed_table)
    return 0
}
