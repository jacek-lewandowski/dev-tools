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

# --- sync creates a project sandbox clone on main, with role file and hook
pid=$(ai_sandbox_project_id "$proj"); pdir=$(ai_sandbox_dir_for "$proj"); mkdir -p "$pdir"
knowledge sync "$proj" >"$tmp/sync1.out" 2>&1 || cat "$tmp/sync1.out"
clone="$pdir/knowledge"
assert_eq "clone on main" "$(git -C "$clone" branch --show-current)" main
assert_contains "status ok" "$(cat "$clone/.sync-status")" "ok"
assert_eq "role file names the role and project id" "$(cat "$clone/.git/ai-knowledge-role")" "proposals $pid"
assert_file "pre-commit hook installed" "$clone/.git/hooks/pre-commit"
[ -x "$clone/.git/hooks/pre-commit" ] && r=yes || r=no
assert_eq "hook is executable" "$r" yes
assert_file "mount target CLAUDE.md pre-created" "$pdir/.claude/CLAUDE.md"
assert_file "mount target AGENTS.md pre-created" "$pdir/.codex/AGENTS.md"
assert_file "mount target agents dir pre-created" "$pdir/.gemini/agents"
assert_link "sandbox claude skill symlink" "$pdir/.claude/skills/propose-rule" "../../.agents/skills/propose-rule"
assert_link "sandbox codex skill symlink" "$pdir/.codex/skills/propose-rule" "../../.agents/skills/propose-rule"

# What the propose-rule skill does: a temporary branch, one file, rename to the final name.
today=$(date +%F)
propose_in() {   # <clone> <slug> [rule text]; prints the branch name
    local c=$1 slug=$2 hex
    git -C "$c" checkout -q -b "proposal/tmp-$slug" main
    printf -- '---\nscope: global\nproject: p\nproject_id: x\nmachine: test\ntarget: rules/global.md\nevidence: e\n---\n\n# %s\n\n%s\n' \
        "$slug" "${3:-rule}" > "$c/proposals/$today-$slug.md"
    git -C "$c" add "proposals/$today-$slug.md"; git -C "$c" commit -qm "proposal: $slug"
    hex=$(git -C "$c" rev-parse HEAD | cut -c1-4)
    git -C "$c" branch -q -m "proposal/$today-$slug-$hex"; git -C "$c" checkout -q main
    printf 'proposal/%s-%s-%s' "$today" "$slug" "$hex"
}

# --- an in-scope proposal is pushed; out of scope and malformed are refused; dirty is skipped
b1=$(propose_in "$clone" test)
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "proposal branch pushed" "$(git -C "$remote" rev-parse "$b1")" "$(git -C "$clone" rev-parse "$b1")"
assert_eq "proposal file on the branch" "$(git -C "$remote" ls-tree -r --name-only "$b1" -- proposals/ | grep -v README)" "proposals/$today-test.md"
assert_contains "status counts the push" "$(cat "$clone/.sync-status")" "pushed 1"
git -C "$clone" checkout -q -b "proposal/$today-escape-abcd" main
echo hacked >> "$clone/roles/planner.md"; git -C "$clone" commit -q --no-verify -am "escape"; git -C "$clone" checkout -q main
git -C "$clone" checkout -q -b "proposal/tmp-half" main
echo 'scope: global' > "$clone/proposals/$today-half.md"; git -C "$clone" add -A; git -C "$clone" commit -qm "half"; git -C "$clone" checkout -q main
knowledge sync "$proj" >/dev/null 2>&1
assert_contains "out-of-scope branch refused" "$(cat "$clone/.sync-status")" "refused"
assert_contains "refusal names the branch" "$(cat "$clone/.sync-status")" "escape-abcd"
assert_contains "malformed name refused" "$(cat "$clone/.sync-status")" "tmp-half"
git -C "$remote" show-ref -q "refs/heads/proposal/$today-escape-abcd" && r=yes || r=no
assert_eq "refused branch not on the remote" "$r" no
git -C "$remote" show-ref -q "refs/heads/proposal/tmp-half" && r=yes || r=no
assert_eq "malformed branch not on the remote" "$r" no
git -C "$clone" branch -q -D "proposal/$today-escape-abcd" "proposal/tmp-half"
echo wip > "$clone/proposals/wip.md"
knowledge sync "$proj" >/dev/null 2>&1
assert_contains "dirty tree skipped" "$(cat "$clone/.sync-status")" "skipped"
rm "$clone/proposals/wip.md"

# --- the hook refuses commits on main in a proposing clone and out-of-scope paths on a proposal branch
echo hacked >> "$clone/rules/global.md"
out=$(git -C "$clone" commit -qam "on main" 2>&1) && r=0 || r=$?
assert_eq "hook refuses a commit on main" "$r" 1
assert_contains "hook names the skill" "$out" "propose-rule"
git -C "$clone" checkout -q rules/global.md
git -C "$clone" checkout -q -b "proposal/$today-hooky-0000" main
echo x > "$clone/roles/x.md"; git -C "$clone" add roles/x.md
git -C "$clone" commit -qm "bad path" >/dev/null 2>&1 && r=0 || r=$?
assert_eq "hook refuses a path outside proposals/ on a proposal branch" "$r" 1
git -C "$clone" reset -q roles/x.md; rm "$clone/roles/x.md"
echo ok > "$clone/proposals/$today-hooky.md"; git -C "$clone" add proposals/
git -C "$clone" commit -qm "good path" >/dev/null 2>&1 && r=0 || r=$?
assert_eq "hook accepts a proposals/ path on a proposal branch" "$r" 0
git -C "$clone" checkout -q main; git -C "$clone" branch -q -D "proposal/$today-hooky-0000"

