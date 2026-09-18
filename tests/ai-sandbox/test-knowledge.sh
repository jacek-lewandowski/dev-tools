#!/usr/bin/env bash
# The shared knowledge repository: read-only rules for every sandbox, a
# proposals branch per sandbox, all network git on the host.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

# The lib derives its paths from AI_SANDBOX_ROOT when sourced, so the fake home
# has to exist first.
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

assert_eq "knowledge root derives from the sandbox root" "$AI_KNOWLEDGE_ROOT" "$AI_SANDBOX_ROOT/knowledge"
assert_eq "render lives in the shared store" "$AI_KNOWLEDGE_RENDER" "$AI_SANDBOX_ROOT/shared/knowledge"
ai_knowledge_configured && r=yes || r=no
assert_eq "not configured without the config file" "$r" no
assert_contains "ai-knowledge is an installed helper" "$(ai_sandbox_helpers)" "ai-knowledge"

git config --global user.email t@example.com; git config --global user.name t
git config --global init.defaultBranch main
export AI_KNOWLEDGE_GIT_TIMEOUT=20
knowledge() { bash "$REPO_ROOT/bin/ai/ai-knowledge" "$@"; }

remote="$tmp/remote.git"; git init -q --bare "$remote"
mkdir -p "$HOME/.gemini" "$HOME/.claude"
printf '# Rules\n\n- be brief\n\n<!-- BEGIN dev-tools:ai-sandbox-environment -->\nsandbox block\n<!-- END dev-tools:ai-sandbox-environment -->\n' > "$HOME/.gemini/GEMINI.md"
integ="$tmp/work/dev-tools"; mkdir -p "$integ"; git -C "$integ" init -q
proj="$tmp/work/p"; mkdir -p "$proj"; git -C "$proj" init -q

# --- init seeds an empty remote and wires the host
knowledge init "file://$remote" --integrator "$integ" >"$tmp/init.out" 2>&1 || cat "$tmp/init.out"
assert_file "config written" "$AI_KNOWLEDGE_CONFIG"
assert_contains "remote recorded" "$(cat "$AI_KNOWLEDGE_CONFIG")" "REMOTE=file://$remote"
assert_contains "integrator recorded" "$(cat "$AI_KNOWLEDGE_CONFIG")" "INTEGRATOR=$integ"
assert_eq "main seeded on the remote" "$(git -C "$remote" ls-tree --name-only main | LC_ALL=C sort | tr '\n' ' ')" "README.md decisions.md proposals roles rules skills "
assert_eq "global rules taken from GEMINI.md without the sandbox block" \
    "$(git -C "$remote" show main:rules/global.md | tr -d '\n')" '# Rules- be brief'
assert_link "host GEMINI.md points at the render" "$HOME/.gemini/GEMINI.md" "$AI_KNOWLEDGE_RENDER/GLOBAL.md"
assert_file "host GEMINI.md backed up" "$(ls "$HOME"/.gemini/GEMINI.md.pre-ai-knowledge.* 2>/dev/null | head -1)"
assert_contains "GLOBAL.md rendered" "$(cat "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "- be brief"
assert_file "claude role rendered" "$AI_KNOWLEDGE_RENDER/claude/agents/planner.md"
assert_file "gemini role rendered" "$AI_KNOWLEDGE_RENDER/gemini/agents/planner.md"
assert_contains "antigravity role rendered with model_decision" \
    "$(cat "$AI_KNOWLEDGE_RENDER/antigravity/rules/planner.md")" "trigger: model_decision"
assert_contains "codex role rendered as toml" "$(cat "$AI_KNOWLEDGE_RENDER/codex/agents/planner.toml")" 'developer_instructions = '
assert_link "host claude agent symlink" "$HOME/.claude/agents/planner.md" "$AI_KNOWLEDGE_RENDER/claude/agents/planner.md"
assert_file "own skill copied into ~/.agents" "$HOME/.agents/skills/propose-rule/SKILL.md"
assert_file "own skill copied into the shared store" "$AI_SANDBOX_ROOT/shared/agent-skills/skills/propose-rule/SKILL.md"
assert_link "host claude skill symlink" "$HOME/.claude/skills/propose-rule" "../../.agents/skills/propose-rule"

