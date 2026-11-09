# Review of the process-report skill brief (Fiona, reviewer 1, 2026-11-09)

Class: brief review. Checked: task statement, brief, global rules, real transcripts under ~/.claude/projects/-home-jlewandowski-dev-public-dev-tools/.

## Spot-checks that hold
- Session 4256d730: 258 assistant lines, 140 distinct message.id, output sum 430 859 naive vs 190 297 deduplicated; last cost-state outputTokens 251 368. All as the brief states.
- Subagent layout (`<session>/subagents/agent-<id>.jsonl` + `.meta.json` with agentType, description, toolUseId, finished) true; first user line of a subagent carries "You are <Name>"; spawn tool is `Agent` in all 109 uses; versions 2.1.287 to 2.1.316 seen.
- Fixed headings, taxonomy (mockup/ui-*/mobile-ui separate), facts vs suggestions split, UI/UX section, fit/roles section: the report answers the task statement.

## Important
1. Period semantics undefined (Script section). Sessions here run for days (the dedup session spans many); the brief never says whether `--since/--until` select by session file, first line or per-line timestamp. Two projects will then report different windows for the same dates, and O4's "sessions in the period" is undefined. Resolve: filter each message/agent by its own timestamp, and state that in SKILL.md; add a fixture session straddling the boundary to O2/O3.
2. "Typed prompt" rule is wrong against real data (Script, user lines; O2). In the real session, non-meta string user lines also include `<command-name>/model`, `<local-command-stdout>`, `<pasted_content ...>`-prefixed text and "ok"; the brief excludes only `<task-notification>` and tool results, so slash commands and local-command echoes would be counted as rounds with the user. Also 186 `queue-operation` `enqueue` lines are typed prompts sent while an agent was busy (221 more are notifications); the brief does not say whether those reappear as `user` lines. Rounds with the user is the central UI/UX metric, so verify against the real file and extend the exclusion list (`<command-`, `<local-command-`) and the fixture; also restrict to `isSidechain == false`.

## Lesser (not blocking)
3. `cost-state` is a top-level `type`, not a `system` subtype (brief groups it with `system turn_duration`); 4 lines in the checked session, 18 of 21 sessions have one. A reader implementing from the brief may look in the wrong place; say "type cost-state".
4. cost-state covers the main session only (the brief infers this and O1 tests it), so "per session USD as recorded" excludes subagent cost; the cost table should say so in the output, otherwise cross-project USD is not comparable.
5. "per task where it can be attributed" (Cost table 3) has no method; either drop it or say the lead fills it from the evidence files and marks it `unknown` otherwise. Same for "time to first thing the user could look at": the script offers only `Artifact` publish times, which do not exist for React Native / dev-server work; say that other cases are the lead's reading, marked as such.
6. Default project dir derives from cwd by replacing `/` and `.` only. Worktrees (other cwd) and paths with other characters give other dirs; the script should fail loudly listing near-miss directories rather than report an empty period (the "empty period" line would hide a wrong dir). Add to O3.
7. `compactions` is listed in output but no transcript signal is named (`system` subtype `compact_boundary`, 1 seen); name it or drop it.
8. O1 asks to "explain the difference" between 190 297 and 251 368 (likely thinking tokens or subagent/other-model usage); fine, but the note should state which total the report prints as "output tokens", so the figure means the same everywhere.
9. O4 second half (copy under ~/.agents) and O8 listing imports via ast are more evidence than the risk needs; O7 grep and O10 `du` are two lines each, fine. Consider merging O6/O9/O10 into one read obligation. No obligation covers SKILL.md actually driving a lead end to end; one dry run of the skill on this project's last 7 days producing a report that passes `--check` would prove the goal better than O4 plus O5 separately.
10. Unnecessary for a user who dislikes overhead: the 8-heading template with a per-row 25-word limit and "at most seven suggestions" are guessed (the brief admits it); acceptable, but the Waste section repeats the 2026-10-31 three lists, the heaviest part of that round. Keep, since the task statement asks for it; the open questions are reasonable (recommendations 1 to 3 are sound).
11. Comparability across projects otherwise good: fixed taxonomy, script-produced numbers, `unknown` rule. Missing: a statement that `fit` and `kind` are the lead's judgement with a one-line definition of each fit value (`too heavy` against what: the class the task was given, by the rules' class definitions), else leads will vary.

## Verdict
Two Important findings (1, 2); a delta re-review after the brief is fixed.

## Round 2 (delta only)

