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
