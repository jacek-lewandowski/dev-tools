Task: 2026-11-09-ui-prototype-track

# Plan review, round 1 (Marta, reviewer 3)

Object: `docs/superpowers/plans/2026-11-09-ui-prototype-track-plan.md` (26c502e) against the spec and `~/knowledge` main. Verdict: accepted, no Critical or Important finding.

## Checked
- Old blocks G1, G2, G3, G6 (inline cell), G7, RM1: each occurs exactly once at `ae5436e` (current main; the plan was written at `ed5e562`). Script in the scratchpad (`chk.py`); the New texts count 0 now, as they must before landing. Anchors for G4, G5, G8, P1, P2, R1 exist once each.
- Every Appendix A block (G1 to G8, P1, P2, R1, RM1, X1) and Appendix B is carried by a task (T1 G1-G8, T2 X1/P1/P2/R1/RM1, T3 B) with a V-* key and a script that copies from the spec. COV maps each goal G-a to G-e to keys; no observable goal part is uncovered.
- WORDS: recomputed the ledger, global.md +392 (RM1 is README, its +1 is not in the 392); base 6301 confirmed.
- Impact searches: search 1 re-run unchanged, 3 lines in rules/README as recorded (the plan counts a fourth, the Writer-names line, which the pattern `Writer: ` matches there too; same places). No other role list in `rules/`, `roles/`, `skills/` outside process-report test fixtures (role names as data, no list). Renderer reading (`cmd_render`, `frontmatter`) matches RN-1. Residue RS-OLD sound (six Old blocks, count 0 after).
- Closing merges follow `knowledge-integrate` steps 2, 5, 6 (`-s ours --no-ff`, message `proposal: <slug> integrated`, branches never checked out). Explicit-path `git add` is stricter than the skill's `-A` and fine.
- Planner's assumptions: P1 and P2 placement is right (P1 after line 56 of `roles/planner.md`, P2 ends the Obligations paragraph at line 105); Appendix B date = commit date and entries above the task-key entry is right (decisions.md says newest first); task-key work is committed (`ae5436e`), tree clean, so the T4 precondition holds now.
- RN-2 routed to the user: adequate. The render needs `rsync` and writes to the host's `~/.claude`; the paths in RN-2 match `AI_KNOWLEDGE_RENDER=$AI_SANDBOX_ROOT/shared/knowledge`, and RN-1 plus the spec's verified loop prove that the role file would render. It must reach the user's batched list as the plan says.

## Lesser findings (applied to the plan by me, no decision needed)
1. CL-3 and the "two proposal branches" section claimed other open proposals remain ("five"). Only the two are open (`ai-knowledge proposals` lists exactly them; the other `proposal/*` are ancestors). After the merges the command prints nothing. Fixed expected result and sentence.
2. RS-NAMES: `grep -w prototyper` without `-i` misses G4 and G5 ("Prototyper:"), and G1 ("prototypers"), P1, P2, R1, G3 never match `-w`; the expected hit list was inexact. Fixed (`-i`, exact list).
3. DEC-1: `sed -n 15,60p` would not reach the task-key entry after three entries land; replaced with `grep -n '^- 20' decisions.md | head -5`.
4. RN-1: the renderer's regex needs `re.DOTALL`; stated.
5. Added a review-time note on the state of the tree (main `ae5436e`, clean).

## Not blocking, for the implementer
- GATE-DIFF base is `ae5436e`, not `ed5e562`; use the commit that is HEAD when T1 starts.
- Substring counts prove presence, not placement; AN-1/AN-2 cover placement.