Finding 1 (period): fixed. Per-line timestamps, agents likewise, straddling fixture in O2, O4 counts only meta files with a line in the period.
Finding 2 (typed prompts): fixed in substance. Exclusions now cover `<command-`, `<local-command-`, `<agent-message`, `<system-reminder`, `<task-notification`; main session only; the `queued_command` attachment with `origin.kind` human is counted. Spot-check: `2f29ba24` has one non-notification enqueue, with no matching `user` line and exactly one `queued_command` attachment with origin `{kind: human}`: claim true. The other attachments in `4256d730` have origin `task-notification` or `peer` and are correctly not counted.
Minor, wrong evidence claim: "6 of 6 in 4256d730" is not what the data shows. Those 6 enqueues are all `<agent-message from=...>` subagent hand-backs, not typed prompts; 5 reappear as `user` lines within 120 s, 1 only as a `peer` attachment. No typed queued prompt delivered later as a `user` line was observed. The dedup rule (same text within 120 s) is harmless and can stay, but the "checked" sentence should be reworded (for example "no typed case seen; hand-backs reappear as user lines and are excluded by prefix"). Not blocking.
Lesser findings 3 to 8, 10, 11: addressed (cost-state type, main_session_only label, compact_boundary, project-dir fail with near-miss list, fit definition, dry run O10). Nothing new found that blocks.

Verdict: round 2 closes with no Critical or Important finding.

## Round 3 (user delta: computed by the script, reviewer step)

Object: the added rules for task key, task rows, top five, repeated commands, per-UI-task figures, `--markdown`, `--check --stats`, the review step and the `Review:` line.

### Important
1. Task key does not work outside this project's doc layout, and the lead cannot repair it (Derived by rule, Task key; `--check`). The key exists only for a `<date>-<slug>` stem under `evidence|plans|specs|briefs`, and "no other linking is attempted". In a tracker project, where tasks are `#123` in commit subjects and prompts and plan files sit wherever the lead chose, most spawns and commits become `unassigned`. That is honest, but Work done and per-task cost then come out nearly empty, which defeats the report's main table. And because `--check` fails any script-filled cell that differs from the JSON, the lead has no way to correct or override a wrong or missing attribution; it may only say so in prose. Resolve with both: (a) a second key source in the same function, `#<n>` (or `GH-<n>`) found in commit subjects and spawn prompts, same most-frequent / `unassigned` rule, one fixture; (b) say in SKILL.md and the report's "Method and gaps" that the `unassigned` share is printed in the report header and, above a stated share (for example half of spawns), the Work done table is labelled "unreliable: most work unassigned" by the script. A lead-supplied key map is not needed; do not add one.
2. Plausible wrong figures with no visible marker in the report (the JSON labels exist, the report does not carry them):
   - Per-task tokens and cost cover subagents only; the lead's own tokens (usually the largest part, and the whole of a task done without agents) sit in no task. A column headed "tokens (output)" reads as the task's cost. Label the column "agents only" and print the lead's share as its own row, otherwise cross-project comparison is skewed toward agent-heavy tasks.
   - A commit touching a path of two keys is given to the alphabetically first key; a shared spec or a long-lived design path collects the commits and spawns of every phase into one "task". Mark such rows `ambiguous` in the cell, not only in the JSON.
   - Wall-clock "first spawn or commit to last activity" is inflated by any later touch of an old evidence file (a fix commit a week later); mark windows longer than, say, 48 h as `spans N days`, since a user reads it as working time.
   - `rounds_before_first_screenshot` has no stated value when there is no screenshot or it lies outside the window; it must print `none` (not 0), or the "no agent looked before the user" finding is read as "0 rounds".

### Lesser
3. Repeated commands: substring keywords (`test`, `build`, `lint`, `npm`) also match `git commit -m "add test"`, `grep test`, `ls tests/`; same cwd is not same commit, so a re-run after an edit counts as a repeat; and two agents re-running one check is often what the plan's obligations require (reviewer re-runs). The list is labelled "facts" under Waste; label it in the report "candidate repeats, not verified waste", and match the first word(s) of the command rather than a substring.
4. `Class:` regex and `O<n>` counts are this project's plan format. They degrade honestly to `unknown`, but then the column is empty in every other project and the "class given" vs `fit?` comparison, the point of the report, is lost. Cheap fix: `unknown` is fine; do not add more formats. Consider dropping the `O<n>` / evidence-count columns (reviewer-rerun count was in the 2026-10-31 prompt but nothing in the user's two remarks needs it).
5. Usage line of the script was not updated: it lacks `--markdown PATH` and `--stats JSON`; SKILL.md step 1 says the script writes JSON to `.tmp/...` while the script prints JSON to stdout (redirection is not stated).
6. `--check` comparing each script-filled cell requires an exact, stable rendering (number formats, rounding, empty cells); name one formatting function used by both `--markdown` and `--check` so they cannot drift, and include in O5 a case with a hand-reformatted but equal number (for example 1,234 vs 1234) deciding which way it goes.
7. Word budget: the skeleton alone (up to 15 rows with about ten script columns, two cost tables, two waste tables) may approach 1 500 words before any prose, so a correct report could fail `--check`. O10 should record the skeleton's word count on real data; if it exceeds about 900, reduce the row cap or columns, not the prose budget.

