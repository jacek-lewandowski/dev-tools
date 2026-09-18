# Shared knowledge v2, phase 5: hardening after the adversarial review

Spec: `docs/superpowers/specs/2026-09-18-shared-knowledge-v2-design.md`, phase 5
(added 2026-09-18; a spec change, so this plan goes to a reviewer before work).
Invariants: the spec's, unchanged. Findings come from three adversarial reviews of
2026-09-18 (invariants, operator journey, robustness); each task names the
findings it closes by the letters of the spec's phase 5 goal.

Tasks are grouped by file so that implementers never share a file. They run one
after another because every task adds cases to `tests/ai-sandbox/test-knowledge.sh`.
Each task: tests first, surgical edits, `bash tests/ai-sandbox/test-knowledge.sh`
green (plus the suite the task names), one Conventional Commit ending with the
Co-Authored-By line, no other file touched. The known failure `test-tools.sh`
case 20 is sandbox-only and ignored. Never touch `~/knowledge` or `~/.ai-sandbox`.

## Contracts

```
converted legacy proposal branch   proposal/<YYYY-MM-DD>-<project-id>-<slug>-<4 hex>
                                   (project-id = the old branch name after "proposals/")
locks                              flock -w 300 on $AI_KNOWLEDGE_ROOT/.lock around sync_main+render,
                                   and on <sandbox dir>/.knowledge.lock around one clone's sync
closed branch                      tip is an ancestor of origin/main AND `git ls-tree -r <tip> -- proposals/`
                                   lists a .md other than README.md; otherwise "empty", kept
status words (first token)         ok: | skipped: | refused: | conflict: | diverged: | offline: |
                                   push failed: | empty:  (tests anchor on "^<timestamp> <word>")
```

## Tasks

### Task 1: `ai-sandbox` enters a running sandbox; refusal text names the single repair

Goal (g, i): in `bin/ai/ai-sandbox`, `ai_sandbox_require_current` runs only inside
the branch that would `compose up`, so a running container is entered whatever its
stamp. `bin/ai/ai-sandbox-restart` keeps the check before `down`. In
`bin/ai/ai-sandbox-lib.sh`, `ai_sandbox_require_current` says: re-run
`create-ai-sandbox.sh <project dir>` for this sandbox (reading the project from
the stamp or `project-path`), and names `bin/ai/ai-sandbox-migrate-knowledge` as the
way to do every sandbox at once.
Files: `bin/ai/ai-sandbox`, `bin/ai/ai-sandbox-lib.sh`, `tests/ai-sandbox/test-knowledge.sh`.
Tests: with `DOCKER_STUB_RUNNING=true`, `ai-sandbox` on the stale sandbox exits 0
and the stub log shows `compose ... exec`, no `up`; with the stub reporting not
running it is still refused; `ai-sandbox-restart` on a running stale sandbox is
refused; the refusal names `create-ai-sandbox.sh` and the project directory.
Acceptance: the section's assertions and the existing start-script section pass.

### Task 2: `ai-knowledge` sync hardening

Goal (a, b, c, d, e, f, k): in `bin/ai/ai-knowledge`:
- `set -Eeuo pipefail`; the two `grep` in `net_failed` cannot fail the script.
- Scope check: `git diff --name-only --no-renames "origin/main...$b"` captured with
  its exit status; a non-zero status (no merge base) is `refused` with "no common
  history with main"; any path outside `proposals/` is `refused` as today.
- Closed-branch rule per the contract; a branch whose tip is an ancestor but whose
  tree holds no proposal file is counted `empty` and left alone; the status line
  says `empty N` when N > 0 and the first status word stays `ok:`.
- A clone whose HEAD is unborn after cloning is put on `main` from `origin/main`.
- The `diverged` message for role `integrator` says merge `origin/main` in the
  clone, never `reset`; the proposals-role message says how to move stray commits
  onto a proposal branch and then reset.
- `record_integrator` skips, with a warning naming `ai-knowledge sync --all`, when
  the integrator clone exists and its `main` is ahead of `origin/main`.
- `main push failed` becomes a `push failed:` status.
- A `knowledge` path that exists and is not a git checkout is moved to
  `knowledge.not-a-clone.<timestamp>` before cloning, and the status says so.
- `cmd_sync` and `cmd_sync_all`: a `cmd_render` failure is a warning and the clone
  sync still runs; the render's temp directory is removed on failure.
- Locks per the contract: `sync_main`+`cmd_render` under the main lock;
  `sync_project_clone` under the clone lock (children of `--all` take it too).
- `print_hints` prints commands with `%q` for paths.
- The malformed-name refusal carries `git -C ~/knowledge branch -m <b> proposal/<date>-<slug>-<4 hex>`.
- Integrator sync: when `main`'s tree holds a proposal file other than README, warn
  once per sync ("a proposal branch was merged for real; see the doc on re-opening").
Files: `bin/ai/ai-knowledge`, `tests/ai-sandbox/test-knowledge.sh`.
Tests: orphan branch refused; a branch renaming `rules/global.md` into `proposals/`
refused; an empty branch reported `empty 1` and still present after the sync; a
`timeout` stub on PATH that makes `git fetch` exit 128 silently yields an
`offline:` status and a visible message, not a stale `ok:`; a `master`-headed bare
remote gives a sandbox clone on `main` with rules present; the integrator diverged
message contains `merge` and not `reset --hard`; `init --integrator` with an
integrator clone one commit ahead skips the record and names `sync --all`; a
non-git `knowledge` directory is moved aside; two `sync --all` runs started
together both end with every clone `ok:` (use `&` and `wait`); existing status
assertions are re-anchored on the status word where they used containment of `ok`.
Acceptance: assertions pass; `bash tests/ai-sandbox/run-tests.sh` green except
test-tools case 20.