# --- sync creates a project sandbox clone on its proposals branch
pid=$(ai_sandbox_project_id "$proj"); pdir=$(ai_sandbox_dir_for "$proj"); mkdir -p "$pdir"
knowledge sync "$proj" >"$tmp/sync1.out" 2>&1 || cat "$tmp/sync1.out"
clone="$pdir/knowledge"
assert_eq "clone on its proposals branch" "$(git -C "$clone" branch --show-current)" "proposals/$pid"
assert_eq "proposals branch pushed" "$(git -C "$remote" rev-parse "proposals/$pid")" "$(git -C "$clone" rev-parse HEAD)"
assert_contains "status ok" "$(cat "$clone/.sync-status")" "ok"
assert_file "mount target CLAUDE.md pre-created" "$pdir/.claude/CLAUDE.md"
assert_file "mount target AGENTS.md pre-created" "$pdir/.codex/AGENTS.md"
assert_file "mount target agents dir pre-created" "$pdir/.gemini/agents"
assert_link "sandbox claude skill symlink" "$pdir/.claude/skills/propose-rule" "../../.agents/skills/propose-rule"
assert_link "sandbox codex skill symlink" "$pdir/.codex/skills/propose-rule" "../../.agents/skills/propose-rule"

# --- an in-scope proposal is pushed; out of scope is refused; dirty is skipped
mkdir -p "$clone/proposals/$pid"; echo 'scope: global' > "$clone/proposals/$pid/2026-09-14-test.md"
git -C "$clone" add -A; git -C "$clone" commit -qm "proposal: test"
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "proposal pushed" "$(git -C "$remote" ls-tree -r --name-only "proposals/$pid" -- "proposals/$pid/")" "proposals/$pid/2026-09-14-test.md"
echo hacked >> "$clone/rules/global.md"; git -C "$clone" commit -qam "escape"
knowledge sync "$proj" >/dev/null 2>&1
assert_contains "out-of-scope change refused" "$(cat "$clone/.sync-status")" "refused"
assert_eq "remote branch untouched by the refused push" \
    "$(git -C "$remote" show "proposals/$pid:rules/global.md" | grep -c hacked)" 0
git -C "$clone" reset -q --hard HEAD~1
echo wip > "$clone/proposals/$pid/wip.md"
knowledge sync "$proj" >/dev/null 2>&1
assert_contains "dirty tree skipped" "$(cat "$clone/.sync-status")" "skipped"
rm "$clone/proposals/$pid/wip.md"

# --- the integrator sees the branch, edits main, closes the proposal
idir=$(ai_sandbox_dir_for "$integ"); mkdir -p "$idir"
knowledge sync "$integ" >/dev/null 2>&1
iclone="$idir/knowledge"
assert_eq "integrator clone on main" "$(git -C "$iclone" branch --show-current)" main
assert_contains "integrator has the proposals branch locally" "$(git -C "$iclone" branch --list 'proposals/*')" "proposals/$pid"
assert_eq "proposals listing" "$(knowledge proposals --repo "$iclone")" "proposals/$pid proposals/$pid/2026-09-14-test.md"
echo '- be kind' >> "$iclone/rules/global.md"; git -C "$iclone" commit -qam "feat: kindness"
git -C "$iclone" checkout -q "proposals/$pid"; git -C "$iclone" rm -q "proposals/$pid/2026-09-14-test.md"
git -C "$iclone" commit -qm "proposal: test integrated"; git -C "$iclone" checkout -q main
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "main pushed" "$(git -C "$remote" rev-parse main)" "$(git -C "$iclone" rev-parse main)"
assert_eq "proposal branch pushed" "$(git -C "$remote" rev-parse "proposals/$pid")" "$(git -C "$iclone" rev-parse "proposals/$pid")"
assert_contains "render follows main" "$(cat "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "- be kind"

# --- the project sandbox picks up both on its next sync
knowledge sync "$proj" >/dev/null 2>&1
assert_no_file "closed proposal removed locally" "$clone/proposals/$pid/2026-09-14-test.md"
assert_contains "main merged into the branch" "$(cat "$clone/rules/global.md")" "- be kind"
assert_contains "status ok after round trip" "$(cat "$clone/.sync-status")" "ok"

