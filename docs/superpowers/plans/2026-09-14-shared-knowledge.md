# Shared Knowledge Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every AI sandbox read-only access to a versioned, private knowledge repository and a write-only proposals branch, with the host doing all network git and this repository's sandbox acting as integrator.

**Architecture:** A new host helper `bin/ai/ai-knowledge` owns the repository: config, canonical main checkout, rendering into the read-only shared store, and per-sandbox clone sync. The existing sandbox scripts call it before every start and swap the live `GEMINI.md` mounts for the rendered view when it is configured. Two skills close the loop: `propose-rule` in every sandbox and `knowledge-integrate` in this repository.

**Tech Stack:** bash, git, python3 (frontmatter parsing and rendering), rsync, the existing bash test harness in `tests/ai-sandbox/harness.sh`.

**Spec:** `docs/superpowers/specs/2026-09-14-shared-knowledge-design.md`

## Global Constraints

- Edit points in existing files are marked with `# PLAN-ANCHOR knowledge <id>` comment lines. Locate them with `grep -rn "PLAN-ANCHOR knowledge <id>" bin/`. Never use line numbers. A task removes only the anchors it names; the last task sweeps the rest.
- Without `~/.ai-sandbox/knowledge/config` every existing behaviour is unchanged, and every existing test keeps passing.
- No `git push --force`, no `git rebase`, no branch rewrite anywhere in host code.
- All network git runs under `timeout "${AI_KNOWLEDGE_GIT_TIMEOUT:-60}"`.
- Sandbox scripts never fail a start because of knowledge sync; problems go to `.sync-status` and stderr.
- Every shared mount stays `:ro`; the only writable knowledge mount is the sandbox's own clone.
- Tests run with `bash tests/ai-sandbox/test-knowledge.sh` and `bash tests/ai-sync/test-sync.sh`; the full suites with `bash tests/ai-sandbox/run-tests.sh`.
- Commits use Conventional Commits and end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

### Task 1: Library constants and helper registration

**Files:**
- Modify: `bin/ai/ai-sandbox-lib.sh` (anchor `helpers-list`)
- Test: `tests/ai-sandbox/test-knowledge.sh` (created here, grown by later tasks)

**Interfaces:**
- Produces: `AI_KNOWLEDGE_ROOT` (`$AI_SANDBOX_ROOT/knowledge`), `AI_KNOWLEDGE_CONFIG` (`$AI_KNOWLEDGE_ROOT/config`), `AI_KNOWLEDGE_RENDER` (`$AI_SANDBOX_ROOT/shared/knowledge`), function `ai_knowledge_configured` (true when the config file exists), and `ai-knowledge` in `ai_sandbox_helpers`.

- [x] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-knowledge.sh`:

```bash
#!/usr/bin/env bash
# The shared knowledge repository: read-only rules for every sandbox, a
# proposals branch per sandbox, all network git on the host.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"

assert_eq "knowledge root derives from the sandbox root" "$AI_KNOWLEDGE_ROOT" "$AI_SANDBOX_ROOT/knowledge"
assert_eq "render lives in the shared store" "$AI_KNOWLEDGE_RENDER" "$AI_SANDBOX_ROOT/shared/knowledge"
ai_knowledge_configured && r=yes || r=no
assert_eq "not configured without the config file" "$r" no
assert_contains "ai-knowledge is an installed helper" "$(ai_sandbox_helpers)" "ai-knowledge"

rm -rf "$tmp"
finish
```

- [x] **Step 2: Run it to verify it fails**

Run: `bash tests/ai-sandbox/test-knowledge.sh`
Expected: failures on the three knowledge assertions (unbound variable or "no", missing helper).

- [x] **Step 3: Add the constants and the helper**

In `bin/ai/ai-sandbox-lib.sh`, after the `AI_SANDBOX_MAX_RUNNING=3` line add:

```bash
# The shared knowledge repository (see ai-knowledge). Configured when the config
# file exists; every knowledge feature is inert otherwise.
AI_KNOWLEDGE_ROOT="$AI_SANDBOX_ROOT/knowledge"
AI_KNOWLEDGE_CONFIG="$AI_KNOWLEDGE_ROOT/config"
AI_KNOWLEDGE_RENDER="$AI_SANDBOX_ROOT/shared/knowledge"
ai_knowledge_configured() { [ -f "$AI_KNOWLEDGE_CONFIG" ]; }
```

Replace the `# PLAN-ANCHOR knowledge helpers-list` line with `ai-knowledge`.

