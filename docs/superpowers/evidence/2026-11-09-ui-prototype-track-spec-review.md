# Spec review, round 1: UI prototype track (Arek, reviewer 2)

Object: docs/superpowers/specs/2026-11-09-ui-prototype-track-design.md at b3a5f89.
Verdict: blocking, 4 Important findings; no Critical.

## Important

1. Prototyper pin contradicts the README as of 294c0d0. Invariants ("role files carry no `model:`"), the role contract (Tier: cheaper, "no `tools:` line") and X1's frontmatter omit `model:`. `roles/README.md` now says a single-tier role pins it (runner haiku; implementer, scout, writer sonnet), and the lead passes a model only for two-tier roles. The prototyper is single-tier (cheaper, beside implementers), so unpinned it inherits the lead's model: the Jurek-on-opus failure that role-model-pins fixed. Fix: X1 frontmatter gets `model: sonnet`; the invariant is deleted or reversed; add prototyper to the README's list of pinned roles (README is not in the Scope list); G2 stays. The decisions entry may cite role-model-pins.
2. G8 collides with the small class. Section 2 gives a small change "one look at the rendered or running result where the change is visible". G8 applies to "a visible change" of any class: screenshots of every screen and state at the task's widths, narrowest always, base-tree pictures beside them, one page, linked from the report. For a colour or wording tweak this is more than the whole change, and the invariant "class definitions are unchanged" does not hold in practice. Fix: scope G8 to the brief and phase classes (small keeps its one look, recorded as one picture in its evidence file), or say so in G8's first sentence.
3. G1's trigger is unbounded. "a layout, a visual style, a new screen" is design work, hence phase class and a user-approved prototype. A new screen inside an already approved direction (the common case after the first round) would need a new prototype round, and Q2 (brief inside an approved direction) is then partly pre-decided against its own recommendation. Fix: "a new screen the approved direction does not cover" and name that a screen within an approved prototype is not design work by this clause.
4. The approved prototype has no home in the repository. X1 writes the variant outside the working tree, G3 has the lead commit "the approved prototype", G1 and R1 require the spec to cite its path, but no block says where it lands or who copies it. A cited path outside the repo does not survive the sandbox ("context travels in files"), and R1 cannot check a citation to nothing. Fix: one clause in G1 or P1: the lead copies the approved variant beside the spec and the spec cites that path.

## Lesser (not blocking)

- Q5 is not a genuine decision: slot names are fixed by rule and the recommendation is already an assumption; drop it and record the assumption (ask-vs-assume steps 2 and 5). Q1 to Q4 are correctly stated; no missing candidate.
- G7 omits shadows, which PP6 lists; the decisions entry for PP6 says "style values" generally. Add if wanted (+1 word).
- "prototype brief" shares the word "brief" with the Brief class (approved by the user after review). P1 or G1 could say it is not a brief of that class and gets no user approval.
- The ledger is right (recomputed: G1 +98, G2 +1, G3 +3, G4 +32, G5 +5, G7 +12, G8 +203; G6 +1 not recomputed by script); +355 is about 6% of global.md, and G8 is 55% of it. Proportionate if finding 2 trims G8 to the larger classes.

## Applied by the reviewer (no decision needed)

- Assumptions: replaced the stale "main clean at 5e48a74, 14 ahead" with the real state (main at 116227e plus uncommitted integrator edits to global.md, reviewer.md, decisions.md). Old blocks G1, G2, G3, G6, G7 re-checked as substrings of the current working tree: all present.
- Problem, ANA bullet: the reference image became the spec delta; the mockup restyle was a separate Zuzia task (report: the transcripts do not show a rejection).
- Fate table: added a scope sentence (non-visual inputs are not listed) and the missing UKF S4 row (non-goal).
- X1 Limits: added "Publish it as a page where the environment can", since nothing told the prototyper to publish.

## Checks that passed

- Facts against the four reports (UKF times 10:16Z, 10:27Z, 10:55Z, 10:59Z, 18:18Z, a9b3cf1; NOD O8/O9; ANA aded3a6, D9/D10; OME Suggestion 3 and Fit; OOM five and four) and both proposals (PF, PP1 to PP6 in file order) match.
- Fate table: every taken input maps to a block (G1, G7, G8, P1, P2, R1, X1); PP5 and PP3 and PP6 lint are stated as not taken; the decisions entries match the table.
- Render enumerates roles/ (ai-knowledge:493); ai-delegate accepts only scout, writer, second-reviewer; the process-report skill has the kinds cited; no name collisions for Tosia, Franek, Julka; process-report skill and knowledge-integrate step 6 (merge -s ours) exist as cited.
- Blocks do not duplicate or contradict any existing clause apart from findings 1 to 3. "Without an agent review" in G1 is explicit against the rule that the user sees reviewed versions.
