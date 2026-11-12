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
# C-STATUS: the outcome of a sync is <sandbox dir>/status/knowledge, line 1 "<time> <word> <message>".
status_file() { printf '%s/status/knowledge' "$(dirname "$1")"; }   # <clone>
status_of() {   # <clone>: line 1 without its timestamp, as the sync's own text (ok/refused/offline carry their colon)
    local l w
    l=$(head -1 "$(status_file "$1")" 2>/dev/null | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8} //')
    case $l in
        ok\ *|refused\ *|offline\ *) w=${l%% *}; l="$w: ${l#* }" ;;
        warn\ *) l=${l#warn } ;;
    esac
    printf '%s' "$l"
}
assert_status() {   # <name> <clone> <word>: the status line starts, after its timestamp, with the word
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$(status_of "$2")" in
        "$3"*) _pass "$1" ;;
        *)     _fail "$1" "expected status word '$3', got '$(status_of "$2")'" ;;
    esac
}

STATUS_SHAPE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} (ok|warn|refused|offline) .+$'
assert_status_shape() {   # <name> <clone> <word>: line 1 of the status file is the contract's shape with that word
    local line; line=$(head -1 "$(status_file "$2")" 2>/dev/null)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ $line =~ $STATUS_SHAPE ]] && [ "$(printf '%s' "$line" | cut -d' ' -f2)" = "$3" ]; then _pass "$1"
    else _fail "$1" "line 1 of $(status_file "$2") is '$line', expected the shape with word '$3'"; fi
}

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

# --- D10: `tools:` reaches the Claude copy only; Gemini's tool names differ
# (fixture role in the test's own checkout, removed again right after)
cp "$AI_KNOWLEDGE_ROOT/main/roles/planner.md" "$tmp/planner.orig"
printf -- '---\nname: probe\ndescription: probe role\ntools: Read, Grep\n---\ntools: a body line stays\nbody\n' > "$AI_KNOWLEDGE_ROOT/main/roles/probe.md"
knowledge render >"$tmp/render-tools.out" 2>&1 || cat "$tmp/render-tools.out"
assert_contains "tools key kept in the claude copy" "$(cat "$AI_KNOWLEDGE_RENDER/claude/agents/probe.md")" "tools: Read, Grep"
assert_eq "tools key absent from the front matter of the gemini copy" "$(awk 'NR==1{next} /^---$/{exit} /^tools:/{n++} END{print n+0}' "$AI_KNOWLEDGE_RENDER/gemini/agents/probe.md")" 0
assert_same_bytes() {   # <name> <a> <b>: cmp, because $(...) drops trailing newlines
    TESTS_RUN=$((TESTS_RUN + 1))
    if cmp -s "$2" "$3"; then _pass "$1"; else _fail "$1" "$2 and $3 differ byte for byte"; fi
}
grep -v -x 'tools: Read, Grep' "$AI_KNOWLEDGE_RENDER/claude/agents/probe.md" > "$tmp/probe.expected"
assert_same_bytes "gemini copy is the claude copy minus that line" "$tmp/probe.expected" "$AI_KNOWLEDGE_RENDER/gemini/agents/probe.md"
assert_contains "a body line starting with tools: stays in the gemini copy" "$(cat "$AI_KNOWLEDGE_RENDER/gemini/agents/probe.md")" "tools: a body line stays"
assert_same_bytes "role without the key identical in claude and gemini copies" "$AI_KNOWLEDGE_RENDER/claude/agents/planner.md" "$AI_KNOWLEDGE_RENDER/gemini/agents/planner.md"
assert_same_bytes "role without the key unchanged from its source" "$tmp/planner.orig" "$AI_KNOWLEDGE_RENDER/claude/agents/planner.md"
# `model:` holds Claude Code aliases: Claude copy keeps it, Gemini copy drops it
printf -- '---\nname: probe\ndescription: probe role\nmodel: haiku\n---\nmodel: a body line stays\nbody\n' > "$AI_KNOWLEDGE_ROOT/main/roles/probe.md"
knowledge render >"$tmp/render-model.out" 2>&1 || cat "$tmp/render-model.out"
assert_contains "model key kept in the claude copy" "$(cat "$AI_KNOWLEDGE_RENDER/claude/agents/probe.md")" "model: haiku"
assert_eq "model key absent from the front matter of the gemini copy" "$(awk 'NR==1{next} /^---$/{exit} /^model:/{n++} END{print n+0}' "$AI_KNOWLEDGE_RENDER/gemini/agents/probe.md")" 0
grep -v -x 'model: haiku' "$AI_KNOWLEDGE_RENDER/claude/agents/probe.md" > "$tmp/probe.expected"
assert_same_bytes "gemini copy is the claude copy minus the model line" "$tmp/probe.expected" "$AI_KNOWLEDGE_RENDER/gemini/agents/probe.md"
assert_contains "a body line starting with model: stays in the gemini copy" "$(cat "$AI_KNOWLEDGE_RENDER/gemini/agents/probe.md")" "model: a body line stays"
assert_eq "model key not in the antigravity copy" "$(grep -c '^model: haiku' "$AI_KNOWLEDGE_RENDER/antigravity/rules/probe.md")" 0
assert_eq "model key not in the codex copy" "$(grep -c '^model: haiku' "$AI_KNOWLEDGE_RENDER/codex/agents/probe.toml")" 0
rm -f "$AI_KNOWLEDGE_ROOT/main/roles/probe.md"
knowledge render >/dev/null 2>&1
assert_link "host claude agent symlink" "$HOME/.claude/agents/planner.md" "$AI_KNOWLEDGE_RENDER/claude/agents/planner.md"
assert_file "own skill copied into ~/.agents" "$HOME/.agents/skills/propose-rule/SKILL.md"
assert_file "own skill copied into the shared store" "$AI_SANDBOX_ROOT/shared/agent-skills/skills/propose-rule/SKILL.md"
assert_link "host claude skill symlink" "$HOME/.claude/skills/propose-rule" "../../.agents/skills/propose-rule"

# --- sync creates a project sandbox clone on main, with role file and hook
pid=$(ai_sandbox_project_id "$proj"); pdir=$(ai_sandbox_dir_for "$proj"); mkdir -p "$pdir"
knowledge sync "$proj" >"$tmp/sync1.out" 2>&1 || cat "$tmp/sync1.out"
clone="$pdir/knowledge"
assert_eq "clone on main" "$(git -C "$clone" branch --show-current)" main
assert_status "status ok" "$clone" "ok:"
assert_status_shape "status file line 1 is the contract's shape (ok)" "$clone" ok
assert_eq "status file carries role= and project-id= after line 1" "$(sed -n '2,$p' "$(status_file "$clone")" | tr '\n' ' ')" "role=proposals project-id=$pid "
assert_no_file "no status file is written below the clone" "$clone/.sync-status"
assert_file "the sandbox directory holds status/" "$pdir/status"
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
assert_contains "status counts the push" "$(status_of "$clone")" "pushed 1"
git -C "$clone" checkout -q -b "proposal/$today-escape-abcd" main
echo hacked >> "$clone/roles/planner.md"; git -C "$clone" commit -q --no-verify -am "escape"; git -C "$clone" checkout -q main
git -C "$clone" checkout -q -b "proposal/tmp-half" main
echo 'scope: global' > "$clone/proposals/$today-half.md"; git -C "$clone" add -A; git -C "$clone" commit -qm "half"; git -C "$clone" checkout -q main
knowledge sync "$proj" >/dev/null 2>&1
assert_status "out-of-scope branch refused" "$clone" "refused:"
assert_status_shape "status file line 1 is the contract's shape (refused)" "$clone" refused
assert_contains "refusal names the branch" "$(status_of "$clone")" "escape-abcd"
assert_contains "malformed name refused" "$(status_of "$clone")" "tmp-half"
git -C "$remote" show-ref -q "refs/heads/proposal/$today-escape-abcd" && r=yes || r=no
assert_eq "refused branch not on the remote" "$r" no
git -C "$remote" show-ref -q "refs/heads/proposal/tmp-half" && r=yes || r=no
assert_eq "malformed branch not on the remote" "$r" no
git -C "$clone" branch -q -D "proposal/$today-escape-abcd" "proposal/tmp-half"
echo wip > "$clone/proposals/wip.md"
knowledge sync "$proj" >/dev/null 2>&1
assert_status "dirty tree skipped" "$clone" "skipped:"
assert_status_shape "status file line 1 is the contract's shape (warn)" "$clone" warn
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
assert_contains "status file of the integrator says so" "$(cat "$(status_file "$iclone")")" "role=integrator"
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
assert_status "integrator status ok" "$iclone" "ok:"

# --- the proposer's next sync fast-forwards main and drops its closed branch without re-creating it
knowledge sync "$proj" >/dev/null 2>&1
assert_contains "main fast-forwarded in the clone" "$(cat "$clone/rules/global.md")" "- be kind"
git -C "$clone" show-ref -q "refs/heads/$b1" && r=yes || r=no
assert_eq "closed branch deleted locally" "$r" no
git -C "$remote" show-ref -q "refs/heads/$b1" && r=yes || r=no
assert_eq "closed branch not re-created on the remote" "$r" no
assert_contains "status counts the close" "$(status_of "$clone")" "closed 1"

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

# --- an amendment that lands between the integrator's fetch and its remote deletion is kept by the lease
b_lease=$(propose_in "$clone" lease); tip0=$(git -C "$clone" rev-parse "$b_lease")
knowledge sync "$proj" >/dev/null 2>&1; knowledge sync "$integ" >/dev/null 2>&1
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: lease rejected" "$b_lease"
mkdir -p "$tmp/lease"; ln -sfn "$REPO_ROOT/tests/ai-sandbox/stub/lease-timeout" "$tmp/lease/timeout"
LEASE_STUB_MODE=amend LEASE_STUB_CLONE="$clone" PATH="$tmp/lease:$PATH" knowledge sync "$integ" >"$tmp/lease.out" 2>&1
assert_eq "amendment made during the integrator's sync" "$(git -C "$clone" rev-parse "$b_lease" | grep -vc "^$tip0\$")" 1
assert_eq "leased deletion keeps the amended branch on the remote" "$(git -C "$remote" rev-parse -q --verify "refs/heads/$b_lease")" "$(git -C "$clone" rev-parse "$b_lease")"
assert_status "rejected lease leaves the integrator status ok" "$iclone" "ok:"
assert_eq "rejected lease is not reported as a failed deletion" "$(grep -c 'cannot delete' "$tmp/lease.out")" 0
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "proposal amended under the lease listed again" "$(knowledge proposals --repo "$iclone")" "$b_lease proposals/$today-lease.md"
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: lease rejected again" "$b_lease"
knowledge sync "$integ" >/dev/null 2>&1; knowledge sync "$proj" >/dev/null 2>&1
git -C "$remote" show-ref -q "refs/heads/$b_lease" && r=yes || r=no
assert_eq "re-closed leased branch deleted" "$r" no

# --- a clone parked on a proposal branch still gets main; a closed parked branch is left on main
b3=$(propose_in "$clone" park); git -C "$clone" checkout -q "$b3"
echo '- be brief' >> "$iclone/rules/global.md"; git -C "$iclone" commit -qam "feat: brevity"
knowledge sync "$integ" >/dev/null 2>&1
knowledge sync "$proj" >/dev/null 2>&1
knowledge sync "$integ" >/dev/null 2>&1   # the integrator fetches the parked branch
assert_eq "parked clone keeps its branch" "$(git -C "$clone" branch --show-current)" "$b3"
assert_eq "parked clone's main follows origin" "$(git -C "$clone" rev-parse main)" "$(git -C "$remote" rev-parse main)"
assert_status "parked clone status ok" "$clone" "ok:"
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: park rejected" "$b3"
knowledge sync "$integ" >/dev/null 2>&1; knowledge sync "$proj" >/dev/null 2>&1
assert_eq "closed parked branch: clone moved to main" "$(git -C "$clone" branch --show-current)" main
git -C "$clone" show-ref -q "refs/heads/$b3" && r=yes || r=no
assert_eq "closed parked branch deleted" "$r" no

# --- a local commit on main is diverged; proposal branches are still pushed
git -C "$clone" commit -q --no-verify --allow-empty -m "local on main"
b4=$(propose_in "$clone" diverge)
knowledge sync "$proj" >/dev/null 2>&1
assert_status "diverged main reported" "$clone" "diverged:"
assert_contains "diverged message moves the commits onto a proposal branch" "$(status_of "$clone")" "branch proposal/tmp-"
assert_contains "diverged message resets only after that" "$(status_of "$clone")" "reset --hard origin/main"
assert_eq "proposal pushed despite diverged main" "$(git -C "$remote" rev-parse "$b4")" "$(git -C "$clone" rev-parse "$b4")"
git -C "$clone" reset -q --hard origin/main
knowledge sync "$integ" >/dev/null 2>&1
git -C "$iclone" merge -q -s ours --no-ff -m "proposal: diverge rejected" "$b4"
knowledge sync "$integ" >/dev/null 2>&1; knowledge sync "$proj" >/dev/null 2>&1
assert_status "status ok after the reset" "$clone" "ok:"

# --- offline is a status, not a failure, and the manual commands are printed
mv "$remote" "$remote.away"
knowledge sync "$proj" >"$tmp/offline.out" 2>&1; rc=$?
assert_eq "offline sync exits 0" "$rc" 0
assert_status "offline status" "$clone" "offline:"
assert_status_shape "status file line 1 is the contract's shape (offline)" "$clone" offline
assert_contains "manual fetch of main printed" "$(cat "$tmp/offline.out")" "git -C $AI_KNOWLEDGE_ROOT/main fetch --prune origin"
assert_contains "manual fetch of the clone printed" "$(cat "$tmp/offline.out")" "git -C $clone fetch --prune origin"
assert_contains "manual sync printed" "$(cat "$tmp/offline.out")" "ai-knowledge sync $proj"
assert_eq "no push printed when nothing is pending" "$(grep -c 'git -C .* push ' "$tmp/offline.out")" 0
b5=$(propose_in "$clone" offline)
knowledge sync "$proj" >"$tmp/offline2.out" 2>&1
assert_contains "pending push printed when offline" "$(cat "$tmp/offline2.out")" \
    "git -C $clone push origin $b5:refs/heads/$b5"