### Task 3: migration script

Goal (h): in `bin/ai/ai-sandbox-migrate-knowledge`:
- The table gains a `running` column from `ai_sandbox_container_running`; running
  stale sandboxes are stopped and recreated only after one `[y/N]` prompt naming
  them (stdin; no answer means skip); skipped ones are listed at the end.
- At the top, when the remote URL is ssh (`git@` or `ssh://`) and `ssh-add -l`
  returns 2 or 1, print how to load the key (`eval "$(ssh-agent -s)"; ssh-add`)
  and exit 1 before touching anything. All git network calls in the script run
  with `GIT_TERMINAL_PROMPT=0` and `timeout 60`.
- Conversion covers every open file on every old branch found either on the remote
  or as a local `proposals/*` branch in any clone on this host, using the contract
  name `<project-id>-<slug>`; a file is "already converted" only when a branch with
  that exact `<project-id>-<slug>` exists on the remote. Step 0 still pushes a
  local old branch that is ahead of an existing remote branch; a local old branch
  whose remote is gone is converted from the clone instead of re-pushed.
- The ours-merge and remote deletion stay integrator-host only and behind the
  existing confirmation; moving clones to `main` and deleting local old branches
  runs regardless of that answer once every open file has a counterpart.
- The script ends with `ai-knowledge sync --all` and prints that the doctor inside
  sandboxes is rebuilt by the next plain `create-ai-sandbox.sh <project>` run.
Files: `bin/ai/ai-sandbox-migrate-knowledge`, `tests/ai-sandbox/test-knowledge.sh`.
Tests: a running stale sandbox is skipped without `y` and recreated with `y`; two
old branches from two projects with the same slug become two branches; a local-only
old branch (remote deleted) is converted, not re-pushed; declining the deletion
still moves clones to `main`; an ssh remote without an agent exits 1 before any
change (stub `ssh-add -l` returning 2); every clone ends `ok:` after the run.
Acceptance: assertions pass.

### Task 4: documents, skill, messages in create

Goal (j, i): `docs/shared-knowledge.md` gains "Upgrading from the first design"
before "Deployment" (order: run the installed `ai-sandbox-migrate` once to refresh
the helpers; stop or accept stopping running sandboxes; run the migration script;
`ai-knowledge init <url> --integrator DIR` once more to record the integrator;
`ai-knowledge sync --all`; a plain `create-ai-sandbox.sh <project>` to rebuild the
image with the new doctor); step 5 adds the migration step and says to migrate the
integrator's host last; the doctor sentence in step 4 is corrected; a "Re-opening a
closed proposal" paragraph (`git show <merge>^2:proposals/<file> > f.md;
ai-knowledge propose f.md --push`) and a warning that `git merge` without `-s ours`
puts the file on `main`. `.agents/skills/knowledge-integrate/SKILL.md` gets the
re-open recipe and the `-s ours` warning. `bin/ai/create-ai-sandbox.sh` usage text
(the "Shared knowledge (optional)" paragraph) and the doctor's `NOT migrated` line
name `create-ai-sandbox.sh <project>`. `PROJECT_MAP.md` row of the migration
script mentions the running-sandbox prompt.
Files: those four and `PROJECT_MAP.md`; no test file.
Acceptance: `grep -n "Upgrading from the first design\|Re-opening" docs/shared-knowledge.md`
finds both; `grep -c 'proposals branch, synced by the host on every start' bin/ai/create-ai-sandbox.sh` is 0;
`bash tests/ai-sandbox/test-knowledge.sh` still green.

### Task 5: the lease and the doctor under test

Goal: a test that fails if the leased delete becomes a plain delete: a `timeout`
stub placed first on PATH for one run that, when it sees `push ... --force-with-lease`,
first pushes an amendment from the proposer clone and then execs the real command;
the branch must survive and be listed again. A test that the generated doctor
contains the `create-ai-sandbox.sh` repair text. Remove the stub afterwards.
Files: `tests/ai-sandbox/test-knowledge.sh`, `tests/ai-sandbox/stub/` (a new stub
used only by this case, named so it is not on PATH by default).
Acceptance: the case passes with the current code and fails when the lease is
removed (state that you tried it, then restored the code).

### Task 6: suites

`bash tests/ai-sandbox/run-tests.sh` and `bash tests/ai-sync/test-sync.sh` with
output at hand; done by the lead after task 5, followed by one review of the whole
phase diff.

## Assumptions

- `flock` is available on the host (verified here: `/usr/bin/flock`, util-linux).
- `DOCKER_STUB_RUNNING=true` makes the stub docker report a running container
  (verified in the stub) and `ai_sandbox_container_running` reads it (verified,
  `ai-sandbox-lib.sh`).
- `git diff --no-renames` reports a rename as a deletion plus an addition (git
  semantics; task 2's test proves it).
- The migration's confirmation reads stdin, as its existing prompt does (verified).

## Deferred list

Empty.
