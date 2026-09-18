# Shared knowledge v2, phase 3: per-proposal branches, commit-time checks, in-sandbox status

Spec: `docs/superpowers/specs/2026-09-18-shared-knowledge-v2-design.md`, phase 3 and
"Branch model". Spec change: the "Closing" bullet and the deletion invariant were
clarified on 2026-09-18 to match the mechanisms below (plan review found the old
wording needed a forbidden checkout and left the remote tip unguarded); the
guessed assumption about the two open proposals became a migration step.
Reviewed once; its blocking findings are folded in.
Unverified assumptions: none that decide feasibility; see the end.
Invariants: the spec's, including the amended deletion rule: the host deletes a
branch only when it is a `proposal/*` branch whose tip is an ancestor of
`origin/main`.

Tests: `bash tests/ai-sandbox/test-knowledge.sh`; full suites at the end. Phases 1
and 2 are in place: stamps, `sync --all`, `_sync-clone PROJECT SANDBOX_DIR`.

## Contracts

```
branch      proposal/<YYYY-MM-DD>-<slug>-<4 hex>        one proposal, created from main; the host
            refuses any proposal/* name outside ^proposal/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+-[0-9a-f]{4}$
file        proposals/<YYYY-MM-DD>-<slug>.md            frontmatter: scope, project, project_id,
                                                        machine, target, evidence
clone       every clone has main checked out; proposal branches are local branches beside it
role file   <clone>/.git/ai-knowledge-role = "<proposals|integrator> <project-id>"   written by the host
            on every sync; the hook reads the role, the propose-rule skill reads the project id
hook        <clone>/.git/hooks/pre-commit  installed/refreshed by the host on every sync
ai-knowledge proposals [--repo DIR]   "<branch> <path>" per open proposal file on local
                                       proposal/* branches that are not ancestors of main
ai-knowledge propose FILE [--repo DIR] [--project-id ID] [--machine M] [--slug S]
                                       creates proposal/<date>-<slug>-<hex> from origin/main in
                                       DIR (default: the canonical checkout) holding FILE as
                                       proposals/<date>-<slug>.md with the given frontmatter
                                       added, without touching the working tree; used by the
                                       migration here and by init in phase 4
.sync-status (proposals role)   "ok: main current; pushed N; closed M" | "skipped: ..." |
                                "diverged: main has local commits; ..." | "refused: <branch> ..."
                                | "conflict: <branch> ..." | "offline: ..."
```

## Mechanisms

- **Fast-forwarding main.** With `main` checked out: `merge --ff-only origin/main`.
  With a proposal branch checked out (an agent left it there): `fetch origin
  main:main`, which git accepts only for a branch that is not checked out
  (verified). A non-integrator clone whose `main` has local commits is `diverged`
  and left alone; the hook prevents that from happening by accident.
- **Closing a proposal.** The integrator runs, on `main`, `git merge -s ours --no-ff
  -m "proposal: <slug> integrated|rejected" proposal/<name>`. Main's tree is
  unchanged, the branch tip becomes an ancestor of main, no checkout and no file
  removal commit are needed. The spec's "remove the file, then merge" reaches the
  same state; this is the shorter route to it.
- **Branch suffix.** The skill commits on a temporary branch name and renames it to
  `proposal/<date>-<slug>-<4 hex of the commit>`, so the suffix comes from the
  commit as the spec says.
- **Order in every sync.** fetch with `--prune` → fast-forward `main` → classify
  each local `proposal/*` branch: malformed name (`refused`), closed (its tip is an
  ancestor of `origin/main`), open → push open ones only → delete closed ones.
  A clone whose `main` is `diverged` still processes its proposal branches.
- **Deletion.** Local: closed branches are deleted (checking out `main` first when a
  clean clone sits on one). Remote, integrator only and only after `main` was
  pushed: for each `origin/proposal/*` whose tip is an ancestor of `origin/main`,
  `push --force-with-lease=refs/heads/<b>:<that tip> origin :refs/heads/<b>`; a
  "stale info" rejection means the proposer pushed an amendment meanwhile and the
  branch is open again, not an error; an already-deleted branch is not an error.