assert_contains "offline status names the pending push" "$(status_of "$clone")" "push"
knowledge sync "$integ" >"$tmp/offline3.out" 2>&1
assert_contains "integrator manual fetch printed" "$(cat "$tmp/offline3.out")" "git -C $iclone fetch origin"
mv "$remote.away" "$remote"
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "pending proposal pushed once online" "$(git -C "$remote" rev-parse "$b5")" "$(git -C "$clone" rev-parse "$b5")"
assert_status "status ok again once online" "$clone" "ok:"

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
assert_status "manual clone status ok" "$mdir/knowledge" "ok:"
assert_file "manual clone got the hook" "$mdir/knowledge/.git/hooks/pre-commit"
git -C "$mdir/knowledge" checkout -q -b "proposals/old-id" main
knowledge sync "$manual" >/dev/null 2>&1
assert_status "old-style branch skipped" "$mdir/knowledge" "skipped:"
assert_contains "old-style skip names the migration" "$(status_of "$mdir/knowledge")" "migrate-knowledge"
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
assert_contains "doctor lists pending reports" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'refs/reports/'
assert_contains "sandbox block names the report ref and its invariant" "$(tr '\n' ' ' < "$AI_KNOWLEDGE_RENDER/GLOBAL.md" | tr -s ' ')" "refs/reports/<date>-<project>-<hex>, outside main and every branch"
assert_eq "sandbox block no longer names a per-sandbox branch" "$(grep -c 'proposals/<project-id>' "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" 0
assert_contains "sandbox block names the proposal branch pattern" "$(cat "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "proposal/<date>-<slug>-<hex>"
assert_file "seed installed beside the helper" "$AI_SANDBOX_ROOT/bin/knowledge-seed/skills/propose-rule/SKILL.md"
assert_contains "summary names the knowledge render" "$(cat "$tmp/create.out")" "Shared knowledge repository"

