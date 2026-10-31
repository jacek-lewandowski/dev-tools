# Task classes: one class per task, parameters per class

Date: 2026-10-31
Status: approved 2026-10-31 (plan review by Fiona, two rounds; every closed question answered as recommended)
Inputs: `.tmp/process-report-synthesis.md` and the four reports behind it
(`process-report1.md` amen-app, `process-repor2t.md` omega-psir,
`process-report3.md` analogiesio-assets, `process-report4.md` nieznajomi,
whose token figures are context sizes); `~/knowledge` at `dff9565`.
Scope: `rules/global.md`, `roles/planner.md`, `roles/implementer.md`,
`roles/reviewer.md`, `decisions.md`. No new role file. The edits land through
the integrator sandbox; this sandbox edits nothing under `~/knowledge`.

## Goal

Observable when done:

- Every task carries one of three classes, small, brief or phase, plus an
  optional refactor flag, recorded where the task is stated; `global.md`
  names the classes in one bullet in place of today's four scattered tiers
  (mechanical config change, small change, brief-only work, spec and phase).
- The planner, implementer and reviewer roles each carry one table of what
  applies to which class; their inline "for a task brief with no phase plan,
  or a small change without a brief" clauses are gone.
- Each of the eight candidate changes is accepted, modified or rejected on a
  cited figure, and the accepted ones are operative sentences in the blocks
  the candidates table names.
- `global.md` has not grown: `wc -w` at most 4400, its count at `dff9565`.
- `decisions.md` has one entry per logical change, naming what it revises.

## Why three classes and a flag