- [x] **Step 4: Run the test and the migrate suite**

Run: `bash tests/ai-sandbox/test-knowledge.sh && bash tests/ai-sandbox/test-migrate.sh`
Expected: both pass.

- [x] **Step 5: Commit**

```bash
git add bin/ai/ai-sandbox-lib.sh tests/ai-sandbox/test-knowledge.sh
git commit -m "feat(ai-sandbox): declare the shared knowledge paths and helper"
```

### Task 2: Seed files and the two skills

**Files:**
- Create: `bin/ai/knowledge-seed/README.md`, `bin/ai/knowledge-seed/decisions.md`, `bin/ai/knowledge-seed/proposals/README.md`, `bin/ai/knowledge-seed/roles/README.md`, `bin/ai/knowledge-seed/roles/planner.md`, `bin/ai/knowledge-seed/roles/implementer.md`, `bin/ai/knowledge-seed/roles/reviewer.md`, `bin/ai/knowledge-seed/skills/propose-rule/SKILL.md`
- Create: `.agents/skills/knowledge-integrate/SKILL.md`, symlink `.claude/skills/knowledge-integrate -> ../../.agents/skills/knowledge-integrate`

**Interfaces:**
- Produces: the seed directory `ai-knowledge init` copies verbatim into an empty repository (everything except `rules/global.md`, which init derives from the host's GEMINI.md).

- [x] **Step 1: Write the seed files**

`README.md`: purpose, layout, the branch rule, the four commands.
`decisions.md`: a header and the entry format `- <date> <proposal-id> integrated|rejected: <why>`.
`proposals/README.md`: the proposal frontmatter (`scope`, `project`, `session`, `evidence`, `target`) and the one-file-one-commit rule.
`roles/README.md`: the role frontmatter (`name`, `description`, optional `tools`, `model`) and what it renders to.
`roles/planner.md`, `roles/implementer.md`, `roles/reviewer.md`: short starter bodies.
`skills/propose-rule/SKILL.md`: the procedure from the spec, with the file template and the commit command.

- [x] **Step 2: Write the integrator skill**

`.agents/skills/knowledge-integrate/SKILL.md`: the procedure from the spec, and `ln -s ../../.agents/skills/knowledge-integrate .claude/skills/knowledge-integrate`.

- [x] **Step 3: Check the frontmatter parses**

Run: `for f in bin/ai/knowledge-seed/roles/*.md bin/ai/knowledge-seed/skills/*/SKILL.md .agents/skills/knowledge-integrate/SKILL.md; do head -1 "$f" | grep -q '^---$' || echo "no frontmatter: $f"; done`
Expected: no output for the role and skill files (README files are exempt).

- [x] **Step 4: Commit**

```bash
git add bin/ai/knowledge-seed .agents/skills/knowledge-integrate .claude/skills/knowledge-integrate
git commit -m "feat(ai-knowledge): seed files, propose-rule and knowledge-integrate skills"
```

### Task 3: The ai-knowledge helper

**Files:**
- Create: `bin/ai/ai-knowledge`
- Test: `tests/ai-sandbox/test-knowledge.sh`

**Interfaces:**
- Consumes: Task 1 constants; `ai_sandbox_project_root`, `ai_sandbox_project_id`, `ai_sandbox_dir_for` from the lib; the seed directory from Task 2, located through `DEV_TOOLS_DIR` in `$AI_SANDBOX_ROOT/config` with the script's own directory as fallback.
- Produces: commands `init`, `sync`, `render`, `status`, `proposals`; the render tree under `AI_KNOWLEDGE_RENDER`; the clone at `<sandbox dir>/knowledge` with `.sync-status`; host wiring of `~/.gemini/GEMINI.md`, `~/.claude/agents`, own skills.

- [x] **Step 1: Extend the test**

Append to `tests/ai-sandbox/test-knowledge.sh` before `rm -rf "$tmp"`:

```bash
git config --global user.email t@example.com; git config --global user.name t
git config --global init.defaultBranch main
export AI_KNOWLEDGE_GIT_TIMEOUT=20
knowledge() { bash "$REPO_ROOT/bin/ai/ai-knowledge" "$@"; }

remote="$tmp/remote.git"; git init -q --bare "$remote"
printf '# Rules\n\n- be brief\n\n<!-- BEGIN dev-tools:ai-sandbox-environment -->\nsandbox block\n<!-- END dev-tools:ai-sandbox-environment -->\n' > "$HOME/.gemini/GEMINI.md" 2>/dev/null || { mkdir -p "$HOME/.gemini"; printf '# Rules\n\n- be brief\n' > "$HOME/.gemini/GEMINI.md"; }
integ="$tmp/work/dev-tools"; mkdir -p "$integ"; git -C "$integ" init -q
proj="$tmp/work/p"; mkdir -p "$proj"; git -C "$proj" init -q

# --- init seeds an empty remote and wires the host
knowledge init "file://$remote" --integrator "$integ" >"$tmp/init.out" 2>&1 || cat "$tmp/init.out"
assert_file "config written" "$AI_KNOWLEDGE_CONFIG"
assert_contains "remote recorded" "$(cat "$AI_KNOWLEDGE_CONFIG")" "REMOTE=file://$remote"
assert_contains "integrator recorded" "$(cat "$AI_KNOWLEDGE_CONFIG")" "INTEGRATOR=$integ"
assert_eq "main seeded on the remote" "$(git -C "$remote" ls-tree --name-only main | sort | tr '\n' ' ')" "README.md decisions.md proposals roles rules skills "
assert_eq "global rules taken from GEMINI.md without the sandbox block" \
    "$(git -C "$remote" show main:rules/global.md | tr -d '\n')" '# Rules- be brief'
assert_link "host GEMINI.md points at the render" "$HOME/.gemini/GEMINI.md" "$AI_KNOWLEDGE_RENDER/GLOBAL.md"
assert_file "host GEMINI.md backed up" "$(ls "$HOME"/.gemini/GEMINI.md.pre-ai-knowledge.* | head -1)"
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
assert_eq "proposal pushed" "$(git -C "$remote" ls-tree --name-only "proposals/$pid" -- "proposals/$pid/" )" "proposals/$pid/2026-09-14-test.md"
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
assert_contains "proposals listing" "$(knowledge proposals --repo "$iclone")" "proposals/$pid proposals/$pid/2026-09-14-test.md"
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

# --- offline is a status, not a failure
mv "$remote" "$remote.away"
knowledge sync "$proj" >/dev/null 2>&1; rc=$?
assert_eq "offline sync exits 0" "$rc" 0
assert_contains "offline status" "$(cat "$clone/.sync-status")" "offline"
mv "$remote.away" "$remote"
```

- [x] **Step 2: Run to verify it fails**

Run: `bash tests/ai-sandbox/test-knowledge.sh 2>&1 | tail -5`
Expected: failures because `bin/ai/ai-knowledge` does not exist.

- [x] **Step 3: Write `bin/ai/ai-knowledge`**

The full script as implemented in this task: a `set -euo pipefail` bash program sourcing `ai-sandbox-lib.sh`, defining `git_net` (timeout wrapper), `load_config`, `seed_dir`, `cmd_init`, `sync_main`, `cmd_render` (python3 renderer writing to a temp dir then `rsync -a --delete --inplace`), `wire_host`, `prepare_targets`, `link_skills_into`, `sync_clone` (proposals and integrator roles as specified), `cmd_sync`, `cmd_status`, `cmd_proposals`, and a `case` dispatcher. `chmod +x`.

- [x] **Step 4: Run the test**

Run: `bash tests/ai-sandbox/test-knowledge.sh`
Expected: all pass.

- [x] **Step 5: Commit**

```bash
git add bin/ai/ai-knowledge tests/ai-sandbox/test-knowledge.sh
git commit -m "feat(ai-knowledge): host-side sync, render and proposals for the knowledge repository"
```

### Task 4: Hook the sandbox scripts

**Files:**
- Modify: `bin/ai/create-ai-sandbox.sh` (anchors `usage-commands`, `sync-call`, `block-write`, `compose-brain`, `doctor-status`, `summary-brain`)
- Modify: `bin/ai/ai-sandbox` (anchor `start-sync`), `bin/ai/ai-sandbox-restart` (anchor `restart-sync`)
- Test: `tests/ai-sandbox/test-knowledge.sh`

**Interfaces:**
- Consumes: `ai-knowledge sync <project>` from Task 3; `ai_knowledge_configured`, `AI_KNOWLEDGE_ROOT`, `AI_KNOWLEDGE_RENDER` from Task 1.

- [x] **Step 1: Extend the test**

Append before `rm -rf "$tmp"`:

```bash
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
assert_eq "sandbox block not written into the repository file" \
    "$(grep -c 'ai-sandbox-environment' "$AI_KNOWLEDGE_ROOT/main/rules/global.md")" 0
assert_contains "doctor reports knowledge" "$(cat "$pdir/sandbox-doctor.sh" 2>/dev/null || grep -h 'knowledge' "$pdir"/*.sh "$AI_SANDBOX_ROOT"/image/* 2>/dev/null)" "knowledge"

# --- without config nothing changes
rm "$AI_KNOWLEDGE_CONFIG"
other="$tmp/work/q"; mkdir -p "$other"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$other" >"$tmp/create2.out" 2>&1 || cat "$tmp/create2.out"
compose=$(cat "$(ai_sandbox_dir_for "$other")/docker-compose.yml")
assert_contains "live GEMINI.md mount kept without config" "$compose" "$HOME/.gemini/GEMINI.md:$HOME/.gemini/GEMINI.md\""
assert_eq "no knowledge mounts without config" "$(printf '%s\n' "$compose" | grep -c knowledge)" 0
```

- [x] **Step 2: Run to verify it fails**

Run: `bash tests/ai-sandbox/test-knowledge.sh 2>&1 | grep -c 'not ok'`
Expected: several failures on the compose assertions.

- [x] **Step 3: Edit `create-ai-sandbox.sh` at each anchor**

`usage-commands`: add `ai-knowledge          init | sync | render | status | proposals -- the shared knowledge repository` and remove the anchor.

`sync-call`: replace the anchor with

```bash
# Shared knowledge repository: when configured, the rendered main branch is what
# the tools read, and the sandbox gets its own clone. All network git runs here.
KNOWLEDGE="no"
if ai_knowledge_configured; then
    step "Shared knowledge repository"
    "$SCRIPT_DIR/ai-knowledge" sync "$PROJECT_ABS_DIR" || warn "knowledge sync reported a problem; see above"
    KNOWLEDGE="yes"
fi
```

`block-write`: wrap the python block so that when `KNOWLEDGE=yes` the block goes to `$AI_KNOWLEDGE_ROOT/sandbox-environment.md` followed by `"$SCRIPT_DIR/ai-knowledge" render`, and the existing GEMINI.md write runs otherwise. Add the `~/knowledge` and `propose-rule` note to `SANDBOX_BLOCK` when `KNOWLEDGE=yes`.

`compose-brain`: emit the knowledge mounts when `KNOWLEDGE=yes`, else the two existing lines. Because this is inside a heredoc, split the heredoc: end `COMPOSE_VOLS` before the brain lines, emit either block with a conditional `cat`, then continue with a second heredoc for the remaining volumes.

`doctor-status`: add `status "knowledge"   "$( [ -f "$HOME/knowledge/.sync-status" ] && cat "$HOME/knowledge/.sync-status" || echo "not configured" )"`.

`summary-brain`: print `Shared knowledge:   $AI_KNOWLEDGE_RENDER/GLOBAL.md (from the knowledge repository)` when `KNOWLEDGE=yes`, else the existing line.

- [x] **Step 4: Edit the start scripts**

`ai-sandbox`, replace the anchor with:

```bash
# Knowledge sync before the container comes up, so the rules it reads are the
# current main and its proposals reach the remote. Never blocks the start.
if ai_knowledge_configured; then
    "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-knowledge" sync "$AI_SANDBOX_PROJECT" || true
fi
```

`ai-sandbox-restart`: the same block replacing its anchor.

- [x] **Step 5: Run the knowledge test and the full sandbox suite**

Run: `bash tests/ai-sandbox/test-knowledge.sh && bash tests/ai-sandbox/run-tests.sh 2>&1 | tail -3`
Expected: all pass, `ALL SUITES PASSED`.

- [x] **Step 6: Commit**

```bash
git add bin/ai/create-ai-sandbox.sh bin/ai/ai-sandbox bin/ai/ai-sandbox-restart tests/ai-sandbox/test-knowledge.sh
git commit -m "feat(ai-sandbox): mount the rendered knowledge read-only and sync the clone on every start"
```

### Task 5: ai-sync hands GEMINI.md to git

**Files:**
- Modify: `bin/ai/ai-sync` (anchors `sync-push-brain`, `sync-pull-brain`)
- Test: `tests/ai-sync/test-sync.sh`

- [x] **Step 1: Extend the test**

Append before the final cleanup in `tests/ai-sync/test-sync.sh`:

```bash
# --- once the knowledge repository owns GEMINI.md, ai-sync leaves it alone
mkdir -p "$HOME/.ai-sandbox/knowledge"; echo 'REMOTE=x' > "$HOME/.ai-sandbox/knowledge/config"
rc=$(run push)
assert_eq "push still succeeds with knowledge configured" "$rc" 0
assert_eq "GEMINI.md not pushed when git owns it" "$(transfers | grep -c GEMINI.md)" 0
assert_contains "the skip is announced" "$(cat "$tmp/out")" "knowledge repository"
printf 'shared-brain/\nshared-brain/GEMINI.md\n' > "$RCLONE_STUB_INDEX"
rc=$(run pull)
assert_eq "GEMINI.md not pulled when git owns it" "$(transfers | grep -c GEMINI.md)" 0
rm "$HOME/.ai-sandbox/knowledge/config"
```

- [x] **Step 2: Run to verify it fails**

Run: `bash tests/ai-sync/test-sync.sh 2>&1 | grep 'not ok'`
Expected: the two "not pushed/pulled" assertions fail.

- [x] **Step 3: Implement**

Replace each anchor plus the following `push_file`/`pull_file` GEMINI.md line with:

```bash
    if [ -f "${AI_SANDBOX_ROOT:-$HOME/.ai-sandbox}/knowledge/config" ]; then
        log_skip "GEMINI.md is owned by the knowledge repository (ai-knowledge); not synced"
    else
        push_file "$HOME/.gemini/GEMINI.md"               shared-brain
    fi
```

and the pull equivalent with `pull_file shared-brain/GEMINI.md "$HOME/.gemini"`.

- [x] **Step 4: Run the test**

Run: `bash tests/ai-sync/test-sync.sh`
Expected: all pass.

- [x] **Step 5: Commit**

```bash
git add bin/ai/ai-sync tests/ai-sync/test-sync.sh
git commit -m "feat(ai-sync): skip GEMINI.md once the knowledge repository owns it"
```

### Task 6: Documentation and anchor sweep

**Files:**
- Modify: `PROJECT_MAP.md`, `bin/ai/create-ai-sandbox.sh` (usage text block "Mounted live from the host")
- Sweep: every remaining `PLAN-ANCHOR knowledge` line

- [x] **Step 1: Update PROJECT_MAP.md**

Add rows for `bin/ai/ai-knowledge`, `bin/ai/knowledge-seed/`, `.agents/skills/knowledge-integrate/`, `tests/ai-sandbox/test-knowledge.sh`, and the two design documents.

- [x] **Step 2: Update the usage text**

In the "Mounted live from the host" paragraph mention that with `ai-knowledge init` the rules come from the rendered knowledge repository instead, read-only, and the sandbox gets `~/knowledge`.

- [x] **Step 3: Sweep the anchors**

Run: `grep -rln "PLAN-ANCHOR knowledge" bin tests docs .agents | xargs -r sed -i '/PLAN-ANCHOR knowledge/d'; grep -rn "PLAN-ANCHOR knowledge" . --exclude-dir=.git --exclude-dir=node_modules | grep -v docs/superpowers`
Expected: no output.

- [x] **Step 4: Full verification**

Run: `bash tests/ai-sandbox/run-tests.sh 2>&1 | tail -3 && bash tests/ai-sync/test-sync.sh | tail -2 && bash -n bin/ai/ai-knowledge bin/ai/create-ai-sandbox.sh bin/ai/ai-sandbox bin/ai/ai-sandbox-restart bin/ai/ai-sync`
Expected: `ALL SUITES PASSED`, ai-sync `0 failed`, no syntax errors.

- [x] **Step 5: Commit**

```bash
git add -A PROJECT_MAP.md bin docs .agents .claude tests
git commit -m "docs(ai-knowledge): project map, usage text, remove plan anchors"
```
