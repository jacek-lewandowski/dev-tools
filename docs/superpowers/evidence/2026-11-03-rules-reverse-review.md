# Fiona, reviewer 1: reverse review of the rule set after 2026-11-03

Object: `~/knowledge` main at 0a5975f (`rules/global.md`, `roles/*.md`,
`decisions.md`); changes `dd91d76..main`. Nothing edited, nothing committed.

## Important

**I1. global.md, Ask vs. assume (new step 2 and the lead's relay sentence).**
The step makes "what a reasonable user would expect" count as *clearly right*,
and the last step then says "take it, do not ask". No question is exempt, so the
filter now overrides three rules that require a question:
- planner.md, The end user: "a business rule (a permission, a price, a retention
  period, who may see what) you ask about and never invent", and planner.md's
  "A heuristic that survives the check is a decision for the user".
- global.md, A compatible fix needs no question: "Ask first ... when it alters
  what an end user sees or must do".
- §1 🔴 and "Ask ... when an action is 🔴".

Scenario: Ola, a brief writer, asks "may team members see archived records, or
the owner only?". The lead runs the five steps, judges "owner only" what a user
would expect, and "answers itself": a business rule invented at the lead, the
exact outcome planner.md forbids, and it never reaches the user. The same path
lets an implementer decide an incompatible fix. The relay sentence also makes the
lead do design (it answers a design question itself) and check "the project's
data", which "The lead only stitches ... reads reports, not code" forbids, and it
bypasses "every spec question goes to the same agent" (the spec's author).
Today nothing says which wins. Resolve: exempt from steps 2 and 5 business rules,
incompatible behaviour changes, contract changes and 🔴 confirmations; limit the
lead's own answer to what the spec, plan or rules settle (step 4), route a spec
question to the spec's author, and relay the rest.

**I2. global.md, Discussion is not execution.** "Answered in the conversation,
without changing files" collides with "The lead only stitches" (the lead may not
assess itself) and with "Context between roles travels in files" (a reviewer's
assessment is a report file the lead commits). Scenario: the user asks the lead
to assess a design; the lead either assesses in its own context (breaks
stitching) or spawns a reviewer whose report file is a file change (breaks this
rule). This very review is that case. Resolve: say the rule protects the object
under discussion (code, spec, rules, configuration); reports and evidence files
an assessment produces are allowed.

**I3. global.md, Context lifecycle (handover review), with reviewer.md row
Handover.** Findings on an implementer note have no one able to fix them. The
rule says "The lead fixes blocking findings", but the lead holds no code context
and may not read code; the note's author is still reachable (the review precedes
`/clear`), yet the self-review bullet says the lead retires the implementer as
soon as its own review is done, so by the handover review it is gone. Scenario:
the reviewer finds Wojtek's note omits where the uncommitted change lies; the
lead guesses or reads the tree itself. Resolve: keep the implementers whose notes
the handover lists live until the handover review closes, and send note findings
to them.

**I4. Same rule and row: the open-task check is unbounded and the row lacks the
blocking test.** "Every open task in a plan or evidence file" has no scope (which
repositories, which dates) and "open" is undefined: dev-tools keeps 18 specs and
briefs and no status convention (`/usr/bin/grep -rlE '^\s*- \[[ x]\]'
docs/superpowers` returns 0 files; the same command finds a known `- [ ]` file),
plus the untracked, shelved supervisor spec. global.md says such a gap "blocks
only when a fresh lead could not take the stated next step"; reviewer.md's row
does not, so a reviewer applying its general rule ("Block ... on ... an explicit
rule") marks every unlisted old task Important and the lead spends both rounds on
stale plans. Resolve: scope the check to the plans and evidence files the
handover or the current spec names, define "open" (no closing evidence or
review), and copy the blocking sentence into the row.

**I5. planner.md, The end user, against planner.md's guard paragraph and
reviewer.md's plan checklist.** The end-user section asks the planner to settle
"an empty state, invalid input, a failure, an interruption, a retry"; the guard
rule cuts every edge case or retry without a reachable trigger and its source,
and the reviewer makes a speculative one Important. Scenario: the spec reviewer
flags an unsettled interruption flow; the planner adds it; the plan reviewer
flags the same retry as speculative. Resolve: say that settling a flow state
includes stating it unreachable, and that every state handled names its trigger
source as the guard rule requires.

## Minor

- **M1. Duplicate, drifted: implementer note self-review** in global.md (Context
  lifecycle) and implementer.md: "against the tree" against "the repository's log
  and status"; the role's trigger covers only retirement at a task boundary,
  while global also requires a note at 350k (mid-task) and at the lead's `/clear`
  (open task). Keep the procedure in the role, global only "the lead retires it
  after the implementer reports the note reviewed", and name all three triggers in
  the role.
- **M2. Duplicate, drifted: a brief's contents** in global.md (Every task has a
  class: "a few lines, goal, tests, acceptance criterion, evidence file"),
  planner.md's class table (adds class and flag) and the new end-user section and
  reviewer row (add end user and flow). Global should point to planner.md.
- **M3. implementer.md, last bullets:** "The lead commits only the spec, the plans,
  the reports and the evidence files" excludes the handover the lead must now
  commit; same list in global.md, The lead only stitches.
