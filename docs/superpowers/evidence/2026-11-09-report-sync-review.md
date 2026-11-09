# Review: report sync through refs/reports (brief class)

Reviewer: Fiona, reviewer 1. Round 1. Object: dev-tools `8bcbfdc..a9b2a98`, ~/knowledge `756f196`.
Brief: `docs/superpowers/specs/2026-11-09-report-sync-brief.md`. Evidence: `2026-11-09-report-sync.md`.

Verdict: **blocked on one Important finding** (I1). Delta re-review after the fix.

Re-run: `bash tests/ai-sandbox/test-knowledge.sh` at a9b2a98 -> `454 run, 0 failed`.
Residue search of the brief re-run unchanged: non-docs hits are all proposal-specific, as the evidence says.
Repro of I1 and M1: a scratch copy of the suite (lines 1-1114 plus the scenarios below), git 2.34.1.

## Important

**I1. A report whose remote ref is already gone can never be closed; the status says it moved.**
`bin/ai/ai-knowledge`, `sync_clone`, tombstone loop. A leased delete of a ref the remote does
not have answers `! [rejected] (delete) -> refs/reports/X (stale info)`, not "remote ref does not
exist" (checked with plain git 2.34.1 and through the sync). That case goes to the `*"stale info"*`
arm: local ref and tombstone kept, `reports` hides the report, and every integrator sync adds
"report X not closed: the remote ref moved since it was fetched", which is false; no doc gives a
way out. Reachable triggers, both reproduced:
- the integrator sandbox (dev-tools, where process reports are made) files its own report and the
  user closes it before a host sync: the push loop skips tombstoned refs, so it never reached the
  remote -> stuck after two syncs;
- the remote ref was deleted but the local cleanup did not follow (the leased push applied and
  `git_net` timed out with 124, or the sync died before `update-ref -d`, or a hand delete) -> stuck.
This is deviation (1): the brief's Contract ("stale info" counts as done, as for proposals) was the
safe reading; counting it as done loses nothing, because the lease keeps a moved remote ref and the
following fetch brings it back. Resolve: on "stale info", `ls-remote origin refs/reports/<name>`;
empty -> done (delete local ref and tombstone); present -> keep and report as now. Or follow the
Contract. Add regression tests for both triggers, written first, and align the close paragraph of
`docs/shared-knowledge.md`.

## Minor (not blocking)

- **M1.** Integrator status shows `reports pushed N` on every sync, N = open reports: the integrator
  re-pushes every fetched ref (a no-op push exits 0 and counts). Reproduced: `ok: main current;
  pushed 0; closed 0; reports pushed 3` on a sync that changed nothing; it also costs one network
  push per open report per sync. The test "integrator status carries no report text for a no-op"
  passes only because it runs on the sync that first fetched the ref (the fetch follows the push
  loop). Resolve: in the integrator, push only refs the remote lacks or holds at another value, or
  count only those.
- **M2.** `create-ai-sandbox.sh` doctor loop: in the integrator sandbox every open report, fetched
  from the remote, is labelled "pending: reaches the remote on the next host sync". The brief
  specified the loop for writer clones only. Resolve: read the role from `.git/ai-knowledge-role`
  and label them open in the integrator.
- **M3.** An off-pattern ref under `refs/reports/` on the remote is fetched into the integrator and
  keeps its status `refused:` on every sync; deleting it locally is undone by the next fetch. Only a
  manual push can create one (the host refuses such names), so it stays in this report.

## Deviations

1. Stale lease keeps everything: **not accepted** as implemented, see I1.
2. A tombstone in a writer clone is ignored and the ref pushed as usual: accepted. It matches R4
   ("ignored") and "acted on only in the integrator clone"; the stale tombstone left in the writer
   clone is inert.
3. Two hint assertions changed for the user-requested `--prune` fix (4ec9305): accepted. Only those
   two lines are removed from the suite, each replaced by the new text at the same strength.
4. R5 fresh clone via `file://`: accepted. A plain-path clone hardlinks the whole object store, which
   the production ssh remote never does; `file://` gives the negotiated transfer the host uses. The
   check proves the transport, not `sync_clone`'s own clone (which uses `$REMOTE`, a path in tests).

## Obligations

B0, R1-R6, R8 as recorded are settled by the evidence and the re-run; R6 checked: the READMEs are
`diff`-equal, the skill body is 499 words, `main` of ~/knowledge has no `reports/` history. R9 (host
smoke) settles the GitHub assumption. The invariant holds on every path read: no fetch outside the
integrator takes `refs/reports/*`, the writer drops a ref only after its push exits 0, and remote
deletion is limited to the integrator clone and `REPORT_RE` names.