# --- the integrator sees the branch, edits main, closes with an ours-merge; the branch dies everywhere
idir=$(ai_sandbox_dir_for "$integ"); mkdir -p "$idir"
knowledge sync "$integ" >/dev/null 2>&1
iclone="$idir/knowledge"
assert_eq "integrator clone on main" "$(git -C "$iclone" branch --show-current)" main
assert_eq "integrator role file" "$(cut -d' ' -f1 "$iclone/.git/ai-knowledge-role")" integrator
assert_contains "integrator has the proposal branch locally" "$(git -C "$iclone" branch --list 'proposal/*')" "$b1"
assert_eq "proposals listing" "$(knowledge proposals --repo "$iclone")" "$b1 proposals/$today-test.md"
echo '- be kind' >> "$iclone/rules/global.md"
git -C "$iclone" commit -qam "feat: kindness" && r=0 || r=$?
assert_eq "hook lets the integrator commit on main" "$r" 0
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: test integrated" "$b1"
assert_eq "ours-merge leaves main's tree unchanged" "$(git -C "$iclone" ls-tree -r --name-only HEAD -- proposals/ | grep -vc README)" 0
assert_eq "closed proposal no longer listed" "$(knowledge proposals --repo "$iclone")" ""
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "main pushed" "$(git -C "$remote" rev-parse main)" "$(git -C "$iclone" rev-parse main)"
git -C "$remote" show-ref -q "refs/heads/$b1" && r=yes || r=no
assert_eq "closed branch deleted on the remote" "$r" no
git -C "$iclone" show-ref -q "refs/heads/$b1" && r=yes || r=no
assert_eq "closed branch deleted in the integrator clone" "$r" no
assert_contains "render follows main" "$(cat "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "- be kind"
assert_contains "integrator status ok" "$(cat "$iclone/.sync-status")" "ok"

# --- the proposer's next sync fast-forwards main and drops its closed branch without re-creating it
knowledge sync "$proj" >/dev/null 2>&1
assert_contains "main fast-forwarded in the clone" "$(cat "$clone/rules/global.md")" "- be kind"
git -C "$clone" show-ref -q "refs/heads/$b1" && r=yes || r=no
assert_eq "closed branch deleted locally" "$r" no
git -C "$remote" show-ref -q "refs/heads/$b1" && r=yes || r=no
assert_eq "closed branch not re-created on the remote" "$r" no
assert_contains "status counts the close" "$(cat "$clone/.sync-status")" "closed 1"

# --- an amendment pushed after the close reopens the proposal instead of being deleted
b2=$(propose_in "$clone" amend)
knowledge sync "$proj" >/dev/null 2>&1; knowledge sync "$integ" >/dev/null 2>&1
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: amend rejected" "$b2"
git -C "$clone" checkout -q "$b2"; echo more >> "$clone/proposals/$today-amend.md"
git -C "$clone" commit -qam "amend more"; git -C "$clone" checkout -q main
knowledge sync "$proj" >/dev/null 2>&1
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "amended branch survives the integrator's sync" "$(git -C "$remote" rev-parse "$b2")" "$(git -C "$clone" rev-parse "$b2")"
assert_eq "amended proposal listed again" "$(knowledge proposals --repo "$iclone")" "$b2 proposals/$today-amend.md"
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: amend rejected again" "$b2"
knowledge sync "$integ" >/dev/null 2>&1; knowledge sync "$proj" >/dev/null 2>&1
git -C "$remote" show-ref -q "refs/heads/$b2" && r=yes || r=no
assert_eq "re-closed branch deleted" "$r" no

# --- a clone parked on a proposal branch still gets main; a closed parked branch is left on main
b3=$(propose_in "$clone" park); git -C "$clone" checkout -q "$b3"
echo '- be brief' >> "$iclone/rules/global.md"; git -C "$iclone" commit -qam "feat: brevity"
knowledge sync "$integ" >/dev/null 2>&1
knowledge sync "$proj" >/dev/null 2>&1
knowledge sync "$integ" >/dev/null 2>&1   # the integrator fetches the parked branch
assert_eq "parked clone keeps its branch" "$(git -C "$clone" branch --show-current)" "$b3"
assert_eq "parked clone's main follows origin" "$(git -C "$clone" rev-parse main)" "$(git -C "$remote" rev-parse main)"
assert_contains "parked clone status ok" "$(cat "$clone/.sync-status")" "ok"
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: park rejected" "$b3"
knowledge sync "$integ" >/dev/null 2>&1; knowledge sync "$proj" >/dev/null 2>&1
assert_eq "closed parked branch: clone moved to main" "$(git -C "$clone" branch --show-current)" main
git -C "$clone" show-ref -q "refs/heads/$b3" && r=yes || r=no
assert_eq "closed parked branch deleted" "$r" no

