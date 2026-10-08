# Review of the phase 2 plan, round 1

Date: 2026-10-08. Verdict: **blocked** (2 important). The plan reaches the goal and honours the
phase 3-4 contracts. P2 holds (verified: ~/knowledge on main, role `integrator`, pre-commit hook
allows main). `test-knowledge.sh` render tests use a temporary `$AI_KNOWLEDGE_ROOT`; T1 should say
"the test's fixture checkout", not "the knowledge main checkout".

## Important

1. **A12/P1 have no failure branch, and the check comes after the push (T6, T7, Assumptions).**
   The host sync (T7 step 1) pushes the role files before anything has tested whether `tools:`
   limits a native subagent; the scout smoke run is step 3 of the same batched request. If A12 is
   false, a native scout gets Bash and file tools (breaks I10, can read untracked files); published
   history cannot be rewritten. Resolution: a check before T6 — a throwaway subagent with an inline
   definition (e.g. `claude -p --agents '{...}'` with `tools: WebSearch,WebFetch`) that must fail to
   call Read and Bash; if not possible, an A12 smoke run before the sync. Fallback if A12 is false:
   the scout and runner limits are prose only; the plan stops and returns a spec change (I10
   wording, A12 row) to the user; the phase does not close. P1: state that the only guard for
   second-reviewer is its description plus the lead's C1 rule, recorded as an accepted residual
   (D8 implies it), not as "mitigated".
2. **Per-change commits cannot be made from one drafted working tree (T4, T6).** T4 drafts four
   edits in one file; T6 wants one commit per change, each with a decisions.md entry; splitting
   hunks needs `git add -p` (interactive, unsupported); a rejected or edited (f) leaves a file that
   cannot be staged cleanly. Resolution: T6 applies approved global.md edits in sequence (drafts as
   patch files outside the tree, or the implementer reapplies each hunk after the previous
   commit), decisions.md entries written at commit time, one per commit; or group (c)-(f) into one
   approved commit. The plan must say which.

## Non-blocking

- T4.1 tier clause is consistent with C1/D4 (runner haiku = cheapest; scout/writer fallback
  sonnet = cheaper). It adds a third tier name ("cheapest") to global.md; keep it called out in the
  diff shown to the user.
- T7 step 3: no wrapper exists in phase 2, so say which ad-hoc report path the lead hands the
  native writer and runner smoke runs.
- The scout smoke run should explicitly ask the scout to read a local file and run a command, and
  expect both refused (the A12 evidence).
- Mark P2 verified.
