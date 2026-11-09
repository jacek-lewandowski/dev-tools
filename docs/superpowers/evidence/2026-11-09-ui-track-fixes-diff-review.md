# 2026-11-09-ui-track-fixes: diff review

Marta, reviewer 3. Class: brief diff. Object: `~/knowledge` fab0379 (parent abbc2b9), against spec
`docs/superpowers/specs/2026-11-09-ui-prototype-track-design.md`, "Amendment A1 (2026-11-09)", and
evidence `docs/superpowers/evidence/2026-11-09-ui-track-fixes.md`.

Verdict: accepted. No Critical or Important finding; the round closes. No fix commits made.

## Checks run

Own script (scratchpad `check.py`) extracts every fenced block of Amendment A1 from the spec and reads
the files with `git show <rev>:<path>`.

- Known case: at abbc2b9 each Old block (G8, P1, P2, R1) counts 1 and each New block 0, as the spec
  states the Old blocks were copied from abbc2b9. The extraction therefore reproduces the tree byte for
  byte, so the zero counts below are real.
- At fab0379: each Old block 0, each New block 1 in its named file.
- Whole-file reconstruction: abbc2b9 with the four Old->New replacements, and the decisions entry
  (`<landing date>` = 2026-11-09) inserted directly after `## Entries`, equals fab0379 byte for byte for
  `rules/global.md`, `roles/planner.md`, `roles/reviewer.md` and `decisions.md`.
  `git diff --stat abbc2b9 fab0379` lists only those four files. Nothing else changed.
- `wc -w rules/global.md`: 6912 at both revisions, as the evidence records.
- Evidence method: the implementer's `land.py` counted the Old blocks in the tree before applying
  (known answer 1 each) and asserts 1/0 before replacing; that is a check on a known case, and the
  result matches mine.

## Coherence in place

Read against `rules/global.md` §4 ("When the environment cannot run it", the G8 sub-bullets),
`roles/planner.md` (class table, "The spec", "Obligations"), `roles/reviewer.md` (class table, other
bullets) and `roles/prototyper.md`. No contradiction found: G8, P2 and R1 now name the same source of
the widths (the brief's acceptance criterion or the phase's obligations); R1's unreachable-platform
clause matches G8's "What no agent can reach joins the user's batched check"; R1 bound to brief and
phase agrees with the Small-diff row's single look; P1's narrowest width matches G8 and
`roles/prototyper.md` ("at every width the sheet names").

## Lesser findings (not blocking, not fixed)

1. `roles/reviewer.md`, visible-change bullet: in "except in live data or the placeholders it marks",
   "it" refers to the approved prototype (as `roles/prototyper.md` "use placeholders marked as such"
   shows), but the nearest nouns are "a missing or extra element" and "a finding". Resolving it means
   rewording an approved New block, so it needs a spec amendment; left as is.
2. `roles/planner.md`, prototype sheet paragraph: the landed line "The sheet is not a brief of the brief
   class: it" is short against its neighbours, because the New block ends mid-paragraph. Cosmetic;
   reflowing by hand would break the verbatim New-block check and the repository has no Markdown
   formatter, so left as is.
3. Evidence file names its script at `/tmp/claude-1000/s/land.py`, outside any repository, and not the
   exact command line run. The claims are settled by the re-run above, so nothing is missing for this
   review; a later reader cannot re-run it once `/tmp` is cleared.
