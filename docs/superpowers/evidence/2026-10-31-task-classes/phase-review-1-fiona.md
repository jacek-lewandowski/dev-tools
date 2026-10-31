# Fiona, reviewer 1 — phase review of task-classes phase 1 (~/knowledge dff9565..a4942d5), round 1
(saved by the lead from the hand-back)

Verdict: BLOCK on one Important finding (O7 fails on "who runs the gate"). Defect of the contract text; every block landed byte for byte.

## Important (blocking): who runs the phase gate
- roles/planner.md, P1 Phase row (new): "The gate, every suite outside CI and every residue search are phase-level obligations; no task cites them."
- roles/planner.md, "## Obligations" (unchanged): "Residue obligations and any obligation that only the finished phase can satisfy are phase-level: the plan marks them so, no task cites them, and the phase review runs them itself."
- roles/reviewer.md, R2 (new): "a phase-level obligation you run yourself and record in your report"; R1 Phase-diff row: "You run: The phase-level obligations (residue searches, the AGENT-MARK search) yourself".
- rules/global.md, G10 (new): the gate is "run once on the tree the phase review accepted, by the implementer the lead names or else by a runner"; G13: the lead "names who runs the gate".
Failure: a planner marks the gate phase-level; the reviewer, following planner.md and R2, runs it itself before accepting, which G10 forbids and which the same R1 row forbids ("no ... renders of your own").
Resolution: spec amendment (user approval): a block for the planner "Obligations" sentence ("... the phase review runs them itself, except the gate, which runs after acceptance as global §4 says") and the same qualifier in R2 ("a phase-level obligation other than the gate"); then the implementer applies it.

## Lesser (spec text, fold into the amendment)
1. roles/reviewer.md R1 Small-diff row, Round: "One; lesser findings never reopen it." vs global.md G12: a blocking finding on a small diff has no stated path in the table. Resolve: "One; a blocking finding gets a delta re-review".
2. roles/implementer.md I1 Small row ("Red test: where behaviour changes"; "Review: one diff review") does not carve out the mechanical config change the class bullet makes "a small change with no test and no review".
3. AGENT-MARK: 4 hits, all rule text defining the marker; "AGENT-MARK task-classes" → 0. No marker remains.

## Obligations re-run at a4942d5
O1 4389 holds; O2 holds; contract check (own script, known case at dff9565) every new text once, every old text 0, Appendix B verbatim once under "## Entries", all 11 cited decisions exist; O4 seven phrases → 0; O6 confirmed not runnable here (ai-knowledge status "not configured"), request stated in T3.md; O7 run by the reviewer: agrees on gate contents, per-task package suite, re-run rule, rounds cap, second reviewer, refactor flag, and every accepted candidate's sentence stands in its blocks; fails on who-runs-the-gate.

## Coverage
Goal items 1–5 ↔ O2+O4, O3+O4, O7, O1, O5. No uncovered goal item. Commits read in full; trailers signed Zuzia; nothing outside the five files changed.
