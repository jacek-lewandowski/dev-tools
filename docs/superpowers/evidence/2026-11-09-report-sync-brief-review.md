# Review of the brief: process reports travel through the knowledge sync

Reviewer: Fiona. Object: `docs/superpowers/specs/2026-11-09-report-sync-brief.md` against
`2026-11-09-report-sync-brief-request.md`. Read-only; the brief's two searches re-run unchanged
on the current tree (first grep: hits in PROJECT_MAP, create-ai-sandbox.sh 210/1052/1600, seed
files, migrate script, ai-knowledge, integrator SKILL, tests; second grep: the line list the
brief gives, matches).

Verdict: one more round. Two Important findings (one impact-set miss, one contract claim that
does not hold), one Important gap in the obligations. Rest is lesser.

## Important

1. Closing keeps the report text in `main` and so in every clone; "never on `main`" does not
   hold. Contract, "Closed like a proposal": the ours-merge makes the report commit the second
   parent of a `main` commit, and the brief states the text stays reachable with
   `git show <merge>^2:...`. Every sandbox of every project fetches `main` (the sync fast-forwards
   it and the clone has no narrower refspec), so after the first close, project A's task names,
   commit subjects and paths sit in the object store of project B's sandbox. Before close the
   same holds for `refs/remotes/origin/report/*` (default `fetch --prune origin` takes all
   branches). The user accepted reports on dedicated branches of the private remote; the task
   statement says "never on `main`". Neither the exposure to other projects' sandboxes nor the
   permanence is named. Resolve: either state both in the brief and put them to the user as the
   decision it is (it is an incompatible reading of the accepted exception), or choose a close
   that leaves no object on `main` (the integrator deletes the branch after reading; the host
   needs a deletion path for a non-ancestor `report/*` tip, which the brief then has to add and
   test), or restrict who fetches `report/*`.

2. Impact-set miss: `docs/shared-knowledge.md`. The recorded grep has `--exclude-dir=docs`, so
   the repository's main documentation of this mechanism is never searched. It states the
   branch contract (lines 207-209), the hook (297-299), the sync algorithm and classification
   (311-336), the closing rule and "Re-opening a closed proposal" (333-364), the command table
   (189-190), the `reports`-relevant integrator steps (414-423) and the role table (438-439).
   After the change it would describe only proposals and the `ai-knowledge` command list would
   omit `reports`. Search that would have found it:
   `grep -n 'proposal/\*\|ai-knowledge proposals' docs/shared-knowledge.md` (about 12 hits).
   Add the file to "Places that change" with an R4-style read obligation. Also missing from
   the list: `create-ai-sandbox.sh:1052`, the sandbox block rendered into every agent's rules
   (asserted by `test-knowledge.sh:318`); it names only `proposal/` branches and the hook, so
   either list it as unchanged on purpose with the reason or extend it by one clause. The
   dispatch `ai-knowledge:1129` and `usage` are covered by "update usage" but name the case
   line.

3. Obligations do not guard the cross-kind scope, which is the new risk of a kind-driven
   rewrite. R2/R3 test a report touching a non-`reports/` path and R1 proves proposals are
   unchanged on the existing fixtures, but nothing asserts that a `proposal/*` branch touching
   `reports/` is refused, nor that a `report/*` branch touching `proposals/` is refused, in the
   hook and in the host check. A shared prefix variable that is not rebound per kind passes
   every listed case. Add both cases to R2 (host) and R3 (hook). Also add: a closed report is
   deleted on the remote through the lease path (the stub `tests/ai-sandbox/stub/lease-timeout`
   matches only `:refs/heads/proposal/*`; fine for deletion, but its `amend` mode would not
   exercise reports, so state that no amend case is needed or add one).

## Lesser

- The process-report body is 498 words today (`awk` below the frontmatter, `wc -w`); the new
  "file the report" step with the git recipe needs roughly 80 words, and the brief says only
  "keep under 500". Say what is cut (the "Known gaps" bullets are the candidates) or the
  implementer trades rules silently.
- Old host / old clone, assumption text is right (old host ignores `report/*`, old hook does
  not guard it, new host rewrites the hook per sync). One consequence is unstated: until the
  host is updated, the skill (shipped on `main` by the integrator) tells agents to file a
  report that never leaves the clone, with no error. The skill step should say the report
  reaches the integrator only after the host's next sync with the new `ai-knowledge`, and tell
  the agent to leave the `.tmp/` copy meanwhile (it does: step 1 keeps scratch).
- Report directory is `reports/<project>/`, but scope only checks the `reports/` prefix, so a
  report branch can write another project's directory. Acceptable (same trust as proposals);
  say so.