# --- offline is a status, not a failure, and the manual commands are printed
mv "$remote" "$remote.away"
knowledge sync "$proj" >"$tmp/offline.out" 2>&1; rc=$?
assert_eq "offline sync exits 0" "$rc" 0
assert_contains "offline status" "$(cat "$clone/.sync-status")" "offline"
assert_contains "manual fetch of main printed" "$(cat "$tmp/offline.out")" "git -C $AI_KNOWLEDGE_ROOT/main fetch origin"
assert_contains "manual fetch of the clone printed" "$(cat "$tmp/offline.out")" "git -C $clone fetch origin"
assert_contains "manual sync printed" "$(cat "$tmp/offline.out")" "ai-knowledge sync $proj"
assert_eq "no push printed when nothing is pending" "$(grep -c 'git -C .* push ' "$tmp/offline.out")" 0
mkdir -p "$clone/proposals/$pid"; echo 'scope: global' > "$clone/proposals/$pid/2026-09-14-offline.md"
git -C "$clone" add -A; git -C "$clone" commit -qm "proposal: offline"
knowledge sync "$proj" >"$tmp/offline2.out" 2>&1
assert_contains "pending push printed when offline" "$(cat "$tmp/offline2.out")" \
    "git -C $clone push origin HEAD:refs/heads/proposals/$pid"
assert_contains "offline status names the pending push" "$(cat "$clone/.sync-status")" "push"
# the integrator gets its own list
knowledge sync "$integ" >"$tmp/offline3.out" 2>&1
assert_contains "integrator manual fetch printed" "$(cat "$tmp/offline3.out")" "git -C $iclone fetch origin"
mv "$remote.away" "$remote"
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "pending proposal pushed once online" \
    "$(git -C "$remote" ls-tree -r --name-only "proposals/$pid" -- "proposals/$pid/" | grep -c offline)" 1
assert_contains "status ok again once online" "$(cat "$clone/.sync-status")" "ok"

# --- a manually cloned repository is put on its branch by the next sync
manual="$tmp/work/m"; mkdir -p "$manual"; git -C "$manual" init -q
mid=$(ai_sandbox_project_id "$manual"); mdir=$(ai_sandbox_dir_for "$manual"); mkdir -p "$mdir"
mv "$remote" "$remote.away"
knowledge sync "$manual" >"$tmp/manual.out" 2>&1
assert_contains "manual clone printed" "$(cat "$tmp/manual.out")" "git clone file://$remote $mdir/knowledge"
mv "$remote.away" "$remote"
git clone -q "file://$remote" "$mdir/knowledge"
knowledge sync "$manual" >/dev/null 2>&1
assert_eq "manual clone moved onto its proposals branch" "$(git -C "$mdir/knowledge" branch --show-current)" "proposals/$mid"
assert_contains "manual clone status ok" "$(cat "$mdir/knowledge/.sync-status")" "ok"

# --- create-ai-sandbox.sh mounts the render read-only and the clone read-write
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/create.out" 2>&1 || cat "$tmp/create.out"
compose=$(cat "$pdir/docker-compose.yml")
assert_contains "GLOBAL.md at GEMINI.md, read-only" "$compose" "shared/knowledge/GLOBAL.md:$HOME/.gemini/GEMINI.md:ro\""
assert_contains "GLOBAL.md at CLAUDE.md, read-only" "$compose" "shared/knowledge/GLOBAL.md:$HOME/.claude/CLAUDE.md:ro\""
assert_contains "GLOBAL.md at codex AGENTS.md, read-only" "$compose" "shared/knowledge/GLOBAL.md:$HOME/.codex/AGENTS.md:ro\""
assert_contains "claude agents mounted" "$compose" "shared/knowledge/claude/agents:$HOME/.claude/agents:ro\""
assert_contains "gemini agents mounted" "$compose" "shared/knowledge/gemini/agents:$HOME/.gemini/agents:ro\""
assert_contains "codex agents mounted" "$compose" "shared/knowledge/codex/agents:$HOME/.codex/agents:ro\""
assert_contains "clone mounted read-write at ~/knowledge" "$compose" "\"$pdir/knowledge:$HOME/knowledge\""
case "$compose" in
    *"$HOME/.gemini/GEMINI.md:$HOME/.gemini/GEMINI.md"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "live GEMINI.md mount replaced" "still mounted live" ;;
    *) TESTS_RUN=$((TESTS_RUN+1)); _pass "live GEMINI.md mount replaced" ;;
