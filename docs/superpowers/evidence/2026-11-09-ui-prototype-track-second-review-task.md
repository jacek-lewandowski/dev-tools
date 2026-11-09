# Second review task: UI prototype track spec (round 1)

Object: the design spec `docs/superpowers/specs/2026-11-09-ui-prototype-track-design.md`
(commit b3a5f89), read from this repository. Read it with `cat` only; do not run git or
any other command.

The spec changes the shared agent rules. Its contract blocks G1–G8, P1–P2, R1 and X1
are the text that will land in the rules and role files. It fixes how work that changes
what users see is prototyped, approved by the user and verified.

Review the spec as a plan of design work. Report only findings that block it or would
materially improve it:
- a goal not served by any contract block;
- a contract block that contradicts another block or the spec's invariants;
- a rule an agent could not follow as written, or could satisfy without achieving its
  goal;
- an input the spec's own table marks as taken but no block carries;
- a cheaper way to reach the same goal.

For each finding give its severity (Critical, Important, Minor), the spec section or
block, the problem, and a concrete fix. Do not restate what is fine.