- **M4. global.md, table row Lead, Past 350k:** "Handover, its review and `/clear`
  at the end of the current turn" cannot hold; the review spans several turns
  (spawn, wait, fix, re-review) and grows the lead past its ceiling. Say "before
  any other work".
- **M5. global.md, The lead's persona:** "it complains, then does the work in
  full" contradicts "The lead only stitches"; "allergic to over-engineering ...
  judged by its cost to maintain" is a decision criterion inside a "tone only"
  rule. Use "sees the work done in full", and move the criterion to a rule or drop
  it.
- **M6. Persona leak through the name:** the trailer example and the signing rule
  put "Skippy Wspaniały" into every lead commit (dev-tools is a public tree) and,
  by the existing habit, into handover file names (`handover-stefan.md`). This is
  intended by the rename, but it is the one path by which the persona reaches
  files; state it as allowed or use a neutral slot name in trailers.
- **M7. Outside the repository:** the memory entry `agent-names.md` still says the
  lead is Stefan and signs as Stefan "until the host syncs", and this sandbox's
  rendered CLAUDE.md is the pre-2026-11-02 text (four steps, Stefan); b4d9f9c and
  7c1657b, 9 minutes apart, are signed differently. Update the memory at the sync.

## Verdict on question 1

1. **Handover review (2026-11-02):** achieves its purpose for the lead's own
   handover and is followable; the cost (a stronger-tier review at each handover
   past 250k, including before a long wait) is proportionate to a `/clear` that
   leaves nobody to correct it. Not followable as written for implementer notes
   (I3) and unbounded on open tasks (I4). Keep, fix I3 and I4.
2. **Implementer note self-review:** cheap, followable, achieves the narrower
   purpose decisions.md states (the author's blind spots remain, as accepted
   there). Keep; M1.
3. **End user:** the planner section and the reviewer rows achieve it. The new
   filter step works against its own decision's "never inventing business rules"
   (I1), and "Discussion is not execution" cannot be followed by a lead that only
   stitches (I2). Costs more than it buys until I1, I2 and I5 are fixed.
4. **Persona:** tone is contained: files, agent messages, code and verification
   claims are explicitly plain, and no rule is relaxed. Residue in M5 and M6 only.
   Achieves its purpose.

## Round 2

Delta read: the uncommitted `git -C ~/knowledge diff` against 0a5975f
(`rules/global.md`, `roles/implementer.md`, `roles/planner.md`,
`roles/reviewer.md`, `decisions.md`), and the rules around each hunk.

- I1 resolved. Business rules, incompatible changes, contract changes and 🔴
  confirmations are exempt from steps 2 and 5. The lead now answers only what
  step 4 settles, sends spec questions to the spec's author and relays the rest.
  A Minor residue remains (N1).
- I2 resolved. The rule now protects only the object under discussion, and
  assessment reports and evidence files are allowed.
- I3 resolved. Note findings go to the note's implementer, which stays live until
  the handover review closes; the self-review bullet carries the same exception.
- I4 resolved. The check is scoped to the plans and evidence files the handover or
  the current spec names, "open" is defined, and the row repeats the blocking
  test.
- I5 resolved. A state may be settled as unreachable, and each state handled names
  its trigger and source under the guard rule.
- M1 resolved. The procedure lives only in implementer.md, with all four triggers
  (task boundary, long wait, past 350k, the lead's `/clear`); global.md keeps only
  the lead's side.
- M2 resolved. global.md defers a brief's contents to the planner role.
- M3 resolved. Both commit lists now include the lead's own handover.
- M4 resolved. The 350k row now reads "before any other work".
- M5 resolved. The text now reads "sees the work done in full", and the
  maintenance-cost criterion is gone; "allergic to over-engineering" stays as tone.
- M6 resolved. The name is allowed in trailers, file names and signatures as the
  slot's name.

New findings, all Minor:

- **N1. planner.md, "A heuristic that survives the check is a decision for the
  user"**, against global.md, Ask vs. assume. The new exemption list does not
  include this case, because a domain threshold or naming convention is not a
  business rule as the examples define one. So a planner's own steps 2 and 5 can
  still adopt a "clearly right" heuristic that the planner role reserves for the
  user. Resolve: add "a domain fact derived by heuristic" to the exemption list.
- **N2. global.md, Ask vs. assume, last sentence.** "A question an agent puts to the
  lead goes through the same steps" is followed by "answers itself only what ...
  the fourth step settles". As a result, steps 2, 3 and 5 still run at the lead but
  cannot act. Step 3, in particular, asks the lead to check the project's data,
  which it may not read. Resolve: say the lead runs only the fourth step.
- **N3. implementer.md, fix-round bullet.** An implementer kept live for the
  handover review now receives note findings, but its role has no bullet for
  them. The only bullet that matches ("continued for the fix round of a review")
  asks for a test before any change, which is meaningless for a note gap.
  Resolve: a clause saying a handover-review finding on your note is fixed in the
  note and reported, with no test.

Round 2 verdict: 0 Critical, 0 Important, 3 Minor (new). Every finding from
round 1 within the repository's scope is resolved, and the delta introduces no
blocking contradiction. The review closes; N1-N3 are not blocking.
