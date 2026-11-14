#!/usr/bin/env bash
# No program of the toolchain reads where a checkout lives (C-INSTALL): ai-knowledge finds its
# seed beside itself, the status line and handover-ready find tools/ beside themselves (the
# image's copy: ~/tools), and a config line naming a checkout is not read.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

T=$(mktemp -d)
copy_ai() {   # <destination root>: a writable copy of bin/ai at <root>/bin/ai
    mkdir -p "$1/bin"; cp -a "$REPO_ROOT/bin/ai" "$1/bin/ai"; chmod -R u+w "$1"
}

# ---------------------------------------------------------------------------
# O10 / O16 (init half): ai-knowledge init seeds from beside itself, writable for its owner
# ---------------------------------------------------------------------------
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
printf 'DEV_TOOLS_DIR=%s\n' "$REPO_ROOT" >> "$AI_SANDBOX_ROOT/config"   # a checkout with a seed, named by the config
copy_ai "$T/noseed"; rm -rf "$T/noseed/bin/ai/knowledge-seed"
remote="$tmp/remote.git"; git init -q --bare "$remote"
git config --global user.email t@example.com; git config --global user.name t
out=$(bash "$T/noseed/bin/ai/ai-knowledge" init "file://$remote" 2>&1); rc=$?
assert_ne "init from a copy without a seed fails" "$rc" 0
assert_contains "and names the install" "$out" "ai-sandbox-install"
assert_eq "and not the recorded checkout" "$(printf '%s' "$out" | grep -c 'DEV_TOOLS_DIR')" 0
assert_eq "nothing was seeded from the checkout the config names" "$(git -C "$remote" for-each-ref | wc -l | tr -d ' ')" 0

copy_ai "$T/seeded"; chmod -R a-w "$T/seeded"   # an installed revision is read-only
# a remote of its own and a clean knowledge directory: the case is the seeding of an empty remote
rm -rf "$AI_SANDBOX_ROOT/knowledge"
remote="$tmp/remote2.git"; git init -q --bare "$remote"
# the suite's rsync stub keeps file modes as rsync -a does: a read-only seed arrives read-only
out=$(bash "$T/seeded/bin/ai/ai-knowledge" init "file://$remote" 2>&1); rc=$?
assert_eq "init from a read-only copy with a seed: exit 0" "$rc" 0
assert_contains "the remote holds the seed" "$(git -C "$remote" ls-tree --name-only main | tr '\n' ' ')" "skills"
assert_eq "nothing outside .git in the host-owned checkout is read-only for its owner" \
    "$(find "$AI_SANDBOX_ROOT/knowledge/main" -path '*/.git' -prune -o ! -perm -u+w -print | wc -l | tr -d ' ')" 0
chmod -R u+w "$T/seeded"

# ---------------------------------------------------------------------------
# O11: tools/ beside the revision; the checkout in ~/dev/public/dev-tools is not looked at
# ---------------------------------------------------------------------------
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
mkdir -p "$HOME/dev/public/dev-tools/tools/context_statusline"   # where the old lookup went
copy_ai "$T/bare"
run() {   # <program> [args]; stdin {} ; session id set for handover-ready
    CLAUDE_CODE_SESSION_ID=p4-test bash "$@" <<<'{}' >"$tmp/out" 2>"$tmp/err"; echo $?
}
assert_eq "context-statusline with no tools/ beside it exits 2" "$(run "$T/bare/bin/ai/context-statusline")" 2
assert_eq "handover-ready with no tools/ beside it exits 2" "$(run "$T/bare/bin/ai/handover-ready" --clear)" 2
cp -a "$REPO_ROOT/tools" "$T/bare/tools"; chmod -R u+w "$T/bare/tools"
mkdir -p "$HOME/.claude/projects/p"; : > "$HOME/.claude/projects/p/p4-test.jsonl"   # the session handover-ready marks
assert_eq "context-statusline with tools/ beside it runs" "$(run "$T/bare/bin/ai/context-statusline" --plain)" 0
assert_eq "handover-ready with tools/ beside it runs" "$(run "$T/bare/bin/ai/handover-ready" --clear)" 0
# O19: neither wrapper runs a module planted in PYTHONPATH or in the working directory
mkdir -p "$T/plant/tools/context_statusline"
planted='import os\nopen(os.environ["MARKER"], "w").close()\n'
printf "$planted" > "$T/plant/json.py"; printf "$planted" > "$T/plant/tools/context_statusline/__init__.py"
for prog in context-statusline handover-ready; do
    arg=--plain; [ "$prog" = handover-ready ] && arg=--clear
    rm -f "$T/pymarker"
    rc=$(cd "$T/plant" && MARKER="$T/pymarker" PYTHONPATH="$T/plant" run "$T/bare/bin/ai/$prog" "$arg")
    assert_eq "$prog with a planted PYTHONPATH and working directory runs" "$rc" 0
    assert_no_file "$prog ran no planted module" "$T/pymarker"
done
printf 'import os\nopen(os.environ["MARKER"], "w").close()\n' > "$T/plant/probe.py"
(cd "$T/plant" && MARKER="$T/pymarker" PYTHONPATH="$T/plant" python3 -c 'import json')
assert_file "known case: a Python without -I imports the planted json.py, so the marker can appear" "$T/pymarker"
# the image's copy: in the build context, nothing beside it, the sandbox mounts ~/tools
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
mkdir -p "$T/ctx"; cp "$REPO_ROOT/bin/ai/context-statusline" "$T/ctx/"
assert_eq "the image's context-statusline without ~/tools exits 2" "$(run "$T/ctx/context-statusline" --plain)" 2
cp -a "$REPO_ROOT/tools" "$HOME/tools"
assert_eq "the image's context-statusline with ~/tools runs" "$(run "$T/ctx/context-statusline" --plain)" 0

# ---------------------------------------------------------------------------
# D26: the base's installed ai-sandbox-migrate sources its own lib (which defines
# ai_sandbox_helpers) and then the checkout's, and copies what the list names. The merged
# lib must leave the name defined and the list empty, or the first run on a host copies
# every helper over the installed ones.
# ---------------------------------------------------------------------------
n=$(bash -c '. "$1"; ai_sandbox_helpers() { echo base-helper; }; . "$1"; ai_sandbox_helpers | wc -l' _ "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh")
assert_eq "sourcing the lib after the base's definition leaves the list empty" "$n" 0
assert_eq "the lib defines ai_sandbox_helpers" "$(bash -c '. "$1"; type -t ai_sandbox_helpers' _ "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh")" function

rm -rf "$T"
finish