## Tasks

### Task 1: host sync for the new branch model

Goal: `sync_clone` implements the contract for both roles. Proposals role: dirty →
`skipped`; fetch; fast-forward `main` as above; for each local `proposal/*`
branch: scope check (`diff --name-only origin/main...branch` all under
`proposals/`), else `refused` for that branch and no push of it; push fast-forward
only, a diverged remote is `conflict` for that branch; delete closed branches.
Integrator role: `main` ff-only (`diverged` otherwise), push `main` if ahead,
fetch `refs/heads/proposal/*:refs/heads/proposal/*` per branch (a non-ff refusal for
a branch the integrator committed on is not an error), push local `proposal/*`
that are ff of the remote, delete closed branches locally and, per the mechanism
above, on the remote. `cmd_propose` implements the contract with plumbing
(`read-tree` into a temporary index, `hash-object`, `write-tree`, `commit-tree`,
`update-ref`), so no working tree is touched.
New clones are created on `main`; a clone found on an old `proposals/*` branch is
`skipped` with a message naming the migration script. The role file is written on
every sync. `cmd_proposals` lists per the contract. Offline hints list the pushes
per branch as today.
Files: `bin/ai/ai-knowledge`.
Tests: the existing sections that assume `proposals/<id>` are rewritten for the
new model: clone created on `main`; a proposal branch made in the clone is pushed;
a branch touching `roles/` is `refused` and not pushed while another is pushed; a
dirty tree is `skipped`; the integrator sees the branch in `proposals`, edits main,
closes with the `-s ours` merge, its sync pushes main and deletes the branch on
the remote; the proposer's next sync fast-forwards main, deletes its local branch,
and lists nothing; a clone parked on a proposal branch still gets `main` updated;
a clone with a local commit on `main` is `diverged` but its proposal branch is
still pushed; a `proposal/tmp-x` branch is `refused`; an amendment pushed after
the close survives the integrator's sync and shows in `proposals` again; a closed
branch still held locally by the proposer is not re-created on the remote; the
offline case prints the per-branch push; `sync --all` still ends `ok` for every
clone; `propose` creates a well-formed branch from a file without changing the
working tree.
Acceptance: assertions pass.

### Task 2: the pre-commit hook

Goal: the host writes `<clone>/.git/hooks/pre-commit` (executable, bash, no
dependency on dev-tools) at clone creation and refreshes it on every sync: on
`main` with role `proposals` it refuses, naming the `propose-rule` skill; on
`proposal/*` it refuses any staged path outside `proposals/`; anything else passes.
It reads the first word of `.git/ai-knowledge-role`; a missing role file means
`proposals`. The doc notes it is advisory and the host scope check enforces.
Files: `bin/ai/ai-knowledge` (a heredoc or a function that writes the hook).
Tests: in a proposals clone, a commit to `rules/global.md` on `main` fails with
the skill's name in the output; a commit of `roles/x.md` on a proposal branch
fails; a commit of `proposals/x.md` on a proposal branch succeeds; in the
integrator clone a commit on `main` succeeds. Commits made with `--no-verify` in
the existing tests stay as they are where the test needs a rule violation.
Acceptance: assertions pass.

### Task 3: skills and seed files