### (c) Reviewer step
Runnable: who (lead), what agent (fresh `reviewer`, cheaper tier), what it gets (report, JSON, cited sources), the three questions, a two-round limit and the `Review:` line are stated; cost is bounded by two rounds on a 1 500-word report. Gaps: "cited sources" is unbounded, so say the reviewer may sample (for example check every Suggestion and every figure in the Waste lists, and ten other cells) rather than re-read every evidence file; the `Review:` line is self-attested and `--check` can verify its format only (state that); O10 correctly admits step 4 is unproved until first use, which is acceptable for a reviewer step that is plain text.

### (d) Proportion
The user's two remarks justify the computed tables, `--markdown`, the strict `--check` and the review step. Beyond them: `O<n>`/evidence-file counting, the `Class:` regex, the per-role "reviewer spawns" and the near-miss directory listing add parsing and fixtures without serving either remark (near-miss listing came from round 1 and is small). The script is now roughly the size of two tasks (transcript reader, git reader, task derivation, markdown emitter, report checker); for one implementer in one pass it is at the upper edge, not past it, provided finding 1 is solved by one more regex rather than a mapping facility, and the O<n>/evidence columns are cut. The brief itself is 3 400 words, long for a brief; the task statement's own concern about overhead applies to the brief, so after the fixes tighten, not extend, it.

### Verdict
Two Important findings (1, 2); a delta re-review after the fixes. Everything else is lesser and does not reopen the round.

## Round 4 (whole brief after the rewrite)

Earlier Important findings: all fixed and still present after the tightening.
- Per-line timestamp period, `--until` inclusive, straddling fixture (O2): present.
- Round count: exclusion prefixes, `isSidechain` false, human `queued_command` attachment, 120 s de-duplication, the 6-of-6 wording corrected: present.
- Dedup by `message.id` with the known-case fixture and the second-source check (O1), `cost-state` as `main_session_only`, `compact_boundary`, fail-loud project dir with near misses (O3): present.
- Round 3: `#<n>`/`GH-<n>` second key source, `unassigned` share in the header and `unreliable` label above half, `agents only` column plus the lead's final row, `ambiguous`/`spans N days`/`overlap` markers, `none` instead of 0, candidate-repeats label with first-word matching, one cell formatter, word count of the skeleton recorded in O10, reviewer sampling, O<n> columns cut: all present. Report sections, the eye-judged section, the fit definitions and the reviewer step with the `Review:` line are intact.

### Important (one, small)
1. The new `#<n>` source (Task key (b)) is applied to spawn prompts as well as commit subjects. In the UI/UX projects this report is meant for, prompts routinely contain CSS colours (`#333`, `#1a2b3c`, `#fff`) and anchors, which would become task keys; "most frequent key in the prompt" can then pick a colour, a wrong attribution with no marker (the row looks like a task `#333`). Resolve: take `#<n>` from prompts only when it is preceded by `issue`, `PR` or `GH`, or restrict it to commit subjects and to numbers that also occur in a commit subject in the period; add one fixture with `#333` in a prompt that must stay `unassigned`. (Also state that a prompt carrying both a path key and `#<n>` counts both kinds in the same frequency tally, or that path keys win.)

### Lesser
2. "Lead's tokens = session totals minus all agents" is computed from main-session assistant lines, not from `cost-state` (which has no per-session token split); say so in the row's footnote so it is not read as USD-derived.
3. The brief is now 2 600 words; acceptable for a brief with ten obligations, no further tightening needed.

### Verdict
Round closes with one small Important finding (1); the fix is a one-line rule plus a fixture and needs no further review round, only a check by the lead that the sentence and fixture are in the brief. Nothing else blocks.