- Stats JSON not shipped: the integrator cannot re-run `--check --stats` on the report. The
  brief records this as a decision; fine, but then "figures were checked by the report's own
  review" is the only assurance; the skill text should say the figures are not re-checkable.
- Comments in `bin/ai/ai-sandbox:18` and `ai-sandbox-restart:6` ("its proposals reach the
  remote") become incomplete; wording only.
- `reports` listing: the brief says "README excluded as there is none"; keep the filter shared
  and harmless rather than special-casing, so one implementation really serves both.

## Checked and fine

- Proposal behaviour: the plan keeps proposals byte-identical and R1 pins it against a B0
  capture; the hook `case` gains an arm, `proposal/*` arm text stays.
- Old clone with new host and the reverse do not break: the new host refreshes the hook, an
  old host leaves `report/*` branches unclassified and unpushed.
- Close mechanics: `tip_state` classifies an ours-merged report as closed (ancestor, not on the
  first-parent chain), the local branches and the remote branch go the same way as for
  proposals once the three loops and the fetch refspec are widened; the `reports/`-on-main
  warning twin is the right guard against a plain merge.
- Branch regex, `ai_sandbox_slug` (exists in `ai-sandbox-lib.sh:28`) and the hex suffix are
  consistent with `PROPOSAL_RE`.
- Unchanged-on-purpose list (migrate script, `propose`, proposals README, propose-rule skill)
  matches the grep.
- Brief names evidence file, user and the three decisions left open; B0 baseline before R1 is
  the right order.

# Round 2

Read the rewritten brief once against `bin/ai/ai-knowledge` (clone 208 and 701, fetches 221, 408, 732-744)
and a scratch experiment with real git.

Round 1: Important 1 fixed in design (invariant, close by deletion), Important 2 fixed (docs file,
no `docs` exclusion, `KNOWLEDGE_NOTE`), Important 3 fixed (cross-kind cases in R2/R3). Nothing round 1
accepted was dropped, except the "ignore branches already ancestors of main" filter in `reports`, which
is moot without ours-merges.

## Important

1. The fetch-narrowing recipe does not work as written. Contract: "the initial clone uses
   `git clone -c remote.origin.fetch=...` or equivalent". Tested: `git clone -c
   remote.origin.fetch=<narrow> src c` either dies ("multiple updates for ref ... not allowed") or,
   with a non-colliding refspec, appends to the default `+refs/heads/*` and the clone stays wide.
   Clone-then-narrow-then-delete-refs is no better: the clone has already fetched the report objects
   into `.git/objects`, and deleting refs leaves them there until gc, so R5's `git cat-file -e
   <report commit>` still succeeds in a fresh clone (and in any existing wide clone that ever fetched
   one). Resolve: build the clone with `git init` + `remote add` + narrowed `config` + first fetch, and
   state that a previously wide clone is not claimed clean without `gc --prune=now`; or use the simpler
   mechanism below.
2. Writer-side cleanup compares "remote tip equals local tip" through `refs/remotes/origin/report/*`,
   which the narrowed refspec never creates (a push only updates tracking refs that a fetch refspec
   maps). The writer therefore cannot tell pushed from pending by that ref. Name the signal: the push's
   exit status in the same sync, or `git ls-remote origin refs/heads/<b>` for a later sync; R5's
   "still holds them while offline" depends on it.

## Lesser

- The Contract says R7 guards the plain-merge history check; the history checks are in R5.
- Offline tombstone retry, lease form and "stale info counts as done" match the existing proposal path
  (798-834); the host should act on tombstones only in the integrator clone and only for names matching
  `REPORT_RE` (an agent in any clone can run `update-ref`).
- A report authored in the integrator clone is pushed like any other and closed the same way; fine.

## Heavier than the invariant needs

Yes, by the whole narrowing apparatus (per-role `remote.origin.fetch`, clone rewrite, wide-clone
narrowing, host checkout refspecs at 221 and 408, writer cleanup, R5 wide-clone case). Simpler
mechanism that keeps the invariant: store reports outside `refs/heads/`, as `refs/reports/<date>-<project>-<hex>`.
Verified with real git: a default `git clone`, `fetch --prune origin` and the host checkout never
fetch `refs/reports/*`, while `push origin <local>:refs/reports/<name>` creates it on the remote. Then:
no refspec change anywhere, no existing-clone migration, objects never enter other clones; only the
integrator's sync adds `fetch origin refs/reports/*:refs/reports/*`. The writer commits on a local
`report/tmp-*` branch as the recipe says, then `update-ref refs/reports/<name>` (hook arm for
`report/*` kept on the branch); the host pushes `refs/reports/*` refs and drops the writer's ref after
a successful push. The tombstone and lease-delete path stay as designed (refspec `:refs/reports/<name>`).
Caveat: a remote host that rejects custom ref namespaces; plain git and GitHub accept them, and the
brief's smoke test (R2 push) would show it. Recommend this over the narrowing.

Verdict: not yet. Two Important findings; Important 1 largely disappears with the `refs/reports/*`
namespace. Rest of the brief is sound.

# Redesign review (reports as `refs/reports/<name>`)

Read the whole new brief once. Mechanics tried in a scratch bare repo (default clone and
`fetch --prune` never take `refs/reports/*`; `push <c>:refs/reports/<n>` creates it; integrator
`fetch origin 'refs/reports/*:refs/reports/*'` takes it; `update-ref refs/reports-closed/<n>` tombstone;
`push --force-with-lease=refs/reports/<n>:<tip> origin :refs/reports/<n>` deletes it; a repeat gives
"stale info", which the brief counts as done; `fetch --prune origin` does not touch `refs/reports/*`
locally, so the host's own local delete is needed, as designed). Recorded grep re-run unchanged: same
hit set as round 1 plus `docs/shared-knowledge.md` and the doc/spec files; no further sites. A search for
`ls-remote|for-each-ref|--mirror|fetch --all|--prune` over `bin/ai` and the integrator skill finds no
code that enumerates all refs (the migrate script uses `ls-remote --heads` and `refs/heads/proposals/*`),
so nothing else sees the new namespace.

Verdict: sound; no Critical or Important finding. The two round 2 Importants are gone by construction.
One more spot to tighten in R9 (below, Lesser because the step is not yet run, but fix before sending it).

## Lesser

1. R9, `git commit-tree` needs an identity. The host's canonical checkout may have none (`build_commit`
   in `ai-knowledge` passes `-c user.name=... -c user.email=...` for exactly this case; in the scratch
   test an empty ident failed with "empty ident name"). Use
   `git -c user.name=smoke -c user.email=smoke@localhost commit-tree ...`, or the step fails before it
   reaches GitHub and the user may read that as a refusal.
2. R9 is not sufficient to settle feasibility. It proves push, listing and delete of a plain ref and that
   a default fetch ignores it, but not the two exact forms the host will use: the leased delete
   `git push --force-with-lease=refs/reports/<n>:<tip> origin :refs/reports/<n>` and the integrator's
   `git fetch origin 'refs/reports/*:refs/reports/*'` (a server that hides or rewrites custom refs could
   pass the plain push and fail these). Add both: fetch the ref into a scratch clone with that refspec,
   then delete with the lease form and `ls-remote` for emptiness. Also state the cleanup on failure: if the
   delete is refused, the test ref `refs/reports/9999-12-31-smoke-test-0000` stays on the remote, so the
   message should say to report that and not to retry blindly. The commands otherwise touch only that
   test ref (the commit object is a harmless unreferenced child of `origin/main` content); `cd` into the
   canonical checkout and `push origin <sha>:<ref>` are safe.
3. Order inside the report block: the integrator pushes every local `refs/reports/*` before acting on
   tombstones, so a tombstoned ref whose remote delete is pending is pushed again first (no-op while the
   remote has it, harmless). Skip tombstoned names in the push step so a stale-lease case cannot try to
   overwrite a moved remote ref; one sentence.
4. The status chain in `sync_clone` ends in one `set_status`; the brief says reports add `reports pushed N`
   only when N > 0 or one was refused or failed, but does not say that a pending (offline) or refused
   report takes the same precedence as the proposal ones (`refused:` first, `offline:` pending count).
   Say it, and give R2/R4 a status assertion for a refused report and for an offline pending one.
5. R2 has no case for an orphan ref (no common history); the brief lists it as refused. One line in R2.
6. Writer recipe: `checkout -b report/tmp-<project>` fails if an earlier interrupted run left that branch;
   the skill step should say to delete it first. Not blocking.

## Checked and fine

- Writer recipe: the commit passes the new `report/*` hook arm on the tmp branch; after `update-ref`,
  `checkout main` and `branch -D` the commit stays reachable only through `refs/reports/<name>`; the
  host's proposal loops (`refs/heads/proposal/*`) never see the tmp branch. `<hex>` after the commit is
  computable before `update-ref`.
- Cleanup signal (push exit 0 in the same sync, delete at once, retry-safe because the push is
  idempotent) works without a tracking ref, which round 2 flagged.
- Close by tombstone outside `refs/reports/`, acted on only in the integrator clone and only for
  `REPORT_RE` names; the lease form and offline retry match the proposal path.
- Impact set against the simpler design: proposal sites, fetch sites, `cmd_proposals` and the lease stub
  correctly unchanged; docs file, `KNOWLEDGE_NOTE`, doctor, help and comments listed.
- R5 now asserts the invariant on the real inputs (fresh and existing second clone, history empty on
  remote and integrator, host checkout), and it holds by construction.
