#!/usr/bin/env bash
# create-ai-sandbox.sh and the installed revision (C-INSTALL): it mounts the install root's
# tools, refuses before writing anything when none is installed, runs the commands beside
# itself, writes nothing the host's config or PATH depend on, and runs from a read-only tree.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

T=$(mktemp -d)
create() { bash "$1/create-ai-sandbox.sh" --display=none --no-start "${@:2}"; }

# ---------------------------------------------------------------------------
# O8: the compose file mounts the install root's tools and names no path of the tree create ran from
# ---------------------------------------------------------------------------
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"; proj="$tmp/work/proj"; mkdir -p "$proj"
before_cfg=$(cat "$AI_SANDBOX_ROOT/config")
rm "$AI_SANDBOX_ROOT/bin"   # create must not need, or make, the PATH entry
create "$REPO_ROOT/bin/ai" "$proj" >"$tmp/out" 2>&1; rc=$?
assert_eq "create under an install: exit 0" "$rc" 0
compose="$(ai_sandbox_dir_for "$proj")/docker-compose.yml"
assert_eq "the compose file holds exactly one tools mount" "$(grep -c '/tools:' "$compose")" 1
assert_contains "and it is the install root's" "$(cat "$compose")" \
    "\"$AI_SANDBOX_ROOT/installed/current/tools:$HOME/tools:ro\""
assert_eq "no path of the tree create ran from is in it" "$(grep -cF "$REPO_ROOT" "$compose")" 0
assert_eq "the config is byte-identical (a budget only)" "$(cat "$AI_SANDBOX_ROOT/config")" "$before_cfg"
assert_no_file "create made no ~/.ai-sandbox/bin" "$AI_SANDBOX_ROOT/bin"
assert_eq "create did not touch ~/.bashrc" "$([ -e "$HOME/.bashrc" ] && echo present || echo absent)" absent
assert_contains "the usage names ai-sandbox-install" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)" "ai-sandbox-install"
assert_eq "and does not say create installs the commands" \
    "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1 | grep -c 'installed into ~/.ai-sandbox/bin')" 0

# no installed revision: refused before anything is written
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"; proj="$tmp/work/proj"; mkdir -p "$proj"
rm "$AI_SANDBOX_ROOT/installed/current"
create "$REPO_ROOT/bin/ai" "$proj" >"$tmp/out" 2>&1; rc=$?
assert_eq "no installed revision: exit 1" "$rc" 1
assert_contains "the message names ai-sandbox-install" "$(cat "$tmp/out")" "ai-sandbox-install"
assert_eq "no sandbox directory was made" "$(ls -d "$AI_SANDBOX_ROOT"/*-agent 2>/dev/null | wc -l | tr -d ' ')" 0
assert_eq "no project-path" "$(find "$AI_SANDBOX_ROOT" -name project-path | wc -l | tr -d ' ')" 0
assert_eq "docker was not asked anything" "$(cat "$DOCKER_STUB_LOG")" ""
# a revision directory without tools is no revision either
mkdir -p "$AI_SANDBOX_ROOT/installed/rev/empty"; ln -s rev/empty "$AI_SANDBOX_ROOT/installed/current"
create "$REPO_ROOT/bin/ai" "$proj" >"$tmp/out" 2>&1; rc=$?
assert_eq "a revision without tools: exit 1" "$rc" 1

# a symlinked directory: the commands create runs are those of the link's target
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"; proj="$tmp/work/proj"; mkdir -p "$proj"
mkdir -p "$T/target"; cp -a "$REPO_ROOT/bin/ai" "$T/target/ai"; chmod -R u+w "$T/target"
ln -s "$T/target/ai" "$T/link"
CALLS="$tmp/calls"; export CALLS; : > "$CALLS"
for c in ai-sandbox-migrate ai-knowledge; do
    printf '#!/bin/sh\necho "%s $*" >> "$CALLS"\n' "$c" > "$T/target/ai/$c"; chmod +x "$T/target/ai/$c"
done
mkdir -p "$AI_SANDBOX_ROOT/knowledge"; : > "$AI_SANDBOX_ROOT/knowledge/config"   # knowledge configured: create runs sync and render
# commands of another tree, where the old install copies were, that create must not run
rm "$AI_SANDBOX_ROOT/bin"; mkdir "$AI_SANDBOX_ROOT/bin"
for c in ai-sandbox-migrate ai-knowledge ai-sandbox-extensions; do
    printf '#!/bin/sh\necho "SOMEWHERE ELSE %s" >> "$CALLS"\n' "$c" > "$AI_SANDBOX_ROOT/bin/$c"; chmod +x "$AI_SANDBOX_ROOT/bin/$c"
done
create "$T/link" "$proj" >"$tmp/out" 2>&1; rc=$?
assert_eq "create through a symlinked directory: exit 0" "$rc" 0
assert_contains "ran the target's migrate" "$(cat "$CALLS")" "ai-sandbox-migrate"
assert_contains "and the target's knowledge sync" "$(cat "$CALLS")" "ai-knowledge sync"
assert_contains "and the target's knowledge render" "$(cat "$CALLS")" "ai-knowledge render"
assert_eq "and nothing from anywhere else" "$(grep -c 'SOMEWHERE ELSE' "$CALLS")" 0
assert_eq "no create module or command is named through ~/.ai-sandbox/bin" \
    "$(grep -rn 'AI_SANDBOX_ROOT/bin' "$REPO_ROOT/bin/ai/create.d" "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" | wc -l | tr -d ' ')" 0

# ---------------------------------------------------------------------------
# O16: from a read-only tree, two creates in one HOME both work, and the build context is
# the one a writable tree gives
# ---------------------------------------------------------------------------
ctx_summary() {   # <dir>: names, modes and bytes of the build context, HOME-independent
    (cd "$1" && find . -printf '%m %p\n' | LC_ALL=C sort; find . -type f -exec sha256sum {} + | LC_ALL=C sort)
}
mkdir -p "$T/ro"; cp -a "$REPO_ROOT/bin" "$T/ro/bin"; chmod -R a-w "$T/ro"
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"; proj="$tmp/work/proj"; mkdir -p "$proj"
create "$T/ro/bin/ai" "$proj" >"$tmp/out1" 2>&1; rc1=$?
create "$T/ro/bin/ai" "$proj" >"$tmp/out2" 2>&1; rc2=$?
assert_eq "the first create from a read-only tree: exit 0" "$rc1" 0
assert_eq "the second create from it: exit 0" "$rc2" 0
ro_ctx=$(ctx_summary "$AI_SANDBOX_ROOT/image/build")
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"; proj="$tmp/work/proj"; mkdir -p "$proj"
create "$REPO_ROOT/bin/ai" "$proj" >"$tmp/out1" 2>&1
create "$REPO_ROOT/bin/ai" "$proj" >"$tmp/out2" 2>&1
assert_eq "the build context equals the one a writable tree gives (names, modes, bytes)" \
    "$(ctx_summary "$AI_SANDBOX_ROOT/image/build")" "$ro_ctx"
assert_ne "and it is not empty" "$ro_ctx" ""
assert_eq "nothing in the build context is read-only for its owner" \
    "$(find "$AI_SANDBOX_ROOT/image/build" ! -perm -u+w | wc -l | tr -d ' ')" 0

chmod -R u+w "$T/ro"; rm -rf "$T"
finish
