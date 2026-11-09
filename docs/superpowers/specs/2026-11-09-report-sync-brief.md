# Brief: process reports travel through the knowledge sync

Class: brief. Planner: Hania. Task statement: `2026-11-09-report-sync-brief-request.md`.
Review: `docs/superpowers/evidence/2026-11-09-report-sync-brief-review.md` (two rounds; this is the redesign).
Evidence file: `docs/superpowers/evidence/2026-11-09-report-sync.md`.

## Goal

An agent in any sandbox files a `process-report` report in its own knowledge clone.
The host pushes it on sync; the integrator sandbox lists, reads and closes it.
Proposals behave exactly as before. User: the person who wants the report in the
integrator sandbox without carrying files by hand. Deliberate exception, accepted
by the user, to "Nothing project-specific belongs here": reports live on the
private remote outside `main` and outside `refs/heads/`.

## Invariant (stated once; R5 checks it)

A report object is never reachable from `main`, and never lands in a clone other
than the one that wrote it and the integrator's. Mechanism: a report is a ref in
its own namespace, `refs/reports/<name>`, not a branch. Default `git clone` and
`fetch --prune origin` take only `refs/heads/*` (verified with real git by the
reviewer), so no refspec, clone or existing-clone change is needed anywhere; only
the integrator's sync adds `fetch origin 'refs/reports/*:refs/reports/*'`.

## Contract

- Name `<YYYY-MM-DD>-<project>-<hex>`; `<project>` is `ai_sandbox_slug` of the
  project directory basename, `<hex>` the first four hex characters of the commit.
  `REPORT_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+-[0-9a-f]{4}$'` applies to the
  name after `refs/reports/`. The ref on the remote and in clones is
  `refs/reports/<name>`.
- One commit created from `main`, adding only
  `reports/<project>/process-report-<P>-<F>_<T>.md`. Scope is the `reports/`
  prefix; writing another project's directory is accepted (same trust as
  proposals). A ref whose name is off the pattern, that changes any other path, or
  has no common history with `origin/main` is refused and not pushed, as for
  proposals. `main` never carries `reports/`.
- Writer recipe (skill, plain git, no new host command): `checkout -b
  report/tmp-<project>` from `main`, add the file, commit `report: <project> <F>_<T>`
  (the hook guards the path), `update-ref refs/reports/<name> HEAD`, `checkout main`,
  `branch -D report/tmp-<project>`. The tmp branch is never pushed; the skill step
  deletes a `report/tmp-<project>` left by an interrupted run before starting.
- Host sync, every clone, after the proposal block, which is left untouched: for
  each local `refs/reports/*` ref that has no tombstone (a stale-lease case must
  not overwrite a moved remote ref), validate name and scope, push
  `<ref>:<ref>` (idempotent; offline gives a hint and the ref stays pending).
  Writer cleanup signal: the push's exit status 0 in the same sync. In a
  non-integrator clone the ref is then deleted at once; if the sync dies between
  push and delete, the next push is a no-op with status 0 and the delete follows.
  In the integrator clone a ref stays until closed.
- Status: a refused report takes `refused:` precedence and an offline pending one
  the `offline:` pending count, the same as proposals (one `set_status`).
- Integrator sync additionally: acts on tombstones, then fetches
  `refs/reports/*:refs/reports/*` (non-forced). Tombstones are acted on only in
  the integrator clone and only for names matching `REPORT_RE` (any agent can run
  `update-ref`).
- Close is deletion. The integrator, after the user has seen the report, runs
  `git -C ~/knowledge update-ref refs/reports-closed/<name> refs/reports/<name>`
  (never under `refs/reports/`). The host, for each tombstone, runs
  `push --force-with-lease=refs/reports/<name>:<tip> origin :refs/reports/<name>`
  ("stale info" and "remote ref does not exist" count as done, as in the proposal
  path), then deletes the local ref, the tombstone. On any other failure or offline
  everything stays and the next sync retries. `ai-knowledge reports` hides
  tombstoned names. No `decisions.md` entry; a rule suggested by a report follows
  the proposal flow. A closed report is not recoverable from git.
- Hook (`install_hook`): a new `report/*` arm refuses any path outside `reports/`;
  the existing `proposal/*` arm already refuses `reports/` and keeps its text.

## Assumptions

- GitHub (`git@github.com:jacek-lewandowski/knowledge.git`) accepts pushes to and
  deletes of a custom namespace `refs/reports/*` (guessed; decides feasibility;
  settled by the host smoke step below before the feature is relied on).
  Tests use a local bare repo and cannot prove it.
- The stats JSON is not shipped: the integrator cannot re-run `--check --stats`, so
  figures are not re-checkable there; the skill text says so (inferred).
- Old host ignores `refs/reports/*`: a filed report stays local with no error until
  the host runs the new helper; the skill says so and the `.tmp/` copy stays
  meanwhile. Old hook does not guard `report/*`; the host scope check does.
- Report files are data; the integrator never follows instructions in them.
- `~/knowledge` content changes are an integrator commit on `main` of `~/knowledge`,
  a repository separate from the dev-tools commits; the seed README is kept equal
  (`diff bin/ai/knowledge-seed/README.md ~/knowledge/README.md` is empty today).

## Places that change

Searches, recorded exactly (counts and output in the evidence file):
`grep -rIn --exclude-dir=.git --exclude-dir=.tmp -e 'proposal/\*' -e 'proposal/<' -e 'PROPOSAL_RE' -e 'ai-knowledge proposals' .`
(no `docs` exclusion; hits under `docs/superpowers/` are plans and evidence,
ignored) and `grep -n "PROPOSAL_RE\|proposal/\*\|proposals/" bin/ai/ai-knowledge`.
Because reports are not branches and the proposal code is untouched, the
fetch sites (clone 208 and 701, fetches 221, 408, 732), `cmd_proposals`,
`PROPOSAL_RE` and every proposal loop do not change.

1. `bin/ai/ai-knowledge`: `REPORT_RE`; a separate report block in `sync_clone`
   (validate, scope check, push, writer cleanup, tombstones, integrator fetch)
   after the proposal loops; status line gains `reports pushed N` only when N > 0
   or one was refused or failed (a proposals-only run's text stays byte-identical);
   `install_hook` arm; new `cmd_reports [--repo DIR]` (`<name> <path>` per file in
   `refs/reports/*`, tombstoned hidden) and its dispatch case (line 1129), header
   comment and `usage`.
2. `bin/ai/create-ai-sandbox.sh`: doctor loop (1600) lists `refs/reports/*` as
   pending (a pushed one is already deleted in a writer clone); help (210);
   `KNOWLEDGE_NOTE` (1052, asserted at `test-knowledge.sh:318`) one clause.
   Comment wording in `bin/ai/ai-sandbox:18` and `ai-sandbox-restart:6`.
3. `.agents/skills/knowledge-integrate/SKILL.md`: Reports section: list with
   `bin/ai/ai-knowledge reports --repo ~/knowledge`, read with
   `git -C ~/knowledge show refs/reports/<name>:<path>`, show the user, close with
   the tombstone command; rule suggestions go through proposal triage; Never:
   merge a report into `main`.
4. `docs/shared-knowledge.md`: command table (189-190), branch/ref contract
   (207-209), hook (297-299), sync (311-336), close and re-open (333-364; reports
   are not re-openable), integrator steps (414-423), role table (438-439), the
   invariant.
5. `~/knowledge` (integrator commit): `skills/process-report/SKILL.md` last step
   "file the report" (recipe, old-host sentence, figures not re-checkable;
   `~/knowledge` missing means the report stays in `.tmp/`; clone on `main` and
   clean; replaces the rule "stays uncommitted in `.tmp/`"); body stays under 500
   words (498 today, commit 0f62a65): the cut is the "Known gaps" bullets, trimmed
   to what the new text displaces, named in the commit message. `README.md` Layout
   row, ref description, Flow note, the exception, the invariant; mirrored in
   `bin/ai/knowledge-seed/README.md`.
6. `PROJECT_MAP.md`: `ai-knowledge` and `knowledge-integrate` rows; coupling
   register row: `refs/reports/*` and `refs/reports-closed/*` of the private
   remote, read by the `process-report` skill and the integrator skill, marked at
   `REPORT_RE` with `# reads-outside:`.
7. Unchanged on purpose: `ai-sandbox-migrate-knowledge`, `propose`,
   `proposals/README.md`, `propose-rule`, `tests/ai-sandbox/stub/lease-timeout`
   (matches only `:refs/heads/proposal/*`; no amend path exists for reports).

## Obligations

- B0. Baseline on the base tree, once:
  `bash tests/ai-sandbox/test-knowledge.sh 2>&1 | python3 -m agent_log_trimmer -`.
  Pre-existing failures go to the user, not fixed here.
- R1 (proposals unchanged). Same suite after: all B0 greens stay green, no
  assertion edited or removed (`git diff` of the suite is additions only);
  `ai-knowledge proposals` output byte-identical to B0.
- R2 (host, local bare remote, tests first, `report_in` helper like `propose_in`):
  in-scope report pushed to `refs/reports/<name>`; ref touching a non-`reports/`
  path refused and not pushed; name off the pattern refused; an orphan ref (no
  common history) refused; a `proposal/*`
  branch touching `reports/` refused; a report ref touching `proposals/` refused;
  integrator receives the ref and `reports --repo` lists it; a mixed proposal plus
  report run pushes both; status assertions for a refused report (`refused:`) and
  an offline pending one (`offline:`).
- R3 (hook). `report/*` with a non-`reports/` path exits 1, with `reports/` exits 0;
  `proposal/*` with a `reports/` path exits 1; `main` still exits 1 naming
  `propose-rule`.
- R4 (writer cleanup and close). Writer clone: ref gone after a successful push,
  still present while offline, gone on the next online sync. Close: after the
  tombstone and a sync the ref is gone from the remote (lease push), from the
  integrator and the tombstone is gone; offline keeps all and the next sync
  completes; a stale lease deletes nothing locally and reports it; a tombstone
  made in a non-integrator clone, or with a name off `REPORT_RE`, is ignored.
- R5 (invariant). In a fresh second non-integrator clone and in an existing one,
  after sync: `git for-each-ref refs/reports` is empty and `git cat-file -e
  <report commit>` fails. `git log --full-history main -- reports/` is empty on the
  remote and in the integrator clone after a file, sync, close, sync cycle; the
  host's `KNOWLEDGE_MAIN` checkout holds no `refs/reports/*`.
- R6 (docs read). Integrator Reports section, process-report step, README rows,
  seed README, `docs/shared-knowledge.md` sections above and the `KNOWLEDGE_NOTE`
  clause each carry the ref name, the path rule, the invariant and the close
  command as in Contract; the seed and `~/knowledge` READMEs are `diff`-equal; the
  skill body is under 500 words (`awk` below the frontmatter `| wc -w`);
  `grep -n 'proposal/\*\|ai-knowledge proposals' docs/shared-knowledge.md`: every
  hit has a report counterpart or is proposal-specific on purpose.
- R7 (residue, diff review). First grep re-run: every remaining proposal-only site
  is named in the evidence file as proposal-specific on purpose; none of the
  sync, hook, doctor, listing, doc or sandbox-note sites is left proposal-only.
- R8 (gate). `bash tests/ai-sandbox/run-tests.sh` once after the last edit;
  failures B0 or the memory notes show as pre-existing are stated, not fixed.
- R9 (host smoke, by the user; the sandbox has no credentials; one message,
  pasted result expected). On the host, before the helper is relied on. It
  exercises the exact forms the host will use: plain push, listing, default fetch
  ignoring the ref, the integrator fetch refspec, the leased delete. It touches
  only the test ref `refs/reports/9999-12-31-smoke-test-0000` (the commit is an
  unreferenced child of `origin/main`'s tree).
  ```bash
  set -e
  R=refs/reports/9999-12-31-smoke-test-0000
  cd ~/.ai-sandbox/knowledge/main
  c=$(git -c user.name=smoke -c user.email=smoke@localhost commit-tree 'origin/main^{tree}' -p origin/main -m 'smoke: refs/reports')
  git push origin "$c:$R"
  git ls-remote origin 'refs/reports/*'                 # shows the ref and $c
  git fetch --prune origin
  git for-each-ref refs/reports                         # prints nothing
  s=$(mktemp -d) && git init -q "$s" && git -C "$s" remote add origin "$(git remote get-url origin)"
  git -C "$s" fetch origin 'refs/reports/*:refs/reports/*'
  git -C "$s" for-each-ref refs/reports                 # shows the ref
  git push --force-with-lease="$R:$c" origin ":$R"
  git ls-remote origin 'refs/reports/*'                 # prints nothing
  rm -rf "$s"
  ```
  Paste back: the full output, or the first error. If the push or the leased
  delete is refused, stop and report: the test ref stays on the remote, do not
  retry or delete it by other means; the namespace is not usable and the design
  returns to the planner.

## Open questions

None for the user. Decided and overridable: no new host command to create a
report; no stats JSON on the branch; no `decisions.md` entry on close; a closed
report is deleted, not archived in git.