assert_contains "create stamps SANDBOX_KNOWLEDGE=1" "$(cat "$pdir/.env")" 'SANDBOX_KNOWLEDGE=1'
assert_contains "create records the project dir" "$(cat "$pdir/.env")" "SANDBOX_PROJECT_DIR=$proj"
assert_contains "stamp passed into the container" "$compose" 'SANDBOX_KNOWLEDGE=${SANDBOX_KNOWLEDGE}'
assert_contains "subagent cache TTL passed into the container" "$compose" 'CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=1h'
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
assert_contains "stale refusal names the single-sandbox repair with the stamped project" "$msg" "create-ai-sandbox.sh $tmp/work/fab-b"
msg=$(ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-c-agent" 2>&1) || true
assert_contains "unstamped refusal explains the missing stamp" "$msg" "before the knowledge stamp"
assert_contains "unstamped refusal without a recoverable project shows a placeholder" "$msg" "create-ai-sandbox.sh <project dir>"
printf '%s\n' "$tmp/work/fab-c" > "$AI_SANDBOX_ROOT/fab-c-agent/project-path"
msg=$(ai_sandbox_require_current "$AI_SANDBOX_ROOT/fab-c-agent" 2>&1) || true
assert_contains "unstamped refusal falls back to project-path" "$msg" "create-ai-sandbox.sh $tmp/work/fab-c"
rm -f "$AI_SANDBOX_ROOT/fab-c-agent/project-path"
# --- _sync-clone syncs one clone and never renders (phase 2)
knowledge _sync-clone "$proj" "$pdir" >"$tmp/one.out" 2>&1 || cat "$tmp/one.out"
assert_status "_sync-clone leaves the clone ok" "$clone" "ok:"
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
assert_status "all: project clone ok" "$clone" "ok:"
assert_status "all: integrator clone ok" "$iclone" "ok:"
assert_status "all: third clone created and ok" "$tdir/knowledge" "ok:"
assert_eq "all: one render when main did not move" "$(grep -c 'rendered' "$tmp/all1.out")" 1
assert_contains "all: table row for the third sandbox" "$(grep "$(basename "$tdir")" "$tmp/all1.out" | tail -1)" " ok main current"
assert_contains "all: unstamped sandbox reported, not synced" "$(grep fab-c-agent "$tmp/all1.out" | tail -1)" "unstamped"
assert_contains "all: unstamped row names create-ai-sandbox.sh" "$(grep fab-c-agent "$tmp/all1.out" | tail -1)" "create-ai-sandbox.sh"
assert_contains "all: stale row names create-ai-sandbox.sh with the stamped project" "$(grep fab-b-agent "$tmp/all1.out" | tail -1)" "create-ai-sandbox.sh $tmp/work/fab-b"
assert_contains "all: stale row names the bulk script as the shortcut" "$(grep fab-b-agent "$tmp/all1.out" | tail -1)" "ai-sandbox-migrate-knowledge"
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
assert_contains "status shows the last sync of the real sandbox" "$(printf '%s\n' "$all" | grep "$(basename "$pdir")")" " ok main current"
one=$(knowledge status "$proj" 2>&1)
assert_contains "status with a project keeps the single view" "$one" "clone:       $pdir/knowledge"
assert_eq "status with a project lists no other sandbox" "$(printf '%s\n' "$one" | grep -c fab-)" 0
assert_contains "doctor reads the stamp" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'SANDBOX_KNOWLEDGE'
assert_contains "doctor names the migration script" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'ai-sandbox-migrate-knowledge'
assert_contains "doctor names the single repair" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 'create-ai-sandbox.sh'
# --- the start scripts refuse a sandbox whose stamp does not match the host
stale="$tmp/work/stale"; mkdir -p "$stale"; git -C "$stale" init -q
sdir=$(ai_sandbox_dir_for "$stale"); mkdir -p "$sdir"
printf 'services: {}\n' > "$sdir/docker-compose.yml"
printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$stale" > "$sdir/.env"
# a running container is entered whatever its stamp: the check guards only the start
: > "$DOCKER_STUB_LOG"
msg=$(cd "$stale" && DOCKER_STUB_RUNNING=true bash "$REPO_ROOT/bin/ai/ai-sandbox" 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox enters a running stale sandbox" "$r" 0
assert_contains "entering a running stale sandbox goes through compose" "$(stub_docker_log)" "compose"
assert_contains "entering a running stale sandbox execs into it" "$(stub_docker_log)" "exec"
assert_eq "no compose up for a running stale sandbox" "$(grep -c ' up' "$DOCKER_STUB_LOG")" 0
: > "$DOCKER_STUB_LOG"
msg=$(cd "$stale" && DOCKER_STUB_RUNNING=false bash "$REPO_ROOT/bin/ai/ai-sandbox" 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox refuses to start a stale sandbox" "$r" 1
assert_contains "ai-sandbox names the migration script" "$msg" "ai-sandbox-migrate-knowledge"
assert_contains "ai-sandbox names create-ai-sandbox.sh with the project directory" "$msg" "create-ai-sandbox.sh $stale"
assert_eq "no compose call for a refused start" "$(grep -c compose "$DOCKER_STUB_LOG")" 0
msg=$(cd "$stale" && DOCKER_STUB_RUNNING=true bash "$REPO_ROOT/bin/ai/ai-sandbox-restart" 2>&1) && r=0 || r=$?
assert_eq "ai-sandbox-restart refuses a running stale sandbox" "$r" 1
assert_eq "no compose down for a refused restart" "$(grep -c 'compose.*down' "$DOCKER_STUB_LOG")" 0
assert_contains "restart refusal names create-ai-sandbox.sh with the project directory" "$msg" "create-ai-sandbox.sh $stale"
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
assert_eq "nothing converted when the run stops" "$(git -C "$remote" for-each-ref 'refs/heads/proposal/*' | grep -c -E -- '-oldproj-1234-(alpha|beta|gamma|delta)-')" 0
git -C "$mdir/knowledge" fetch -q origin; git -C "$mdir/knowledge" merge -q --no-edit origin/proposals/oldproj-1234
oldtip=$(git -C "$mdir/knowledge" rev-parse HEAD)
out=$(printf 'y\n' | migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "branch migration succeeds" "$r" 0
# the converted branch is named <project-id>-<slug>, so equal slugs from two projects never collide
newbranches=$(git -C "$remote" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*' | grep -E -- "^proposal/$today-oldproj-1234-(alpha|beta|gamma|delta)-[0-9a-f]{4}\$" | sort)
assert_eq "four old proposals became four proposal branches" "$(printf '%s\n' "$newbranches" | grep -c .)" 4
gb=$(printf '%s\n' "$newbranches" | grep gamma)
assert_contains "converted file carries project_id" "$(git -C "$remote" show "$gb:proposals/$today-oldproj-1234-gamma.md")" "project_id: oldproj-1234"
assert_contains "converted file carries machine unknown" "$(git -C "$remote" show "$gb:proposals/$today-oldproj-1234-gamma.md")" "machine: unknown"
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
# --- migration (phase 5): running sandboxes are stopped only on request, equal slugs from two projects
# stay apart, conversion runs on every host, declining the deletion still moves clones to main
for id in px-1111 py-2222; do
    git -C "$oldc" checkout -q -b "proposals/$id" origin/main; mkdir -p "$oldc/proposals/$id"
    printf -- '---\nscope: global\n---\n\n# same\n\nfrom %s\n' "$id" > "$oldc/proposals/$id/2026-09-06-same.md"
    git -C "$oldc" add -A; git -C "$oldc" commit -qm "$id"; git -C "$oldc" push -q origin "proposals/$id"
done
git -C "$clone" fetch -q origin; git -C "$clone" checkout -q -b proposals/px-1111 origin/proposals/px-1111
rproj="$tmp/work/r"; mkdir -p "$rproj"; git -C "$rproj" init -q
rdir=$(ai_sandbox_dir_for "$rproj"); mkdir -p "$rdir"
printf 'services:\n  x:\n    container_name: "%s"\n' "$(basename "$rdir")" > "$rdir/docker-compose.yml"
printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$rproj" > "$rdir/.env"
: > "$DOCKER_STUB_LOG"
# no answer to either prompt: the running sandbox is skipped, the remote branches stay, clones still move
out=$(DOCKER_STUB_RUNNING=true migrate --display=none 2>&1 </dev/null) && r=0 || r=$?
assert_eq "a skipped running sandbox is not a failure" "$r" 0
assert_contains "table shows the running column" "$(printf '%s\n' "$out" | head -1)" "running"
assert_contains "the prompt names the running sandbox" "$(printf '%s\n' "$out" | grep -i 'y/N' | head -1)" "$(basename "$rdir")"
assert_eq "running stale sandbox not stopped without an answer" "$(grep -c 'compose.*down' "$DOCKER_STUB_LOG")" 0
assert_eq "running stale sandbox left stale" "$(ai_sandbox_knowledge_state "$rdir")" stale
assert_contains "skipped running sandbox listed at the end" "$(printf '%s\n' "$out" | grep '^skipped')" "$(basename "$rdir")"
assert_eq "two projects with the same slug became two branches" \
    "$(git -C "$remote" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*' | grep -c -E -- "^proposal/$today-p[xy]-[0-9]{4}-same-[0-9a-f]{4}\$")" 2
git -C "$remote" show-ref -q refs/heads/proposals/px-1111 && r=yes || r=no
assert_eq "deletion declined: old remote branch kept" "$r" yes
assert_eq "deletion declined: clone still moved to main" "$(git -C "$clone" branch --show-current)" main
assert_eq "deletion declined: converted local old branch dropped" "$(git -C "$clone" branch --list 'proposals/*' | wc -l | tr -d ' ')" 0
assert_status "deletion declined: moved clone synced ok" "$clone" "ok:"
: > "$DOCKER_STUB_LOG"
# 'y' to both prompts: the running sandbox is stopped and recreated, the converted branches are deleted
out=$(printf 'y\ny\n' | DOCKER_STUB_RUNNING=true migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "confirmed run succeeds" "$r" 0
assert_contains "running stale sandbox stopped after y" "$(stub_docker_log)" "down"
assert_eq "running stale sandbox recreated after y" "$(ai_sandbox_knowledge_state "$rdir")" current
assert_contains "already converted files are not converted again" "$out" "already has a proposal/* branch"
assert_eq "no second branch for an already converted file" \
    "$(git -C "$remote" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*' | grep -c -E -- "^proposal/$today-px-1111-same-")" 1
git -C "$remote" show-ref -q refs/heads/proposals/px-1111 && r=yes || r=no
assert_eq "old remote branches deleted after y" "$r" no
assert_status "full run: project clone ok" "$clone" "ok:"
assert_status "full run: integrator clone ok" "$iclone" "ok:"
assert_status "full run: manual clone ok" "$mdir/knowledge" "ok:"
assert_status "full run: recreated sandbox clone ok" "$rdir/knowledge" "ok:"
assert_contains "the end names the plain create run that rebuilds the doctor" "$out" "create-ai-sandbox.sh <project>"
rm -rf "$rdir"
# --- migration (phase 5): a remote old branch that a skipped running clone still holds is never
# deleted; "already converted" is decided by the file's body, not by the branch name
git -C "$oldc" checkout -q -b proposals/px-1 origin/main; mkdir -p "$oldc/proposals/px-1"
printf -- '---\nscope: global\n---\n\n# held\n\nv1\n' > "$oldc/proposals/px-1/2026-09-08-held.md"
git -C "$oldc" add -A; git -C "$oldc" commit -qm "held v1"; git -C "$oldc" push -q origin proposals/px-1
qproj="$tmp/work/q"; mkdir -p "$qproj"; git -C "$qproj" init -q
qdir=$(ai_sandbox_dir_for "$qproj"); mkdir -p "$qdir"
printf 'services: {}\n' > "$qdir/docker-compose.yml"
printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$qproj" > "$qdir/.env"
# the running sandbox's clone sits on the old branch with an unpushed v2 of the file
git clone -q "file://$remote" "$qdir/knowledge"; git -C "$qdir/knowledge" checkout -q -b proposals/px-1 origin/proposals/px-1
printf -- '---\nscope: global\n---\n\n# held\n\nv2, unpushed\n' > "$qdir/knowledge/proposals/px-1/2026-09-08-held.md"
git -C "$qdir/knowledge" add -A; git -C "$qdir/knowledge" commit -q --no-verify -m "held v2"
v2=$(git -C "$qdir/knowledge" rev-parse HEAD)
held_branches() { git -C "$remote" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*' | grep -E -- "^proposal/$today-px-1-held-[0-9a-f]{4}\$" || true; }
# run 1: 'n' to stopping the running sandbox, 'y' to the deletion
out=$(printf 'n\ny\n' | DOCKER_STUB_RUNNING=true migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "held branch: run 1 succeeds" "$r" 0
assert_eq "held branch: v1 on the remote is converted" "$(held_branches | grep -c .)" 1
git -C "$remote" show-ref -q refs/heads/proposals/px-1 && r=yes || r=no
assert_eq "held branch: the remote old branch is kept while the skipped clone holds it" "$r" yes
assert_contains "held branch: the output says which sandbox holds it" "$(printf '%s\n' "$out" | grep 'proposals/px-1.*kept')" "$(basename "$qdir")"
assert_eq "held branch: the skipped clone is untouched" "$(git -C "$qdir/knowledge" rev-parse HEAD)" "$v2"
assert_eq "held branch: the skipped clone stays on its branch" "$(git -C "$qdir/knowledge" branch --show-current)" proposals/px-1
# run 2: the sandbox was stopped; v2 differs from the converted v1, so it becomes a second branch
out=$(printf 'y\n' | DOCKER_STUB_RUNNING=false migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "held branch: run 2 succeeds" "$r" 0
assert_eq "held branch: v2 became a second proposal branch" "$(held_branches | grep -c .)" 2
b1=$(held_branches | sed -n 1p); b2=$(held_branches | sed -n 2p)
[ "$(git -C "$remote" show "$b1:proposals/$today-px-1-held.md")" != "$(git -C "$remote" show "$b2:proposals/$today-px-1-held.md")" ] && r=differ || r=same
assert_eq "held branch: the two converted files differ" "$r" differ
assert_contains "held branch: v2 is reachable from a remote ref" "$(git -C "$remote" branch --contains "$v2")" "main"
git -C "$remote" show-ref -q refs/heads/proposals/px-1 && r=yes || r=no
assert_eq "held branch: the remote old branch is deleted once nothing holds it" "$r" no
assert_eq "held branch: the clone moved to main" "$(git -C "$qdir/knowledge" branch --show-current)" main
assert_eq "held branch: the clone's converted old branch dropped" "$(git -C "$qdir/knowledge" branch --list 'proposals/*' | wc -l | tr -d ' ')" 0
# run 3: a local-only old branch whose file equals a counterpart's body is not converted again
git -C "$mdir/knowledge" checkout -q -b proposals/px-1 main; mkdir -p "$mdir/knowledge/proposals/px-1"
git -C "$remote" show "$b2:proposals/$today-px-1-held.md" | sed '/^project_id:/d; /^machine:/d' > "$mdir/knowledge/proposals/px-1/2026-09-08-held.md"
git -C "$mdir/knowledge" add -A; git -C "$mdir/knowledge" commit -q --no-verify -m "held again"
out=$(printf 'y\n' | migrate --display=none 2>&1) && r=0 || r=$?
assert_eq "same body: run succeeds" "$r" 0
assert_contains "same body: reported as already converted" "$out" "already has a proposal/* branch"
assert_eq "same body: no third branch" "$(held_branches | grep -c .)" 2
assert_eq "same body: the local old branch dropped" "$(git -C "$mdir/knowledge" branch --list 'proposals/*' | wc -l | tr -d ' ')" 0
assert_eq "same body: the clone moved to main" "$(git -C "$mdir/knowledge" branch --show-current)" main
rm -rf "$qdir"
# a host without the integrator converts a local-only old branch (its remote branch is gone) from the clone
sed -i 's/^INTEGRATOR=.*/INTEGRATOR=/' "$AI_KNOWLEDGE_CONFIG"
git -C "$mdir/knowledge" checkout -q -b proposals/solo-9999 main; mkdir -p "$mdir/knowledge/proposals/solo-9999"
printf -- '---\nscope: global\n---\n\n# epsilon\n\nlocal only\n' > "$mdir/knowledge/proposals/solo-9999/2026-09-05-epsilon.md"
git -C "$mdir/knowledge" add -A; git -C "$mdir/knowledge" commit -q --no-verify -m "epsilon"
out=$(migrate --display=none 2>&1 </dev/null) && r=0 || r=$?
assert_eq "non-integrator host: run succeeds" "$r" 0
assert_eq "non-integrator host: local-only old branch converted" \
    "$(git -C "$remote" for-each-ref --format='%(refname:short)' 'refs/heads/proposal/*' | grep -c -E -- "^proposal/$today-solo-9999-epsilon-[0-9a-f]{4}\$")" 1
git -C "$remote" show-ref -q refs/heads/proposals/solo-9999 && r=yes || r=no
assert_eq "non-integrator host: local-only old branch not re-pushed" "$r" no
assert_eq "non-integrator host: clone moved to main" "$(git -C "$mdir/knowledge" branch --show-current)" main
assert_eq "non-integrator host: converted local branch dropped" "$(git -C "$mdir/knowledge" branch --list 'proposals/*' | wc -l | tr -d ' ')" 0
assert_status "non-integrator host: clone ok" "$mdir/knowledge" "ok:"
# a conversion that fails keeps the local branch and names it; the clone still moves to main
git -C "$mdir/knowledge" checkout -q -b proposals/solo-8888 main; mkdir -p "$mdir/knowledge/proposals/solo-8888"
printf -- '---\nscope: global\n---\n\n# zeta\n\nlocal only\n' > "$mdir/knowledge/proposals/solo-8888/2026-09-07-zeta.md"
git -C "$mdir/knowledge" add -A; git -C "$mdir/knowledge" commit -q --no-verify -m "zeta"
knowledge sync >/dev/null 2>&1 || true
chmod -R a-w "$AI_KNOWLEDGE_ROOT/main/.git"
out=$(migrate --display=none 2>&1 </dev/null) && r=0 || r=$?
chmod -R u+w "$AI_KNOWLEDGE_ROOT/main/.git"
assert_eq "failed conversion makes the run exit 1" "$r" 1
assert_contains "failed conversion names the branch" "$out" "proposals/solo-8888"
git -C "$mdir/knowledge" show-ref -q refs/heads/proposals/solo-8888 && r=yes || r=no
assert_eq "failed conversion keeps the local branch" "$r" yes
assert_eq "failed conversion: nothing pushed for it" "$(git -C "$remote" for-each-ref 'refs/heads/proposal/*' | grep -c -- '-solo-8888-')" 0
assert_eq "failed conversion: clone still moved to main" "$(git -C "$mdir/knowledge" branch --show-current)" main
out=$(migrate --display=none 2>&1 </dev/null) && r=0 || r=$?
assert_eq "kept branch converted on the next run" "$(git -C "$remote" for-each-ref 'refs/heads/proposal/*' | grep -c -- "-solo-8888-zeta-")" 1
assert_eq "kept branch dropped once converted" "$(git -C "$mdir/knowledge" branch --list 'proposals/*' | wc -l | tr -d ' ')" 0
sed -i "s|^INTEGRATOR=.*|INTEGRATOR=$integ|" "$AI_KNOWLEDGE_CONFIG"
# an ssh remote without an agent holding a key stops the run before anything is touched
printf 'SANDBOX_KNOWLEDGE=0\nSANDBOX_PROJECT_DIR=%s\n' "$stale" > "$sdir/.env"
sed -i "s|^REMOTE=.*|REMOTE=ssh://stub$remote|" "$AI_KNOWLEDGE_CONFIG"
: > "$DOCKER_STUB_LOG"; unset SSH_AUTH_SOCK
out=$(migrate --display=none 2>&1 </dev/null) && r=0 || r=$?
assert_eq "ssh remote without an agent: exit 1" "$r" 1
assert_contains "ssh remote without an agent: says how to load a key" "$out" 'eval "$(ssh-agent -s)"; ssh-add'
assert_eq "ssh remote without an agent: stale sandbox untouched" "$(ai_sandbox_knowledge_state "$sdir")" stale
assert_eq "ssh remote without an agent: docker never called" "$(wc -l < "$DOCKER_STUB_LOG")" 0
export SSH_AUTH_SOCK="$tmp/empty-agent.sock"; : > "$SSH_AUTH_SOCK"
out=$(migrate --display=none 2>&1 </dev/null) && r=0 || r=$?
assert_eq "ssh remote with an empty agent: exit 1" "$r" 1
unset SSH_AUTH_SOCK; rm -f "$tmp/empty-agent.sock"
sed -i "s|^REMOTE=.*|REMOTE=file://$remote|" "$AI_KNOWLEDGE_CONFIG"
out=$(migrate --display=none 2>&1 </dev/null) && r=0 || r=$?
assert_eq "file remote: the stale sandbox is recreated" "$(ai_sandbox_knowledge_state "$sdir")" current
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

# --- a bare remote whose HEAD names a missing master: the second host must not re-seed
remote3="$tmp/remote3.git"; git init -q --bare --initial-branch=master "$remote3"
home6="$tmp/home6"; mkdir -p "$home6/.gemini"; echo '# host six rules' > "$home6/.gemini/GEMINI.md"
HOME="$home6" AI_SANDBOX_ROOT="$home6/.ai-sandbox" bash "$REPO_ROOT/bin/ai/ai-knowledge" init "file://$remote3" >/dev/null 2>&1 </dev/null || true
assert_eq "first host seeded main on a master-headed remote" "$(git -C "$remote3" rev-parse --verify -q main | wc -c | tr -d ' ')" 41
home7="$tmp/home7"; mkdir -p "$home7/.gemini"; printf '# host six rules\n- seven only\n' > "$home7/.gemini/GEMINI.md"
out=$(HOME="$home7" AI_SANDBOX_ROOT="$home7/.ai-sandbox" bash "$REPO_ROOT/bin/ai/ai-knowledge" init "file://$remote3" 2>&1 </dev/null) || true
assert_eq "second host does not re-seed" "$(printf '%s\n' "$out" | grep -c 'seeding')" 0
assert_eq "second host's checkout is on main" "$(git -C "$home7/.ai-sandbox/knowledge/main" branch --show-current)" main
assert_contains "second host sees its drift" "$out" "+- seven only"
# --- ssh remotes: a refused key is loaded into an agent, started when needed
export SSH_STUB_LOADED="$tmp/ssh-loaded" SSH_STUB_AGENT="$tmp/ssh-agent.sock" SSH_STUB_LOG="$tmp/ssh.log" SSH_STUB_KEY="$tmp/id_test"
: > "$SSH_STUB_KEY"; : > "$SSH_STUB_LOG"; rm -f "$SSH_STUB_LOADED" "$SSH_STUB_AGENT"
sshremote="ssh://stub$remote"
sed -i "s|^REMOTE=.*|REMOTE=$sshremote|" "$AI_KNOWLEDGE_CONFIG"
for r in "$AI_KNOWLEDGE_ROOT/main" "$clone" "$iclone"; do git -C "$r" remote set-url origin "$sshremote"; done
unset SSH_AUTH_SOCK
knowledge sync "$proj" >"$tmp/ssh1.out" 2>&1 </dev/null || true
assert_status "no agent, no terminal: offline" "$clone" "offline:"
assert_no_file "no agent started without a terminal" "$SSH_STUB_AGENT"
assert_eq "no key added without an agent" "$(grep -c 'ssh-add -t' "$SSH_STUB_LOG")" 0
export SSH_AUTH_SOCK="$tmp/user-agent.sock"; : > "$SSH_AUTH_SOCK"
knowledge sync "$proj" >"$tmp/ssh2.out" 2>&1 </dev/null || true
assert_status "existing agent: key loaded, sync ok" "$clone" "ok:"
assert_contains "key added with a one hour lifetime" "$(cat "$SSH_STUB_LOG")" "ssh-add -t 3600 $SSH_STUB_KEY"
rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
sleep 2 | knowledge sync "$proj" >/dev/null 2>&1 || true
assert_contains "without a terminal ssh-add cannot wait on stdin" "$(cat "$SSH_STUB_LOG")" "stdin=/dev/null"
assert_eq "the user's agent is not killed" "$(grep -c 'ssh-agent -k' "$SSH_STUB_LOG")" 0
assert_contains "user told the key went into their agent" "$(cat "$tmp/ssh2.out")" "one hour"
unset SSH_AUTH_SOCK; rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
if command -v script >/dev/null 2>&1; then
    script -qec "bash '$REPO_ROOT/bin/ai/ai-knowledge' sync '$proj'" /dev/null >"$tmp/ssh3.out" 2>&1 || true
    assert_status "terminal: agent started, sync ok" "$clone" "ok:"
    assert_contains "terminal: agent started" "$(cat "$SSH_STUB_LOG")" "ssh-agent -s"
    assert_contains "terminal: agent killed at exit" "$(cat "$SSH_STUB_LOG")" "ssh-agent -k"
    assert_no_file "terminal: agent marker gone after the run" "$SSH_STUB_AGENT"
    rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
    SSH_STUB_AGENT_FAIL=1 SSH_AGENT_PID=999999 script -qec "bash '$REPO_ROOT/bin/ai/ai-knowledge' sync '$proj'" /dev/null >/dev/null 2>&1 || true
    assert_status "agent start failure: sync goes offline" "$clone" "offline:"
    assert_eq "agent start failure: nothing is killed" "$(grep -c 'ssh-agent -k' "$SSH_STUB_LOG")" 0
    rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
    script -qec "bash '$REPO_ROOT/bin/ai/ai-knowledge' sync '$tmp/nonexistent'" /dev/null >/dev/null 2>&1 || true
    assert_contains "die: agent had been started" "$(cat "$SSH_STUB_LOG")" "ssh-agent -s"
    assert_no_file "die: agent killed anyway" "$SSH_STUB_AGENT"
    rm -f "$SSH_STUB_LOADED"; : > "$SSH_STUB_LOG"
    script -qec "bash '$REPO_ROOT/bin/ai/ai-knowledge' sync --all" /dev/null >/dev/null 2>&1 || true
    assert_status "all under a started agent: project ok" "$clone" "ok:"
    assert_status "all under a started agent: integrator ok" "$iclone" "ok:"
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
# --- phase 5: the scope check fails closed (no merge base; a rename out of rules/)
otree=$(git -C "$clone" mktree </dev/null); oc=$(git -C "$clone" commit-tree "$otree" -m orphan)
git -C "$clone" update-ref "refs/heads/proposal/$today-orphan-abcd" "$oc"
knowledge sync "$proj" >/dev/null 2>&1
assert_status "orphan branch refused" "$clone" "refused:"
assert_contains "orphan refusal explains the missing history" "$(status_of "$clone")" "no common history with main"
git -C "$remote" show-ref -q "refs/heads/proposal/$today-orphan-abcd" && r=yes || r=no
assert_eq "orphan branch not on the remote" "$r" no
git -C "$clone" branch -q -D "proposal/$today-orphan-abcd"
git -C "$clone" checkout -q -b "proposal/$today-rename-abcd" main
git -C "$clone" mv rules/global.md "proposals/$today-rename.md"; git -C "$clone" commit -q --no-verify -m "rename out of rules"
git -C "$clone" checkout -q main
knowledge sync "$proj" >/dev/null 2>&1
assert_status "rename out of rules/ refused" "$clone" "refused:"
assert_contains "rename refusal names the removed path" "$(status_of "$clone")" "rules/global.md"
git -C "$remote" show-ref -q "refs/heads/proposal/$today-rename-abcd" && r=yes || r=no
assert_eq "renaming branch not on the remote" "$r" no
git -C "$clone" branch -q -D "proposal/$today-rename-abcd"
git -C "$clone" branch -q proposal/tmp-rename-me main
knowledge sync "$proj" >/dev/null 2>&1
assert_contains "malformed-name refusal says how to rename" "$(status_of "$clone")" "git -C ~/knowledge branch -m proposal/tmp-rename-me proposal/<date>-<slug>-<4 hex>"
git -C "$clone" branch -q -D proposal/tmp-rename-me

# --- an empty branch (its tip on main's first-parent chain) is reported and kept at all three sites
git -C "$clone" branch -q "proposal/$today-empty-aaaa" main
git -C "$clone" branch -q "proposal/$today-older-bbbb" origin/main~1
knowledge sync "$proj" >/dev/null 2>&1
assert_status "empty branches leave the status ok" "$clone" "ok:"
assert_contains "empty branches counted" "$(status_of "$clone")" "empty 2"
assert_eq "empty branches kept" "$(git -C "$clone" branch --list "proposal/$today-empty-aaaa" "proposal/$today-older-bbbb" | wc -l | tr -d ' ')" 2
git -C "$remote" show-ref -q "refs/heads/proposal/$today-empty-aaaa" && r=yes || r=no
assert_eq "empty branch not pushed" "$r" no
git -C "$clone" push -q origin "proposal/$today-empty-aaaa:refs/heads/proposal/$today-empty-aaaa"
git -C "$iclone" branch -q "proposal/$today-iempty-cccc" main
knowledge sync "$integ" >/dev/null 2>&1
assert_status "integrator ok with empty branches around" "$iclone" "ok:"
git -C "$remote" show-ref -q "refs/heads/proposal/$today-empty-aaaa" && r=yes || r=no
assert_eq "integrator leaves an empty remote branch alone" "$r" yes
assert_eq "integrator keeps its own empty branch" "$(git -C "$iclone" branch --list "proposal/$today-iempty-cccc" | wc -l | tr -d ' ')" 1
git -C "$clone" push -q origin ":refs/heads/proposal/$today-empty-aaaa"
git -C "$clone" branch -q -D "proposal/$today-empty-aaaa" "proposal/$today-older-bbbb"
git -C "$iclone" branch -q -D "proposal/$today-iempty-cccc" "proposal/$today-empty-aaaa"

# --- a failing render keeps the previous GLOBAL.md and still syncs the clone
mkdir -p "$tmp/nopy"; printf '#!/bin/sh\necho "python3 stub: broken" >&2\nexit 1\n' > "$tmp/nopy/python3"; chmod +x "$tmp/nopy/python3"
sum_before=$(md5sum < "$AI_KNOWLEDGE_RENDER/GLOBAL.md"); rm -f "$(status_file "$clone")"
PATH="$tmp/nopy:$PATH" knowledge sync "$proj" >"$tmp/render-fail.out" 2>&1; rc=$?
assert_eq "render failure does not fail the sync" "$rc" 0
assert_eq "previous GLOBAL.md kept" "$(md5sum < "$AI_KNOWLEDGE_RENDER/GLOBAL.md")" "$sum_before"
assert_status "clone synced despite the render failure" "$clone" "ok:"
assert_contains "render failure is reported" "$(cat "$tmp/render-fail.out")" "render"
assert_eq "render temp dir removed" "$(ls -d "$AI_SANDBOX_ROOT"/shared/.knowledge-render.* 2>/dev/null | wc -l | tr -d ' ')" 0
assert_eq "render failure leaves no unexpected-error trace" "$(grep -c 'unexpected error' "$tmp/render-fail.out")" 0

# --- a git that dies without a word (exit 128, no output) is offline, never a silently stale status
mkdir -p "$tmp/lease"; ln -sfn "$REPO_ROOT/tests/ai-sandbox/stub/lease-timeout" "$tmp/lease/timeout"
rm -f "$(status_file "$clone")"
LEASE_STUB_MODE=fetch-fail PATH="$tmp/lease:$PATH" knowledge sync "$proj" >"$tmp/silent.out" 2>&1; rc=$?
assert_eq "silent fetch failure exits 0" "$rc" 0
assert_status "silent fetch failure is offline" "$clone" "offline:"
assert_contains "silent fetch failure is reported with its exit code" "$(cat "$tmp/silent.out")" "exit code 128"
assert_eq "silent fetch failure leaves no unexpected-error trace" "$(grep -c 'unexpected error' "$tmp/silent.out")" 0
knowledge sync "$proj" >/dev/null 2>&1
assert_status "ok again with the real timeout" "$clone" "ok:"

# --- a clone of a master-headed remote is put on main with the rules present
p7="$tmp/work/seven"; mkdir -p "$p7"; git -C "$p7" init -q
d7="$home7/.ai-sandbox/$(ai_sandbox_project_id "$p7")-agent"; mkdir -p "$d7"
HOME="$home7" AI_SANDBOX_ROOT="$home7/.ai-sandbox" knowledge sync "$p7" >"$tmp/seven.out" 2>&1 || cat "$tmp/seven.out"
assert_eq "master-headed remote: clone on main" "$(git -C "$d7/knowledge" branch --show-current)" main
assert_file "master-headed remote: rules present in the clone" "$d7/knowledge/rules/global.md"
assert_status "master-headed remote: status ok" "$d7/knowledge" "ok:"

# --- init --integrator while the integrator clone is ahead: the record waits for sync --all
i7="$tmp/work/integ7"; mkdir -p "$i7"; git -C "$i7" init -q
id7="$home7/.ai-sandbox/$(ai_sandbox_project_id "$i7")-agent"; mkdir -p "$id7"
git clone -q "file://$remote3" "$id7/knowledge" 2>/dev/null; git -C "$id7/knowledge" checkout -q -B main origin/main
git -C "$id7/knowledge" commit -q --allow-empty -m "ahead"
out=$(HOME="$home7" AI_SANDBOX_ROOT="$home7/.ai-sandbox" knowledge init "file://$remote3" --integrator "$i7" 2>&1 </dev/null) || true
assert_contains "record skipped while the integrator clone is ahead" "$out" "the record is skipped"
assert_contains "the skip names sync --all as the way forward" "$out" "Run: ai-knowledge sync --all"
assert_eq "no integrator recorded while the clone is ahead" "$(git -C "$remote3" show main:README.md | grep -c 'ai-knowledge integrator:')" 0

# --- the integrator's diverged main is repaired by a merge, never a reset
side="$tmp/side"; git clone -q "file://$remote" "$side"
echo '- from the side' >> "$side/rules/global.md"; git -C "$side" commit -qam "feat: side"; git -C "$side" push -q origin main
git -C "$iclone" commit -q --allow-empty -m "local integrator commit"
knowledge sync "$integ" >/dev/null 2>&1
assert_status "integrator main diverged" "$iclone" "diverged:"
assert_contains "integrator diverged message says merge" "$(status_of "$iclone")" "merge"
assert_eq "integrator diverged message never says reset --hard" "$(status_of "$iclone" | grep -c 'reset --hard')" 0
git -C "$iclone" merge -q --no-edit origin/main
knowledge sync "$integ" >/dev/null 2>&1
assert_status "integrator ok after the merge" "$iclone" "ok:"
assert_eq "integrator's merged main pushed" "$(git -C "$remote" rev-parse main)" "$(git -C "$iclone" rev-parse main)"

# --- main carrying a proposal file: the integrator is told a branch was merged for real
printf 'stray\n' > "$iclone/proposals/$today-stray.md"; git -C "$iclone" add -A; git -C "$iclone" commit -qm "oops"
knowledge sync "$integ" >"$tmp/stray.out" 2>&1
assert_contains "integrator warned about a proposal file on main" "$(cat "$tmp/stray.out")" "merged for real"
assert_contains "the warning names the file" "$(cat "$tmp/stray.out")" "proposals/$today-stray.md"
git -C "$iclone" rm -q "proposals/$today-stray.md"; git -C "$iclone" commit -qm "remove the stray"
knowledge sync "$integ" >"$tmp/stray2.out" 2>&1
assert_eq "no warning once main is clean" "$(grep -c 'merged for real' "$tmp/stray2.out")" 0

# --- a rejected push of main is a 'push failed' status
printf '#!/bin/sh\nwhile read old new ref; do [ "$ref" != refs/heads/main ] || { echo "main is frozen" >&2; exit 1; }; done\nexit 0\n' > "$remote/hooks/pre-receive"
chmod +x "$remote/hooks/pre-receive"
git -C "$iclone" commit -q --allow-empty -m "frozen out"
knowledge sync "$integ" >/dev/null 2>&1
assert_status "rejected main push is a push failed status" "$iclone" "push failed:"
rm -f "$remote/hooks/pre-receive"
knowledge sync "$integ" >/dev/null 2>&1
assert_status "integrator ok once the push goes through" "$iclone" "ok:"

# --- a knowledge path that is not a clone is moved aside, never removed
ng="$tmp/work/nongit"; mkdir -p "$ng"; git -C "$ng" init -q
ngdir=$(ai_sandbox_dir_for "$ng"); mkdir -p "$ngdir/knowledge"; echo precious > "$ngdir/knowledge/notes.txt"
knowledge sync "$ng" >"$tmp/nongit.out" 2>&1 || cat "$tmp/nongit.out"
aside=$(ls -d "$ngdir"/knowledge.not-a-clone.* 2>/dev/null | head -1)
assert_file "non-git knowledge dir moved aside" "$aside"
assert_eq "moved-aside content intact" "$(cat "$aside/notes.txt" 2>/dev/null)" precious
assert_status "clone created beside the moved dir" "$ngdir/knowledge" "ok:"
assert_contains "status says the old directory was moved" "$(status_of "$ngdir/knowledge")" "not-a-clone"
home8="$tmp/home8"; mkdir -p "$home8/.gemini" "$home8/.ai-sandbox/knowledge/main"; echo stray > "$home8/.ai-sandbox/knowledge/main/stray.txt"
HOME="$home8" AI_SANDBOX_ROOT="$home8/.ai-sandbox" knowledge init "file://$remote" >"$tmp/init8.out" 2>&1 </dev/null || cat "$tmp/init8.out"
assert_file "init moves a non-git main aside" "$(ls -d "$home8"/.ai-sandbox/knowledge/main.not-a-clone.* 2>/dev/null | head -1)"
assert_eq "init cloned main after moving the directory" "$(git -C "$home8/.ai-sandbox/knowledge/main" branch --show-current)" main

# --- hints quote paths: a HOME with a space in it
home9="$tmp/home nine"; mkdir -p "$home9/.gemini"; p9="$tmp/work/nine"; mkdir -p "$p9"; git -C "$p9" init -q
HOME="$home9" AI_SANDBOX_ROOT="$home9/.ai-sandbox" knowledge init "file://$remote" >/dev/null 2>&1 </dev/null || true
d9="$home9/.ai-sandbox/$(ai_sandbox_project_id "$p9")-agent"; mkdir -p "$d9"
mv "$remote" "$remote.away"
HOME="$home9" AI_SANDBOX_ROOT="$home9/.ai-sandbox" knowledge sync "$p9" >"$tmp/space.out" 2>&1
mv "$remote.away" "$remote"
assert_contains "fetch hint quotes the path with a space" "$(cat "$tmp/space.out")" "git -C $(printf '%q' "$home9/.ai-sandbox/knowledge/main") fetch --prune origin"
assert_contains "clone hint quotes the path with a space" "$(cat "$tmp/space.out")" "git clone file://$remote $(printf '%q' "$d9/knowledge")"

# --- two sync --all runs at once: locks keep every clone ok and no child fails
knowledge sync --all >"$tmp/conc1.out" 2>&1 &
c1=$!
knowledge sync --all >"$tmp/conc2.out" 2>&1 &
c2=$!
wait "$c1" || true; wait "$c2" || true
assert_status "concurrent all: project clone ok" "$clone" "ok:"
assert_status "concurrent all: integrator clone ok" "$iclone" "ok:"
assert_status "concurrent all: manual clone ok" "$mdir/knowledge" "ok:"
assert_eq "concurrent all: no error row in either table" "$(cat "$tmp/conc1.out" "$tmp/conc2.out" | grep -c 'error:')" 0
assert_eq "concurrent all: no unexpected-error trace" "$(cat "$tmp/conc1.out" "$tmp/conc2.out" | grep -c 'unexpected error')" 0
assert_eq "concurrent all: scratch files removed" "$(ls "$AI_SANDBOX_ROOT"/*-agent/.sync-output.* "$AI_SANDBOX_ROOT"/*-agent/.sync-exit.* 2>/dev/null | wc -l | tr -d ' ')" 0

has_ref_plain() {   # <repo> <ref>
    git -C "$1" show-ref -q --verify "$2" && echo yes || echo no
}
# --- the host's own checkout prunes tracking refs of proposal branches deleted on the remote
b_prune=$(propose_in "$clone" prune)
knowledge sync "$proj" >/dev/null 2>&1; knowledge sync "$proj" >/dev/null 2>&1
assert_eq "host checkout tracks the pushed proposal" "$(has_ref_plain "$AI_KNOWLEDGE_ROOT/main" "refs/remotes/origin/$b_prune")" yes
git -C "$remote" update-ref -d "refs/heads/$b_prune"
git -C "$clone" branch -q -D "$b_prune"
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "host checkout drops the tracking ref of a deleted proposal" "$(has_ref_plain "$AI_KNOWLEDGE_ROOT/main" "refs/remotes/origin/$b_prune")" no

# --- reports: refs/reports/<name>, outside main and refs/heads; every clone pushes, the integrator reads and closes
# What the process-report skill does: a temporary branch from main, one file, a ref in refs/reports/.
# Extra arguments go to git commit (the tests that must get past the hook pass --no-verify).
report_in() {   # <clone> <project> <F_T> <path or ""> [commit args]; prints the ref name
    local c=$1 pr=$2 ft=$3 path=$4 hex; shift 4
    path=${path:-reports/$pr/process-report-test-$ft.md}
    git -C "$c" checkout -q -b "report/tmp-$pr" main
    mkdir -p "$c/$(dirname "$path")"; printf '# report %s\n' "$ft" > "$c/$path"
    git -C "$c" add -f "$path"; git -C "$c" commit -qm "report: $pr $ft" "$@" >/dev/null 2>&1
    hex=$(git -C "$c" rev-parse HEAD | cut -c1-4)
    git -C "$c" update-ref "refs/reports/$today-$pr-$hex" HEAD
    git -C "$c" checkout -q main; git -C "$c" branch -q -D "report/tmp-$pr"
    printf 'refs/reports/%s-%s-%s' "$today" "$pr" "$hex"
}
has_ref() {   # <repo> <ref>
    git -C "$1" show-ref -q --verify "$2" && echo yes || echo no
}
rproj="$tmp/work/r"; mkdir -p "$rproj"; git -C "$rproj" init -q
rdir=$(ai_sandbox_dir_for "$rproj"); mkdir -p "$rdir"
knowledge sync "$rproj" >/dev/null 2>&1
rclone="$rdir/knowledge"
knowledge sync "$integ" >/dev/null 2>&1
assert_status "reports: integrator clone ok before the first report" "$iclone" "ok:"
knowledge proposals --repo "$iclone" > "$tmp/proposals-before-reports.out" 2>&1

# R3: the hook guards report/* and proposal/* against each other
git -C "$clone" checkout -q -b "report/tmp-hook" main
mkdir -p "$clone/roles"; echo x > "$clone/roles/x.md"; git -C "$clone" add roles/x.md
git -C "$clone" commit -qm "bad" >/dev/null 2>&1 && r=0 || r=$?
assert_eq "hook refuses a path outside reports/ on a report branch" "$r" 1
git -C "$clone" reset -q roles/x.md; rm "$clone/roles/x.md"
mkdir -p "$clone/reports/p"; echo ok > "$clone/reports/p/process-report-hook.md"; git -C "$clone" add -f reports/p/process-report-hook.md
git -C "$clone" commit -qm "good" >/dev/null 2>&1 && r=0 || r=$?
assert_eq "hook accepts a reports/ path on a report branch" "$r" 0
git -C "$clone" checkout -q main; git -C "$clone" branch -q -D "report/tmp-hook"
git -C "$clone" checkout -q -b "proposal/$today-hookr-0000" main
mkdir -p "$clone/reports/p"; echo x > "$clone/reports/p/x.md"; git -C "$clone" add -f reports/p/x.md
out=$(git -C "$clone" commit -qm "reports on a proposal branch" 2>&1) && r=0 || r=$?
assert_eq "hook refuses reports/ on a proposal branch" "$r" 1
assert_contains "the proposal arm keeps its text" "$out" "a proposal branch may change only proposals/"
git -C "$clone" reset -q reports/p/x.md; rm -r "$clone/reports"
git -C "$clone" checkout -q main; git -C "$clone" branch -q -D "proposal/$today-hookr-0000"
echo hacked >> "$clone/rules/global.md"
out=$(git -C "$clone" commit -qam "on main" 2>&1) && r=0 || r=$?
assert_eq "hook still refuses main" "$r" 1
assert_contains "main refusal still names the skill" "$out" "propose-rule"
git -C "$clone" checkout -q rules/global.md

# R2/R4: an in-scope report is pushed to refs/reports/<name>, then dropped from the writer clone
rr1=$(report_in "$clone" p 2026-11-01_2026-11-02 "")
rr1_tip=$(git -C "$clone" rev-parse "$rr1")
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "report pushed to refs/reports" "$(git -C "$remote" rev-parse "$rr1")" "$rr1_tip"
assert_eq "report ref gone from the writer clone after the push" "$(has_ref "$clone" "$rr1")" no
assert_eq "report file is the only change" "$(git -C "$remote" diff --name-only main "$rr1")" "reports/p/process-report-test-2026-11-01_2026-11-02.md"
assert_contains "status counts the pushed report" "$(status_of "$clone")" "reports pushed 1"
assert_status "status ok after a report" "$clone" "ok:"
git -C "$remote" for-each-ref --format='%(refname)' 'refs/heads/*' | grep -q report && r=yes || r=no
assert_eq "no branch carries the report" "$r" no

# the integrator receives it and lists it; a proposals-only run reads as before
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "integrator holds the report ref" "$(git -C "$iclone" rev-parse "$rr1")" "$rr1_tip"
assert_eq "reports listing" "$(knowledge reports --repo "$iclone")" "${rr1#refs/reports/} reports/p/process-report-test-2026-11-01_2026-11-02.md"
assert_eq "proposals listing unchanged by reports" "$(knowledge proposals --repo "$iclone")" "$(cat "$tmp/proposals-before-reports.out")"
assert_eq "integrator status carries no report text for a no-op" "$(status_of "$iclone" | grep -c 'reports pushed')" 0
assert_contains "the report is readable from the ref" "$(git -C "$iclone" show "$rr1:reports/p/process-report-test-2026-11-01_2026-11-02.md")" "# report"

# R5: no other clone ever receives it
knowledge sync "$rproj" >/dev/null 2>&1
assert_eq "existing second clone: no report ref" "$(git -C "$rclone" for-each-ref refs/reports | wc -l | tr -d ' ')" 0
git -C "$rclone" cat-file -e "$rr1_tip" 2>/dev/null && r=yes || r=no
assert_eq "existing second clone: no report commit" "$r" no
fresh="$tmp/fresh-clone"; git clone -q "file://$remote" "$fresh"
assert_eq "fresh clone: no report ref" "$(git -C "$fresh" for-each-ref refs/reports | wc -l | tr -d ' ')" 0
git -C "$fresh" cat-file -e "$rr1_tip" 2>/dev/null && r=yes || r=no
assert_eq "fresh clone: no report commit" "$r" no
assert_eq "host main checkout holds no report ref" "$(git -C "$AI_KNOWLEDGE_ROOT/main" for-each-ref refs/reports | wc -l | tr -d ' ')" 0
assert_eq "remote main has no reports/ history" "$(git -C "$remote" log --full-history --oneline main -- reports/ | wc -l | tr -d ' ')" 0

# R2: refused reports are not pushed
rr_bad_path=$(report_in "$clone" p 2026-11-03_2026-11-04 roles/escape.md --no-verify)
rr_prop_path=$(report_in "$clone" p 2026-11-05_2026-11-06 proposals/sneaky.md --no-verify)
git -C "$clone" update-ref "refs/reports/Bad_Name" "$rr_bad_path"
blob=$(echo x | git -C "$clone" hash-object -w --stdin)
t1=$(printf '100644 blob %s\tf.md\n' "$blob" | git -C "$clone" mktree)
t2=$(printf '040000 tree %s\tp\n' "$t1" | git -C "$clone" mktree)
t3=$(printf '040000 tree %s\treports\n' "$t2" | git -C "$clone" mktree)
orphan=$(git -C "$clone" -c user.name=t -c user.email=t@e commit-tree "$t3" -m orphan)
git -C "$clone" update-ref "refs/reports/$today-p-0f0f" "$orphan"
git -C "$clone" checkout -q -b "proposal/$today-rsneak-abcd" main
mkdir -p "$clone/reports/p"; echo x > "$clone/reports/p/x.md"; git -C "$clone" add -f reports/p/x.md
git -C "$clone" commit -q --no-verify -m "proposal touching reports/"; git -C "$clone" checkout -q main
knowledge sync "$proj" >/dev/null 2>&1
assert_status "refused report takes the refused status" "$clone" "refused:"
assert_contains "refusal names the report outside reports/" "$(status_of "$clone")" "${rr_bad_path#refs/reports/} changes roles/escape.md"
assert_contains "refusal names the report touching proposals/" "$(status_of "$clone")" "${rr_prop_path#refs/reports/} changes proposals/sneaky.md"
assert_contains "refusal names the off-pattern name" "$(status_of "$clone")" "Bad_Name"
assert_contains "refusal names the orphan" "$(status_of "$clone")" "$today-p-0f0f (no common history with main)"
assert_contains "a proposal branch touching reports/ is refused" "$(status_of "$clone")" "proposal/$today-rsneak-abcd changes reports/p/x.md"
for rf in "$rr_bad_path" "$rr_prop_path" refs/reports/Bad_Name "refs/reports/$today-p-0f0f" "refs/heads/proposal/$today-rsneak-abcd"; do
    assert_eq "refused ref not on the remote: $rf" "$(has_ref "$remote" "$rf")" no
    git -C "$clone" update-ref -d "$rf"
done

# R2: a mixed run pushes both kinds
rr2=$(report_in "$clone" p 2026-11-07_2026-11-08 "")
b_mix=$(propose_in "$clone" mixed)
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "mixed run: report pushed" "$(has_ref "$remote" "$rr2")" yes
assert_eq "mixed run: proposal pushed" "$(has_ref "$remote" "refs/heads/$b_mix")" yes
assert_status "mixed run: ok" "$clone" "ok:"
assert_contains "mixed run: both counted" "$(status_of "$clone")" "pushed 1; closed 0; reports pushed 1"

# R2/R4: offline keeps the ref and counts it pending; the next online sync pushes and drops it
mv "$remote" "$remote.away"
rr3=$(report_in "$clone" p 2026-11-09_2026-11-10 "")
knowledge sync "$proj" >"$tmp/roffline.out" 2>&1
assert_status "offline status with a pending report" "$clone" "offline:"
assert_contains "offline counts the pending report" "$(status_of "$clone")" "pending push: 1 branch(es)"
assert_contains "pending report push printed" "$(cat "$tmp/roffline.out")" "git -C $clone push origin $rr3:$rr3"
assert_eq "report still local while offline" "$(has_ref "$clone" "$rr3")" yes
mv "$remote.away" "$remote"
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "pending report pushed once online" "$(has_ref "$remote" "$rr3")" yes
assert_eq "pending report dropped once pushed" "$(has_ref "$clone" "$rr3")" no

# R4: a tombstone made in a non-integrator clone is ignored
rr4=$(report_in "$clone" p 2026-11-11_2026-11-12 "")
git -C "$clone" update-ref "refs/reports-closed/${rr4#refs/reports/}" "$rr4"
knowledge sync "$proj" >/dev/null 2>&1
assert_eq "a writer-clone tombstone does not delete the remote report" "$(has_ref "$remote" "$rr4")" yes
git -C "$clone" update-ref -d "refs/reports-closed/${rr4#refs/reports/}"

# R4: close = tombstone; offline keeps everything, the next sync completes it
knowledge sync "$integ" >/dev/null 2>&1
rn1=${rr1#refs/reports/}
git -C "$iclone" update-ref "refs/reports-closed/$rn1" "$rr1"
assert_eq "a tombstoned report is hidden from the listing" "$(knowledge reports --repo "$iclone" | grep -c "^$rn1 ")" 0
assert_contains "other reports stay listed" "$(knowledge reports --repo "$iclone")" "${rr2#refs/reports/} "
mv "$remote" "$remote.away"
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "offline close: local ref kept" "$(has_ref "$iclone" "$rr1")" yes
assert_eq "offline close: tombstone kept" "$(has_ref "$iclone" "refs/reports-closed/$rn1")" yes
mv "$remote.away" "$remote"
assert_eq "offline close: remote ref kept" "$(has_ref "$remote" "$rr1")" yes
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "close: remote ref deleted by the leased push" "$(has_ref "$remote" "$rr1")" no
assert_eq "close: integrator ref deleted" "$(has_ref "$iclone" "$rr1")" no
assert_eq "close: tombstone deleted" "$(has_ref "$iclone" "refs/reports-closed/$rn1")" no
assert_eq "close: other reports untouched" "$(has_ref "$remote" "$rr2")" yes

# R4: a stale lease deletes nothing and says so
rn2=${rr2#refs/reports/}
git -C "$iclone" update-ref "refs/reports-closed/$rn2" "$rr2"
git -C "$remote" update-ref "$rr2" "$(git -C "$remote" rev-parse main)"
knowledge sync "$integ" >"$tmp/rstale.out" 2>&1
assert_eq "stale lease: remote ref kept" "$(has_ref "$remote" "$rr2")" yes
assert_eq "stale lease: local ref kept" "$(has_ref "$iclone" "$rr2")" yes
assert_eq "stale lease: tombstone kept" "$(has_ref "$iclone" "refs/reports-closed/$rn2")" yes
assert_contains "stale lease reported" "$(status_of "$iclone")" "$rn2"
git -C "$iclone" update-ref -d "refs/reports-closed/$rn2"

# R4: a tombstone whose name is off the pattern is ignored, even in the integrator clone
git -C "$remote" update-ref refs/reports/Odd_Name "$(git -C "$remote" rev-parse main)"
knowledge sync "$integ" >/dev/null 2>&1
git -C "$iclone" update-ref refs/reports-closed/Odd_Name "$(git -C "$iclone" rev-parse main)"
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "off-pattern tombstone: remote ref kept" "$(has_ref "$remote" refs/reports/Odd_Name)" yes
git -C "$iclone" update-ref -d refs/reports-closed/Odd_Name
git -C "$remote" update-ref -d refs/reports/Odd_Name; git -C "$iclone" update-ref -d refs/reports/Odd_Name

# I1: a close whose remote ref is already gone is done, not "moved"
# (a) the integrator's own report, closed before any push reached the remote
rr_own=$(report_in "$iclone" dev-tools 2026-11-13_2026-11-14 "")
rn_own=${rr_own#refs/reports/}
git -C "$iclone" update-ref "refs/reports-closed/$rn_own" "$rr_own"
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "own report closed before a push: local ref gone" "$(has_ref "$iclone" "$rr_own")" no
assert_eq "own report closed before a push: tombstone gone" "$(has_ref "$iclone" "refs/reports-closed/$rn_own")" no
assert_eq "own report closed before a push: never on the remote" "$(has_ref "$remote" "$rr_own")" no
assert_eq "own report closed: no false moved note" "$(status_of "$iclone" | grep -c 'not closed')" 0
# (b) the remote ref was deleted but the local cleanup did not follow
rr5=$(report_in "$clone" p 2026-11-15_2026-11-16 "")
knowledge sync "$proj" >/dev/null 2>&1; knowledge sync "$integ" >/dev/null 2>&1
git -C "$remote" update-ref -d "$rr5"
git -C "$iclone" update-ref "refs/reports-closed/${rr5#refs/reports/}" "$rr5"
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "remote already deleted: local ref gone" "$(has_ref "$iclone" "$rr5")" no
assert_eq "remote already deleted: tombstone gone" "$(has_ref "$iclone" "refs/reports-closed/${rr5#refs/reports/}")" no
# (c) a moved remote ref is still kept (stale lease case above), and M1: a no-op integrator sync pushes nothing
rr6=$(report_in "$clone" p 2026-11-17_2026-11-18 "")
knowledge sync "$proj" >/dev/null 2>&1; knowledge sync "$integ" >/dev/null 2>&1
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "no-op integrator sync does not count fetched reports as pushed" "$(status_of "$iclone" | grep -c 'reports pushed')" 0
git -C "$iclone" update-ref "refs/reports-closed/${rr6#refs/reports/}" "$rr6"
git -C "$remote" update-ref "$rr6" "$(git -C "$remote" rev-parse main)"
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "moved remote ref: local ref kept" "$(has_ref "$iclone" "$rr6")" yes
assert_contains "moved remote ref: reported" "$(status_of "$iclone")" "${rr6#refs/reports/}"
git -C "$iclone" update-ref -d "refs/reports-closed/${rr6#refs/reports/}"; git -C "$iclone" update-ref -d "$rr6"
git -C "$remote" update-ref -d "$rr6"
# an integrator-written report that the remote lacks is pushed and kept until closed
rr7=$(report_in "$iclone" dev-tools 2026-11-19_2026-11-20 "")
knowledge sync "$integ" >/dev/null 2>&1
assert_eq "integrator's own open report pushed" "$(has_ref "$remote" "$rr7")" yes
assert_eq "integrator's own open report kept" "$(has_ref "$iclone" "$rr7")" yes
assert_contains "integrator push of its own report counted" "$(status_of "$iclone")" "reports pushed"
git -C "$iclone" update-ref -d "$rr7"; git -C "$remote" update-ref -d "$rr7"
assert_contains "doctor labels reports by role" "$(cat "$AI_SANDBOX_ROOT/image/build/sandbox-doctor")" 's/^role=//p'

# R5 again after a file, sync, close, sync cycle
assert_eq "cycle: remote main has no reports/ history" "$(git -C "$remote" log --full-history --oneline main -- reports/ | wc -l | tr -d ' ')" 0
assert_eq "cycle: integrator main has no reports/ history" "$(git -C "$iclone" log --full-history --oneline main -- reports/ | wc -l | tr -d ' ')" 0
assert_eq "cycle: host main checkout holds no report ref" "$(git -C "$AI_KNOWLEDGE_ROOT/main" for-each-ref refs/reports | wc -l | tr -d ' ')" 0

# --- O9 (C-STATUS): a create binds the status directory read-only, knowledge configured or not;
# --- status and the sync --all table show line 1 without control characters; the doctor shows every file's line 1
assert_contains "create binds status/ read-only at /run/ai-sandbox/status" "$(cat "$pdir/docker-compose.yml")" "\"$pdir/status:/run/ai-sandbox/status:ro\""
assert_contains "create passes the status path on" "$(cat "$pdir/docker-compose.yml")" "SANDBOX_STATUS_DIR=/run/ai-sandbox/status"
cp "$(status_file "$clone")" "$tmp/status.keep"
printf '2026-01-01T00:00:00 ok seen\033[31mred\rtail\nrole=proposals\nproject-id=%s\n' "$pid" > "$(status_file "$clone")"
one=$(knowledge status "$proj" 2>&1); all=$(knowledge status 2>&1)
assert_contains "status with a project shows line 1" "$one" "2026-01-01T00:00:00 ok seen[31mredtail"
assert_eq "status with a project shows no control character" "$(printf '%s' "$one" | tr -d '\n' | LC_ALL=C grep -c "[[:cntrl:]]")" 0
assert_contains "status without an argument shows line 1" "$(printf '%s\n' "$all" | grep "$(basename "$pdir")")" "2026-01-01T00:00:00 ok seen[31mredtail"
assert_eq "status without an argument shows no control character" "$(printf '%s' "$all" | tr -d '\n' | LC_ALL=C grep -c "[[:cntrl:]]")" 0
assert_eq "status shows line 1 only, not the keys" "$(printf '%s\n' "$one" | grep -c 'project-id=')" 0
cp "$tmp/status.keep" "$(status_file "$clone")"
knowledge sync --all >"$tmp/o9-all.out" 2>&1 || cat "$tmp/o9-all.out"
assert_contains "the sync --all table shows line 1" "$(grep "$(basename "$pdir")" "$tmp/o9-all.out" | tail -1)" " ok main current"
# the generated doctor, run against a fixture status directory
doctor="$AI_SANDBOX_ROOT/image/build/sandbox-doctor"
fx="$tmp/status-fixture"; mkdir -p "$fx" "$tmp/doctor-home"
printf '2026-02-02T01:02:03 warn first\033[1mfile\nrole=integrator\nsecond-line-secret\n' > "$fx/knowledge"
printf '2026-02-02T01:02:04 ok other\n' > "$fx/other"
dout=$(env -u DISPLAY -u WAYLAND_DISPLAY HOME="$tmp/doctor-home" SANDBOX_STATUS_DIR="$fx" SANDBOX_KNOWLEDGE=1 bash "$doctor" 2>&1)
assert_contains "doctor prints line 1 of a status file with its age" "$dout" "2026-02-02T01:02:03 warn first[1mfile ["
assert_contains "doctor prints line 1 of every status file" "$dout" "2026-02-02T01:02:04 ok other ["
assert_contains "doctor gives the age" "$dout" " min ago]"
assert_eq "doctor prints no line but line 1" "$(printf '%s\n' "$dout" | grep -c 'second-line-secret')" 0
assert_eq "doctor prints no control character from a status file" "$(printf '%s' "$dout" | tr -d '\n' | LC_ALL=C grep -c "[[:cntrl:]]")" 0
dout=$(env -u DISPLAY -u WAYLAND_DISPLAY HOME="$tmp/doctor-home" SANDBOX_KNOWLEDGE=1 bash "$doctor" 2>&1)
assert_contains "doctor without a status directory says the clone is not synced" "$dout" "clone not synced yet"
rm -rf "$fx" "$tmp/doctor-home"

# --- O10 (the origin): create makes knowledge/ and an empty bare origin before any start and binds the origin
# --- read-only; every sync refreshes it from the host's own refs, so that it holds exactly the contract's refs
orefs() {   # <repo> [pattern...]: "<ref> <object>" per ref, sorted
    git -C "$1" for-each-ref --format='%(refname) %(objectname)' "${@:2}" | LC_ALL=C sort
}
orig_proj="$pdir/knowledge-origin.git"; orig_integ="$idir/knowledge-origin.git"
hostrepo="$AI_KNOWLEDGE_ROOT/main"
omain=$(git -C "$remote" rev-parse main)
# remote: a branch, a tag and two reports; the host's own repository: refs no origin may carry
git -C "$remote" update-ref refs/heads/proposal/2026-01-01-o10-aaaa "$omain"
git -C "$remote" update-ref refs/heads/other-o10 "$omain"
git -C "$remote" tag o10-tag "$omain"
git -C "$remote" update-ref refs/reports/2026-01-01-o10-aaaa "$omain"
git -C "$remote" update-ref refs/reports/2026-01-02-o10-bbbb "$omain"
git -C "$hostrepo" update-ref refs/sandbox/zz/heads/x "$omain"
git -C "$hostrepo" update-ref refs/pushed-reports/zz/2026-01-01-o10-aaaa "$omain"
git -C "$hostrepo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
# refs an origin once held or a sandbox-side process wrote: the next sync removes them
mkdir -p "$orig_proj" "$orig_integ"
git init -q --bare "$orig_proj" 2>/dev/null; git init -q --bare "$orig_integ" 2>/dev/null
for o in "$orig_proj" "$orig_integ"; do
    git -C "$o" update-ref refs/heads/stale-o10 "$omain" 2>/dev/null
    git -C "$o" update-ref refs/odd/o10 "$omain" 2>/dev/null
done
git -C "$orig_proj" update-ref refs/reports/2026-01-03-o10-cccc "$omain" 2>/dev/null
knowledge sync "$proj" >"$tmp/o10-sync-p.out" 2>&1 || cat "$tmp/o10-sync-p.out"
knowledge sync "$integ" >"$tmp/o10-sync-i.out" 2>&1 || cat "$tmp/o10-sync-i.out"
assert_eq "origin is a bare repository" "$(git -C "$orig_proj" rev-parse --is-bare-repository 2>&1)" true
assert_eq "origin HEAD follows main" "$(git -C "$orig_proj" symbolic-ref HEAD 2>&1)" refs/heads/main
assert_eq "origin heads equal the remote's heads (proposals sandbox)" "$(orefs "$orig_proj" refs/heads)" "$(orefs "$remote" refs/heads)"
assert_eq "origin heads equal the remote's heads (integrator)" "$(orefs "$orig_integ" refs/heads)" "$(orefs "$remote" refs/heads)"
assert_eq "origin heads equal the host's remote-tracking refs" \
    "$(orefs "$orig_proj" refs/heads | sed 's#^refs/heads/##')" \
    "$(orefs "$hostrepo" refs/remotes/origin | grep -v '^refs/remotes/origin/HEAD ' | sed 's#^refs/remotes/origin/##')"
assert_eq "the proposals origin holds no ref but heads" "$(orefs "$orig_proj" | grep -vc '^refs/heads/')" 0
assert_eq "the proposals origin holds no report" "$(orefs "$orig_proj" refs/reports | wc -l | tr -d ' ')" 0
assert_eq "no origin holds a head named for the symbolic HEAD" "$(orefs "$orig_proj" refs/heads/HEAD | wc -l | tr -d ' ')" 0
assert_eq "the integrator origin's reports equal the remote's" "$(orefs "$orig_integ" refs/reports)" "$(orefs "$remote" refs/reports)"
assert_eq "the integrator origin holds no ref but heads and reports" "$(orefs "$orig_integ" | grep -vc '^refs/heads/\|^refs/reports/')" 0
assert_eq "the integrator origin holds the reports this section gave the remote" "$(orefs "$orig_integ" refs/reports | grep -c -- '-o10-')" 2
assert_eq "the host fetched the remote's reports into refs/origin-reports" \
    "$(orefs "$hostrepo" refs/origin-reports | sed 's#^refs/origin-reports/##')" "$(orefs "$remote" refs/reports | sed 's#^refs/reports/##')"
assert_eq "a sync leaves a sandbox's namespace in the host repository as it was" "$(orefs "$hostrepo" refs/sandbox refs/pushed-reports | wc -l | tr -d ' ')" 2
# the remote drops a branch and a report; the host is offline once: the origin keeps the last fetch
before_off=$(orefs "$orig_integ")
git -C "$hostrepo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main   # an offline sync prunes nothing on the host
mv "$remote" "$remote.away"
knowledge sync "$integ" >"$tmp/o10-off.out" 2>&1 || cat "$tmp/o10-off.out"
assert_eq "offline: the host's pointer origin/HEAD is not published as a branch" "$(orefs "$orig_integ" refs/heads/HEAD | wc -l | tr -d ' ')" 0
assert_status "offline status" "$iclone" "offline:"
assert_eq "offline: the origin keeps the last fetch" "$(orefs "$orig_integ")" "$before_off"
mv "$remote.away" "$remote"
git -C "$remote" update-ref -d refs/heads/other-o10; git -C "$remote" update-ref -d refs/reports/2026-01-02-o10-bbbb
git -C "$iclone" update-ref -d refs/reports/2026-01-02-o10-bbbb   # else the integrator's clone would push it back
# a dirty clone is skipped whole by the clone-side sync; the origin is refreshed first all the same
echo dirt > "$clone/o10-dirt"
knowledge sync "$proj" >"$tmp/o10-dirty.out" 2>&1 || cat "$tmp/o10-dirty.out"
assert_status "dirty clone: skipped" "$clone" "skipped:"
assert_eq "dirty clone: the origin is refreshed (a deleted branch is pruned)" "$(orefs "$orig_proj" refs/heads)" "$(orefs "$remote" refs/heads)"
rm -f "$clone/o10-dirt"
knowledge sync "$integ" >"$tmp/o10-i2.out" 2>&1 || cat "$tmp/o10-i2.out"
assert_eq "a report deleted on the remote leaves the integrator's origin" "$(orefs "$orig_integ" refs/reports)" "$(orefs "$remote" refs/reports)"
assert_eq "and the host's refs/origin-reports" \
    "$(orefs "$hostrepo" refs/origin-reports | sed 's#^refs/origin-reports/##')" "$(orefs "$remote" refs/reports | sed 's#^refs/reports/##')"
# sync --all refreshes every current sandbox's origin
git -C "$remote" update-ref refs/heads/all-o10 "$omain"
knowledge sync --all >"$tmp/o10-all.out" 2>&1 || cat "$tmp/o10-all.out"
assert_eq "sync --all refreshes the proposals origin" "$(orefs "$orig_proj" refs/heads)" "$(orefs "$remote" refs/heads)"
assert_eq "sync --all refreshes the integrator origin" "$(orefs "$orig_integ" refs/heads)" "$(orefs "$remote" refs/heads)"
# clean up the remote and the host's planted refs
for r in refs/heads/all-o10 refs/heads/proposal/2026-01-01-o10-aaaa refs/reports/2026-01-01-o10-aaaa refs/tags/o10-tag; do git -C "$remote" update-ref -d "$r"; done
git -C "$iclone" update-ref -d refs/reports/2026-01-01-o10-aaaa; git -C "$iclone" branch -q -D proposal/2026-01-01-o10-aaaa 2>/dev/null
git -C "$hostrepo" update-ref -d refs/sandbox/zz/heads/x; git -C "$hostrepo" update-ref -d refs/pushed-reports/zz/2026-01-01-o10-aaaa
git -C "$hostrepo" tag -d o10-tag >/dev/null 2>&1; git -C "$hostrepo" symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null
knowledge sync "$proj" >/dev/null 2>&1; knowledge sync "$integ" >/dev/null 2>&1
assert_eq "after the cleanup the integrator origin's reports equal the remote's" "$(orefs "$orig_integ" refs/reports)" "$(orefs "$remote" refs/reports)"
assert_eq "after the cleanup the origins hold the remote's heads and nothing else" "$(orefs "$orig_proj")$(orefs "$orig_integ" refs/heads)" "$(orefs "$remote" refs/heads)$(orefs "$remote" refs/heads)"

# create: knowledge/ and the origin exist before the sync step runs, and before any start
o10p="$tmp/work/o10p"; mkdir -p "$o10p"
rec="$tmp/o10-tree"; mkdir -p "$rec/bin/ai"; cp -a "$REPO_ROOT/bin/ai/." "$rec/bin/ai/"; ln -s "$REPO_ROOT/tools" "$rec/tools"
o10dir=$(ai_sandbox_dir_for "$o10p")
cat > "$rec/bin/ai/ai-knowledge" <<REC
#!/usr/bin/env bash
{ [ -d "$o10dir/knowledge" ] && echo knowledge-dir; [ -d "$o10dir/knowledge-origin.git" ] && echo origin-dir
  [ "\$(git -C "$o10dir/knowledge-origin.git" rev-parse --is-bare-repository 2>/dev/null)" = true ] && echo origin-bare
  git -C "$o10dir/knowledge-origin.git" for-each-ref | wc -l | sed 's/^/refs /'; } > "$tmp/o10-rec.out"
exit 1
REC
bash "$rec/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$o10p" >"$tmp/o10-create1.out" 2>&1 || cat "$tmp/o10-create1.out"
assert_eq "create made knowledge/ and an empty bare origin before the sync step, which failed here" "$(tr '\n' ' ' < "$tmp/o10-rec.out")" "knowledge-dir origin-dir origin-bare refs 0 "
assert_contains "the failed sync step did not fail create" "$(cat "$tmp/o10-create1.out")" "knowledge sync reported a problem"
assert_file "the compose file was written although the sync failed" "$o10dir/docker-compose.yml"
oc=$(cat "$o10dir/docker-compose.yml")
assert_contains "create binds the origin read-only at its mount" "$oc" "\"$o10dir/knowledge-origin.git:/run/ai-sandbox/knowledge-origin.git:ro\""
assert_contains "create binds the clone read-write beside it" "$oc" "\"$o10dir/knowledge:$HOME/knowledge\""
ai_sandbox_writable_path "$o10dir/knowledge-origin.git" && r=writable || r=host-only
assert_eq "no sandbox can write the origin (the compose parser sees the bind as read-only)" "$r" host-only
ai_sandbox_writable_path "$o10dir/knowledge" && r=writable || r=host-only
assert_eq "the clone stays writable to its sandbox" "$r" writable
# a sync that works finds the empty knowledge/ create made and clones into it
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$o10p" >"$tmp/o10-create2.out" 2>&1 || cat "$tmp/o10-create2.out"
assert_file "the sync cloned into the directory create made" "$o10dir/knowledge/.git"
assert_eq "an empty knowledge/ is not moved aside" "$(ls -d "$o10dir"/knowledge.not-a-clone.* 2>/dev/null | wc -l | tr -d ' ')" 0
assert_eq "the sync of a create fills the origin" "$(orefs "$o10dir/knowledge-origin.git" refs/heads)" "$(orefs "$remote" refs/heads)"
# the same with a remote that cannot be reached: the directories are there all the same
cp "$AI_KNOWLEDGE_CONFIG" "$tmp/o10-config.keep"
sed -i "s#^REMOTE=.*#REMOTE=file://$tmp/no-such-remote.git#" "$AI_KNOWLEDGE_CONFIG"
o10q="$tmp/work/o10q"; mkdir -p "$o10q"; o10qdir=$(ai_sandbox_dir_for "$o10q")
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$o10q" >"$tmp/o10-create3.out" 2>&1 || cat "$tmp/o10-create3.out"
assert_file "offline create: knowledge/ exists" "$o10qdir/knowledge"
assert_eq "offline create: the origin is a bare repository" "$(git -C "$o10qdir/knowledge-origin.git" rev-parse --is-bare-repository 2>&1)" true
assert_contains "offline create: the origin is bound" "$(cat "$o10qdir/docker-compose.yml")" "knowledge-origin.git:/run/ai-sandbox/knowledge-origin.git:ro\""
cp "$tmp/o10-config.keep" "$AI_KNOWLEDGE_CONFIG"
rm -rf "$rec"

# --- O11 (the in-sandbox command): sandbox-knowledge-sync in a fixture home, against a fixture origin and status
# --- directory; it removes a ref inside only as the status file lists it, and exits 0 in every case
o11="$tmp/o11"; mkdir -p "$o11/status"
oo="$o11/origin.git"; git init -q --bare "$oo"; git -C "$oo" symbolic-ref HEAD refs/heads/main
ow="$o11/work"; git init -q -b main "$ow"
printf 'one\n' > "$ow/rules.md"; git -C "$ow" add rules.md; git -C "$ow" commit -qm "one"
git -C "$ow" push -q "$oo" main
ocommit() {   # <message>: a commit on the fixture work repository's main, pushed to the fixture origin; prints it
    printf '%s\n' "$1" > "$ow/f-$(printf '%s' "$1" | tr -c 'a-z0-9' '_').md"; git -C "$ow" add -A; git -C "$ow" commit -qm "$1"
    git -C "$ow" push -q "$oo" main; git -C "$ow" rev-parse HEAD
}
ostatus() {   # <name> <role> <project id> [status lines...]: the status file of the fixture sandbox <name>
    local d="$o11/status/$1"; mkdir -p "$d"; { printf '2026-01-01T00:00:00 ok seen\nrole=%s\nproject-id=%s\n' "$2" "$3"; shift 3; [ $# -eq 0 ] || printf '%s\n' "$@"; } > "$d/knowledge"
}
osync() {   # <name>: run the command for the fixture sandbox <name>; its clone is $o11/<name>
    SANDBOX_KNOWLEDGE_CLONE="$o11/$1" SANDBOX_STATUS_DIR="$o11/status/$1" SANDBOX_KNOWLEDGE_ORIGIN="$oo" bash "$REPO_ROOT/bin/ai/sandbox-knowledge-sync" 2>&1
}
ogit() { local n=$1; shift; git -C "$o11/$n" "$@"; }
today11=$(date +%F); pb1="proposal/$today11-ofirst-aaaa"; rp1="$today11-ofirst-bbbb"
git -C "$ow" push -q "$oo" "main:refs/heads/$pb1"; git -C "$ow" push -q "$oo" "main:refs/reports/$rp1"

# creates the clone on main when absent (also into an empty directory); role file and hook
ostatus w1 proposals pid-w1; mkdir "$o11/w1e"; ostatus w1e proposals pid-w1e
out=$(osync w1); r=$?
assert_eq "the command exits 0 for a clone it creates" "$r" 0
assert_eq "an absent clone is created on main" "$(ogit w1 branch --show-current)" main
assert_eq "the new clone's main is the origin's main" "$(ogit w1 rev-parse main)" "$(git -C "$oo" rev-parse main)"
assert_eq "the new clone fetches from the origin" "$(ogit w1 config --get remote.origin.url)" "$oo"
assert_eq "the role file is <role> <project id>" "$(cat "$o11/w1/.git/ai-knowledge-role")" "proposals pid-w1"
[ -x "$o11/w1/.git/hooks/pre-commit" ] && r=yes || r=no
assert_eq "the command installs the hook" "$r" yes
assert_contains "the command says what it did" "$out" "cloned the origin"
osync w1e >/dev/null; assert_eq "an empty directory receives the clone" "$(ogit w1e branch --show-current)" main
assert_eq "a proposals clone holds no other clone's proposal branch" "$(ogit w1 for-each-ref refs/heads/proposal | wc -l | tr -d ' ')" 0
assert_eq "a proposals clone fetches no report" "$(ogit w1 for-each-ref refs/reports | wc -l | tr -d ' ')" 0
assert_eq "the hook of the sync on the host equals the hook the command installs" "$(cat "$clone/.git/hooks/pre-commit")" "$(cat "$o11/w1/.git/hooks/pre-commit")"

# a non-empty ~/knowledge that is no clone is left alone and said so; the command exits 0
mkdir "$o11/w2"; echo mine > "$o11/w2/notes.txt"; ostatus w2 proposals pid-w2
out=$(osync w2); r=$?
assert_eq "a non-clone directory: exit 0" "$r" 0
assert_eq "a non-clone directory is untouched" "$(ls -A "$o11/w2" | tr '\n' ' ')" "notes.txt "
assert_contains "a non-clone directory is reported" "$out" "left alone"

# the integrator fetches proposal branches and reports; its role file says so
ostatus i1 integrator pid-i1; osync i1 >/dev/null
assert_eq "the integrator's role file" "$(cat "$o11/i1/.git/ai-knowledge-role")" "integrator pid-i1"
assert_eq "the integrator fetches the proposal branches" "$(ogit i1 rev-parse "refs/heads/$pb1")" "$(git -C "$oo" rev-parse "refs/heads/$pb1")"
assert_eq "the integrator fetches the reports" "$(ogit i1 rev-parse "refs/reports/$rp1")" "$(git -C "$oo" rev-parse "refs/reports/$rp1")"

# adopts a clone of the base design: the origin URL is replaced, local branches and unpushed commits stay, the old status file goes
git init -q --bare "$o11/oldremote.git"; git -C "$ow" push -q "$o11/oldremote.git" main
git clone -q "$o11/oldremote.git" "$o11/a1" 2>/dev/null; ostatus a1 proposals pid-a1
git -C "$o11/a1" checkout -q -b "proposal/$today11-olocal-cccc"; echo local > "$o11/a1/local.md"; git -C "$o11/a1" add local.md
git -C "$o11/a1" -c user.email=t@e -c user.name=t commit -q --no-verify -m "unpushed"
ltip=$(git -C "$o11/a1" rev-parse HEAD); git -C "$o11/a1" checkout -q main; echo old > "$o11/a1/.sync-status"
out=$(osync a1); r=$?
assert_eq "adopting: exit 0" "$r" 0
assert_eq "adopting: the origin URL is replaced" "$(ogit a1 config --get remote.origin.url)" "$oo"
assert_eq "adopting: the unpushed commit and its branch stay" "$(ogit a1 rev-parse "refs/heads/proposal/$today11-olocal-cccc")" "$ltip"
assert_no_file "adopting: the old status file is removed" "$o11/a1/.sync-status"
assert_eq "adopting: the next fetch is from the origin" "$(ogit a1 rev-parse refs/remotes/origin/main)" "$(git -C "$oo" rev-parse main)"
assert_contains "adopting is said" "$out" "now fetches from the host's origin"

# fast-forwards main unless the tree is dirty or the integrator's main is ahead, and says which
c2=$(ocommit "two")
osync w1 >/dev/null
assert_eq "main is fast-forwarded (checked out)" "$(ogit w1 rev-parse main)" "$c2"
assert_file "the working tree follows a checked-out main" "$o11/w1/f-two.md"
c3=$(ocommit "three")
echo dirt > "$o11/w1/dirt.txt"; out=$(osync w1)
assert_eq "a dirty tree: main stays" "$(ogit w1 rev-parse main)" "$c2"
assert_contains "a dirty tree is reported" "$out" "uncommitted"
rm -f "$o11/w1/dirt.txt"
ogit w1 checkout -q -b "proposal/$today11-oother-dddd"; osync w1 >/dev/null
assert_eq "main moves although another branch is checked out" "$(ogit w1 rev-parse main)" "$c3"
assert_eq "and the checked-out branch is where it was" "$(ogit w1 branch --show-current)" "proposal/$today11-oother-dddd"
ogit w1 checkout -q main
echo local > "$o11/w1/mine.md"; ogit w1 add mine.md; ogit w1 -c user.email=t@e -c user.name=t commit -q --no-verify -m "local on main"
mtip=$(ogit w1 rev-parse main); c4=$(ocommit "four"); out=$(osync w1)
assert_eq "a main with local commits is not moved" "$(ogit w1 rev-parse main)" "$mtip"
assert_contains "and it is reported" "$out" "local commits"
ogit w1 reset -q --hard "$c3"
osync i1 >/dev/null
echo ahead > "$o11/i1/ahead.md"; ogit i1 add ahead.md; ogit i1 -c user.email=t@e -c user.name=t commit -q -m "integrator commit"
itip=$(ogit i1 rev-parse main); c5=$(ocommit "five"); git -C "$ow" reset -q --hard "$c4"
out=$(osync i1)
assert_eq "the integrator's main may be ahead and stays" "$(ogit i1 rev-parse main)" "$itip"
assert_contains "the integrator is told its main differs" "$out" "origin/main"

# deletes a branch listed closed-proposal= only while its tip is the listed commit
ogit w1 checkout -q main
for b in k1 k2 k3 k4; do ogit w1 branch -q "proposal/$today11-$b-eeee" main; done
ogit w1 checkout -q -b "proposal/$today11-k5-eeee" main; echo k5 > "$o11/w1/k5.md"; ogit w1 add k5.md
ogit w1 -c user.email=t@e -c user.name=t commit -q --no-verify -m k5; ogit w1 checkout -q main
t1=$(ogit w1 rev-parse "proposal/$today11-k1-eeee"); t5=$(ogit w1 rev-parse "proposal/$today11-k5-eeee")
ogit w1 checkout -q "proposal/$today11-k4-eeee"
ostatus w1 proposals pid-w1 "closed-proposal=proposal/$today11-k1-eeee $t1" "closed-proposal=proposal/$today11-k2-eeee $t5" \
    "closed-proposal=proposal/$today11-k4-eeee $t1" "closed-proposal=main $(ogit w1 rev-parse main)" "closed-proposal=proposal/../x $t1"
out=$(osync w1)
has_b() { ogit w1 show-ref -q --verify "refs/heads/$1" && echo yes || echo no; }
assert_eq "a listed branch at the listed commit is deleted" "$(has_b "proposal/$today11-k1-eeee")" no
assert_eq "a listed branch whose tip is not the listed commit is kept" "$(has_b "proposal/$today11-k2-eeee")" yes
assert_eq "a branch the status does not list is kept" "$(has_b "proposal/$today11-k3-eeee")" yes
assert_eq "the checked-out closed branch is left and main checked out first" "$(has_b "proposal/$today11-k4-eeee")$(ogit w1 branch --show-current)" "nomain"
assert_eq "main is never deleted by a listing" "$(has_b main)" yes
assert_eq "a branch outside proposal/ or with a malformed name is not touched" "$(has_b "proposal/$today11-k5-eeee")" yes

# a writer deletes a report listed pushed-report=; the integrator does not
for n in r1 r2; do ogit w1 update-ref "refs/reports/$today11-$n-ffff" main; done
ostatus w1 proposals pid-w1 "pushed-report=$today11-r1-ffff" "pushed-report=../heads/main" "closed-report=$today11-r2-ffff"
osync w1 >/dev/null
has_r() { ogit "$1" show-ref -q --verify "$2" && echo yes || echo no; }
assert_eq "a listed pushed report is deleted for a writer" "$(has_r w1 "refs/reports/$today11-r1-ffff")" no
assert_eq "an unlisted report is kept" "$(has_r w1 "refs/reports/$today11-r2-ffff")" yes
assert_eq "a writer ignores closed-report=" "$(has_r w1 "refs/reports/$today11-r2-ffff")" yes
assert_eq "an unsafe listed name deletes nothing" "$(has_b main)" yes
ogit i1 update-ref "refs/reports/$today11-r3-ffff" main
ostatus i1 integrator pid-i1 "pushed-report=$today11-r3-ffff"; osync i1 >/dev/null
assert_eq "the integrator ignores pushed-report=" "$(has_r i1 "refs/reports/$today11-r3-ffff")" yes

# the integrator deletes a report and its tombstone only while the status lists it closed-report=
# (an origin without the report is no such signal)
for n in s1 s2; do ogit i1 update-ref "refs/reports/$today11-$n-ffff" main; ogit i1 update-ref "refs/reports-closed/$today11-$n-ffff" main; done
ostatus i1 integrator pid-i1; osync i1 >/dev/null
assert_eq "a tombstoned report stays while the status does not list it (the origin lacks it)" "$(has_r i1 "refs/reports/$today11-s1-ffff")$(has_r i1 "refs/reports-closed/$today11-s1-ffff")" yesyes
ostatus i1 integrator pid-i1 "closed-report=$today11-s1-ffff"; osync i1 >/dev/null
assert_eq "a listed report and its tombstone are deleted" "$(has_r i1 "refs/reports/$today11-s1-ffff")$(has_r i1 "refs/reports-closed/$today11-s1-ffff")" nono
assert_eq "an unlisted one is kept, both refs" "$(has_r i1 "refs/reports/$today11-s2-ffff")$(has_r i1 "refs/reports-closed/$today11-s2-ffff")" yesyes

# exit 0 in every case: no status file, no origin, an origin that is no repository, an empty origin
mkdir -p "$o11/status/n1"; out=$(osync n1); r=$?
assert_eq "no status file: exit 0, the clone is made" "$r$(ogit n1 branch --show-current)" "0main"
assert_eq "no status file: no role file is written" "$(ls "$o11/n1/.git/ai-knowledge-role" 2>/dev/null | wc -l | tr -d ' ')" 0
out=$(SANDBOX_KNOWLEDGE_CLONE="$o11/n2" SANDBOX_STATUS_DIR="$o11/status/n1" SANDBOX_KNOWLEDGE_ORIGIN="$o11/no-such-origin" bash "$REPO_ROOT/bin/ai/sandbox-knowledge-sync" 2>&1); r=$?
assert_eq "no origin: exit 0" "$r" 0
assert_contains "no origin: said" "$out" "no knowledge origin"
mkdir "$o11/not-a-repo"
out=$(SANDBOX_KNOWLEDGE_CLONE="$o11/n3" SANDBOX_STATUS_DIR="$o11/status/n1" SANDBOX_KNOWLEDGE_ORIGIN="$o11/not-a-repo" bash "$REPO_ROOT/bin/ai/sandbox-knowledge-sync" 2>&1); r=$?
assert_eq "an origin that is no repository: exit 0" "$r" 0
assert_contains "an origin that is no repository: said" "$out" "cannot clone"
git init -q --bare "$o11/empty.git"; git -C "$o11/empty.git" symbolic-ref HEAD refs/heads/main
out=$(SANDBOX_KNOWLEDGE_CLONE="$o11/n4" SANDBOX_STATUS_DIR="$o11/status/n1" SANDBOX_KNOWLEDGE_ORIGIN="$o11/empty.git" bash "$REPO_ROOT/bin/ai/sandbox-knowledge-sync" 2>&1); r=$?
assert_eq "an empty origin: exit 0, the clone follows main" "$r$(git -C "$o11/n4" symbolic-ref HEAD)" "0refs/heads/main"
# hostile status content cannot make it delete outside the listed kinds
ostatus n1 integrator pid-n1 "closed-report=../heads/main" "closed-report=" "closed-proposal=" "closed-proposal=proposal/x"; osync n1 >/dev/null
assert_eq "malformed status lines delete nothing" "$(ogit n1 show-ref -q --verify refs/heads/main && echo yes)" yes

# the generated entrypoint runs it when SANDBOX_KNOWLEDGE=2, not otherwise, and the start does not fail when it does
ep="$AI_SANDBOX_ROOT/image/build/entrypoint.sh"; epstub="$o11/epstub"; mkdir -p "$epstub" "$o11/ep-etc" "$o11/ep-zi"
printf '#!/bin/bash\necho ran >> "$STUB_SKS_LOG"\n[ -z "${STUB_SKS_FAIL:-}" ] || { echo boom >&2; exit 1; }\n' > "$epstub/sandbox-knowledge-sync"; chmod +x "$epstub/sandbox-knowledge-sync"
printf '#!/bin/bash\necho "DBUS_SESSION_BUS_ADDRESS='"'"'unix:path=/nonexistent'"'"';"\n' > "$epstub/dbus-launch"; chmod +x "$epstub/dbus-launch"
run_ep_sks() {   # <value of SANDBOX_KNOWLEDGE, or "unset"> [fail]: prints the entrypoint's exit status and the number of runs
    : > "$o11/sks.log"
    if [ "$1" = unset ]; then unset SANDBOX_KNOWLEDGE; else export SANDBOX_KNOWLEDGE=$1; fi
    STUB_SKS_LOG="$o11/sks.log" STUB_SKS_FAIL="${2:-}" SANDBOX_RUNTIME_DIR="$o11/ep-run" SANDBOX_ETC_DIR="$o11/ep-etc" SANDBOX_ZONEINFO_DIR="$o11/ep-zi" \
        CLAUDE_PLUGINS_LIST=/nonexistent PATH="$epstub:$PATH" TZ= bash "$ep" true >"$o11/ep.out" 2>&1; local rc=$?
    printf '%s:%s' "$rc" "$(wc -l < "$o11/sks.log" | tr -d ' ')"
}
assert_eq "the entrypoint runs the command when SANDBOX_KNOWLEDGE=2" "$(run_ep_sks 2)" "0:1"
assert_eq "not for SANDBOX_KNOWLEDGE=1" "$(run_ep_sks 1)" "0:0"
assert_eq "not for SANDBOX_KNOWLEDGE=0" "$(run_ep_sks 0)" "0:0"
assert_eq "not when SANDBOX_KNOWLEDGE is unset" "$(run_ep_sks unset)" "0:0"
assert_eq "the start does not fail when the command does" "$(run_ep_sks 2 fail)" "0:1"
assert_contains "and the failure is said" "$(cat "$o11/ep.out")" "sandbox-knowledge-sync did not finish"
unset SANDBOX_KNOWLEDGE
# the command is in the image, not on the host
dfile=$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")
assert_contains "the image copies the command" "$dfile" "COPY sandbox-knowledge-sync /usr/local/bin/sandbox-knowledge-sync"
assert_contains "and makes it executable" "$dfile" "/usr/local/bin/sandbox-knowledge-sync"
assert_file "the build context holds the command" "$AI_SANDBOX_ROOT/image/build/sandbox-knowledge-sync"
assert_eq "the command is not a host helper" "$(ai_sandbox_helpers | grep -c 'sandbox-knowledge-sync')" 0
assert_contains "the compose file passes the origin's mount path on" "$(cat "$pdir/docker-compose.yml")" "SANDBOX_KNOWLEDGE_ORIGIN=/run/ai-sandbox/knowledge-origin.git"

# --- O6 (C-STAMP): the project and the role come from the stamps and the host's
# --- configuration, not from what a sandbox can write in the project or its clone
mkdir -p "$proj/sub/deep" "$proj/plainsub"
git -C "$proj/sub" init -q                                  # a nested repository the sandbox made
git config -f "$proj/.git/config" core.worktree "$integ"    # the project's own config names another project
assert_eq "tree inputs: the project is still the stamped one" "$(cd "$proj/sub/deep" && PATH="$PATH" bash -c '. "$1"; ai_sandbox_project_root' _ "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh")" "$proj"
out=$(cd "$proj/sub/deep" && bash "$REPO_ROOT/bin/ai/ai-sandbox" --print-context 2>&1)
assert_contains "tree inputs: print-context from a subdirectory names the stamped sandbox" "$out" "dir=$pdir"
out=$(cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox" --print-context 2>&1)
assert_contains "tree inputs: print-context in the project names the stamped sandbox" "$out" "dir=$pdir"
assert_contains "tree inputs: status names the stamped project" "$(knowledge status "$proj" 2>&1)" "project:     $proj"
assert_contains "tree inputs: status from a subdirectory names the stamped clone" "$(knowledge status "$proj/sub/deep" 2>&1)" "clone:       $pdir/knowledge"
# what the sandbox can write in its clone: a role file naming the other role, a commit on main
pmain=$(git -C "$remote" rev-parse main); cmain=$(git -C "$clone" rev-parse main)
printf 'integrator %s\n' "$pid" > "$clone/.git/ai-knowledge-role"
echo '- planted' >> "$clone/rules/global.md"; git -C "$clone" commit -q --no-verify -am "planted on main"
knowledge sync "$proj/sub/deep" >"$tmp/o6-sync.out" 2>&1 || cat "$tmp/o6-sync.out"
assert_eq "tree inputs: sync from a subdirectory addresses the stamped sandbox" "$(grep -c 'no sandbox directory' "$tmp/o6-sync.out")" 0
assert_eq "tree inputs: sync syncs as proposals" "$(cat "$clone/.git/ai-knowledge-role")" "proposals $pid"
assert_eq "tree inputs: the clone's main does not reach the remote (sync)" "$(git -C "$remote" rev-parse main)" "$pmain"
knowledge sync --all >"$tmp/o6-all.out" 2>&1 || cat "$tmp/o6-all.out"
assert_eq "tree inputs: sync --all syncs the stamped sandbox as proposals" "$(cat "$clone/.git/ai-knowledge-role")" "proposals $pid"
assert_eq "tree inputs: the clone's main does not reach the remote (sync --all)" "$(git -C "$remote" rev-parse main)" "$pmain"
git -C "$clone" reset -q --hard "$cmain"
n=$(ls "$AI_SANDBOX_ROOT" | grep -c -- '-agent$')
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj/plainsub" >"$tmp/o6-create.out" 2>&1 || cat "$tmp/o6-create.out"
assert_eq "tree inputs: create from a subdirectory addresses the stamped sandbox" "$(head -1 "$pdir/project-path")" "$proj"
assert_eq "tree inputs: create made no other sandbox" "$(ls "$AI_SANDBOX_ROOT" | grep -c -- '-agent$')" "$n"
# _sync-clone resolves nothing: the project and the sandbox are what its parent names
rm -rf "$proj/sub/.git" "$proj/plainsub"; git config -f "$proj/.git/config" --unset core.worktree
mkdir -p "$tmp/work/nowhere"
msg=$(knowledge _sync-clone "$tmp/work/nowhere" 2>&1) && r=0 || r=$?
assert_eq "_sync-clone without its sandbox argument refuses" "$r" 1
assert_contains "_sync-clone names what it needs" "$msg" "usage"
msg=$(knowledge _sync-clone "$proj/sub" "$pdir" 2>&1) && r=0 || r=$?
assert_eq "_sync-clone takes the project it is given" "$(cat "$clone/.git/ai-knowledge-role")" "proposals $(ai_sandbox_project_id "$proj/sub")"
printf 'proposals %s\n' "$pid" > "$clone/.git/ai-knowledge-role"

# --- O21: init --integrator records what the lookup returns once the sandbox exists
orepo="$tmp/work/orepo"; mkdir -p "$orepo"; git -C "$orepo" init -q
ln -s "$tmp/work" "$tmp/olink"
out=$(knowledge init "file://$remote" --integrator "$tmp/olink/orepo" 2>&1) || echo "$out"
assert_contains "init records the resolved directory" "$(cat "$AI_KNOWLEDGE_CONFIG")" "INTEGRATOR=$orepo"
assert_contains "init, before its sandbox exists, names the directory" "$out" "$orepo"
assert_contains "init, before its sandbox exists, says none exists yet" "$out" "no sandbox exists yet"
assert_contains "init says the sandbox create-ai-sandbox.sh creates for exactly that directory takes the role" "$out" "creates for exactly that directory takes the role"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$tmp/olink/orepo" >"$tmp/o21-create.out" 2>&1 || cat "$tmp/o21-create.out"
assert_eq "the record is the value the lookup returns once create has run" \
    "$(sed -n 's/^INTEGRATOR=//p' "$AI_KNOWLEDGE_CONFIG")" "$(ai_sandbox_project_root "$tmp/olink/orepo")"
assert_file "create made the sandbox the record names" "$(ai_sandbox_dir_for "$orepo")/project-path"
out=$(knowledge init "file://$remote" --integrator "$tmp/olink/orepo/" 2>&1) || echo "$out"
assert_contains "init names the sandbox once it exists" "$out" "$(basename "$(ai_sandbox_dir_for "$orepo")")"
assert_eq "init no longer says none exists" "$(printf '%s\n' "$out" | grep -c 'no sandbox exists yet')" 0
out=$(knowledge init "file://$remote" --integrator "$orepo" 2>&1) || echo "$out"
assert_contains "init without a link names the same sandbox" "$out" "$(basename "$(ai_sandbox_dir_for "$orepo")")"

# --- without config nothing changes
rm "$AI_KNOWLEDGE_CONFIG"
other="$tmp/work/q"; mkdir -p "$other"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$other" >"$tmp/create2.out" 2>&1 || cat "$tmp/create2.out"
compose=$(cat "$(ai_sandbox_dir_for "$other")/docker-compose.yml")
assert_contains "live GEMINI.md mount kept without config" "$compose" "$HOME/.gemini/GEMINI.md:$HOME/.gemini/GEMINI.md\""
assert_eq "no knowledge mounts without config" "$(printf '%s\n' "$compose" | grep -c knowledge)" 0
assert_contains "create stamps SANDBOX_KNOWLEDGE=0 without config" "$(cat "$(ai_sandbox_dir_for "$other")/.env")" 'SANDBOX_KNOWLEDGE=0'
assert_no_file "no clone created without config" "$(ai_sandbox_dir_for "$other")/knowledge"
assert_no_file "no origin created without config" "$(ai_sandbox_dir_for "$other")/knowledge-origin.git"
assert_eq "no origin mount without config" "$(printf '%s\n' "$compose" | grep -c 'knowledge-origin')" 0
assert_file "create makes status/ without config" "$(ai_sandbox_dir_for "$other")/status"
assert_contains "create binds status/ read-only without config" "$compose" "\"$(ai_sandbox_dir_for "$other")/status:/run/ai-sandbox/status:ro\""
assert_contains "status/ is among the state directories" "$(ai_sandbox_state_dirs)" "status"

rm -rf "$tmp"
finish
