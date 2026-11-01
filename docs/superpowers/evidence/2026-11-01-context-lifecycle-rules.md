# Evidence: two rules for the knowledge repository (context lifecycle, ask first yourself)

Brief: `docs/superpowers/specs/2026-11-01-context-lifecycle-rules-brief.md`. Base `~/knowledge` `e71e42b`.

## Brief review, round 1

Arek, reviewer 2. Verified at `e71e42b`: every cited line holds the quoted text (global.md 122-127, 172-176, 179-181; planner.md 7; implementer.md 63; runner.md 10); the three removal greps each find exactly one line (126, 172, 175); the two moved-sentence counts are 1 today; `grep -c '^|' rules/global.md` is 0; `grep -rn "70 %" rules roles` is empty; `grep -n -i "continued\|retire\|alive" roles/planner.md` is empty; decisions.md format and newest-first order as cited; the harness claims in C3 and C7 match the task statement; `grep -c "Cache pays off" ~/.claude/CLAUDE.md` is 1; the brief is 181 lines. The class fits (text, two commits, no contract) and the evidence file is named.

### Important

1. **C2/C3 vs. the "Agent lifetimes" sub-bullets that stay (global.md 128-150).** "Alive from the spec to the last phase", "every spec question goes to the same agent", "A second round continues the same reviewer; it is not a new one", "Second reviewer: continued for the second round", "Runner: continued for every suite run", "Writer: alive until its output is accepted" are retained unchanged, while C3 retires every one of these agents at the next stop past 200k and, unconditionally, at the end of a task when the next use is a long wait away (a fix round after the user's approval nearly always is). The removed sentence "decide there on context and consistency" was what reconciled them; nothing replaces it. Fix: one sentence in C2 after "retire the one it replaces": the lifetimes listed below belong to the slot, and the agent in it is replaced as the context lifecycle rule says, under the same name. Say also whether the long-wait retirement covers the second reviewer, whose round 2 is an agy conversation id, not a cached subagent.

2. **A decision the user does not see.** The table makes 200k the effective ceiling for seven roles ("Retired at the next stop"; the 300k column says "The same"), so "stop at 300k" governs only the lead and the implementer, and the context-ceiling decision of 2026-10-31 is narrowed, not refined. "Decisions this brief makes" and the C7 entry are silent on it; so is the lead's handover "at the next task or phase boundary" where the task statement said phase boundaries. Fix: add both to "Decisions this brief makes" and one sentence to C7 (for file-state roles the prepare threshold is the ceiling because retiring them costs nothing), or keep those roles to 300k.

### Lesser

3. **Open item "table placement" is not a decision.** C1 itself says a question with one clearly right candidate is taken and recorded. Decide unindented, drop the item; B2's `grep -c '^|' → 5` then stops depending on the answer (indented would give 0). The threshold item (200k vs. 210k) is genuine: it overrides the user's stated 70 % default.

4. **Lead row, C3: "writes its handover file" names no path.** The brief's decisions say "the project names the path", but global.md will not, so a lead in a project without one has no rule. Fix: "at the path the project names, else beside the evidence files".

5. **C3 third sub-bullet is half fact.** "it keeps the task and the recent files" is rationale (already in C7); keep only "the lead neither triggers nor waits for an implementer's mid-task compaction" (style: operative sentences in global.md).

6. **The 70 % argument is sound but indirect.** Under a 1M window 70 % is 700k, above the 300k ceiling, so no percentage of the window can be a prepare threshold below it; the brief infers the window from observed 535k–768k contexts rather than stating it. State the window (1M) in C7 if the lead confirms it, and note that the status line's percentage reads 20 % and 30 % at the two thresholds, so the sibling brief must colour absolute counts, as the brief already asks.

Verdict: blocked on 1 and 2; both are one-sentence fixes in C2, C7 and the decisions section. Delta re-review after the fix.

## Brief review, round 2

Arek, reviewer 2. Delta only: C2, C3 (bullet and table), C7, "Facts", "Decisions this brief makes", "Open items", B2.

- Finding 1 (sub-bullets vs. lifecycle rule): closed. C2's added sentence makes the listed lifetimes the slot's; the second reviewer has its own row ("Outside this rule ... continued by its conversation id") and the "Facts" bullet names the source (`ai-delegate`, `--conversation <id>`). The long-wait sentence in C3 now has no agent it contradicts.
- Finding 2 (hidden decisions): closed. "Decisions this brief makes" and C7 both state that 200k is the ceiling for the seven file-state roles and that 300k governs the lead and the implementer only, naming the narrowing of context-ceiling; the lead's boundary is the phase boundary, a task boundary only past 200k before a long wait, consistently in the decisions section, the Lead row and C7.
- Finding 3 (table placement): closed, decided unindented; B2's `^|` count is 6 and matches the four-row table.
- Finding 4 (handover path): closed, Lead row names "the path the project names, else beside the evidence files".
- Finding 5 (fact in the operative bullet): closed, the third sub-bullet is the operative clause alone.
- Finding 6 (window): closed; 1M cited from code.claude.com model-config.md with the quoted sentence, C7 carries 70 % = 700k, the decisions section carries the absolute-count note for the status-line brief. The citation is the lead's fetch; not re-fetched here.

New findings from the fixes: none blocking. Lesser: C7's "Supersedes the "Cache pays\n  off" bullet" is a wrap artifact of the edit; B1 already allows the implementer to rewrap it to the file's width, so no brief change is needed.

The one open item (200k vs. 210k) is a genuine decision, since it overrides the user's stated 70 % default, and it is the only one.

Verdict: no Critical or Important finding; the brief is accepted as reviewed and goes to the user.

## Implementation evidence

Zuzia, implementer 1, 2026-11-01. All commands run in `~/knowledge` (branch `main`, base `e71e42b`). The C1–C7 blocks were extracted from the brief file by a script (`apply_brief.py`, scratchpad, not kept) and inserted unchanged; the script's word-sequence check reported every block MISSING on the base and OK after each stage (method checked on the known negative case). The only rewrap: the C7 wrap artifact the round-2 review allowed (`the files; the 350k ceiling ... context-ceiling.`, refilled at width 79, word sequence asserted identical). One blank line was added after the table so it terminates before the `- **PROJECT_MAP.md**` bullet (layout only, inside the C3 hunk).

Commits: `a4a7343` `feat(rules): the asker checks its own question before the user hears it` (C1 + asker-checks entry); `dd91d76` `feat(rules,roles): context lifecycle per role, prepare at 250k and before a long wait` (C2–C6 + context-lifecycle entry). The pre-commit hook (role `integrator`) accepted both.

- B1 Diff scope. `git diff --stat e71e42b..HEAD` →
  ```
   decisions.md         | 41 +++++++++++++++++++++++++++++++++++++++++
   roles/implementer.md |  7 +++++++
   roles/planner.md     |  5 +++++
   roles/runner.md      |  2 ++
   rules/global.md      | 51 ++++++++++++++++++++++++++++++++++++++++++---------
   5 files changed, 97 insertions(+), 9 deletions(-)
  ```
  `git diff e71e42b..HEAD | grep '^diff --git\|^@@'` → six hunks: `decisions.md @@ -14,6 +14,47` (C7, two entries), `roles/implementer.md @@ -61,6 +61,13` (C5), `roles/planner.md @@ -6,6 +6,11` (C4), `roles/runner.md @@ -8,6 +8,8` (C6), `rules/global.md @@ -122,9 +122,10` (C2), `rules/global.md @@ -169,16 +170,48` (C3, the "Cache pays off" bullet replaced by the bullet, a blank line, the table, a blank line; C1 lands in the same hunk, 3 lines replaced by 15). Read in full before each commit; no other line changed. Commits `a4a7343`, `dd91d76`.
- B2 Contract fidelity. `grep -c "runs the question through four steps" rules/global.md` → 1; `grep -c "Context lifecycle: prepare at 250k" rules/global.md` → 1; `grep -c '^|' rules/global.md` → 6; `grep -c "context lifecycle rule" rules/global.md` → 1; `grep -c "nothing of a planner's state" roles/planner.md` → 1; `grep -c "suffix .-handover." roles/implementer.md` → 1; `grep -c "write down what a successor needs" roles/runner.md` → 1; `grep -c "^- 2026-11-01 " decisions.md` → 2, at lines 17 (context-lifecycle-per-role) and 49 (asker-checks-its-own-question-first), the first `- 2026-10-31` at line 58. Commit `dd91d76`.
- B3 Residue. `grep -n "has passed 300k tokens" rules/global.md` → empty (exit 1); `grep -n "Cache pays off" rules/global.md` → empty; `grep -n "pauses usually exceed" rules/global.md` → empty; `grep -c "assume an hour" rules/global.md` → 1; `grep -c "keep agents continued rather than replaced" rules/global.md` → **0, not 1**: the C3 contract text, as approved, wraps that sentence over lines 177–178 (`...keep agents continued rather` / `than replaced.`), so the brief's single-line grep cannot match its own block. The sentence is present exactly once: `tr '\n' ' ' < rules/global.md | tr -s ' ' | grep -o "keep agents continued rather than replaced" | wc -l` → 1. Decided (C1): the contract stays as reviewed rather than being rewrapped ragged to satisfy the grep; the newline-tolerant check is the one to re-run. `grep -n "300k\|200k" rules/global.md roles/*.md` → empty; `grep -n "250k\|350k" rules/global.md roles/*.md` → `rules/global.md:173` (the C3 bullet's first line), `:191` (table header), `:195` (file-state roles row); the C3 bullet is lines 173–189, the table 191–196; `grep -rn "70 %" rules roles` → empty. Commit `dd91d76`.
- B4 Commits. `git log --oneline e71e42b..HEAD` → `dd91d76 feat(rules,roles): context lifecycle per role, prepare at 250k and before a long wait`, `a4a7343 feat(rules): the asker checks its own question before the user hears it`; `git status --short` → empty; `git branch --show-current` → `main`. Trailer on both: `Co-Authored-By: Zuzia (Claude Fable 5.1) <noreply@anthropic.com>`. Not pushed, not fetched.
- B5 Render note. `~/.claude/CLAUDE.md` is the host's render and still shows the old text: `grep -c "Cache pays off" ~/.claude/CLAUDE.md` → 1 at task end. The host must run `ai-knowledge sync --all` to push `main` and re-render `~/.claude/CLAUDE.md` and the role copies; until then every lead reads the old wording. The new table in `rules/global.md` renders through the same path as the roles' tables, so its rendering is confirmed by that render together with theirs (decisions 2026-10-31, O6).