Goal: `bin/ai/knowledge-seed/skills/propose-rule/SKILL.md` describes the new
procedure: on `main`, clean; duplicate check; `git checkout -b proposal/tmp-<slug>`;
write `proposals/<date>-<slug>.md` with the contract's frontmatter (`project_id`
is the second word of `~/knowledge/.git/ai-knowledge-role`, `machine` is
`hostname`, `project` the project directory's basename); commit; rename to the
final name;
`git checkout main`; report, including that the host pushes on the next sync and
the integrator decides. Never: commit on main, touch other paths, push, delete
branches. `.agents/skills/knowledge-integrate/SKILL.md`: list with
`ai-knowledge proposals`, read with `git show`, triage, wait for approval, edit
main with `decisions.md`, close with the `-s ours` merge, never check out a
proposal branch, find a closed proposal's text with `git log --full-history --
proposals/` or `git show <merge>^2:<path>`, report. `bin/ai/knowledge-seed/README.md` and
`proposals/README.md` describe the branch model. The same three seed files are
committed on the knowledge repository's `main` in `~/knowledge` (this sandbox is
the integrator) as one commit with a `decisions.md` entry naming the dev-tools
spec revision as its approval, so the rendered skill every sandbox gets matches.
Files: the four dev-tools files and the three files in `~/knowledge`.
Tests: `grep -c 'proposals/<project-id>' ` over the four dev-tools files is 0;
`diff` between each seed file and its copy on `~/knowledge` main is empty.
Acceptance: both checks.

### Task 4: sandbox-side visibility

Goal: the `KNOWLEDGE_NOTE` block in `create-ai-sandbox.sh` says the clone is on
`main` and that `propose-rule` creates a `proposal/*` branch. The doctor's
knowledge line adds the age of the last sync and, per local `proposal/*` branch,
`pushed` when `origin/<branch>` equals it, `pending` otherwise.
Files: `create-ai-sandbox.sh` (note block, doctor heredoc).
Tests: the generated `image/build/sandbox-doctor` contains `proposal/`; the
rendered `GLOBAL.md` no longer contains `proposals/<project-id>`.
Acceptance: both assertions.

### Task 5: migration additions (disposable script)

Goal: `bin/ai/ai-sandbox-migrate-knowledge` gains a knowledge-branch step after
the sandbox step, in this order: (0) every clone on this host whose `proposals/*`
branch is ahead of its remote is pushed fast-forward, or the run stops naming the
clone; (a) integrator host only: for every remote `proposals/*` branch, each open
proposal file becomes a `proposal/*` branch through `ai-knowledge propose` with
`project_id` from the old branch name and `machine: unknown`, pushed; (b)
integrator host only, with the user's confirmation, and only once every open file
of an old branch has its counterpart on the remote (`ls-remote`): each old branch
is merged into `main` with `-s ours` (so its history stays reachable and the
deletion falls under the invariant), `main` is pushed, then the old branch is
deleted on the remote; (c) every clean clone on `proposals/*` is switched to
`main` and its `proposals/*` local branches deleted, the integrator clone's local
`proposals/*` branches likewise; a dirty clone is reported and left.
Files: the script.
Tests: through the local bare remote, with the old-style branch hand-crafted
(`push origin main:refs/heads/proposals/<id>` plus commits): two files on it become
two well-formed `proposal/*` branches with `project_id` in their frontmatter, the
old branch is an ancestor of `main` and gone from the remote after a confirmed run
(`yes |`), a clone on the old branch ends on `main`, a dirty one is untouched and
named, a clone with an unpushed old-style commit stops the run before anything is
deleted.
Acceptance: assertions pass.

### Task 6: documentation, suites, commits

Goal: `docs/shared-knowledge.md` sections on branches, the clone, the integrator,
proposing and integrating describe the new model, the hook, the `-s ours` close,
the deletion rule and the in-sandbox status; `PROJECT_MAP.md` rows updated. Both
suites with output at hand. One Conventional Commit per task; the `~/knowledge`
commit separately in that repository.

## Assumptions

- `git fetch origin main:main` is refused for the checked-out branch and works
  otherwise (verified by experiment).
- `git merge -s ours --no-ff` on `main` leaves the tree unchanged and makes the
  merged branch an ancestor (git semantics; exercised by task 1's tests).
- `push --force-with-lease=<ref>:<tip> origin :<ref>` deletes only when the remote
  still has that tip and rejects with "stale info" otherwise (verified by the plan
  reviewer's experiment); a branch already gone rejects with "remote ref does not
  exist", treated as success.
- The two open proposals on `proposals/modularyzacja-84a3eb05` are converted by
  task 5, so no integration has to happen before this phase lands. All six local
  old-style branches in `~/knowledge` equal their remotes today (verified).
- `pre-commit` does not run on `git merge`, so the hook never blocks a close
  (verified by the plan reviewer).

## Deferred list

Empty.
