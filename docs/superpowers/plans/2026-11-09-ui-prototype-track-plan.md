Task: 2026-11-09-ui-prototype-track
Class: phase

# UI prototype track: phase 1 plan

Spec: `docs/superpowers/specs/2026-11-09-ui-prototype-track-design.md` (approved 2026-11-09, d36784b). Author of this plan: Bartek.
Evidence directory: `docs/superpowers/evidence/2026-11-09-ui-prototype-track/`, one file per task key (T1 to T5), plus `impact-searches.md` (raw output of the searches below).
Plan type: details the approach only; no spec change. Unverified assumptions: see the end.

Target repository: `~/knowledge` (main, integrator clone). All paths below are relative to it unless prefixed `dev-tools:`. Nothing in dev-tools changes except this plan and the evidence files.
Commit trailer `Task: 2026-11-09-ui-prototype-track` on every commit (rule added by 2026-11-09-task-key, ed5e562); the spawn message of every agent carries the same line.

## State of the tree when this plan was written

- `~/knowledge` main at `ed5e562` (spec was written against `5e48a74`, re-checked at `c1b8b86` and `8a9b911`). Between `8a9b911` and `ed5e562` the task-key task added text to the "Every task has a class" bullet of `rules/global.md` (+11 lines) and a `decisions.md` entry (+11 lines); the Old blocks of Appendix A are unaffected.
- Old blocks G1, G2, G3, G6, G7 (`rules/global.md`) and RM1 (`roles/README.md`): each occurs exactly once, verbatim, at `ed5e562`. Method: a script that cuts the Old blocks out of the spec's Appendix A and counts each as a substring of its file (result `1` for all six); checked on a known case, since a block altered by one character returns 0. No block's surroundings moved except G1: the "Spec first" bullet now follows the longer class bullet; its own lines are unchanged. Insert anchors verified present: "Writer: one per text task" and "Writer: Basia, Michał, Dorota." (G4, G5), "When the environment cannot run it" (G8), "Goals, contracts, invariants and non-goals change only with the user's approval," (P1), "the claim depends on." (P2), "For a writer's output, re-run the check the brief names" (R1).
- Review-time update: main is now `ae5436e` (task-key's `feat(process-report)` commit landed), the tree is clean, all Old blocks and anchors still occur once and `wc -w rules/global.md` is still 6301; the precondition below is met. Original text of the planning time:
- Working tree of `~/knowledge` was NOT clean: `skills/process-report/scripts/transcript_stats.py` and its test are modified by task-key's implementer (Zuzia). The tasks below touch no file she touches (`skills/` is out of scope), but the closing merges (T4) need a clean tree (knowledge-integrate, step 2). Precondition for T4: `git -C ~/knowledge status --porcelain` is empty; if it is not, T4 waits for that commit, it never stashes or commits her files.
- Word base: `wc -w rules/global.md` = 6301 at `ed5e562`; the ledger adds +392 words (spec), so about 6693 after.

## Contract

Appendix A (G1 to G8, P1, P2, R1, RM1, X1) and Appendix B of the spec land verbatim, as reviewed. They are not copied into this plan: the spec file is the contract text, and the implementer copies from it with a script, never retyping. `<landing date>` in Appendix B becomes the date of the commit (YYYY-MM-DD).

Placement rules the spec leaves implicit (inferred, conventional):
- P1 is a new paragraph, blank line before and after, after the sentence pair ending "the spec changes before any plan does."
- P2 continues the paragraph ending "the claim depends on." (no blank line), as its text reads as further sentences of that paragraph.
- R1 is a bullet right after the "For a writer's output" bullet; G8 a top-level bullet right after the "When the environment cannot run it" bullet; G4 and G5 sub-bullets right after the Writer sub-bullet(s) (G4 after the two-line Writer lifetime entry, before "Second reviewer").
- Appendix B: the three entries go directly under `## Entries`, before the `2026-11-09 2026-11-09-task-key integrated` entry, in the spec's order, one blank line between entries.

## Areas and tasks

One implementer holds the area "knowledge text" for T1 to T5, in this order (no parallelism: one tree, one commit).

- **T1, global rules.** `rules/global.md`: apply G1 to G8. Goal: G-a, G-b (lifetime, tier, slot names), G-c. Discharges: V-G1, V-G2, V-G3, V-G4, V-G5, V-G6, V-G7, V-G8, RS-OLD, AN-1.
- **T2, roles.** New `roles/prototyper.md` (X1); `roles/planner.md` (P1, P2); `roles/reviewer.md` (R1); `roles/README.md` (RM1). Goal: G-b (role file, pin, README list), G-d. Discharges: V-X1, V-P1, V-P2, V-R1, V-RM1, RS-OLD, AN-2, FM-1.
- **T3, decisions.** `decisions.md`: the three Appendix B entries. Goal: G-e (entries). Discharges: V-B, DEC-1.
- **T4, commit and close.** One commit of T1 to T3 with explicit paths (`git add rules/global.md roles decisions.md`, never `-A`), message `feat(rules): visual work approved by eye and shown in pictures, prototyper role (ui-prototype-track, 2026-11-07-fit-check-uses-element-boxes, 2026-11-08-ui-work-approved-on-pictures-verified-on-target-platform)` with the Task trailer and the attribution the lead names; then the two `git merge -s ours --no-ff` merges of the knowledge-integrate skill, step 6, messages `proposal: <slug> integrated`, slugs from the branch names. The user approved the contract (the spec) on 2026-11-09; the commit lands exactly that text. Goal: G-e. Discharges: CL-1, CL-2, CL-3, GATE-DIFF.
- **T5, render.** `ai-knowledge render` cannot run in this sandbox (the Bash check in planning: `rsync` is missing and `sudo apt-get` is unavailable; render would also write to the host's `~/.claude/agents` through `wire_host`). The implementer therefore does not run it; it records this in its evidence, and the lead adds the exact commands to the user's batched check (OBL host-1). Goal: G-b ("renders with the others"). Discharges: RN-1 (a read check) and hands off RN-2.

## Obligations

Check helper: `V-*` use one script, kept in the scratchpad, that extracts the New text of a block from the spec's Appendix A (the fenced block after `New:`, or the whole fenced block for insert-only blocks) and counts it as a substring of the target file; expected `1`. The script is checked first on a known case: the Old block G2 against `rules/global.md` at the base commit returns 1 and a copy with one word changed returns 0. Evidence records the script's path and output per key.

| Key | Claim | Check | Expected |
|---|---|---|---|
| V-G1 | G1 New text is in `rules/global.md` | substring count | 1 |
| V-G2 | G2 New | same | 1 |
| V-G3 | G3 New | same | 1 |
| V-G4 | G4 block is in the file | same | 1 |
| V-G5 | G5 line is in the file | same | 1 |
| V-G6 | G6 New cell (`... writer, prototyper |`) is in the file | same | 1 |
| V-G7 | G7 New | same | 1 |
| V-G8 | G8 block | same | 1 |
| V-P1 | P1 paragraph in `roles/planner.md` | same | 1 |
| V-P2 | P2 text in `roles/planner.md` | same | 1 |
| V-R1 | R1 bullet in `roles/reviewer.md` | same | 1 |
| V-RM1 | RM1 New in `roles/README.md` | same | 1 |
| V-X1 | `roles/prototyper.md` equals the X1 block, byte for byte | diff of the file against the fenced X1 block extracted from the spec | no difference |
| V-B | the three Appendix B entries are in `decisions.md` with the date substituted | substring count of each entry with `<landing date>` replaced by the commit date | 1 each; `grep -c '<landing date>' decisions.md` = 0 |
| RS-OLD | the replaced old texts are gone | substring count of each Old block of G1, G2, G3, G6 (inline cell, with its closing ` |`), G7 and RM1 in its file | 0 for all six |
| RS-NAMES | the names and the tier are not defined twice | `grep -rn 'Tosia' ~/knowledge/rules ~/knowledge/roles` and `grep -rn -i -w 'prototyper' ~/knowledge/rules ~/knowledge/roles` (`-i`: G4 and G5 say "Prototyper:") | `Tosia`: exactly `rules/global.md` G5 line; `prototyper` as a whole word only in G2, G4, G5, G6, RM1 and `roles/prototyper.md` (X1); G1 says "prototypers", G3, P1, P2 and R1 only "prototype", none matches `-w`; the hit list is recorded and each hit matched to a block |
| AN-1 | G4 and G5 sit where the spec says | read `rules/global.md`, "Agent lifetimes" and "Agents carry names": G4 directly after the Writer entry and before "Second reviewer"; G5 directly after "Writer: Basia, Michał, Dorota." | as stated |
| AN-2 | P1, P2, R1 anchors | read `roles/planner.md` ("The spec", "Obligations") and `roles/reviewer.md`: P1 after "and the spec changes before any plan does." as its own paragraph; P2 continues the Obligations paragraph; R1 directly after the writer's-output bullet | as stated |
| FM-1 | the new role has the pin | `head -5 roles/prototyper.md` | front matter has `name: prototyper`, `model: sonnet`, the one-line description of the spec, no `tools:` line |
| DEC-1 | entries are first and newest first | `grep -n '^- 20' decisions.md | head -5` | the ui-prototype-track entry, then the fit/pictures proposal entry, then the fit-check entry... in the spec's order, all above the task-key entry |
| GATE-DIFF | the commit changes only the intended files and no other task's text | `git -C ~/knowledge show --stat <the feat commit>` | exactly `decisions.md`, `roles/README.md`, `roles/planner.md`, `roles/prototyper.md`, `roles/reviewer.md`, `rules/global.md`; `git diff <base>..<commit> -- rules/global.md` shows only G1 to G8 hunks (the task-key hunk is in the base) |
| CL-1 | the two proposals are closed as merges with the proposal as second parent | `git -C ~/knowledge log --merges -3 --format='%h %p %s'`; `git -C ~/knowledge merge-base --is-ancestor <branch> main` for both branches | two merge commits `proposal: ... integrated`; both is-ancestor exit 0 |
| CL-2 | the closing merges changed no tree | `git -C ~/knowledge diff <feat commit> HEAD --stat` | empty |
| CL-3 | the host will see nothing open | `bin/ai/ai-knowledge proposals --repo ~/knowledge` (run from dev-tools) | prints nothing (at review time exactly these two branches were open, all other `proposal/*` branches are already ancestors of main); `git -C ~/knowledge ls-tree main proposals/` lists only `README.md` |
| RN-1 | every role file would render | read `bin/ai/ai-knowledge`, `cmd_render` (loop over `os.listdir(roles)`, skip `README.md`, name from front matter) and confirm `roles/prototyper.md` has a front matter parsed by its regex `^---\n(.*?)\n---\n?(.*)$` (e.g. `python3 -I -c` applying that regex with `re.DOTALL`, as the renderer does, to the file) | match, `name` = `prototyper`, `description` non-empty |
| RN-2 | rendered copies exist (host-side, phase-level, user's batched check) | on the host: `ai-knowledge sync --all`, then `ls ~/.ai-sandbox/shared/knowledge/claude/agents/prototyper.md ~/.ai-sandbox/shared/knowledge/codex/agents/prototyper.toml`, and `grep -c 'Prototyper: Tosia' ~/.ai-sandbox/shared/knowledge/GLOBAL.md` | files exist; count 1. Marked phase-level and "cannot run here": the lead includes it in the closing report's list for the user; no task cites it beyond T5's hand-off |
| COV | the obligations cover the goal | read: G-a by V-G1; G-b by V-X1, FM-1, V-RM1, V-G2, V-G4, V-G5, V-G6, RN-1, RN-2; G-c by V-G8; G-d by V-P1, V-P2, V-R1; G-e by V-B, CL-1 to CL-3 | every goal item has a key; phase-level, run by the phase reviewer |
| NOMARK | no leftovers | `grep -rn 'AGENT-MARK ui-prototype-track' ~/knowledge`; `grep -rn '<landing date>' ~/knowledge/decisions.md` | both empty; phase-level |
| WORDS | the word ledger | `wc -w rules/global.md` before T1 (6301 at plan time) and after | the difference equals 392 (G1 +118, G2 +1, G3 +3, G4 +32, G5 +5, G6 +1, G7 +13, G8 +219); recorded in T1's evidence; if it differs, the implementer lists the cause (a block's line-wrapping does not change word counts; a difference means a typo or a moved block) |

T1 cites WORDS; WORDS is therefore a task obligation of T1, the rest of the "phase-level" marks above (COV, NOMARK, RN-2) are run by the phase review. The gate (the project's checks and suites outside CI) for this repository: the knowledge repository has none; the only checks are the obligations above. No other suite is relevant: `skills/process-report` tests belong to task-key and are untouched.

## Impact set

Searches run at `ed5e562` from `~/knowledge` unless noted; raw output goes to `impact-searches.md` (the implementer re-runs each unchanged and records the output).

1. Static references (roles enumerated in text): `grep -rn -w 'implementer, scout\|scout and writer\|scouts and writers\|runner, scout, writer\|Scout: \|Writer: ' rules roles skills README.md` returned 4 lines: `rules/global.md` Decomposition, `rules/global.md` context-lifecycle table row, `rules/global.md` Writer names (G5 anchor), `roles/README.md` model bullet. Writer lifetime entry found by `grep -n 'Writer' rules/global.md` (lines 169, 187). All four listed places are changed by G2, G6, G5, RM1; none other lists the roles. Category complete for rules and roles.
2. Role names in dev-tools (consumers outside the repository): `grep -n 'case "$role"' bin/ai/ai-delegate` (dev-tools) returns `scout|writer|second-reviewer`; the prototyper is deliberately not delegable (spec non-goal), so no change. `grep -rn 'Tosia\|Franek\|Julka' dev-tools --exclude-dir=.git --exclude-dir=.tmp -l` returned only the spec and its review evidence: the names are not used elsewhere. `grep -rn -i 'implementer.*scout.*writer' dev-tools/bin dev-tools/tests` returned nothing; `dev-tools:bin/ai/knowledge-seed/README.md` line 13 describes roles generically ("planner, implementer, reviewer, ...") and needs no change. Role names come from the agent type in `skills/process-report/SKILL.md` with no list (spec non-goals); not re-searched.
3. Names in strings and rendering: the renderer enumerates `roles/*.md` (`bin/ai/ai-knowledge`, `cmd_render`, verified by reading); `roles/README.md` is excluded by name. The role pins in front matter are read by Claude Code only; spec assumption verified. `model: sonnet` is the single new pin; the other pins are unchanged.
4. Outside the repository: rendered store and host agent links (`~/.ai-sandbox/shared/knowledge`, `~/.claude/agents/*.md` symlinks created by `wire_host`): reached only by the host's next sync (RN-2). Other projects' sandboxes read the new rules in their next session (knowledge-integrate, step 7). The coupling register of `PROJECT_MAP.md` in dev-tools has no entry for roles; unchanged.
5. Duplicated logic: the tier lists (Decomposition, README pin list, lifetime table) are the second copies of the role-tier rule; all three are changed (G2, RM1, G6). A search for the distinctive string `command runners on the cheapest` returned 1 (`rules/global.md`); `runner `haiku`` 1 (`roles/README.md`).
6. Reliance on an invariant: the context-lifecycle table assumes every non-implementer role has a 250k ceiling, which the prototyper adopts (G6); no search exists for this category.

Residue obligations: RS-OLD (old shapes of six blocks) and RS-NAMES. Additions (G4, G5, G8, P1, P2, R1, X1, Appendix B) have no old shape.

## The two proposal branches

Per `knowledge-integrate` step 6, with `-s ours --no-ff`, the message `proposal: <slug> integrated`, after the commit with the text (so the host deletes the branches), for `proposal/2026-11-07-fit-check-uses-element-boxes-a7c5` and `proposal/2026-11-08-ui-work-approved-on-pictures-verified-on-target-platform-128f`. Verified in planning: both are open (`ai-knowledge proposals` lists both), neither is an ancestor of main, each differs from main in one file under `proposals/` only (16 and 17 lines). Never check the branches out. If a plain merge happens by mistake, the skill's remedy applies (remove the file in a normal commit; never rewrite main). The decisions entries of Appendix B already carry both fates (four of six bullets integrated, gallery and lint rejected; fit check integrated). No other `proposal/*` branch is open (checked by `merge-base --is-ancestor` at review time: five are ancestors of main); the `proposals/*` branches are not touched.

## Deferred list

Empty at planning time; nothing folded, kept or dropped.

## Left out

- A guard against a concurrent commit by task-key's implementer on `rules/global.md`: no trigger beyond what the explicit-path commit and the clean-tree precondition already cover.
- Any run of `ai-knowledge render` in the sandbox: it cannot work here (missing `rsync`) and would write to the host's `~/.claude`; replaced by RN-1 and the host check RN-2.

## Unverified assumptions

- Inferred: the Appendix B date is the commit date; the user may replace the slot names Tosia, Franek, Julka before the commit (spec).
- Inferred: the placement rules for P1, P2 and the entries' order (this plan, "Contract"); the reviewer should confirm them.
- Inferred: task-key's implementer commits her `skills/process-report` changes before T4; if she has not, T4 waits.
- Guessed, not deciding feasibility: the host's `ai-knowledge sync --all` renders without a code change (spec: verified by reading the render loop; not run).
