Task: 2026-11-11-sandbox-hardening

# Phase 1 plan, round 1: answers to the review and to the author

Bartek (planner 2), 2026-11-11, a fresh agent in the phase planner's slot. Answers
`plan-review.md` (Fiona, reviewer 1) and applies `author-answers.md` (Hania, the spec's
author) to `docs/superpowers/plans/2026-11-11-sandbox-hardening-p1-plan.md` and its
evidence file `2026-11-11-sandbox-hardening-p1-plan.md` in this directory. The first
versions are kept untracked for the re-review's diff. Properties and keys only; inputs
are named by their class.

Each finding's claim was checked first: F1 by scratch probes in both transports, F2 by
re-running the recorded rule (119) and a widened one (123), F3, F4 and F5 by reading the
tree, F6 by reading the named passages. All claims hold as stated.

| Item | Outcome | Where |
|---|---|---|
| F1 (Critical) fetch not confined to the sandbox's namespace | fixed | Plan: data block (the property, the mirror, full ref names), T09 (one fetch function, confinement, the author's property on the render's checkout, mechanism by path to the untracked file), new O19 with a negative case, O10 (no other ref in an origin), residue R10, B1a's "refs outside the namespace" line, H. Evidence: P-E, S24. The property holds in `knowledge/main` by O19 and R10; choice 3 kept (see "C3"). A sentence for the spec's C-GIT is proposed to the author for later phases (S-3); phase 1 does not wait for it. |
| F2 (Important) the rule misses git starts | fixed | O3 rewritten (any argument, bare or with a path, quoted or not; three exempt forms by name; six-form known case; parse coverage of every bash file under `bin/ai`; exceptions not helpers); residue R1b (text search, read by the review); impact row 1 (123 reports, 106 starts). Evidence: "Structural search" redone with known case 6/6 and the reason the first rule missed three starts, checked on a scratch file; "R1b on the base" classifies all 57 remaining lines. |
| F3 (Important) X1's marker line cannot fail | fixed | B1a runs the fetch in T09's form (the clone's real path as the URL, the root mounted read-only at its own path), so a host process can reach the fixture; a table states pass and failing result for every line. Evidence P-D: the batch run against a Docker shim passes, and fails on two known bad inputs (confinement option removed; fixture changed). O1 reads T09's form against B1a's. |
| F4 (Important) a closed report is pushed again | fixed, today's behaviour kept | Host record `refs/pushed-reports/<id>/<name>` (data block), T10, new O20 (stopped writer and stamp-1 writer across a close), states section, Left out (removal of a removed sandbox's namespace: disk only). `pushed-report=` keeps C-STATUS's shape: a report ref is never moved (PA12, read in the knowledge clone's process-report skill). |
| F5 (Important) `ai-delegate` installed on the host | fixed (folded, with the author's answer to Q3) | T01 (removed from `ai_sandbox_helpers`, create removes an earlier installed copy with one line), new O22, O3's exceptions case, impact row "Host helper list" (S23), PA9 restated, B2 step 2. |
| F6 (Important) committed text lists fixture ingredients | fixed | O2, O6, O7, O8 name inputs by class with "the list is in the test"; B1's control step moved into the fixture file (`control` mode); evidence P-A, P-D restated, P-E written at class level. |
| L1 RP0, RP1 | fixed | RP0: B1a checks the fixture copy against its SHA-256. RP1: commit ids from the lead, every changed path first, no pager, external diff or textconv; states that until phase 4 nothing binds the working tree to what was read. |
| L2 B2 step 1 shows the old copy | fixed | B2 step 1 runs the installed `ai-sandbox-migrate` first, then the installed `ai-knowledge status`; RP1 names what refreshes the helpers. |
| L3 A3 does not hold here | fixed | B1b: the migration is the expected path, with commands, prompts, the "finished" criterion and a recheck on every host (the remote asked directly for old-style branches); T08 lands, RP1 waits for the recheck; the fallback goes to the user. |
| L4 time limits, exec form, no pull | fixed | Contract block `AI_SANDBOX_GIT_TIMEOUT`; O1 (no pull, 124), O12 (no terminal, standard input closed, sandbox's user, standard error cleaned), O18 (timeout state), T03. |
| L5 O8 state | fixed | O8 runs with the container reported not running. |
| L6 role file vs C-STATUS | rejected, following the author | The author's answer to Q1 binds: C-STATUS binds the host, which neither writes nor reads the role file; noted in "Read this first", item 1, for the re-review. |
| L7 A2 fallback changes "one function" | fixed | B1a's A2 row and the questions section send it to the spec's author before T09; the plan no longer chooses it. |
| L8 ast-grep dependency; register search | fixed | Declared in "Read this first" and T11; pinning left to M4 (Left out, with reason). `PROJECT_MAP.md`'s `reads-outside:` search replaced (O16, T12, impact row S21). |
| L9 "never forced" for every push | fixed | O7 (every update of the run recorded, none forced); residue R11 (base empty, known case 3/3, evidence S25). |
| Author Q1 (status keys) | applied | Kept as plan detail; reviewer's L6 difference noted. |
| Author Q2 (no stamped ancestor) | applied | Contract line (links resolved), new O21 (the `init --integrator` case and its printed line), T02 marked design work. The review classified it as not plan detail; the plan follows the author, noted for the re-review. |
| Author Q3 (`ai-delegate`) | applied | See F5. |
| Author Q4 (committed text) | applied | See F6; the plan follows S-1 as if approved. |
| Author Q5 (`MANIFEST`) | applied | E2 added to the plan's deferred list in the author's words, kept for phase 4. |
| Author, choice C3 (host-owned repository) | applied | Kept `knowledge/main`; the author's property stated in T09 and the data block. The separate repository the review suggested is listed under Left out with the reason. |
| Author, choice C4 (lib functions) | applied | Unchanged. |
| Author S-1, S-2 | noted | S-1 is followed; S-2 concerns phases 3 and 4 and needs nothing here beyond the fold. |
| A3 (lead's brief) | fixed | See L3. |
| S-3 | to the author | C-GIT's second use bullet: proposed sentence in the plan's last section and in the planner's report to the lead. |
