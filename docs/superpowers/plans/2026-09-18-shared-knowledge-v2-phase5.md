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
closed branch                      tip is an ancestor of origin/main AND not on origin/main's first-parent
                                   chain (`git rev-list --first-parent origin/main` does not list it);
                                   an ancestor that IS on the chain is "empty", kept. Applied at all
                                   three sites in sync_clone: the classification loop, the post-push
                                   local cleanup, and the remote deletion loop.
scratch files of sync --all         <sandbox dir>/.sync-output.<pid> and .sync-exit.<pid>, removed by the run that made them
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
- Closed-branch rule per the contract at all three sites; an ancestor on the
  first-parent chain is counted `empty` and left alone; the status line says
  `empty N` when N > 0 and the first status word stays `ok:`.
- A clone whose HEAD is unborn after cloning is put on `main` from `origin/main`.
- The `diverged` message for role `integrator` says merge `origin/main` in the
  clone, never `reset`; the proposals-role message says how to move stray commits
  onto a proposal branch and then reset.
- `record_integrator` skips, with a warning naming `ai-knowledge sync --all`, when
  the integrator clone exists and its `main` is ahead of `origin/main`.
- `main push failed` becomes a `push failed:` status.
- A `knowledge` path that exists and is not a git checkout is moved to
  `knowledge.not-a-clone.<timestamp>` before cloning, and the status says so.
- `cmd_render` replaces `$AI_KNOWLEDGE_RENDER` only after every step succeeded
  (the python render and `wire_host` prerequisites); on failure the previous render
  stays intact, the temp directory is removed, and the function returns non-zero
  without `exit`. `cmd_sync` and `cmd_sync_all` treat that as a warning and still
  sync the clones. Note: a function used as the left operand of `||` runs without
  `errexit`, so the render must check its own steps, not rely on `set -e`.
- Locks per the contract. Every call of `cmd_render`, including the `render` and
  `init` commands, runs under the main lock together with `sync_main`; the main
  lock and a clone lock are never held at the same time; a lock timeout is a
  warning plus `skipped: lock busy` for a clone, never an exit. The locked region
  cannot be a subshell: `sync_main` sets `MAIN_FETCHED`, `HINT_FETCH`, `NET_REASON`
  that the callers read afterwards, so use `exec {fd}>lock; flock -w 300 "$fd"`.
- `sync --all` scratch files per the contract, so two runs never read each other's.
- `cmd_sync_all` rows for a stale or unstamped sandbox name `create-ai-sandbox.sh
  <project>` as the repair (goal i), the bulk script as the shortcut.
- `cmd_init`: a `$KNOWLEDGE_MAIN` that exists and is not a git checkout is moved
  aside like the clone, never `rm -rf`'d.
- `print_hints` prints commands with `%q` for paths.
- The malformed-name refusal carries `git -C ~/knowledge branch -m <b> proposal/<date>-<slug>-<4 hex>`.
- Integrator sync: when `main`'s tree holds a proposal file other than README, warn
  once per sync ("a proposal branch was merged for real; see the doc on re-opening").
Files: `bin/ai/ai-knowledge`, `tests/ai-sandbox/test-knowledge.sh`.
Tests: orphan branch refused; a branch renaming `rules/global.md` into `proposals/`
refused; an empty branch (tip equal to `origin/main`, and one created from an older
main) reported `empty` and still present after the sync; a render made to fail
(a role file with broken frontmatter or `python3` hidden from PATH) leaves the
previous `GLOBAL.md` unchanged and still writes the clone's status; a
`timeout` stub on PATH that makes `git fetch` exit 128 silently yields an
`offline:` status and a visible message, not a stale `ok:`; a `master`-headed bare
remote gives a sandbox clone on `main` with rules present; the integrator diverged
message contains `merge` and not `reset --hard`; `init --integrator` with an
integrator clone one commit ahead skips the record and names `sync --all`; a
non-git `knowledge` directory is moved aside; two `sync --all` runs started
together both end with every clone `ok:` and both tables show no `error:` row (use
`&` and `wait`); a hint for a path with a space is quoted; the malformed-name
refusal contains `branch -m`; a `main` carrying a proposal file makes the integrator
sync warn; existing status assertions are re-anchored on the status word where they
used containment of `ok`. A stub `tests/ai-sandbox/stub/lease-timeout` (not on PATH
by default; a test puts a `timeout` symlink to it first on PATH for one run) can
make `git fetch` exit 128 silently for the silent-failure case; task 5 reuses it.
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
- Conversion runs on every host, not only the integrator's: every open file on
  every old branch found on the remote or as a local `proposals/*` branch in any
  clone on this host becomes a branch named per the contract, `<project-id>-<slug>`
  (its file is therefore `proposals/<date>-<project-id>-<slug>.md`; the existing
  migration assertions change accordingly). A file is "already converted" only when
  a branch with that exact `<project-id>-<slug>` exists on the remote (assumption:
  no host has run the earlier script, which used the bare slug). Step 0 still
  pushes a local old branch that is ahead of an existing remote branch; a local old
  branch whose remote is gone is converted from the clone instead of re-pushed.
- Only the ours-merge and the remote deletion stay integrator-host only and behind
  the existing confirmation. Moving clones to `main` runs regardless of that
  answer; a local old branch is deleted only when each of its open files has a
  counterpart on the remote, otherwise it is kept and named. A running sandbox that
  the user chose not to stop keeps its clone untouched too.
- The ssh precheck classifies the URL like `ensure_ssh_access` does (`ssh://`,
  `user@host:path`), not by prefix alone.
- The script ends with `ai-knowledge sync --all` and prints that the doctor inside
  sandboxes is rebuilt by the next plain `create-ai-sandbox.sh <project>` run.
Files: `bin/ai/ai-sandbox-migrate-knowledge`, `tests/ai-sandbox/test-knowledge.sh`.
Tests: a running stale sandbox is skipped without `y` and recreated with `y`; two
old branches from two projects with the same slug become two branches; a local-only
old branch (remote deleted) is converted, not re-pushed, on a non-integrator host
(config without INTEGRATOR); a local-only old branch whose conversion fails (the
canonical checkout made unwritable for that run) is kept and named; declining the
deletion still moves clones to `main`; an ssh remote without an agent exits 1
before any change (stub `ssh-add -l` returning 2); every clone ends `ok:` after
the run.
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
