# Marta, reviewer 3 (Fable) — whole-rule-set review at ~/knowledge HEAD e777927
(saved by the lead from the hand-back, 2026-10-31)

Verdict: BLOCK on A and B. Everything else lesser.

## Important
A. rules/global.md §5 "Review once per phase" contradicts itself on lesser fixes: "lesser findings are fixed without a re-review" is followed by "commits or plan text added later get a review of their own delta." A lesser fix is such a commit, so one lead spawns a delta review and another does not; the first reading recreates the second round Q6(a) removed. Secondary: dropping "or reported to the user" makes every lesser nit a mandatory fix, and the implementer's fix-round bullet then demands a red test ("whatever its severity label"). Resolution: "lesser findings are fixed, or reported to the user, without a re-review; other commits or plan text added later get a review of their own delta."
B. Suites outside CI are inside the gate in global.md §4 ("the full check set, the cross-package suites and every suite outside the CI pipeline") but beside it in roles/planner.md Phase row ("The gate, every suite outside CI and every residue search are phase-level obligations") and "## Obligations" (phase-level obligations "the phase review runs them itself, except the gate"); reviewer.md first bullet "a phase-level obligation other than the gate you run yourself" → the reviewer runs e2e before acceptance, or nobody runs it. Resolution: planner.md Phase row and Obligations: "The gate, which includes every suite outside CI, and every residue search are phase-level"; reviewer.md bullet and row: "other than the gate and the suites it names".

## Lesser
C. Refactor pins have no named result run: class bullet and implementer Refactor row "run once on the base"; planner proves by "Pins green on the result"; reviewer reads "the pins' recorded base run and result run". Resolution: implementer Refactor row "…before the first change; the gate on the result is their result run."
D. Tier and lifetime defaults missing for brief and spec reviews and for brief writing (reviewer table has Brief, Spec, Small-diff objects; planner writes briefs; neither tiered nor in Lifetimes). Resolution: "brief and spec reviews and brief writing on the cheaper tier"; one Lifetimes clause for the brief.
E. global.md Decomposition "recorded in its brief or plan": a small change has neither. Resolution: "recorded where the task is stated".
F. global.md §4 "run once on the tree the phase review accepted": after a gate failure and fix, nothing says the gate runs again. Resolution: "once per accepted tree".
G. A spike fits no class: planner "the lead briefs an implementer with it as a task of its own" before any plan exists; Brief demands approval, suites and a diff review. Resolution: a spike is a task of the phase being planned, no class review.
H. Reviewer always re-runs recorded checks in two places against §4 "re-runs a check only when its recorded output does not settle the claim": Writer's-output row/bullet "re-run the check the brief names" (writer.md records its command, exit code and output); Plan row "The recorded impact-set searches against the base", always. Scope the §4 sentence or state the two exceptions in the table.
I. roles/README.md "Keep the body pure prose so it renders for every tool" vs three role files with tables (assumption inferred, render unverified). Resolution: verify the render, then "prose and plain tables".
J. Duplicated text: reviewer.md writer bullet = Writer's-output row; AGENT-MARK bullet = Phase-diff parenthetical; "mechanical commit spot-checked, hand edits read in full" ×3; implementer.md mechanical-script bullet and "no red test for a mechanical change" restate the Refactor row; global.md Lifetimes "Reviewer: given only the spec, the plan, its evidence files and the diff, or the spec and the plan alone" names two of eight review objects.
K. Pre-existing rationale in global.md (Commits, Files, Forks, Renames, Known case), belongs in decisions.md.
L. skills/propose-rule/SKILL.md step 3 lists "(planner, implementer, reviewer)"; seven roles exist. No rule names who commits an implementer's evidence file.
Spec invariant "a role that finds the class does not fit stops and says so": only the implementer has it; the planner has none for a brief that turns out to be design work.

## Candidates and Q1–Q6: all in force (1 with gap E, 3 with B, 4 with H unstated, 8 with A).
## Obligations at HEAD: O1 4389; O4 0 ×5; O8 0 ×5; O9 1 ×5, decisions.md lines 17 and 29; known-case check passed; T1–T4 match; O6 remains the host's.