# --- a local commit on main is diverged; proposal branches are still pushed
git -C "$clone" commit -q --no-verify --allow-empty -m "local on main"
b4=$(propose_in "$clone" diverge)
knowledge sync "$proj" >/dev/null 2>&1
assert_contains "diverged main reported" "$(cat "$clone/.sync-status")" "diverged"
assert_eq "proposal pushed despite diverged main" "$(git -C "$remote" rev-parse "$b4")" "$(git -C "$clone" rev-parse "$b4")"
git -C "$clone" reset -q --hard origin/main
knowledge sync "$integ" >/dev/null 2>&1
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: diverge rejected" "$b4"
knowledge sync "$integ" >/dev/null 2>&1; knowledge sync "$proj" >/dev/null 2>&1
assert_contains "status ok after the reset" "$(cat "$clone/.sync-status")" "ok"

# --- offline is a status, not a failure, and the manual commands are printed
mv "$remote" "$remote.away"
knowledge sync "$proj" >"$tmp/offline.out" 2>&1; rc=$?
assert_eq "offline sync exits 0" "$rc" 0
assert_contains "offline status" "$(cat "$clone/.sync-status")" "offline"
assert_contains "manual fetch of main printed" "$(cat "$tmp/offline.out")" "git -C $AI_KNOWLEDGE_ROOT/main fetch origin"
assert_contains "manual fetch of the clone printed" "$(cat "$tmp/offline.out")" "git -C $clone fetch --prune origin"
assert_contains "manual sync printed" "$(cat "$tmp/offline.out")" "ai-knowledge sync $proj"
assert_eq "no push printed when nothing is pending" "$(grep -c 'git -C .* push ' "$tmp/offline.out")" 0
b5=$(propose_in "$clone" offline)
knowledge sync "$proj" >"$tmp/offline2.out" 2>&1
assert_contains "pending push printed when offline" "$(cat "$tmp/offline2.out")" \
    "git -C $clone push origin $b5:refs/heads/$b5"
assert_contains "offline status names the pending push" "$(cat "$clone/.sync-status")" "push"
knowledge sync "$integ" >"$tmp/offline3.out" 2>&1
assert_contains "integrator manual fetch printed" "$(cat "$tmp/offline3.out")" "git -C $iclone fetch origin"
mv "$remote.away" "$remote"
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "pending proposal pushed once online" "$(git -C "$remote" rev-parse "$b5")" "$(git -C "$clone" rev-parse "$b5")"
assert_contains "status ok again once online" "$(cat "$clone/.sync-status")" "ok"

# --- a manually cloned repository is adopted; a clone on an old-style branch is skipped
manual="$tmp/work/manual"; mkdir -p "$manual"; git -C "$manual" init -q
mdir=$(ai_sandbox_dir_for "$manual"); mkdir -p "$mdir"
mv "$remote" "$remote.away"
knowledge sync "$manual" >"$tmp/manual.out" 2>&1
assert_contains "manual clone printed" "$(cat "$tmp/manual.out")" "git clone file://$remote $mdir/knowledge"
mv "$remote.away" "$remote"
git clone -q "file://$remote" "$mdir/knowledge"
knowledge sync "$manual" >/dev/null 2>&1
assert_eq "manual clone stays on main" "$(git -C "$mdir/knowledge" branch --show-current)" main
assert_contains "manual clone status ok" "$(cat "$mdir/knowledge/.sync-status")" "ok"
assert_file "manual clone got the hook" "$mdir/knowledge/.git/hooks/pre-commit"
git -C "$mdir/knowledge" checkout -q -b "proposals/old-id" main
knowledge sync "$manual" >/dev/null 2>&1
assert_contains "old-style branch skipped" "$(cat "$mdir/knowledge/.sync-status")" "skipped"
assert_contains "old-style skip names the migration" "$(cat "$mdir/knowledge/.sync-status")" "migrate-knowledge"
git -C "$mdir/knowledge" checkout -q main; git -C "$mdir/knowledge" branch -q -D "proposals/old-id"

# --- propose: a file becomes a well-formed branch from origin/main without touching the tree
printf -- '---\nscope: global\ntarget: rules/global.md\nevidence: e\n---\n\n# From host\n\ntext\n' > "$tmp/rule.md"
head_before=$(git -C "$AI_KNOWLEDGE_ROOT/main" rev-parse HEAD)
pb=$(knowledge propose "$tmp/rule.md" --slug from-host --project-id abc --machine host1 --push 2>"$tmp/propose.err") || cat "$tmp/propose.err"
case "$pb" in proposal/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-from-host-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]) r=yes ;; *) r=no ;; esac
assert_eq "propose prints a well-formed branch name ($pb)" "$r" yes
assert_eq "propose leaves the canonical tree alone" "$(git -C "$AI_KNOWLEDGE_ROOT/main" status --porcelain)$(git -C "$AI_KNOWLEDGE_ROOT/main" rev-parse HEAD)" "$head_before"
assert_contains "propose adds project_id" "$(git -C "$AI_KNOWLEDGE_ROOT/main" show "$pb:proposals/$today-from-host.md")" "project_id: abc"
assert_contains "propose adds machine" "$(git -C "$AI_KNOWLEDGE_ROOT/main" show "$pb:proposals/$today-from-host.md")" "machine: host1"
assert_contains "propose keeps the body" "$(git -C "$AI_KNOWLEDGE_ROOT/main" show "$pb:proposals/$today-from-host.md")" "# From host"
assert_eq "propose --push reaches the remote" "$(git -C "$remote" rev-parse "$pb")" "$(git -C "$AI_KNOWLEDGE_ROOT/main" rev-parse "$pb")"

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
assert_contains "doctor lists proposal branches" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'proposal/'
assert_eq "sandbox block no longer names a per-sandbox branch" "$(grep -c 'proposals/<project-id>' "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" 0
assert_contains "sandbox block names the proposal branch pattern" "$(cat "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "proposal/<date>-<slug>-<hex>"
assert_file "seed installed beside the helper" "$AI_SANDBOX_ROOT/bin/knowledge-seed/skills/propose-rule/SKILL.md"
assert_contains "summary names the knowledge render" "$(cat "$tmp/create.out")" "Shared knowledge repository"

