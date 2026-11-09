# Review, round 1: amendment A1 of the UI prototype track spec

Reviewer: Arek (reviewer 2). Object: "Amendment A1 (2026-11-09)" at 3f86c7e, against `~/knowledge` main abbc2b9. Class: spec.

Verdict: accepted, no Critical or Important finding. The external second review is not in this file; its findings join the round.

## Checks
- Old blocks: G8 (`rules/global.md:534-539`), P1 (`roles/planner.md:58-61`), P2 (`roles/planner.md:117-119`) and R1 (`roles/reviewer.md:77-84`) match the files verbatim. HEAD is abbc2b9.
- Word count: the G8 Old and New blocks are both 76 words, as the Landing section says.
- Verdicts:
  - S1, S2, S3, S5, 3a: real, and the New blocks fix them. G8 sends what no agent can reach to the batched check (`global.md:543`). The prototype is contract (invariant 2). The flow line says a difference is a finding. A phase task has no criteria of its own, and a brief has no tasks. G8 binds only the brief and phase classes (invariant 6).
  - S4 (fit check): not a problem. `global.md:546` states how a fit check is done, not that every visible change needs one. Making it mandatory would be a new obligation. A clipped element at the narrowest width also differs from the prototype, which R1 catches.
  - S6: settled elsewhere. The reviewer's Spec row reads "the sources the spec cites" against the tree.
  - 3b: settled elsewhere. The bullet excepts questions the rules route to the user, and G1 routes the variant choice to the user.
  - 3c: not a problem. `roles/planner.md:216` and `:220` are about code and spikes.
- New blocks: no contradiction with G8's batched-check sub-bullet, the reviewer's blocking rule, invariants 1-2 and 6, or Q1-Q4. No obligation is added beyond what the findings need. P2's "for a brief its acceptance criterion" only makes explicit who names the widths, which G8 already requires of a brief.

## Lesser findings (not blocking, not applied: each needs a wording choice or is cosmetic)
1. R1 New: "A platform the evidence records, with the reason, as reachable by no agent" lets the implementer declare a platform unreachable. The reviewer is not told it may reject a reason that is false (for instance, a browser is reachable). Suggest "with a reason you accept". Without it, the clause reads as a free exit.
2. R1 New: the opening "For a visible change of the brief or phase class" now scopes the bullet, and the sentence on a spec's prototype citation sits in the same bullet. A spec is not a visible change, so a literal reading could skip that sentence. Meaning is unchanged from today. Start that sentence with "In a spec review" if it is touched again.
3. P2 sits in the phase plan's "Obligations" section; the planner's Brief row (`planner.md:22`, "goal, tests, acceptance criterion") does not mention pictures. A brief writer reads the Brief row first. Optional: one clause there. This would be a further change, so it is left to the lead.

## Not verified
The external second reviewer's findings.
