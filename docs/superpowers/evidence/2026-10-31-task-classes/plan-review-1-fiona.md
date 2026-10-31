# Fiona, reviewer 1 — plan review of docs/superpowers/specs/2026-10-31-task-classes-design.md, round 1
(saved by the lead from the reviewer's hand-back)

Verdict: BLOCK on findings 1–6.

Verified and fine: word ledger (12 old counts at dff9565 and 12 new-block counts match; simulated-global.md 4394 words, differs from rules/global.md only in the G blocks plus a trailing newline); O4 residue phrases absent; ~/knowledge/skills grep 0; cited figures for candidates 1, 2, 3, 8 and the cost paragraph hold; every decisions.md entry the spec refines exists.

## Important (blocking)

1. Lost rule, G1/G10 (global.md class bullet, Small). Old small-change bullet ran "the full suites ... in parallel with the review"; decision 2026-10-26 lists "suites" beside "the project's checks". G10 gives the small class "the project's own checks" only; the suites vanish without a stated reason. Resolve: name the changed packages' suites in the small class's gate, or state the drop in D1 with figures (R2 D, R3 U8–U11 ran them and caught nothing).

2. Contradiction, G10 vs unchanged §2 "The lead only stitches ... hands milestone suites to a runner and reads its verdict" (global.md line 100) against G10 "the agent that holds the accepted tree runs it, and a runner is spawned only for what no recorded run on that tree covers" (and D7). "The agent that holds the accepted tree" is undefined with three area implementers in their own worktrees (R4), and the lead may not run suites (2026-10-08 D9). Resolve: edit the stitches bullet in the ledger; name the runner of the gate (the implementer the lead names, otherwise a runner; I1 already says "by you when the lead says so").

3. Claims the reports do not support (candidates table and Appendix B → decisions.md):
   - Row 4 / D6: "48/380 keys, no discrepancy". R4 §2.4 gives only a lower-bound count of re-run verbs, no outcome; R4 §3 has 30 BI task-review findings over 21 tasks without saying whether any came from a re-run. Drop "without a discrepancy".
   - Row 6 / D8: R4 §2.1: 2 important AND 1 critical; §3: G8/T6's important held, was fixed, was not in the first reviewer's report; G2/T6's important acted on; G4/T4's critical refuted. The diff second review caught one real defect in 46 runs — a yield the spec cuts without naming. State the figure (1 held, new to the review, in 46 runs; 80 runs, 302 min) and keep the verdict or put it to the user.
   - Row 7 / D9: "U8–U12 reviews found nothing". R3 §3: U9's review found the verify_evidence.py path defect (became U11 T3), U11 found a mislabelled render; R3 lists U8–U11 as briefs, not small changes.
   - Body and D2: "S3.1–S3.7 found 1–7 blocking items each"; S3.2's plan review is BI0 (R4 table).
   - Row 3, Q2 and D5 name the decision 2026-10-21-suites-outside-ci-run-by-the-change; it is 2026-10-24-... (decisions.md line 154).

4. G12 global.md §5 "A round with no Critical or Important finding closes the review", extended to "every class and object" (D10) on R1 and R3 alone. R4 records BI findings in rounds after an accepted round: G6/T3 r1 acc BI0 m3 → r2 chg BI1 m6; G9 plan r2 acc → r3 chg BI1; G10 plan r2, r3 acc → r4 chg BI3. The reports do not say whether the object changed between rounds. Resolve: scope G12 (closing applies to the object as reviewed; new commits or a revised plan get a delta review) and say so in D10, or make the extension to phases and plans a closed question.

5. Class boundary, G1 Brief: "a change of several commits or of behaviour" overlaps Small, which admits "a local fix" with a regression test "where behaviour changes"; a one-commit bug fix fits both. Resolve: Brief = what is neither small nor phase (several commits, or a stored field, endpoint or server function, short of design work or a contract change).

6. R2 roles/reviewer.md "re-run only as the class table says" contradicts the unchanged bullet "For a writer's output, re-run the check the brief names" (line 77); the R1 table has no row for a writer's output or a spec (R1 #99 spec, R4 G10 spec had spec reviews). Resolve: add the rows, or word R2 "re-run a *recorded* check only as the class table says".

## Lesser (not blocking)

- G1 drops "the implementer changes every occurrence" for a mechanical config change; not in the Dropped list; the one-diff obligation does not prove completeness.
- "One gate per batch" (refactor flag, G1/P1/I1): "batch" undefined in global.md; say per phase or brief.
- G4 ceiling: "the close of the task" undefined for the phase planner ("alive until the phase closes") and the writer ("until its output is accepted"); say what counts as a task for them.
- §5 "A single task is reviewed on its own only when it is design work or changes a contract" now sits beside a class bullet giving every small change and brief its own review; add "of a phase".
- R1 row "Plan or brief": "the checklist below" is the phase-plan checklist; nothing says what a brief review checks.
- Goal 3 has no obligation: add the block keys to the candidates table (1→G2, 2→G4, 3→G10/P1/I1, 4→G7/R1–R2, 5→G10, 6→G3, 7→G1/R1, 8→G12) so O7 reads against it. D3 names nothing it revises (2026-10-08 agent-roles-tiers), though goal 5 requires it.
- Row 5 "the runner's catches (B2, F4L) were checks nobody had run" is inferred from R1 §2's command lists (B2: implementer ran size/knip/jscpd/tsc, never `npm run check`); R1 says nothing of the kind for F4L. Mark it inferred.
- Evidence directory is in dev-tools while T1–T3 run "in the integrator sandbox" and the scope says this sandbox edits nothing under ~/knowledge; say which sandbox writes the evidence files.

Closed questions Q1–Q4: each is the user's, options cover the cases; add the candidate-6 and candidate-8 decisions above (finding 3 second item, finding 4) unless the spec fixes them with figures.
