#!/usr/bin/env bash
# The knowledge sync writes nothing through a link a sandbox placed in its own directories (O8).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
PTY="$REPO_ROOT/tests/ai-sandbox/pty-run.py"
today=$(date +%F)
kn() { DOCKER_STUB_IMAGES="$kimages" bash "$REPO_ROOT/bin/ai/ai-knowledge" "$@"; }
mkproj() { mkdir -p "$1"; git -C "$1" init -q; d=$(ai_sandbox_dir_for "$1"); mkdir -p "$d"
    printf 'services: {}\n' > "$d/docker-compose.yml"; printf 'SANDBOX_KNOWLEDGE=2\nSANDBOX_PROJECT_DIR=%s\n' "$1" > "$d/.env"; }
snap() { ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; elif [ -f "$f" ]; then printf '%s %s\n' "$f" "$(sha256sum < "$f")"; else printf '%s\n' "$f"; fi; done ); }

# A host with a remote whose main holds one skill, the integrator's project and a proposing project p.
host() {
    fake_home >/dev/null; tmp=$FAKE_HOME_DIR
    . "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
    git config --global user.email t@example.com; git config --global user.name t; git config --global init.defaultBranch main
    export AI_KNOWLEDGE_GIT_TIMEOUT=20
    kimages="$(ai_sandbox_image_name base) $(ai_sandbox_image_name docker) $(ai_sandbox_image_name base gui) $(ai_sandbox_image_name docker gui)"
    remote="$tmp/remote.git"; git init -q --bare "$remote"
    mkdir -p "$HOME/.gemini" "$HOME/.claude"; printf '# Rules\n' > "$HOME/.gemini/GEMINI.md"
    integ="$tmp/work/dev-tools"; mkproj "$integ"
    kn init "file://$remote" --integrator "$integ" >/dev/null 2>&1 </dev/null
    git clone -q "$remote" "$tmp/seedclone"; mkdir -p "$tmp/seedclone/skills/newskill"
    printf -- '---\nname: newskill\ndescription: d\n---\nx\n' > "$tmp/seedclone/skills/newskill/SKILL.md"
    git -C "$tmp/seedclone" add -A; git -C "$tmp/seedclone" commit -qm "skill"; git -C "$tmp/seedclone" push -q origin main
    proj="$tmp/work/p"; mkproj "$proj"; sb=$(ai_sandbox_dir_for "$proj")
    kn sync "$proj" >/dev/null 2>&1 </dev/null
    trap_dir="$tmp/trap"; mkdir -p "$trap_dir/dir"; printf 'trap\n' > "$trap_dir/file"; printf 'trap\n' > "$trap_dir/dir/inner"
}

host
assert_link "the first sync made the claude skill link" "$sb/.claude/skills/newskill" "../../.agents/skills/newskill"
for c in .claude/skills .codex/skills .gemini/skills .claude/agents .claude/CLAUDE.md; do
    rm -rf "${sb:?}/$c"
    case $c in */CLAUDE.md) ln -s "$trap_dir/file" "$sb/$c" ;; *) ln -s "$trap_dir/dir" "$sb/$c" ;; esac
    t0=$(snap "$trap_dir")
    kn sync "$proj" >"$tmp/o8.out" 2>"$tmp/o8.err" </dev/null; rc=$?
    assert_eq "O8 $c as a link: sync exits 0" "$rc" 0
    assert_eq "O8 $c as a link: the trap is unchanged" "$(snap "$trap_dir")" "$t0"
    want=$c; case $c in */CLAUDE.md) ;; *) want="${c%%/*} ${c#*/}" ;; esac   # the function names root and path apart
    assert_contains "O8 $c as a link: standard error names the path" "$(cat "$tmp/o8.err")" "$want"
    assert_file "O8 $c as a link: the status file is written" "$sb/status/knowledge"
    assert_eq "O8 $c: the link itself is still a link" "$([ -L "$sb/$c" ] && echo yes)" yes
    rm -f "$sb/$c"
    case $c in */CLAUDE.md) : ;; *) mkdir -p "$sb/$c" ;; esac
done
kn sync "$proj" >/dev/null 2>&1 </dev/null
assert_link "without links the claude skill link is made again" "$sb/.claude/skills/newskill" "../../.agents/skills/newskill"
assert_link "without links the codex skill link is made" "$sb/.codex/skills/newskill" "../../.agents/skills/newskill"
assert_file "without links CLAUDE.md exists again" "$sb/.claude/CLAUDE.md"

# D17: the host's own links are made when ~/.claude and ~/.agents are links to directories elsewhere (a dotfiles layout)
host
mkdir -p "$tmp/dotfiles"; mv "$HOME/.claude" "$tmp/dotfiles/claude"; ln -s "$tmp/dotfiles/claude" "$HOME/.claude"
mkdir -p "$tmp/dotfiles/agents"; rm -rf "$HOME/.agents"; ln -s "$tmp/dotfiles/agents" "$HOME/.agents"
kn sync "$proj" >/dev/null 2>"$tmp/d17.err" </dev/null
assert_link "D17: the host's claude skill link is made through a linked ~/.claude" "$HOME/.claude/skills/newskill" "../../.agents/skills/newskill"
assert_file "D17: the skill's one real copy is below the linked ~/.agents" "$tmp/dotfiles/agents/skills/newskill/SKILL.md"

finish