The reports sort units by kind, but cost followed the process a unit
entered, not its kind: a bug fix given a planner cost 25 M tokens (#112)
against 0.5–6 M for brief-only fixes (#106, #110, #125, U8, U9, D, E); feature
briefs 4–28 M; phases 26–161 M (synthesis, cost table). Text tasks ran through
the writer at the cost of a small change or a brief (U2–U12), so text needs
no class of its own. The tiers already in `global.md` are kept and folded to three: the
mechanical config change becomes the small class's no-review case, since it
sits in the same bullet and differs only in having no test and no review.
Refactor is a flag because its batches ran as phases (#118 B1–B8b, S3.0–S3.7)
and differ in the proof: nine plan and nine diff reviews of B2–B8b found no
blocking defect, the one code defect came from the gate (B2), and pins were
run by implementer and reviewer alike (#125, B6, B8a, B8b). Plan reviews of
refactor batches stay: S3.1 and S3.3–S3.7 found 1–7 blocking items each, S3.2
none (report 4).

## The eight candidates

| # | Candidate | Verdict | Deciding evidence | Blocks |
|---|---|---|---|---|
| 1 | Tier is a rule; Opus only on the user's word; delete amen-app's memory | Accept the sentence; the deletion is the user's (Q3) | R1 §1: five top steps all Opus, #105 and #116 at 148 M under `agent-per-issue.md`; R2 §5.1: the lead chose Opus for H, I, K3 | G2 |
| 2 | Context ceiling for continued agents | Accept; value to the user (Q1); retire at a stop | R4: implementers 535k–768k; R3: writer 475k, 400k per call; R1: #116 round 2 124 M. One phase's implementer ends at 250k–331k (R2 appendix: Wojtek H, Zuzia I) | G4 |
| 3 | Targeted checks per task, gate once, no probe repeats | Modify: keep the per-task package suite; gate, suites outside CI, probes and pins go to phase level (Q2) | Waste: R1 §1 B4 19 e2e runs, 51 M; R4 §2 suite in 52/68 task files plus gate, probes in 56/68. Kept: R2 §5.3 G row 6 caught four specs the brief missed; decision 2026-10-21-implementer-runs-package-suite | G10, P1, I1 |
| 4 | Reviewer re-runs only when a result does not settle the claim | Accept; the late-regression check on old code stays | R3 §2: six rounds, one stale count (6026/6004); R1 §3: re-runs and mutants caught nothing; R4 §2.4: at least 48/380 keys re-run, no finding attributed to a re-run; defects came from reading (R2 B, I; R3 U1a) | G7, R1, R2 |
| 5 | Runner only when the gate differs from what was run | Accept: the gate runs once on the accepted tree, by the implementer the lead names or a runner (Q4) | R2 §4 rows 8–12: same suite twice, nothing new, row 12 repeats row 11; R1 §2: `test:admin` then `check`; the runner's catches were checks nobody had run (B2 shown by R1 §2's command lists; F4L inferred) | G10, G13, I1 |
| 6 | Second reviewer for plans and specs only | Accept as drafted, to the user (Q5) | R4 §2.1 and §3: 46 diff runs → 30 none, 20 minor, 2 important, 1 critical; one important held and was new (G8/T6), one acted on (G2/T6), the critical refuted (G4/T4): one defect in 46 runs, 80 runs, 302 min; 21 plan runs → 15 important, 4 new; R1: 10 runs, 0 findings | G3 |
| 7 | One branch review for a series of small tasks | Modify: small changes only; a brief keeps its review | R2 §5.3: F found 10 findings B's three rounds and C's review missed; R3: U8, U10, U12 reviews found nothing, U9 and U11 only an evidence-tooling defect and a mislabelled render. Feature-brief reviews found real defects (#102, R2 B) | G1, R1 |
| 8 | No second round for lesser-only findings | Accept for every class and object, scoped to the object as reviewed; the extension to phases and plans to the user (Q6) | R1 §3: F5 diff 2, #108 plan 2 found a lesser or a note; R3: U10, U12 found nothing. R4: blocking items after an accepted round (G6/T3, G9 plan, G10 plan), object change between rounds not recorded | G12, R1 |

Not adopted, not supported: dropping plan or brief reviews (blocking items in
11/11 nieznajomi plan reviews, 4 material in H and I, one important in #76)
and per-task reviews of contract tasks (30 blocking over 21 tasks, R4 §3).

## Invariants

- The lead names the class; a role that finds the class does not fit stops
  and says so, it does not reclassify.
- `global.md` carries operative sentences; rationale lives in `decisions.md`.
- A check runs once per tree and is read thereafter; a second run needs a
  reason the first result does not give.
- The class definitions, the gate rule and the round limit stay in
  `global.md`, because the lead runs them and has no role file.

## Non-goals

- New role files or class variants of a role.
- Who writes a brief and whether it is reviewed (kept, see above).
- `roles/runner.md`, `second-reviewer.md`, `scout.md`, `writer.md`: untouched;
  the second reviewer keeps the ability to read a diff when the user asks
  (Q5). The lifetime ceiling applies to every role at a stop, so the
  planner's and the writer's units need no definition of their own.
- The lead's own tokens and the waiting time on the user: reported, not a
  rule matter.
- Project memories: the spec fixes the rule they may not contradict;
  deleting amen-app's memory is the user's action (Q3).
- An impact set for briefs: none today, and the full suite caught the one
  missed dependant (G); unchanged.

## Assumptions

- Verified: every old text in Appendix A is copied from the files at
  `dff9565`; `wc -w rules/global.md` is 4400 there and 4389 with every
  block applied (`.tmp/task-classes/simulated-global.md`).
- Verified: the harness reports a continued agent's context size at each
  stop (R1 and R4 method sections).
- Inferred: a markdown table is "pure prose" for `roles/README.md`; every
  render target reads markdown or a string.
- Inferred: `grep -rn -i "brief\|small change\|runner\|second reviewer"
  ~/knowledge/skills` → 0 hits; the other role files use "brief" for their
  own prompt only, so no sentence outside the four files breaks.
- Guessed, hence Q1: the ceiling value; no report measured the break-even
  between a fresh agent's load (reviewer contexts 113k–287k as proxy) and a
  continued one's per-call cost.

## Phase 1, the only phase: the text lands on main

Goal: `~/knowledge` main carries the blocks of Appendix A verbatim and the
entries of Appendix B at the top of `decisions.md`; the rendered copies
follow. Contract: Appendix A is the contract; it lands as reviewed.
Evidence directory: `docs/superpowers/evidence/2026-10-31-task-classes/` in
dev-tools, written by the implementer and committed by the lead; the
integrator sandbox is this dev-tools sandbox (memory
shared-knowledge-2026-09-14: "the dev-tools sandbox as the integrator"), so
no path crosses a sandbox.

Tasks (one implementer in this sandbox, committing on `~/knowledge` main as
the integrator does):

- T1 `rules/global.md`: apply G1–G13 in order, with N in G4 at 300k (Q1); discharges O1, O2, O4.
- T2 `roles/planner.md`, `roles/implementer.md`, `roles/reviewer.md`: apply
  P1, I1–I2, R1–R2; discharges O3, O4.
- T3 `decisions.md`: prepend D1–D10 under "## Entries"; run `ai-knowledge
  render`; discharges O5, O6. One commit per file.

Obligations:

- O1 (executable): `wc -w rules/global.md` → at most 4400.
- O2 (read): each G block's new text is present once (`grep -c -F` on its
  first line → 1).
- O3 (read): each role file holds its table once and its replaced bullets in
  the new form.
- O4 (executable, residue): `grep -n -F "Small changes skip the brief"
  rules/global.md` → 0; `grep -n -F "Suites run on the accepted tree"
  rules/global.md` → 0; `grep -rn -F "For a task brief with no phase plan"
  roles/` → 0; `grep -rn -F "re-running and re-reading" rules/ roles/` → 0;
  `grep -rn -F "Use it only for design-work tasks" rules/` → 0;
  `grep -n -F "hands milestone suites to a runner" rules/global.md` → 0.
- O5 (read): the ten entries of Appendix B sit directly under "## Entries".
- O6 (executable): `ai-knowledge render` exits 0; `diff
  ~/knowledge/rules/global.md ~/.claude/CLAUDE.md` is empty but for the
  appended sandbox block.
- O7 (read, phase-level): the class bullet and the three tables agree on
  every parameter (gate, re-runs, rounds, second reviewer), and each accepted
  candidate's sentence stands in the blocks its table row names; the phase
  review reads them side by side.

Impact set: static references: none, rule text. Names in strings: the removed
sentences, searched in O4 (skills → 0 before the change). Outside the
repository: the rendered copies (`ai-knowledge render`) and project memories
quoting the old tiers (amen-app `agent-per-issue.md`, `lean-issue-process.md`;
nieznajomi "light mode per memory", R4 row #84), cited from R1 and R4, not
enumerable from here. Duplicated logic:
`docs/superpowers/specs/2026-10-08-agent-roles-design.md` line 915 restates
the old second-reviewer scope as history; left as is.

Deferred list: empty.

## Closed questions for the user

- Q1 Ceiling N: (a) 200k, (b) 300k, (c) 400k, (d) none. Recommend (b): one
  phase's implementer ends at 250k–331k (R2), so (a) retires it after its
  first task; (c) still admits R3's 400k-per-call writer. Decided 2026-10-31: (b).
- Q2 Suites outside CI in a phase: (a) at the gate only (G10), (b) also after
  each task that touches what they read (decision
  2026-10-24-suites-outside-ci-run-by-the-change). Recommend (a): the incident
  behind the decision was per phase; B4's 19 e2e runs are the cost of (b).
  Decided 2026-10-31: (a).
- Q3 amen-app `agent-per-issue.md` and `lean-issue-process.md`: (a) delete,
  (b) keep as that project's routing table. Recommend (a): they produced the
  two most expensive steps of the window (124 M, 73 M) and contradict the
  tier and the implementer-per-area rules. Decided 2026-10-31: (a).
- Q4 Phase gate runner: (a) the implementer the lead names runs it, a runner
  only for what no recorded run covers (G10, G13), (b) always a runner
  (2026-10-08 D9).
  Recommend (a): R2 rows 8–12 and R1 §2 show the runner repeating the run.
  Decided 2026-10-31: (a).
- Q5 Second reviewer on task diffs: (a) none, specs and plans only (G3), (b)
  keep it for contract-task diffs. Recommend (a): one defect held and new in
  46 diff runs (G8/T6), against 80 runs and 302 min of wall-clock; the plan
  runs carry the yield. Decided 2026-10-31: (a).
- Q6 A lesser-only round closes the review: (a) every class and object, scoped
  to the object as reviewed (G12), (b) small and brief only; phase diffs and
  plans keep a re-review of lesser fixes. Recommend (a): the rounds R1 and R3
  record found a lesser or a note; R4's blocking items after an accepted round
  are not shown to be re-reviews of lesser fixes, and the scoping sends every
  changed object back for its delta. Decided 2026-10-31: (a).

## Appendix A: contract blocks

Each block lands verbatim. Old texts are copied from `~/knowledge` at `dff9565`; the markdown line wrapping inside a block is part of the text.

### Word ledger for `rules/global.md`

| Block | Old words | New words |
|---|---|---|
| G1 Spec first + Small changes → class bullet + Spec first | 676 | 624 |
| G2 Decomposition | 72 | 95 |
| G3 Second reviewer | 52 | 64 |
| G4 Lifetimes intro | 56 | 71 |
| G5 Implementer sub-bullet | 93 | 71 |
| G6 Reviewer sub-bullet | 54 | 50 |
| G7 Obligations | 132 | 135 |
| G8 Cache | 72 | 53 |
| G9 Reviewed snippets | 95 | 78 |
| G10 Targeted tests | 98 | 179 |
| G11 Suites on the accepted tree | 71 | 0 |
| G12 §5 | 108 | 149 |
| G13 The lead only stitches | 78 | 77 |
| Whole file | 4400 | 4389 |

Counts by `wc -w` on the old line ranges at `dff9565` and on the new blocks; the whole-file figure is from the simulated file.

### G1 `rules/global.md`

Anchor: §2, the two consecutive bullets "**Spec first, one phase of plan at a time**" and "**Small changes skip the brief.**", replaced together by two bullets in this order: the class bullet, then the shortened spec-first bullet.

Dropped from the old texts: the brief-task mechanics of the spec-first bullet (now in the class bullet and the role tables); the drafting detail planner.md "The phase plan" already carries; "The planner and implementer roles carry the details" (the roles are the details); the rationale clauses "because the planner cannot declare what it did not notice" and "a list that grows faster than phases close it never converges" (in decisions 2026-10-25 every-plan-is-reviewed and 2026-09-16-deferred-list-entry-threshold); "a known-case demonstration is owed only by a check the implementer wrote itself" (the §4 known-case bullet already says the project's checks and a plain diff need none); "the spec changes only where it states that value literally" (follows from the spec rule); "One diff review re-reads the diff ... unless the output does not settle the claim" (now G7 and the reviewer table); "the full suites run, in parallel with the review where a fix round is unlikely" (now G10: the implementer runs the small class's gate, the project's checks and the touched packages' unit suites, before the review; the whole-repository suites are dropped for small changes, see D1); "thoroughness beyond that is stated with its reason" (the reason belongs in the brief, which the brief review reads). Kept from the old text on review: "the implementer changes every occurrence" for a mechanical config change.

Old:

```markdown
- **Spec first, one phase of plan at a time** for work that needs more than one
  phase or rests on a guessed assumption. Smaller work gets a task brief of a
  few lines, goal, tests, acceptance criterion and the path of its evidence
  file, which the implementer takes directly and closes in one pass: it runs
  the full suites itself at the end of the task and records the result in its
  evidence file, no runner is spawned, and one review follows. Blocking
  findings go back to the implementer and the reviewer re-checks only that
  delta; lesser findings are fixed in the same round or reported to the user.
  A brief-only task that turns out to be design work or to change a contract
  is no longer small: it gets a spec and a phase instead of further rounds;
  a change that fits the next bullet needs no brief at all. A spec (e.g.
  `design.md`)
  fixes the goals, invariants, non-goals and phases once, with the contracts
  between phases; it changes only with the user's approval, and before any plan
  does. Only the next phase is planned in detail and against the real tree; its
  draft may be written while the previous phase is still implemented, with every
  assumption marked inferred, and is verified against the tree once that phase
  closes, before anyone else sees it. A phase is also the milestone: the unit of
  the plan, the review, the full suites and the runner's lifetime; the two words
  name one thing. The user approves every phase plan before implementation,
  reading its obligations and its impact set as the statement of what the phase
  delivers and touches; a reviewer agent checks every plan first, on the cheaper
  tier, against the checklist the reviewer role states, because the planner
  cannot declare what it did not notice. Work noticed during implementation goes
  to the spec's deferred list, never into the current task, and only when it has
  a failure scenario a user or an operator can actually reach, or breaks a
  stated invariant. Cosmetics, log noise, risks the current data rules out and
  "worth doing one day" stay in the report that noticed them. Do not ask agents,
  as a routine part of a brief or a review, to list what they noticed outside
  the task: a list that grows faster than phases close it never converges. The
  planner and implementer roles carry the details.
- **Small changes skip the brief.** A change of one commit that adds no stored
  field, endpoint or server function and touches no contract, payment or
  security (a wording, an appearance, an asset, a local fix) needs no brief
  file and no approval before it starts: the lead gives the implementer the
  instruction and the path of the evidence file in its message; the
  implementer writes the regression test first where behaviour changes, makes
  the change and commits. Its obligations are the project's own checks and one
  diff showing that only the intended parts changed, with one look at the
  rendered or running result where the change is visible; a known-case
  demonstration is owed only by a check the implementer wrote itself. One diff
  review re-reads the diff and that result and re-runs nothing recorded with
  its output unless the output does not settle the claim; the full suites run,
  in parallel with the review where a fix round is unlikely, and the user
  approves at merge. A brief's obligations are sized the same way, to what the
  change can break; thoroughness beyond that is stated with its reason. A
  mechanical value change in configuration (a port, a name, a default) that
  touches no logic, contract or security needs neither brief nor review: the
  implementer changes every occurrence, adds no test and runs the check that
  exercises the new value as its only obligation, the spec changes only where
  it states that value literally, and the user approves at merge as above. A
  change that outgrows its tier returns to the brief or the phase plan, with
  the user's approval before implementation continues.
```

New:

```markdown
- **Every task has a class.** The lead decides the class once, from the shape
  of the change, and records it where the task is stated: the lead's message,
  the brief or the plan. *Small*: one commit that adds no stored field,
  endpoint or server function and touches no contract, payment or security
  (a wording, an appearance, an asset, a local fix). No brief and no approval
  before it starts: the lead's message carries the instruction and the path
  of the evidence file; the implementer writes the regression test first
  where behaviour changes, makes the change and commits. Its obligations are
  the project's own checks, the unit-test suite of every package it touched
  and one diff showing that only the intended parts changed, with one look
  at the rendered or running result where the change is visible. One diff
  review follows, or one review of the whole branch when several small
  changes land on one branch before a merge, and the user approves at merge.
  A mechanical value change in configuration (a port, a name, a default) that
  touches no logic, contract or security is a small change with no test and
  no review; the implementer changes every occurrence, and the check that
  exercises the new value is its only obligation. *Brief*: what is neither
  small nor a phase: several commits, or a stored field, endpoint or server
  function, short of design work or a contract change. It gets a brief of a
  few lines, goal, tests, acceptance criterion and the path of its evidence
  file, approved by the user after its review; the implementer closes it in
  one pass, running the full suites itself at the end and after any fix, and
  one diff review follows. A brief's obligations are sized to what the change
  can break. *Phase*: design work, a contract change, or work that needs more
  than one phase or rests on a guessed assumption; the next bullet.
  *Refactor* is a flag on a brief or a phase that changes the proof, not the
  actors: pins run once on the base tree, the mechanical change lands in its
  own commit with its script, one gate runs per brief or phase, and the
  review spot-checks that commit and reads the hand edits in full. A change
  that outgrows its class moves to the next one, with the user's approval
  before implementation continues.
- **Spec first, one phase of plan at a time** for the phase class. A spec (e.g.
  `design.md`) fixes the goals, invariants, non-goals and phases once, with the
  contracts between phases; it changes only with the user's approval, and
  before any plan does. Only the next phase is planned in detail and against
  the real tree; a draft written during the previous phase is verified against
  the tree when that phase closes, before anyone else sees it. A phase is also
  the milestone: the unit of the plan, the review, the full suites and the
  runner's lifetime; the two words name one thing. The user approves every
  phase plan before implementation, reading its obligations and its impact set
  as the statement of what the phase delivers and touches; a reviewer agent
  checks every plan first, on the cheaper tier, against the checklist the
  reviewer role states. Work noticed during implementation goes to the spec's
  deferred list, never into the current task, and only when it has a failure
  scenario a user or an operator can actually reach, or breaks a stated
  invariant. Cosmetics, log noise, risks the current data rules out and "worth
  doing one day" stay in the report that noticed them. Do not ask agents, as a
  routine part of a brief or a review, to list what they noticed outside the
  task; such a list never converges.
```

### G2 `rules/global.md`

Anchor: §2, the bullet "**Decomposition.**", last sentence extended.

Old:

```markdown
- **Decomposition.** Three or more independent modules may go to subagents; a
  single file or component stays with one agent to avoid write conflicts.
  Choose the model per role: implementers, phase planners, plan reviews,
  scouts and writers on the cheaper tier, command runners on the cheapest
  tier, spec writing and adversarial diff reviews on the stronger one. These
  tiers are the defaults; an environment's routing table, where it has one,
  overrides them.
```

New:

```markdown
- **Decomposition.** Three or more independent modules may go to subagents; a
  single file or component stays with one agent to avoid write conflicts.
  Choose the model per role: implementers, phase planners, plan reviews,
  scouts and writers on the cheaper tier, command runners on the cheapest
  tier, spec writing and adversarial diff reviews on the stronger one. These
  tiers are the defaults; an environment's routing table, where it has one,
  overrides them, and nothing else does: a stronger model for one agent needs
  the user's word for that task, recorded in its brief or plan.
```

### G3 `rules/global.md`

Anchor: §2, the bullet "**A second reviewer is optional.**", second sentence replaced (Q5).

Old:

```markdown
- **A second reviewer is optional.** An environment may offer a reviewer from
  another vendor. Use it only for design-work tasks and contract changes, in
  parallel with the reviewer, on the same plan and diff. When none is
  available the review is skipped, never given to an agent of the same vendor.
```

New:

```markdown
- **A second reviewer is optional.** An environment may offer a reviewer from
  another vendor. Use it only on the spec or the plan of design work or of a
  contract change, in parallel with the reviewer; a diff goes to it only on
  the user's word. When none is available the review is skipped, never given
  to an agent of the same vendor.
```

### G4 `rules/global.md`

Anchor: §2, the bullet "**Agent lifetimes follow the unit of work they own.**", its introduction before the sub-bullets. N is 300k (Q1). The ceiling applies at a stop (a hand-back), which every role has, so it needs no notion of "task" for planners or writers.

Old:

```markdown
- **Agent lifetimes follow the unit of work they own.** At most three live
  agents per role. Before spawning, continue a live agent of that role whose
  unit of work is still open; spawn anew when it is closed or when the agent's
  reports show it has lost the thread, and retire the one it replaces.
```

New:

```markdown
- **Agent lifetimes follow the unit of work they own.** At most three live
  agents per role. Before spawning, continue a live agent of that role whose
  unit of work is still open; spawn anew when it is closed, when the agent's
  reports show it has lost the thread, or when its context, as the harness
  reports it at each stop, has passed 300k tokens, and retire the one it
  replaces.
```

### G5 `rules/global.md`

Anchor: §2, lifetimes, the sub-bullet "Implementer:"; "or when its reports show it has lost the thread" moved to G4; the rationale "so later tasks and fixes land with the code still in context" is in decisions 2026-10-25 obligations-evidence-and-fewer-phases.

Old:

```markdown
  - Implementer: one per area of the tree within a phase, as the plan names the
    areas, cheaper tier, given the plan and the task brief. Continued from task
    to task of that area and through the fix round of the phase review, so later
    tasks and fixes land with the code still in context. Spawned fresh when a
    task opens a different area or when its reports show it has lost the thread.
    Findings of a phase review go to the live implementer that holds the code,
    otherwise to a fresh one.
```

New:

```markdown
  - Implementer: one per area of the tree within a phase, as the plan names the
    areas, cheaper tier, given the plan and the task brief. Continued from task
    to task of that area and through the fix round of the phase review.
    Spawned fresh when a task opens a different area. Findings of a phase
    review go to the live implementer that holds the code, otherwise to a
    fresh one.
```

### G6 `rules/global.md`

Anchor: §2, lifetimes, the sub-bullet "Reviewer:"; "Never forked from a planner or an implementer" is already in the Forks bullet.

Old:

```markdown
  - Reviewer: one per review, fresh, given only the spec, the plan, its
    evidence files and the diff, or the spec and the plan alone for a plan
    review. Never forked from a planner or an
    implementer, never shown their reasoning. A second round continues the
    same reviewer; it is not a new one.
```

New:

```markdown
  - Reviewer: one per review, fresh, given only the spec, the plan, its
    evidence files and the diff, or the spec and the plan alone for a plan
    review, never shown a planner's or an implementer's reasoning. A second
    round continues the same reviewer; it is not a new one.
```

### G7 `rules/global.md`

Anchor: §4, the bullet "**Obligations are the proof of a phase.**", the reviewer sentence replaced; "The planner, implementer and reviewer roles carry the details" dropped (the roles are the details).

Old:

```markdown
- **Obligations are the proof of a phase.** A phase plan carries a keyed list of
  obligations, each a claim about the finished phase with the check that settles
  it: a command with its expected result, or a file or symbol to read with the
  property to confirm. Tasks cite the obligations they discharge instead of
  carrying tests and acceptance criteria of their own. The implementer records
  each discharged obligation in its task's evidence file, in the directory the
  plan names: key, the command or the place read, the result and, once it
  exists, the commit. The reviewer verifies from those files, re-running and
  re-reading, instead of rediscovering the tree, and judges whether the evidence
  proves the claim, not whether it is present. The planner, implementer and
  reviewer roles carry the details.
```

New:

```markdown
- **Obligations are the proof of a phase.** A phase plan carries a keyed list of
  obligations, each a claim about the finished phase with the check that settles
  it: a command with its expected result, or a file or symbol to read with the
  property to confirm. Tasks cite the obligations they discharge instead of
  carrying tests and acceptance criteria of their own. The implementer records
  each discharged obligation in its task's evidence file, in the directory the
  plan names: key, the command or the place read, the result and, once it
  exists, the commit. The reviewer verifies from those files instead of
  rediscovering the tree: it reads, re-runs a check only when its recorded
  output does not settle the claim, and judges whether the evidence proves the
  claim, not whether it is present.
```

### G8 `rules/global.md`

Anchor: §2, the bullet "**Cache pays off within a loop, not across tasks.**", two rationale clauses dropped (kept in decisions 2026-09-19).

Old:

```markdown
- **Cache pays off within a loop, not across tasks.** Set the harness's
  subagent prompt-cache lifetime as long as it allows; assume an hour. Inside a
  review-and-fix loop the pauses are minutes long and the cache is the saving,
  so keep those agents continued rather than replaced. Between tasks and phases
  the pauses usually exceed the lifetime and the cache is gone regardless;
  decide there on context and consistency, not on cache.
```

New:

```markdown
- **Cache pays off within a loop, not across tasks.** Set the harness's
  subagent prompt-cache lifetime as long as it allows; assume an hour. Inside a
  review-and-fix loop keep agents continued rather than replaced. Between tasks
  and phases the pauses usually exceed the lifetime; decide there on context
  and consistency, not on cache.
```

### G9 `rules/global.md`

Anchor: §3, the bullet "**Reviewed snippets are contracts, not implementations.**", last sentence dropped; planner.md "The phase plan" states it ("The plan never contains implementation snippets ... extraction scripts").

Old:

```markdown
- **Reviewed snippets are contracts, not implementations.** A code block in an
  approved plan or spec is a contract other work depends on: an exported type, a
  signature, an interface, a data shape. It lands in its destination exactly as
  reviewed, copied from the plan and never regenerated, so the implementation
  can be diffed against it. Plans carry no implementation code; the implementer
  writes it from the task description and the contract, and code review checks
  the result. Extraction scripts, codemods and markers are the implementer's
  tools, chosen per task, never prescribed by the plan.
```

New:

```markdown
- **Reviewed snippets are contracts, not implementations.** A code block in an
  approved plan or spec is a contract other work depends on: an exported type, a
  signature, an interface, a data shape. It lands in its destination exactly as
  reviewed, copied from the plan and never regenerated, so the implementation
  can be diffed against it. Plans carry no implementation code; the implementer
  writes it from the task description and the contract, and code review checks
  the result.
```

### G10 `rules/global.md`

Anchor: §4, the bullet "**Targeted tests during development.**", replaced whole; it absorbs G11. The phase gate is run by the implementer the lead names (I1: "by you when the lead names you") or else by a runner (Q4).

Dropped: "A suite the environment cannot run joins the milestone's request to the user, or the task's report for brief-only work" (kept in implementer.md, I2, and in §4 "When the environment cannot run it"); "The review reads the recorded totals" (now G7).

Old:

```markdown
- **Targeted tests during development.** Full suites and linters run once at
  the milestone and before any claim of "done". Two suites run earlier, by the
  task that touches them, as its last step: the full unit-test suite of every
  package the task changed, and any suite outside the CI pipeline that
  exercises or reads what the change alters. A suite the environment cannot
  run joins the milestone's request to the user, or the task's report for
  brief-only work. The review reads the recorded totals. "Done" and "passing"
  are stated only with the actual command output at hand.
```

New:

```markdown
- **Targeted tests during development; the gate once.** Each class names its
  gate: the project's own checks and the touched packages' unit suites for a
  small change, the full suites for a brief, run by the implementer after its
  last edit and after any fix; for a phase, the full check set, the
  cross-package suites and every suite outside the CI pipeline, run once on
  the tree the phase review accepted, by the implementer the lead names or
  else by a runner. A phase task runs, as its last step, its targeted tests
  and the full unit-test suite of every package it changed; a plan never lists
  the gate or a suite outside CI as a per-task obligation, and a task does not
  repeat a probe, pin or search the plan's evidence already records unless its
  change alters the answer. The gate is one command set in which each suite
  runs once; a runner is spawned only for what no recorded run on that tree
  covers. "Done" and "passing" are stated only with the actual command output
  at hand.
```

### G11 `rules/global.md`

Anchor: §4, the bullet "**Suites run on the accepted tree.**", removed; its content is in G10 ("run once on the tree the phase review accepted"; "after any fix") and in the class bullet.

Old:

```markdown
- **Suites run on the accepted tree.** For design work and contract changes
  the milestone suites start after the diff review has accepted the change, so
  no fix round alters the tree under a running suite. Starting them in parallel
  with the review is for small changes where a fix round is unlikely; when a
  fix lands anyway, the suites run again on the fixed tree before any claim of
  "done".
```

New:

```markdown
(removed)
```

### G12 `rules/global.md`

Anchor: §5, both bullets, replaced; the second is unchanged and quoted for position. The closing of a round is scoped to the object as reviewed (Q6).

Dropped rationale "a review per task multiplies context loads without finding more" (to decisions, D10).

Old:

```markdown
- **Review once per phase**, on the whole diff of the phase, against its
  obligations and evidence files, ending with a check that the obligations
  cover the phase goal. A single task is
  reviewed on its own only when it is design work or changes a contract; a
  review per task multiplies context loads without finding more.
- Maximum 2 review→fix rounds. A third finding with the same root cause means
  redesign, not another hotfix. What a review report contains and when it
  blocks is defined in the reviewer role. A second reviewer's findings belong
  to the same round as the reviewer's, so the limit is counted once.
```

New:

```markdown
- **Review once per phase**, on the whole diff of the phase, against its
  obligations and evidence files, ending with a check that the obligations
  cover the phase goal. A task of a phase is reviewed on its own only when it
  is design work or changes a contract. A round with no Critical or Important
  finding closes the review of the object as reviewed: lesser findings are
  fixed without a re-review; blocking ones return to the implementer, and the
  re-review reads only that delta; commits or plan text added later get a
  review of their own delta.
- Maximum 2 review→fix rounds. A third finding with the same root cause means
  redesign, not another hotfix. What a review report contains and when it
  blocks is defined in the reviewer role. A second reviewer's findings belong
  to the same round as the reviewer's, so the limit is counted once.
```

### G13 `rules/global.md`

Anchor: §2, the bullet "**The lead only stitches.**", the gate clause replaced: the lead names who runs the gate (G10) instead of always handing the suites to a runner.

Old:

```markdown
- **The lead only stitches.** The lead session does no design, planning,
  implementation or review itself. It spawns agents, hands them file paths,
  relays the user's decisions, commits the spec, the plans and the reports
  (implementers commit their own tasks), hands milestone suites to a runner and
  reads its verdict, and writes the report. It reads reports, not code. The
  topology is flat: the lead spawns every agent and continues it by name; agents
  do not spawn agents.
```

New:

```markdown
- **The lead only stitches.** The lead session does no design, planning,
  implementation or review itself. It spawns agents, hands them file paths,
  relays the user's decisions, commits the spec, the plans and the reports
  (implementers commit their own tasks), names who runs the gate and reads
  the verdict, and writes the report. It reads reports, not code. The
  topology is flat: the lead spawns every agent and continues it by name;
  agents do not spawn agents.
```

### P1 `roles/planner.md`

Anchor: Insert a section "## Task classes" after the introduction ("You plan; you do not implement. ... without you.") and before "## The spec".

Old:

```markdown
(none; insertion)
```

New:

```markdown
## Task classes

The lead records the task's class in the brief or the plan; what you write
and what proves the work follow from it.

| Class | You write | What proves the work |
|---|---|---|
| Small | Nothing. The lead's message is the brief. | The project's own checks, the touched packages' unit suites and one diff; no obligations list, no impact set. |
| Brief | A brief of a few lines: goal, tests, acceptance criterion, the path of the evidence file, the class and the refactor flag where set. No obligations list and no impact set. | The brief's tests and acceptance criterion; the full suites the implementer runs at the end are the net for a missed dependant. |
| Phase | The spec and the phase plan as the sections below state. The gate, every suite outside CI and every residue search are phase-level obligations; no task cites them. A probe, pin or search you ran is recorded in the plan's evidence file once and is not an obligation of any task unless the task's change alters its answer. | The keyed obligations, the impact set and the gate run once on the accepted tree. |
| Refactor flag | On a brief or a plan: the pins and the guards they run with, run once on the base before the first change; which commits are mechanical. One gate per brief or phase, never a check set after every task. | Pins green on the result, the mechanical commit's script re-runnable, one gate per brief or phase. |
```

### I1 `roles/implementer.md`

Anchor: Insert after the introduction paragraph ("The plan gives you the goal, ... your own markers.") and before the first bullet.

Old:

```markdown
(none; insertion)
```

New:

```markdown
The lead's message, the brief or the plan names the task's class; the table
says what each class asks of you. The refactor flag adds its row to the class.

| Class | Your brief and evidence | Red test | Checks you run, after your last edit | Review |
|---|---|---|---|---|
| Small | The lead's message; the evidence file at the path it names, holding the project's checks, the touched packages' unit suites, one diff showing only the intended parts changed, and one look at the result where the change is visible. | Where behaviour changes. | The project's own checks and the touched packages' unit suites once; no runner follows. | One diff review, or one review of the branch for a series of small changes. |
| Brief | The brief file; its tests and acceptance criterion are the obligations; the evidence file it names. | Always, except for a mechanical change. | Targeted tests while you work; the full suites at the end and after any fix; no runner follows. | One diff review; a blocking finding returns with a delta re-review. |
| Phase | The plan's task entry; one evidence file per task in the plan's directory, one entry per obligation. | Always, except for a mechanical change. | Targeted tests and the full unit-test suite of every package the task changed; never the gate or a suite outside CI per task, never a probe, pin or search the plan's evidence already records unless your change alters its answer. The gate runs once on the accepted tree, by you when the lead names you, otherwise by a runner. | The phase review and its fix round. |
| Refactor flag | As the class, plus: the pins run once on the base and recorded before the first change; the mechanical change in its own commit with its re-runnable script. | None for the mechanical commit. | One gate per brief or phase. | The mechanical commit is spot-checked, the hand edits are read in full. |
```

### I2 `roles/implementer.md`

Anchor: The bullet "Every obligation your task discharges gets an entry ..." and the bullet "Before you report a task, run the complete unit-test suite ...", replaced by two bullets.

Old:

```markdown
- Every obligation your task discharges gets an entry in your task's evidence
  file, named by the task's key in the directory the plan names: the key, the
  command run or the place read, the result as the tool printed it and, once
  it exists, the commit. Your report points to the entries; it does not
  replace them, because the reviewer reads the file, not your report. A task
  brief with no phase plan names its evidence file itself, and the lead's
  message does so for a small change without a brief; the brief's tests and
  acceptance criterion, or the small change's checks and diff, are its
  obligations.
- Before you report a task, run the complete unit-test suite of every package
  the task changed, not only the tests you wrote or edited, and any suite
  outside the CI pipeline that exercises or reads what your change altered;
  record the totals in your evidence file. A suite the environment cannot run
  joins the milestone's request to the user, or your report for a task brief
  with no phase plan or a small change without one, and the evidence file says
  so. Cross-package suites and the milestone gate stay with the milestone. For
  a task brief with no phase plan, or a small change without a brief, run the
  full suites yourself at the end of the task and after any fix; no runner
  follows.
```

New:

```markdown
- Every obligation your task discharges gets an entry in your task's evidence
  file, named by the task's key in the directory the plan names: the key, the
  command run or the place read, the result as the tool printed it and, once
  it exists, the commit. Your report points to the entries; it does not
  replace them, because the reviewer reads the file, not your report.
- Before you report a task, run the checks the class table names for it, after
  your last edit, and record the totals in your evidence file. A suite the
  environment cannot run joins the milestone's request to the user, or your
  report for a brief or a small change, and the evidence file says so.
```

### R1 `roles/reviewer.md`

Anchor: Insert after "You review; you do not fix." and before the first bullet. The rows for a brief, a spec and a writer's output make the unchanged bullet "For a writer's output, re-run the check the brief names" consistent with R2.

Old:

```markdown
(none; insertion)
```

New:

```markdown
The brief, the plan or the lead's message names the class of what you review;
the table says what you read, what you run and when a round closes. A round
with no Critical or Important finding closes the review of the object as
reviewed; what is added later gets a review of its own delta.

| Object | You read | You run | Round |
|---|---|---|---|
| Small diff, or a branch of small changes | The diff and the recorded results; the rendered or running result where the change is visible. | Nothing recorded with its output, unless the output does not settle the claim. | One; lesser findings never reopen it. |
| Brief diff | The hand-edit commits in full; the evidence file against the brief's tests and acceptance criterion. | A targeted test only when its recorded result does not settle the claim; full-suite totals are read. | A blocking finding gets a delta re-review; lesser findings close the round. |
| Phase diff | The hand-edit commits in full; every task's evidence file; the coverage check against the phase goal. | The phase-level obligations (residue searches, the `AGENT-MARK` search) yourself; a recorded check only when its output does not settle the claim; no mutants, coverage scripts or renders of your own for a claim the evidence settles. | As the brief; at most two rounds. |
| Refactor flag | As the class, plus the mechanical commit spot-checked against its script, and the pins' recorded base run and result run. | As the class. | As the class. |
| Plan | The checklist below. | The recorded impact-set searches against the base of the phase. | A blocking finding gets a delta re-review. |
| Brief | That its tests and acceptance criterion prove its goal, that its class fits the change it describes, and that it names its evidence file. | Nothing. | As the plan. |
| Spec | The goals, invariants, contracts and assumptions against the tree and the sources the spec cites. | Nothing recorded; a search or a read that settles a claim. | As the plan. |
| Writer's output | The output against the style block and the glossary. | The check the brief names. | As the class of the text task. |
```

### R2 `roles/reviewer.md`

Anchor: The first bullet "Verify claims against the phase's evidence files ...", replaced. "re-run a recorded check only as the class table says" leaves the writer-output check and the late-regression-test check untouched: neither is a recorded result.

Old:

```markdown
- Verify claims against the phase's evidence files, not against the reports:
  for every obligation under review, the phase's or, in a single-task review,
  those the task cites, re-run the command or read the named place, and judge
  whether the evidence proves the claim, not whether an entry exists. A
  task-level obligation without an entry, or an entry whose result does not
  settle the claim, is a finding; a phase-level obligation you run yourself and
  record in your report. Then read the hand-edit commits in full; the evidence
  tells you where to look, it does not replace the reading. For a task brief
  with no phase plan, the brief's tests and acceptance criterion are the
  obligations and the file the brief names is the evidence; re-run the
  targeted tests. Full-suite totals the implementer recorded are read, not
  re-run. For a small change without a brief, read the diff and the recorded
  results and re-run nothing unless a result does not settle its claim.
```

New:

```markdown
- Verify claims against the evidence files, not against the reports: for every
  obligation under review, the phase's or, in a single-task review, those the
  task cites, read the named place or the recorded output and judge whether the
  evidence proves the claim, not whether an entry exists; re-run a recorded
  check only as the class table says. A task-level obligation without an
  entry, or an entry whose result does not settle the claim (missing output,
  another commit than the one under review, a result the diff contradicts), is
  a finding; a phase-level obligation you run yourself and record in your
  report. Then read the hand-edit commits in full; the evidence tells you
  where to look, it does not replace the reading.
```

## Appendix B: `decisions.md` entries

Prepended under "## Entries", in this order, in the file's format.

```markdown
- 2026-10-31 task-classes integrated
  rules/global.md, roles/planner.md, roles/implementer.md, roles/reviewer.md:
  no proposal file; the dev-tools spec "Task classes" (2026-10-31), written
  from four process cost reports (amen-app, omega-psir, analogiesio-assets,
  nieznajomi, 2026-10-25…31). The cost of a change was set by the process it
  entered, not by its size: a bug fix that got a planner cost 25 M tokens
  (#112) against 0.5–6 M for brief-only fixes; refactor batches ran eight
  checks plus e2e after each task (#118, 60–167 M each). The tiers already
  existed (mechanical config change, small change, brief, spec and phase) but
  were spread over four bullets and inline "for a task brief with no phase
  plan" clauses in two roles. The lead now names one of three classes (small,
  brief, phase) plus a refactor flag, once, where the task is stated, and the
  planner, implementer and reviewer each carry a table of what applies.
  Separate role files per kind were rejected: the kinds differ in parameters
  (which checks, who repeats them, which model, how many rounds), not in
  actors. The mechanical config change is the small class's no-review case.
  The small class keeps the touched packages' unit suites beside the
  project's checks, narrowing the suites 2026-10-26-light-mode-for-small-code-changes
  listed to the touched packages' unit suites;
  the whole-repository suites it drops caught nothing on small fixes (omega-psir
  E, 15952 tests, the ten baseline failures).
- 2026-10-31 refactor-proof-shape integrated
  rules/global.md, roles/planner.md, roles/implementer.md, roles/reviewer.md:
  nine plan reviews and nine diff reviews of #118 B2–B8b found no blocking
  defect; the one code defect (B2 env-catalog) came from the gate; the pins
  and the markup comparison were run by implementer and reviewer alike (#125,
  B6, B8a, B8b). The refactor flag names in one place the proof the roles
  already described in parts (pins on the base, mechanical commit separate,
  spot-check, hand edits read in full) and adds: pins once, one gate per
  batch, never a check set after every task. Plan reviews of refactor batches
  stay: in nieznajomi S3.1 and S3.3–S3.7 they found 1–7 blocking items each
  (S3.2 none).
- 2026-10-31 tier-on-the-users-word integrated
  rules/global.md: the five most expensive steps in amen-app and in omega-psir
  were all Opus implementers, planners and scouts; the lead chose the model
  itself (omega-psir H, I, K3) or a project memory did ("agent-per-issue":
  one Opus owner per issue plans and implements every phase; #105 and #116
  at 148 M tokens each) against the tier sentence. A stronger model for one
  agent now needs the user's word for that task, recorded in its brief or
  plan; nothing but the environment's routing table overrides the tier.
  Sharpens 2026-10-08 agent-roles-tiers, which named the table as the only
  override but left the lead's own choice unstated.
- 2026-10-31 context-ceiling integrated
  rules/global.md: cache reads were 97–99 % of processed tokens and the payer
  was the continued agent: area implementers at 535k–768k context after 5–9
  stops (nieznajomi), a writer at 475k after five tasks and 400k per call
  (analogiesio), one owner-agent round of 286 turns at 124 M (#116). A continued
  agent is now retired at the stop at which its context, which the harness
  reports at every stop, has passed the ceiling; the replacement starts from
  the files. Refines 2026-09-18-reuse-sub-agents, which holds
  inside the ceiling.
- 2026-10-31 gate-once-per-phase integrated
  rules/global.md, roles/planner.md, roles/implementer.md: plans listed the
  whole check set and e2e as obligations of every task (#118 B4: 19 e2e runs,
  51 M in one round; B8b: eleven tasks each running eight checks and 61
  guards); in nieznajomi the full suite sat in 52 of 68 task evidence files
  and ran again at the gate, and the planner's probes were repeated by 56 of
  68. The per-task package suite stays: it caught four failing specs a brief
  had missed (omega-psir G) and is the answer to the five gate failures of
  2026-10-21. The gate, the suites outside CI and the plan's probes, pins and
  searches are phase-level, run once. Revises
  2026-10-24-suites-outside-ci-run-by-the-change for the phase class only;
  a brief still runs every suite itself, and the per-task package suite of
  2026-10-21-implementer-runs-package-suite is unchanged.
- 2026-10-31 reviewer-re-runs-only-unsettled integrated
  rules/global.md, roles/reviewer.md: reviewer re-runs of recorded checks
  found one stale count in four projects (6026 against 6004, a defect of the
  evidence text), reviewer-made mutants and coverage scripts found nothing
  (#118 B6, B7a, B8b, B3; analogiesio U1a), and the nieznajomi reviewers
  re-ran at least 48 of 380 task keys with no finding attributed to a re-run;
  the defects reviews did find came from reading hand edits, renders and
  library sources. The
  reviewer now re-runs a recorded check only when its output does not settle
  the claim, in every class, and builds no proof of its own for a settled
  claim. The late-regression-test check on old code stays; it is a run no one
  recorded. Narrows "re-running and re-reading" of
  2026-10-25 obligations-evidence-and-fewer-phases.
- 2026-10-31 runner-only-for-unrun-checks integrated
  rules/global.md: a runner's full suite after the implementer's run of the
  same suite on a tree a few lines newer found nothing new in five runs
  (omega-psir H, I; one of them repeated on the same commit), and runners ran
  test:admin and then check, which contains it (#118 B7a–B8b). The two
  defects runners caught (#118 B2, #116 F4L) were checks the implementer had
  not run. The gate is one command set run once on the accepted tree by the
  implementer the lead names, otherwise by a runner, and a runner is spawned
  for what no recorded run on that tree covers; "the lead only stitches" now
  says the lead names who runs the gate. Revises 2026-10-08
  agent-roles-milestone-suites: the lead still reads a verdict, because the
  run lands in an evidence file.
- 2026-10-31 second-reviewer-plans-only integrated
  rules/global.md: 46 second reviews of task diffs returned 30 with no
  finding, 20 minor, 2 important and 1 critical; one important held and was
  new to the review (G8/T6), one was acted on (G2/T6), the critical was
  refuted by a test on the real write path (G4/T4): one defect in 46 runs, out
  of 80 runs and 302 minutes. 21 on plans returned 15 important, at least 4
  not in the first reviewer's report (nieznajomi); ten runs in amen-app
  yielded no finding and two in omega-psir did not run. The second reviewer now reads
  the spec or the plan of design work and contract changes; a diff only on
  the user's word. Narrows 2026-10-08 agent-roles-second-reviewer.
- 2026-10-31 branch-review-for-small-series integrated
  rules/global.md, roles/reviewer.md: a review of a whole branch of seven
  small commits found ten findings that three per-task rounds and one
  per-task review had missed (omega-psir F against B and C), while per-task
  light reviews of five small tasks found nothing in the code (analogiesio
  U8, U10, U12 none; U9 and U11 a defect of the evidence tooling and a
  mislabelled render; 0.2 to 0.85 M each). Small changes that land in a series on one branch get one
  branch review before the merge; a brief keeps its own review, because
  per-task reviews of feature briefs found real defects (#102, omega-psir B).
- 2026-10-31 lesser-only-closes-the-review integrated
  rules/global.md: second rounds that re-checked fixes of lesser findings
  found one lesser finding or a note each (#99 F5 diff 2, #108 plan 2,
  analogiesio U10 and U12). The one-pass rule of 2026-10-28-small-work-one-pass
  now holds for every class and object, scoped to the object as reviewed: a
  round with no Critical or Important finding closes the review of what it
  read, and commits or plan text added later get a review of their own delta.
  The nieznajomi rounds that found blocking items after an accepted round
  (G6/T3, G9 plan, G10 plan) are not known to be re-reviews of lesser fixes;
  the reports do not say whether the object changed between rounds. The rationale sentence "a review per task
  multiplies context loads without finding more" moved here from global.md.
```