Acceptance: B1–B5 recorded; after the two commits the only context thresholds outside `decisions.md` are in the C3 bullet and table (`250k|350k` at lines 173, 191, 195 of `rules/global.md`; `roles/implementer.md` names "the prepare threshold" without a number, as C5 says), and `rules/global.md` reads as bullets with one table (`grep -c '^|'` → 6).

## Diff review, round 1

Marta, reviewer 3, 2026-11-01. Object: `~/knowledge` `a4a7343`, `dd91d76` on `main`, base `e71e42b`; read the full diff and `rules/global.md` 118–215, `decisions.md` 1–60 in context.

Checks re-run in `~/knowledge`:

- Contract fidelity, word for word: a script normalised whitespace in each of the brief's C1–C7 blocks and searched the landed file; all seven present exactly once in word sequence (C7 refilled at width 79, words identical) and all seven absent at `e71e42b` (the known negative). No word changed.
- B2: `four steps` 1, `prepare at 250k` 1, `^|` 6, `context lifecycle rule` 1, planner 1, `-handover` 1, runner 1, `^- 2026-11-01 ` 2 at lines 17 and 49, first `- 2026-10-31` at 58. All match the evidence.
- B3: the three removal greps exit 1; `assume an hour` 1; `keep agents continued rather than replaced` single-line 0, newline-tolerant 1 (line 177–178); `300k\|200k` in rules and roles empty; `250k\|350k` only at `rules/global.md:173,191,195`; `70 %` empty. A wider search (`continu|retire|alive|compact|/clear|cache|handover|lifetime` over `rules`, `roles`, `skills`) finds no other sentence stating a threshold, a lifetime or a cache rule; `rules/global.md:115-116` and `roles/second-reviewer.md:16` agree with the new bullet.
- B4: two commits with the brief's exact subjects, `a4a7343` = C1 + asker entry (decisions.md +9, global.md +14/−1), `dd91d76` = C2–C6 + lifecycle entry; trailer `Co-Authored-By: Zuzia (Claude Fable 5.1)` on both; status clean, branch `main`. Nothing outside the five files changed.
- B5: `grep -c "Cache pays off" ~/.claude/CLAUDE.md` → 1; the render note reads as the brief asks.
- `decisions.md`: both entries follow the `- YYYY-MM-DD <name> integrated` / indented `<targets>: <why>` shape, sit first under `## Entries`, newest first (lifecycle above asker, matching commit order); no new line over 79 columns outside the table rows, which follow the roles' own unwrapped-table convention.
- Context read: the "Agent lifetimes" sub-bullets (spec author alive to the last phase, reviewer's second round continues the same reviewer, runner continued per milestone, second reviewer continued for round 2) are reconciled by C2's slot sentence and the second reviewer's own table row; the blank line after the table is layout the bullet list needs and is recorded.

### Blocking

None.

### Lesser

1. **B3 deviation, `rules/global.md:177-178`, acceptable as recorded; no rewrap.** The brief's single-line grep cannot match its own C3 block, which wraps the sentence; B1 forbids rewrapping where no sentence grew, and a ragged line 177 would serve only the grep. The newline-tolerant count (1) proves the obligation's claim that the sentence moved and exists once. The defect is the brief's check, not the text; the evidence records the command to re-run, which is enough.

Verdict: no Critical or Important finding; the diff is accepted as reviewed. The host's `ai-knowledge sync --all` remains the user's step (B5).