esac
assert_eq "every shared mount is read-only" \
    "$(printf '%s\n' "$compose" | grep -c '/shared/')" \
    "$(printf '%s\n' "$compose" | grep -c '/shared/.*:ro"')"
assert_file "sandbox block written beside the knowledge config" "$AI_KNOWLEDGE_ROOT/sandbox-environment.md"
assert_contains "render carries the sandbox block" "$(cat "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "BEGIN dev-tools:ai-sandbox-environment"
assert_contains "sandbox block tells agents about ~/knowledge" "$(cat "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "propose-rule"
assert_eq "sandbox block not written into the repository file" \
    "$(grep -c 'ai-sandbox-environment' "$AI_KNOWLEDGE_ROOT/main/rules/global.md")" 0
assert_eq "host GEMINI.md still the render symlink after create" "$(readlink "$HOME/.gemini/GEMINI.md")" "$AI_KNOWLEDGE_RENDER/GLOBAL.md"
assert_contains "doctor reports knowledge" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'status "knowledge"'
assert_contains "summary names the knowledge render" "$(cat "$tmp/create.out")" "Shared knowledge repository"

# --- knowledge stamps classify a sandbox from its .env (phase 1)
fab() {   # <name> [env lines...]: a fabricated sandbox directory with a compose file
    local d="$AI_SANDBOX_ROOT/$1-agent"; shift
    mkdir -p "$d"; printf 'services: {}\n' > "$d/docker-compose.yml"
    printf '%s\n' "$@" > "$d/.env"
}
fab fab-a "SANDBOX_KNOWLEDGE=1" "SANDBOX_PROJECT_DIR=$tmp/work/fab-a"
fab fab-b "SANDBOX_KNOWLEDGE=0" "SANDBOX_PROJECT_DIR=$tmp/work/fab-b"
fab fab-c "HOST_UID=1"
mkdir -p "$AI_SANDBOX_ROOT/fab-d-agent"   # no compose file: not a sandbox
assert_eq "stamp read" "$(ai_sandbox_knowledge_stamp "$AI_SANDBOX_ROOT/fab-a-agent")" 1
assert_eq "missing stamp is empty" "$(ai_sandbox_knowledge_stamp "$AI_SANDBOX_ROOT/fab-c-agent")" ""
assert_eq "stamp 1 is current when configured" "$(ai_sandbox_knowledge_state "$AI_SANDBOX_ROOT/fab-a-agent")" current
assert_eq "stamp 0 is stale when configured" "$(ai_sandbox_knowledge_state "$AI_SANDBOX_ROOT/fab-b-agent")" stale
assert_eq "no stamp is unstamped" "$(ai_sandbox_knowledge_state "$AI_SANDBOX_ROOT/fab-c-agent")" unstamped
listing=$(ai_sandbox_list)
assert_contains "list carries the project dir" "$listing" "$(printf '%s\t%s' "$AI_SANDBOX_ROOT/fab-a-agent" "$tmp/work/fab-a")"
assert_contains "list has an empty project for unstamped" "$listing" "$(printf '%s\t' "$AI_SANDBOX_ROOT/fab-c-agent")"
assert_eq "directories without a compose file are not listed" "$(printf '%s\n' "$listing" | grep -c fab-d)" 0
ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-a-agent" 2>/dev/null && r=0 || r=$?
assert_eq "current sandbox passes the prerequisite" "$r" 0
msg=$(ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-b-agent" 2>&1) && r=0 || r=$?
assert_eq "stale sandbox fails the prerequisite" "$r" 1
assert_contains "refusal names the migration script" "$msg" "ai-sandbox-migrate-knowledge"
assert_contains "refusal names the sandbox" "$msg" "fab-b-agent"
# --- without config nothing changes
rm "$AI_KNOWLEDGE_CONFIG"
other="$tmp/work/q"; mkdir -p "$other"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$other" >"$tmp/create2.out" 2>&1 || cat "$tmp/create2.out"
compose=$(cat "$(ai_sandbox_dir_for "$other")/docker-compose.yml")
assert_contains "live GEMINI.md mount kept without config" "$compose" "$HOME/.gemini/GEMINI.md:$HOME/.gemini/GEMINI.md\""
assert_eq "no knowledge mounts without config" "$(printf '%s\n' "$compose" | grep -c knowledge)" 0
assert_no_file "no clone created without config" "$(ai_sandbox_dir_for "$other")/knowledge"

rm -rf "$tmp"
finish
