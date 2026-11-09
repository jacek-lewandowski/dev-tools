Task: 2026-11-09-ui-prototype-track

# Phase review, round 1 (Arek, reviewer 2)

Object: `~/knowledge` `ed816ba..d842b02` (feat 4630d1a, merges f4edac8 and d842b02) against the spec, the plan and T1–T5, impact-searches.md.
Verdict: **accepted**. No Critical or Important finding; the round closes the review. One lesser fix committed by me: `9d9642d` on `~/knowledge` main (not pushed), so HEAD is now one commit past d842b02.

## Evidence against obligations

- V-G1..V-G8, V-P1, V-P2, V-R1, V-RM1, V-X1, RS-OLD (T1/T2): the recorded script output settles each claim (1 per New block, `identical` for X1, 0 per Old block; known case recorded). Not re-run. I also read the whole diff against Appendix A: every hunk is a block of the contract, nothing else.
- AN-1, AN-2, FM-1, RN-1 (T1/T2): placements and front matter confirmed in the diff.
- WORDS (T1): 6301 → 6693; re-checked with `wc -w` on `ed816ba` and HEAD: +392.
- V-B, DEC-1 (T3): the three entries are in `decisions.md` with `2026-11-09`, newest first above the task-key entry; read in the diff.
- GATE-DIFF, CL-1..CL-3 (T4): the feat commit touches exactly the six files; both merges are `-s ours` with the proposal as second parent; `merge-base --is-ancestor` re-run, exit 0 for both. Trailers `Task:` present on all three commits.
- RN-2: pending, the user's host check, by plan.

## Phase-level obligations run by me

- NOMARK: `grep -rn 'AGENT-MARK ui-prototype-track' ~/knowledge` empty (rc 1); `grep -rn '<landing date>' ~/knowledge/decisions.md` empty. Known case: `grep -rln 'AGENT-MARK' ~/knowledge --exclude-dir=.git` finds decisions.md, roles/implementer.md, roles/reviewer.md.
- RS-NAMES: `Tosia` only `rules/global.md:203` (G5); `-i -w prototyper` hits global.md:183 (G4), :203 (G5), :284 (G6), roles/prototyper.md:2,:37 (X1), roles/README.md:20 (RM1). Matches the blocks (G2 says "prototypers" and does not match `-w`, though the plan's expected list names G2).
- Impact searches 1 and 5 re-run unchanged from the plan: 3 lines and rc 1, as recorded.
- Formatting: `~/knowledge` has no Markdown formatter configured.

## Findings (none blocking)

1. Minor, fixed (`9d9642d`). Missed dependant: `roles/implementer.md`, the "You commit your own task" bullet restated the G3 list as "The lead commits **only** the spec, the plans, the reports, the evidence files and its own handover", which now contradicts G3 ("the approved prototype"). An implementer on a tool without `global.md` reads the old list. Fix: added "the approved prototype". The search that would have found it: `grep -rn 'commits the spec\|commits only the spec' rules roles` — for any block that edits a list in `global.md`, search `roles/` for the list's head phrase. The project has no build to hold such a check; a note in the planner's impact-set category "duplicated logic" or a coupling-register entry is the lead's call. (The restated list also lacks "reviewers their own code fixes"; that drift predates this phase and I left it.)
2. Minor, not fixed. Ragged wrapping in G1 ("and\n  against"), G2 ("on the\n  cheapest\n  tier"), G3, G7 (a 92-character line), RM1 ("`sonnet`). A"), the ui-prototype-track decisions entry ("Prototypes are"). Every broken line is an indented continuation inside its list item; no Markdown structure changes, no table row breaks. Left as landed: the spec makes the wrapping part of the contract, and global §3 forbids hand-reflowing without a formatter. Side effect: the distinctive search string `command runners on the cheapest` no longer occurs on one line.
3. Minor, wording, needs a contract decision, not fixed. (a) `roles/reviewer.md` R1 opens "For a visible change", not limited to the brief and phase classes as G8 is; a reviewer of a small visible change could ask for pictures against base pictures that G8 does not require. (b) `rules/global.md` bullet title "The user sees only reviewed versions" versus G1 "A prototype reaches the user without an agent review"; G1 states the exception and the bullet's body excepts questions routed to the user, so it reads consistently. (c) `roles/planner.md` "The phase plan" keeps "prototype results; those are the implementer's work" and "Do not write scripts or prototype" in the code sense, next to the new prototyper; the spec chose to keep it unchanged.
4. Minor, evidence. `impact-searches.md` records search 1 as `grep -rn -w ... rules roles skills README.md`, not the exact command; its last entry `grep -rn AGENT-MARK ui-prototype-track` is not the NOMARK command (it searches a path named `ui-prototype-track`). T3 records the right NOMARK command, and I re-ran both.

## COV

- G-a: V-G1 (visual direction is design work, the spec cites an approved prototype, the first plan waits).
- G-b: V-X1, FM-1 (role file, `model: sonnet`), V-RM1 (README list), V-G2 (tier), V-G4 (lifetime), V-G5 (slot names), V-G6 (table row), RN-1 (render loop reads the front matter); "renders with the others" on the host rests on RN-2, pending with the user.
- G-c: V-G8 (brief and phase classes, small change keeps one look, pictures per platform, element-box fit check, device settings first in the user's check, one page).
- G-d: V-P1 (who writes the sheet), V-P2 (obligations of a visible goal), V-R1 (what the reviewer checks and never judges).
- G-e: V-B (entries give the fate of every PP bullet and of PF, matching "Fate of every input"), CL-1..CL-3 (both proposals closed).
- Phase goal: the blocks, the role file and the entries are on main and the proposals are closed; the render is RN-2. Every observable part of the goal has an obligation.

Note for the lead: CL-2's "no tree change after the feat commit" held at T4; HEAD now carries `9d9642d` on top.
