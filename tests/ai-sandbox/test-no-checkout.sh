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
# the image's copy: in the build context, nothing beside it, the sandbox mounts ~/tools
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
mkdir -p "$T/ctx"; cp "$REPO_ROOT/bin/ai/context-statusline" "$T/ctx/"
assert_eq "the image's context-statusline without ~/tools exits 2" "$(run "$T/ctx/context-statusline" --plain)" 2
cp -a "$REPO_ROOT/tools" "$HOME/tools"
assert_eq "the image's context-statusline with ~/tools runs" "$(run "$T/ctx/context-statusline" --plain)" 0

rm -rf "$T"
finish