assert_contains "create stamps SANDBOX_KNOWLEDGE=1" "$(cat "$pdir/.env")" 'SANDBOX_KNOWLEDGE=1'
assert_contains "create records the project dir" "$(cat "$pdir/.env")" "SANDBOX_PROJECT_DIR=$proj"
assert_contains "stamp passed into the container" "$compose" 'SANDBOX_KNOWLEDGE=${SANDBOX_KNOWLEDGE}'
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
assert_contains "stale refusal explains the mismatch" "$msg" "disagrees"
msg=$(ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-c-agent" 2>&1) || true
assert_contains "unstamped refusal explains the missing stamp" "$msg" "before the knowledge stamp"
# --- _sync-clone syncs one clone and never renders (phase 2)
knowledge _sync-clone "$proj" "$pdir" >"$tmp/one.out" 2>&1 || cat "$tmp/one.out"
assert_contains "_sync-clone leaves the clone ok" "$(cat "$clone/.sync-status")" "ok"
assert_eq "_sync-clone does not render" "$(grep -c 'rendered' "$tmp/one.out")" 0

# --- sync --all: every stamped sandbox in parallel, one render unless main moved
third="$tmp/work/third"; mkdir -p "$third"; git -C "$third" init -q
tdir=$(ai_sandbox_dir_for "$third"); mkdir -p "$tdir"
printf 'services: {}\n' > "$tdir/docker-compose.yml"
printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$third" > "$tdir/.env"
printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$proj" > "$pdir/.env.keep"; cp "$pdir/.env.keep" "$pdir/.env"
printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$integ" > "$idir/.env"
printf 'services: {}\n' > "$idir/docker-compose.yml"
knowledge sync --all >"$tmp/all1.out" 2>&1 || cat "$tmp/all1.out"
assert_contains "all: project clone ok" "$(cat "$clone/.sync-status")" "ok"
assert_contains "all: integrator clone ok" "$(cat "$iclone/.sync-status")" "ok"
assert_contains "all: third clone created and ok" "$(cat "$tdir/knowledge/.sync-status" 2>/dev/null)" "ok"
assert_eq "all: one render when main did not move" "$(grep -c 'rendered' "$tmp/all1.out")" 1
assert_contains "all: table row for the third sandbox" "$(grep "$(basename "$tdir")" "$tmp/all1.out" | tail -1)" "ok"
assert_contains "all: unstamped sandbox reported, not synced" "$(grep fab-c-agent "$tmp/all1.out" | tail -1)" "unstamped"
assert_no_file "all: no clone for the unstamped sandbox" "$AI_SANDBOX_ROOT/fab-c-agent/knowledge"
assert_contains "all: stamped sandbox with a missing project reported" "$(grep fab-a-agent "$tmp/all1.out" | tail -1)" "missing project"
eproj="$tmp/work/e"; mkdir -p "$eproj"; edir=$(ai_sandbox_dir_for "$eproj"); mkdir -p "$edir"
printf 'services: {}\n' > "$edir/docker-compose.yml"; printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$eproj" > "$edir/.env"
chmod 000 "$eproj"
knowledge sync --all >"$tmp/all-err.out" 2>&1 || cat "$tmp/all-err.out"
assert_contains "all: a failing child reports its exit code" "$(grep "$(basename "$edir")" "$tmp/all-err.out" | tail -1)" "error: exit 1"
chmod 755 "$eproj"; rm -rf "$edir"
assert_contains "all: child output printed under its name" "$(cat "$tmp/all1.out")" "== $(basename "$pdir")"
echo '- be patient' >> "$iclone/rules/global.md"; git -C "$iclone" commit -qam "feat: patience"
AI_KNOWLEDGE_JOBS=1 knowledge sync --all >"$tmp/all2.out" 2>&1 || cat "$tmp/all2.out"
assert_eq "all: two renders when the integrator advanced main" "$(grep -c 'rendered' "$tmp/all2.out")" 2
assert_contains "all: render carries the new main" "$(cat "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "- be patient"
assert_contains "all: project clone merged the new main" "$(cat "$clone/rules/global.md")" "- be patient"
rm -rf "$tdir"
# --- status without an argument lists every sandbox with its state
all=$(knowledge status 2>&1)
assert_contains "status keeps the remote header" "$all" "remote:      file://$remote"
assert_contains "status names the integrator clone" "$all" "clone (integrator): $idir/knowledge"
assert_contains "status lists a current sandbox" "$all" "fab-a-agent"
assert_contains "status marks the stale one" "$(printf '%s\n' "$all" | grep fab-b-agent)" "stale"
assert_contains "status marks the unstamped one" "$(printf '%s\n' "$all" | grep fab-c-agent)" "unstamped"
assert_contains "status shows unknown project for unstamped" "$(printf '%s\n' "$all" | grep fab-c-agent)" "unknown"
assert_contains "status shows never for a sandbox without a sync" "$(printf '%s\n' "$all" | grep fab-a-agent)" "never"
assert_contains "status shows the last sync of the real sandbox" "$(printf '%s\n' "$all" | grep "$(basename "$pdir")")" "ok"
one=$(knowledge status "$proj" 2>&1)
assert_contains "status with a project keeps the single view" "$one" "clone:       $pdir/knowledge"
assert_eq "status with a project lists no other sandbox" "$(printf '%s\n' "$one" | grep -c fab-)" 0
assert_contains "doctor reads the stamp" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'SANDBOX_KNOWLEDGE'
assert_contains "doctor names the migration script" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'ai-sandbox-migrate-knowledge'
# --- the start scripts refuse a sandbox whose stamp does not match the host
stale="$tmp/work/stale"; mkdir -p "$stale"; git -C "$stale" init -q
sdir=$(ai_sandbox_dir_for "$stale"); mkdir -p "$sdir"
printf 'services: {}\n' > "$sdir/docker-compose.yml"
printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$stale" > "$sdir/.env"
: > "$DOCKER_STUB_LOG"
msg=$(cd "$stale" && bash "$REPO_ROOT/bin/ai/ai-sandbox" 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox refuses a stale sandbox" "$r" 1
assert_contains "ai-sandbox names the migration script" "$msg" "ai-sandbox-migrate-knowledge"
assert_eq "no compose call for a refused start" "$(grep -c compose "$DOCKER_STUB_LOG")" 0
msg=$(cd "$stale" && bash "$REPO_ROOT/bin/ai/ai-sandbox-restart" 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox-restart refuses a stale sandbox" "$r" 1
assert_eq "no compose down for a refused restart" "$(grep -c 'compose.*down' "$DOCKER_STUB_LOG")" 0
: > "$DOCKER_STUB_LOG"
out=$(cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox" --print-context 2>&1) && r=0 || r=$?
assert_eq "print-context works on a current sandbox" "$r" 0
assert_contains "print-context reports the sandbox dir" "$out" "dir=$pdir"
(cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-restart" >/dev/null 2>&1) && r=0 || r=$?
assert_eq "restart of a current sandbox proceeds" "$r" 0
assert_contains "restart of a current sandbox reaches compose" "$(stub_docker_log)" "down"
# --- the disposable migration script recreates stale and unstamped sandboxes
migrate() { bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate-knowledge" "$@"; }
assert_eq "migration script is not an installed helper" "$(ai_sandbox_helpers | grep -c migrate-knowledge)" 0
mproj="$tmp/work/m"; mkdir -p "$mproj"; git -C "$mproj" init -q
mdir2=$(ai_sandbox_dir_for "$mproj"); mkdir -p "$mdir2"
printf 'services:\n  x:\n    volumes:\n      - "%s:%s"\n      - "%s/.gemini/GEMINI.md:%s/.gemini/GEMINI.md"\n' "$mproj" "$mproj" "$HOME" "$HOME" > "$mdir2/docker-compose.yml"
printf 'HOST_UID=1\n' > "$mdir2/.env"
# an unstamped sandbox on the current layout has project-path and no self-mount to read
nproj="$tmp/work/n"; mkdir -p "$nproj"; git -C "$nproj" init -q
ndir=$(ai_sandbox_dir_for "$nproj"); mkdir -p "$ndir"
printf 'services: {}\n' > "$ndir/docker-compose.yml"; printf 'HOST_UID=1\n' > "$ndir/.env"
printf '%s\n' "$nproj" > "$ndir/project-path"
# fab-b points at a missing project and fab-c has no recoverable path: the whole run is refused
out=$(migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "migration refuses when a project directory is missing" "$r" 1
assert_contains "refusal names the sandbox with the missing project" "$out" "fab-b-agent"
assert_contains "refusal names the sandbox without a recoverable path" "$out" "fab-c-agent"
assert_eq "nothing migrated on a refused run" "$(ai_sandbox_knowledge_state "$mdir2")" unstamped
rm -rf "$AI_SANDBOX_ROOT"/fab-[bcd]-agent
# a project create-ai-sandbox.sh cannot enter: that sandbox fails, the others still migrate
bproj="$tmp/work/bad"; mkdir -p "$bproj"
bdir=$(ai_sandbox_dir_for "$bproj"); mkdir -p "$bdir"
printf 'services: {}\n' > "$bdir/docker-compose.yml"
printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$bproj" > "$bdir/.env"
chmod 000 "$bproj"
: > "$DOCKER_STUB_LOG"
out=$(migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "a failed recreation makes the run exit 1" "$r" 1
assert_eq "unstamped sandbox recreated from its compose mount" "$(ai_sandbox_knowledge_state "$mdir2")" current
assert_eq "unstamped sandbox recreated from project-path" "$(ai_sandbox_knowledge_state "$ndir")" current
assert_eq "stale sandbox recreated from its stamp" "$(ai_sandbox_knowledge_state "$sdir")" current
assert_eq "failed sandbox left stale" "$(ai_sandbox_knowledge_state "$bdir")" stale
assert_contains "recreated compose carries the knowledge mounts" "$(cat "$mdir2/docker-compose.yml")" "$HOME/knowledge"
assert_eq "running containers are stopped before recreation" "$(grep -c 'compose.*down' "$DOCKER_STUB_LOG")" 4
assert_eq "migrated sandboxes are not started" "$(grep -c 'compose.*up' "$DOCKER_STUB_LOG")" 0
assert_contains "summary lists the migrated sandboxes" "$(printf '%s\n' "$out" | grep '^migrated:')" "$(basename "$mdir2")"
assert_contains "summary lists the failed sandbox" "$(printf '%s\n' "$out" | grep '^failed:')" "$(basename "$bdir")"
assert_eq "current sandbox not reported as migrated" "$(printf '%s\n' "$out" | grep '^migrated:' | grep -c "$(basename "$pdir")")" 0
chmod 755 "$bproj"; rm -rf "$bdir"
out=$(migrate 2>&1) && r=0 || r=$?
assert_eq "nothing to migrate exits 0" "$r" 0
assert_contains "nothing to migrate says so" "$out" "nothing to migrate"

# --- migration converts old-style proposals branches and moves clones to main
oldc="$tmp/oldclone"; git clone -q "file://$remote" "$oldc"
git -C "$oldc" checkout -q -b proposals/oldproj-1234 origin/main
mkdir -p "$oldc/proposals/oldproj-1234"
for f in 2026-09-01-alpha 2026-09-02-beta; do
    printf -- '---\nscope: global\nproject: oldproj\ntarget: rules/global.md\nevidence: e\n---\n\n# %s\n\nold rule\n' "$f" > "$oldc/proposals/oldproj-1234/$f.md"
done
git -C "$oldc" add -A; git -C "$oldc" commit -qm "two old proposals"; git -C "$oldc" push -q origin proposals/oldproj-1234
# a clone on this host sits on the old branch with one unpushed proposal
printf 'services: {}\n' > "$mdir/docker-compose.yml"
printf 'SANDBOX_KNOWLEDGE=1\nSANDBOX_PROJECT_DIR=%s\n' "$manual" > "$mdir/.env"
git -C "$mdir/knowledge" fetch -q origin; git -C "$mdir/knowledge" checkout -q -b proposals/oldproj-1234 origin/proposals/oldproj-1234
printf -- '---\nscope: global\n---\n\n# gamma\n\nunpushed\n' > "$mdir/knowledge/proposals/oldproj-1234/2026-09-03-gamma.md"
git -C "$mdir/knowledge" add -A; git -C "$mdir/knowledge" commit -q --no-verify -m "gamma"
# a dirty clone on an old branch is reported and left alone
git -C "$sdir/knowledge" checkout -q -b proposals/dirty-0000 main; echo wip > "$sdir/knowledge/wip.txt"
# the remote moved meanwhile: the clone's push is not a fast-forward, so the run stops before anything is deleted
printf -- '---\nscope: global\n---\n\n# delta\n\nremote side\n' > "$oldc/proposals/oldproj-1234/2026-09-04-delta.md"
git -C "$oldc" add -A; git -C "$oldc" commit -qm "delta"; git -C "$oldc" push -q origin proposals/oldproj-1234
out=$(printf 'y\n' | migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "unpushable old commit stops the run" "$r" 1
assert_contains "the stopping clone is named" "$out" "$(basename "$mdir")"
git -C "$remote" show-ref -q refs/heads/proposals/oldproj-1234 && r=yes || r=no
assert_eq "nothing deleted when the run stops" "$r" yes
assert_eq "nothing converted when the run stops" "$(git -C "$remote" for-each-ref 'refs/heads/proposal/*' | grep -c -E -- '-(alpha|beta|gamma|delta)-')" 0
git -C "$mdir/knowledge" fetch -q origin; git -C "$mdir/knowledge" merge -q --no-edit origin/proposals/oldproj-1234
oldtip=$(git -C "$mdir/knowledge" rev-parse HEAD)
out=$(printf 'y\n' | migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "branch migration succeeds" "$r" 0
newbranches=$(git -C "$remote" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*' | grep -E -- '-(alpha|beta|gamma|delta)-' | sort)
assert_eq "four old proposals became four proposal branches" "$(printf '%s\n' "$newbranches" | grep -c .)" 4
gb=$(printf '%s\n' "$newbranches" | grep gamma)
assert_contains "converted file carries project_id" "$(git -C "$remote" show "$gb:proposals/$today-gamma.md")" "project_id: oldproj-1234"
assert_contains "converted file carries machine unknown" "$(git -C "$remote" show "$gb:proposals/$today-gamma.md")" "machine: unknown"
git -C "$remote" show-ref -q refs/heads/proposals/oldproj-1234 && r=yes || r=no
assert_eq "old remote branch deleted after conversion" "$r" no
git -C "$remote" merge-base --is-ancestor "$oldtip" main && r=yes || r=no
assert_eq "old branch tip is an ancestor of main (ours-merge before deletion)" "$r" yes
assert_eq "clone on the old branch moved to main" "$(git -C "$mdir/knowledge" branch --show-current)" main
assert_eq "old local branches deleted in the moved clone" "$(git -C "$mdir/knowledge" branch --list 'proposals/*' | wc -l | tr -d ' ')" 0
assert_eq "dirty clone left on its branch" "$(git -C "$sdir/knowledge" branch --show-current)" proposals/dirty-0000
assert_contains "dirty clone named in the output" "$out" "$(basename "$sdir")"
assert_eq "integrator clone has no old local branches" "$(git -C "$iclone" branch --list 'proposals/*' | wc -l | tr -d ' ')" 0
out=$(printf 'y\n' | migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "second run has nothing to convert" "$r" 0
assert_contains "second run says so" "$out" "nothing to convert"
rm -f "$sdir/knowledge/wip.txt"; git -C "$sdir/knowledge" checkout -q main; git -C "$sdir/knowledge" branch -q -D proposals/dirty-0000
# --- init on a host with only the installed helper seeds from the seed beside it (phase 4)
remote2="$tmp/remote2.git"; git init -q --bare "$remote2"
home2="$tmp/home2"; mkdir -p "$home2/.gemini"
out=$(HOME="$home2" AI_SANDBOX_ROOT="$home2/.ai-sandbox" bash "$AI_SANDBOX_ROOT/bin/ai-knowledge" init "file://$remote2" 2>&1) && r=0 || r=$?
assert_eq "installed helper inits without a dev-tools checkout" "$r" 0
assert_contains "second remote seeded from the installed seed" "$(git -C "$remote2" ls-tree --name-only main | tr '\n' ' ')" "skills"
assert_file "second remote has the propose-rule skill" "$home2/.ai-sandbox/knowledge/main/skills/propose-rule/SKILL.md"

# --- the integrator is recorded in README.md on main; a second host is warned
assert_contains "integrator recorded on main" "$(git -C "$remote" show main:README.md)" "ai-knowledge integrator: $(hostname):$integ"
kinit() {   # <home> [init args...]: init in another HOME against the first remote
    local h=$1; shift
    mkdir -p "$h/.gemini"
    HOME="$h" AI_SANDBOX_ROOT="$h/.ai-sandbox" bash "$REPO_ROOT/bin/ai/ai-knowledge" init "file://$remote" "$@" 2>&1
}
home3="$tmp/home3"; mkdir -p "$home3/.gemini"; other="$tmp/work/other-integ"; mkdir -p "$other"
git -C "$AI_KNOWLEDGE_ROOT/main" show origin/main:rules/global.md > "$home3/.gemini/GEMINI.md"
out=$(kinit "$home3" --integrator "$other" </dev/null) || true
assert_contains "second integrator host is warned" "$out" "already"
assert_eq "recorded integrator unchanged" "$(git -C "$remote" show main:README.md | grep -c "ai-knowledge integrator: $(hostname):$integ")" 1
assert_eq "no second integrator line" "$(git -C "$remote" show main:README.md | grep -c 'ai-knowledge integrator:')" 1
assert_eq "identical GEMINI.md prints no drift prompt" "$(printf '%s\n' "$out" | grep -c 'File this difference')" 0

# --- init shows GEMINI.md drift and offers to file it as a proposal
home4="$tmp/home4"; mkdir -p "$home4/.gemini"
{ git -C "$AI_KNOWLEDGE_ROOT/main" show origin/main:rules/global.md; echo '- host-only rule'; } > "$home4/.gemini/GEMINI.md"
out=$(printf 'y\n' | kinit "$home4") || true
assert_contains "drift shown as a diff" "$out" "+- host-only rule"
drift=$(git -C "$remote" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*' | grep -- "-gemini-md-" | head -1)
assert_contains "drift filed as a proposal branch" "$drift" "gemini-md-"
assert_contains "drift proposal holds the diff" "$(git -C "$remote" show "$drift:proposals/$today-gemini-md-$(ai_sandbox_slug "$(hostname)").md")" '```diff'
assert_contains "drift proposal names the machine" "$(git -C "$remote" show "$drift:proposals/$today-gemini-md-$(ai_sandbox_slug "$(hostname)").md")" "machine: $(hostname)"
assert_file "drifting GEMINI.md still backed up" "$(ls "$home4"/.gemini/GEMINI.md.pre-ai-knowledge.* 2>/dev/null | head -1)"
assert_contains "plain init names the recorded integrator" "$out" "integrator: $(hostname):$integ"
home5="$tmp/home5"; mkdir -p "$home5/.gemini"
{ git -C "$AI_KNOWLEDGE_ROOT/main" show origin/main:rules/global.md; echo '- another host-only rule'; } > "$home5/.gemini/GEMINI.md"
out=$(kinit "$home5" </dev/null) || true
assert_contains "without a terminal the command to file it is printed" "$out" "ai-knowledge propose"
assert_eq "without a terminal nothing is filed" "$(git -C "$remote" for-each-ref 'refs/heads/proposal/*' | grep -c -- '-gemini-md-')" 1
# --- ssh remotes: a refused key is loaded into an agent, started when needed
export SSH_STUB_LOADED="$tmp/ssh-loaded" SSH_STUB_AGENT="$tmp/ssh-agent.sock" SSH_STUB_LOG="$tmp/ssh.log" SSH_STUB_KEY="$tmp/id_test"
: > "$SSH_STUB_KEY"; : > "$SSH_STUB_LOG"; rm -f "$SSH_STUB_LOADED" "$SSH_STUB_AGENT"
sshremote="ssh://stub$remote"
sed -i "s|^REMOTE=.*|REMOTE=$sshremote|" "$AI_KNOWLEDGE_CONFIG"
for r in "$AI_KNOWLEDGE_ROOT/main" "$clone" "$iclone"; do git -C "$r" remote set-url origin "$sshremote"; done
unset SSH_AUTH_SOCK
knowledge sync "$proj" >"$tmp/ssh1.out" 2>&1 </dev/null || true
assert_contains "no agent, no terminal: offline" "$(cat "$clone/.sync-status")" offline
assert_no_file "no agent started without a terminal" "$SSH_STUB_AGENT"
assert_eq "no key added without an agent" "$(grep -c 'ssh-add -t' "$SSH_STUB_LOG")" 0
export SSH_AUTH_SOCK="$tmp/user-agent.sock"; : > "$SSH_AUTH_SOCK"
knowledge sync "$proj" >"$tmp/ssh2.out" 2>&1 </dev/null || true
assert_contains "existing agent: key loaded, sync ok" "$(cat "$clone/.sync-status")" ok
assert_contains "key added with a one hour lifetime" "$(cat "$SSH_STUB_LOG")" "ssh-add -t 3600 $SSH_STUB_KEY"
rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
sleep 2 | knowledge sync "$proj" >/dev/null 2>&1 || true
assert_contains "without a terminal ssh-add cannot wait on stdin" "$(cat "$SSH_STUB_LOG")" "stdin=/dev/null"
assert_eq "the user's agent is not killed" "$(grep -c 'ssh-agent -k' "$SSH_STUB_LOG")" 0
assert_contains "user told the key went into their agent" "$(cat "$tmp/ssh2.out")" "one hour"
unset SSH_AUTH_SOCK; rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
if command -v script >/dev/null 2>&1; then
    script -qec "bash '$REPO_ROOT/bin/ai/ai-knowledge' sync '$proj'" /dev/null >"$tmp/ssh3.out" 2>&1 || true
    assert_contains "terminal: agent started, sync ok" "$(cat "$clone/.sync-status")" ok
    assert_contains "terminal: agent started" "$(cat "$SSH_STUB_LOG")" "ssh-agent -s"
    assert_contains "terminal: agent killed at exit" "$(cat "$SSH_STUB_LOG")" "ssh-agent -k"
    assert_no_file "terminal: agent marker gone after the run" "$SSH_STUB_AGENT"
    rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
    SSH_STUB_AGENT_FAIL=1 SSH_AGENT_PID=999999 script -qec "bash '$REPO_ROOT/bin/ai/ai-knowledge' sync '$proj'" /dev/null >/dev/null 2>&1 || true
    assert_contains "agent start failure: sync goes offline" "$(cat "$clone/.sync-status")" offline
    assert_eq "agent start failure: nothing is killed" "$(grep -c 'ssh-agent -k' "$SSH_STUB_LOG")" 0
    rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
    script -qec "bash '$REPO_ROOT/bin/ai/ai-knowledge' sync '$tmp/nonexistent'" /dev/null >/dev/null 2>&1 || true
    assert_contains "die: agent had been started" "$(cat "$SSH_STUB_LOG")" "ssh-agent -s"
    assert_no_file "die: agent killed anyway" "$SSH_STUB_AGENT"
    rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
    script -qec "bash '$REPO_ROOT/bin/ai/ai-knowledge' sync --all" /dev/null >/dev/null 2>&1 || true
    assert_contains "all under a started agent: project ok" "$(cat "$clone/.sync-status")" ok
    assert_contains "all under a started agent: integrator ok" "$(cat "$iclone/.sync-status")" ok
    assert_eq "all: agent killed once, by the parent only" "$(grep -c 'ssh-agent -k' "$SSH_STUB_LOG")" 1
else
    echo "# script(1) missing: pseudo-terminal cases skipped"
fi
: > "$SSH_STUB_LOG"
sed -i "s|^REMOTE=.*|REMOTE=file://$remote|" "$AI_KNOWLEDGE_CONFIG"
for r in "$AI_KNOWLEDGE_ROOT/main" "$clone" "$iclone"; do git -C "$r" remote set-url origin "file://$remote"; done
knowledge sync "$proj" >/dev/null 2>&1 </dev/null || true
assert_eq "a file remote never touches ssh, ssh-add or ssh-agent" "$(wc -l < "$SSH_STUB_LOG")" 0
unset SSH_STUB_LOADED SSH_STUB_AGENT SSH_STUB_LOG SSH_STUB_KEY
# --- without config nothing changes
rm "$AI_KNOWLEDGE_CONFIG"
other="$tmp/work/q"; mkdir -p "$other"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$other" >"$tmp/create2.out" 2>&1 || cat "$tmp/create2.out"
compose=$(cat "$(ai_sandbox_dir_for "$other")/docker-compose.yml")
assert_contains "live GEMINI.md mount kept without config" "$compose" "$HOME/.gemini/GEMINI.md:$HOME/.gemini/GEMINI.md\""
assert_eq "no knowledge mounts without config" "$(printf '%s\n' "$compose" | grep -c knowledge)" 0
assert_contains "create stamps SANDBOX_KNOWLEDGE=0 without config" "$(cat "$(ai_sandbox_dir_for "$other")/.env")" 'SANDBOX_KNOWLEDGE=0'
assert_no_file "no clone created without config" "$(ai_sandbox_dir_for "$other")/knowledge"

rm -rf "$tmp"
finish
