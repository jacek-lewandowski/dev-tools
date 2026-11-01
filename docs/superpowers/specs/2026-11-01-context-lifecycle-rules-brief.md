# Brief: two rules for the knowledge repository (ask first yourself; context lifecycle per role)

Status: reviewed by Arek, round 1 (findings 1–6 fixed); approved by the user on 2026-11-01 with the thresholds 250k/350k (a mechanical value change, no re-review). Written by Ola (planner 3), 2026-11-01.

Class **brief** (text changes in `~/knowledge`, committed on `main` by this integrator sandbox; the host pushes on sync). One implementer, one diff review. Evidence file: `docs/superpowers/evidence/2026-11-01-context-lifecycle-rules.md`. Base: `~/knowledge` at `e71e42b`; every line number below was read there.

## Goal

`rules/global.md` makes every asker, the lead first, filter its own question before it reaches the user, and states in one bullet and one table what each role does as its context grows: the prepare threshold, the ceiling, the long-wait trigger, who acts. The three role files that speak of continuation match the table. `decisions.md` carries the rationale. No threshold sentence survives twice.

## Facts the brief rests on (verified unless marked)

- `rules/global.md:122-127` "Agent lifetimes" holds the 300k clause; `172-176` is the "Cache pays off" bullet; `179-181` the "Ask vs. assume" bullet; the file has no table today (`grep -c '^|' rules/global.md` → 0). `roles/planner.md`, `roles/implementer.md`, `roles/reviewer.md` already carry tables, pending the host's render check (decisions 2026-10-31, O6); the new table rides on that same check.
- Lifetime statements in the roles: `roles/implementer.md:61-63` (continued for a further task), `roles/runner.md:7-10` (continued within one milestone). `roles/planner.md` states none (`grep -n -i "continued\|retire\|alive" roles/planner.md` → empty).
- `decisions.md:11-13` fixes the entry format; entries are newest first under `## Entries` (line 15) and land in the same commit as the rule change (line 4-5).
- The renderer (`bin/ai/ai-knowledge`, `frontmatter`/`drop_tools_key`) copies a role file verbatim for Claude Code and drops only `tools:` for Gemini; `~/.claude/CLAUDE.md` is the host's render and changes only on `ai-knowledge sync --all`.
- Harness facts, as the lead checked them on code.claude.com (2026-11-01, *not re-fetched here*): a subagent compacts on its own window; the parent sees a token count at each stop; a subagent is reachable by name in its session and after `--resume`, never after `/clear`; compaction keeps the task and recent files and may lose early instructions; idle compaction starts from 200k tokens by default; the subagent prompt cache lives one hour here.
- The 70 % default comes from the supervisor design D-U3 (`2026-10-30-sandbox-supervisor-design.md:1480`), a percentage of the window read from the status line. The ceiling of 300k (decisions, context-ceiling) was set from contexts of 535k–768k, so the window in use is far above 300k and 70 % of it lies above the ceiling: a percentage of the window cannot be a prepare threshold below a ceiling of a few hundred k. The window is 1M: "Fable 5.1, Fable 5, Sonnet 5 and later, Haiku 5.5, and Opus 4.7 and later run with the 1M window by default" (code.claude.com/docs/en/model-config.md, "Extended context", read 2026-11-01).
- The second reviewer is not a subagent: `ai-delegate` runs it as one external agy call per round and round 2 continues round 1 by `--conversation <id>` (`~/.claude/CLAUDE.md`, sandbox section), so it has no context the lead measures and nothing to retire.

## Decisions this brief makes (the user may change them before approval)

- Thresholds, the user's call at approval (2026-11-01): prepare at **250k tokens**, ceiling **350k**; 250k is five sevenths of the ceiling. The ceiling thereby rises from the 300k of context-ceiling (2026-10-31); the brief had proposed 200k/300k. Stated once, in the new bullet. The sibling status-line brief (2026-11-01) must colour absolute token counts, not percentages: on the 1M window the two thresholds read as 25 % and 35 %.
- For the file-state roles (spec author, phase planner, brief writer, reviewer, runner, scout, writer) the prepare threshold is the ceiling: retiring them costs nothing beyond a fresh read of the files, so they go at the first stop past 250k and the 350k ceiling governs only the lead and the implementer. This narrows the context-ceiling decision of 2026-10-31 for those roles; C7 says so.
- The lead's handover boundary is the phase boundary, as the task statement says; a task boundary only when the lead is past the prepare threshold and a long wait follows.
- The lifetimes listed under "Agent lifetimes" stay and belong to the slot; the agent in it is replaced as the lifecycle rule says, under the same name (C2). The long-wait retirement does not cover the second reviewer (own table row).
- The table is placed unindented after the bullet, so it renders in every tool.
- The lead's handover path: the one the project names, else beside the evidence files (C3); the supervisor design names `.ai-supervisor/handover.md` and is still unapproved.
- A subagent's mid-task compaction stays the harness's; the brief sets no `autoCompactWindow:` in a role file (a config key, unverified here; a later small change if wanted).
- `roles/planner.md` gets one matching paragraph although it states no lifetime today, because the spec's author is the longest-lived subagent and the table retires it.

## Contract: the text as it lands

### C1 `rules/global.md`, the "Ask vs. assume" bullet (lines 179-181), replaced by

```
- **Ask vs. assume.** Ask when different readings of the request lead to
  materially different work, or when an action is 🔴. Otherwise decide, state
  the assumption, proceed. Before any question to the user, the asker, the
  lead included, runs the question through four steps:
  - Write it down with its candidate answers.
  - Check that its premise can occur at all under the project's data, rules
    and contracts; a question about a case that cannot arise is dropped, and
    the report says why.
  - Check whether the spec, the plan, the rules or the data already settle
    it; a settled question is answered from there, with the source named in
    the report.
  - When one candidate is clearly right, take it, record the assumption in
    the report, and do not ask.
  What survives is a genuine decision: ask it as a closed question, with the
  candidates and a recommendation.
```

### C2 `rules/global.md`, "Agent lifetimes" (lines 123-127), the second sentence replaced by

```
  agents per role. Before spawning, continue a live agent of that role whose
  unit of work is still open; spawn anew when it is closed, when the agent's
  reports show it has lost the thread, or when the context lifecycle rule
  retires it, and retire the one it replaces. The lifetimes listed below
  belong to the slot; the agent in it is replaced as the context lifecycle
  rule says, under the same name.
```

### C3 `rules/global.md`, the "Cache pays off" bullet (lines 172-176), replaced by this bullet and table

```
- **Context lifecycle: prepare at 250k, stop at 350k, act before a long
  wait.** Both thresholds count the agent's own context as the harness
  reports it: the lead's status line, a subagent's token count at each stop.
  Set the harness's subagent prompt-cache lifetime as long as it allows;
  assume an hour. Inside a review-and-fix loop keep agents continued rather
  than replaced.
  - A long wait is a pause expected to outlast the cache lifetime: a question
    to the user, the end of a work block, a task whose follow-up is not
    ready. An agent past the prepare threshold that ends its turn before a
    long wait acts now, on the warm cache, not after the return: the lead
    writes its handover, a subagent is retired. A continued subagent whose
    next use is a long wait away is retired at the end of its task, not kept.
  - The lead's `/clear` makes every subagent unreachable, so before it the
    lead asks each live implementer with an open task for its note and lists
    the live agents, their open units and their note paths in the handover.
  - The lead neither triggers nor waits for an implementer's mid-task
    compaction.

| Agent | Past 250k | Past 350k | Who acts |
|---|---|---|---|
| Lead | Writes its handover file (open units of work, live agents by name with their note paths, the next step) at the path the project names, else beside the evidence files, at the phase boundary, then `/clear`; before a long wait, at the current task boundary. | Handover and `/clear` at the end of the current turn. | The lead, from its status line; the user may call for it. |
| Implementer | Finishes the current task; at the task boundary writes a short note beside its evidence file, is retired and replaced in the same slot; the replacement starts from the brief, the plan and the note. | Retired at that stop, after its note. | The lead, from the token count at each stop. |
| Spec author, phase planner, brief writer, reviewer, runner, scout, writer | Retired at the next stop; a fresh agent in the same slot carries on from the files, under the same name. No note, no handover, no compaction. | Not reached: 250k is their ceiling. | The lead, from the token count at each stop. |
| Second reviewer | Outside this rule: each round is one external run, continued by its conversation id; nothing to retire. | The same. | Nobody. |
```

The following bullet (`- **PROJECT_MAP.md**`) starts a new list after the table; nothing else moves.

### C4 `roles/planner.md`, a paragraph after "write a plan another agent can execute without you." (line 7)

```
When you are continued for a later phase or a spec question, or replace a
retired planner in the same slot, start from the spec, the plan and the
deferred list as files, not from what you or your predecessor remember;
nothing of a planner's state lives outside them.
```

### C5 `roles/implementer.md`, a bullet after the one ending "since your last task." (line 63)

```
- When the lead retires you at a task boundary, because your context has
  passed the prepare threshold or a wait longer than the cache lifetime
  follows, first write a short note beside your evidence file, named like it
  with the suffix `-handover`: what is committed, what is uncommitted and
  where, the next step, the open findings. Your replacement starts from the
  brief, the plan and that note; when you are that replacement, read the
  note before you edit.
```

### C6 `roles/runner.md`, a sentence after "between runs." (line 10)

```
A runner retired for its context size is replaced in the same slot by one
that starts from those reports and logs, so write down what a successor needs.
```

### C7 `decisions.md`, two entries at the top of `## Entries`, each in the commit of its rule

```
- 2026-11-01 context-lifecycle-per-role integrated
  rules/global.md, roles/planner.md, roles/implementer.md, roles/runner.md:
  no proposal file; asked by the user on 2026-11-01. The ceiling of
  2026-10-31 context-ceiling said when an agent is retired, not what each
  role does as its context grows nor when the cache makes the moment matter.
  Facts (code.claude.com, 2026-11-01): a subagent compacts on its own window
  and the lead sees only a token count at each stop; compaction keeps the
  task and the recent files and may lose early instructions; a subagent is
  reachable by name in its session and after a resume, never after `/clear`;
  the subagent prompt cache lives one hour here. So roles whose state lives
  in files are replaced in the same slot with no handover; the implementer,
  whose state is a half-done task, compacts mid-task and is replaced at a
  task boundary after a note; the lead hands over by file and `/clear`,
  collecting the implementers' notes first because `/clear` strands them. The
  user's addition: a wait longer than the cache lifetime re-reads the whole
  context at full price on return only to summarise it, so an agent past the
  prepare threshold hands over or is retired before the wait, on the warm
  cache. The user set the values at approval: the ceiling rises from the
  300k of context-ceiling to 350k, and the prepare threshold is 250k, five
  sevenths of it. The supervisor design's "70 % of the window" (D-U3) cannot
  serve as the prepare threshold: the lead's model runs with a 1M window by
  default (code.claude.com model-config.md, 2026-11-01), so 70 % of it is
  700k, above the ceiling, and the contexts that set the old ceiling
  (535k–768k) confirm the window. For the file-state roles the prepare
  threshold is the ceiling, because retiring them costs only a fresh read of
  the files; the 350k ceiling governs the lead and the implementer. The lead hands
  over at the phase boundary, at a task boundary only before a long wait.
  The second reviewer, one external run per round continued by its
  conversation id, has no context the lead measures and stays outside the
  rule. Supersedes the "Cache pays
  off" bullet of 2026-09-19-agent-lifetimes-and-file-carried-context, whose
  two kept sentences moved into the new bullet, and the threshold clause of
  context-ceiling.
- 2026-11-01 asker-checks-its-own-question-first integrated
  rules/global.md: no proposal file; asked by the user on 2026-11-01. Many
  questions the leads put to the user were not decisions: a premise that
  cannot hold under the project's data, rules or contracts, or an answer the
  spec or the rules already settle; the supervisor design's "reverse review"
  (2026-10-30) was conceived to filter exactly these. The "Ask vs. assume"
  bullet now has the asker, the lead included, run that filter itself and
  ask only a genuine decision, as a closed question with a recommendation.
  Extends the bullet rather than adding a second one.
```

## Sentences removed (file, text, the grep that finds it today and must find nothing after)

- `rules/global.md:125-126` "or when its context, as the harness reports it at each stop, has passed 300k tokens": `grep -n "has passed 300k tokens" rules/global.md` (today: 126).
- `rules/global.md:172` "**Cache pays off within a loop, not across tasks.**": `grep -n "Cache pays off" rules/global.md` (today: 172).
- `rules/global.md:174-176` "Between tasks and phases the pauses usually exceed the lifetime; decide there on context and consistency, not on cache.": `grep -n "pauses usually exceed" rules/global.md` (today: 175).
- Moved, not removed (count stays exactly 1 after): `grep -c "assume an hour" rules/global.md`, `grep -c "keep agents continued rather than replaced" rules/global.md`.
- Nothing is removed from the roles or from `decisions.md`.

## Obligations (the brief's tests and acceptance), all run in `~/knowledge`, recorded in the evidence file with output and commit

- B1 Diff scope: `git diff --stat e71e42b..HEAD` names exactly `rules/global.md`, `roles/planner.md`, `roles/implementer.md`, `roles/runner.md`, `decisions.md`; `git diff e71e42b..HEAD` shows only the C1–C7 hunks, prose rewrapped to the file's width where a sentence grew and nowhere else.
- B2 Contract fidelity: each block lands verbatim (tables and bullets as written; only line wrapping may differ): `grep -c "runs the question through four steps" rules/global.md` → 1; `grep -c "Context lifecycle: prepare at 250k" rules/global.md` → 1; `grep -c '^|' rules/global.md` → 6; `grep -c "context lifecycle rule" rules/global.md` → 1; `grep -c "nothing of a planner's state" roles/planner.md` → 1; `grep -c "suffix .-handover." roles/implementer.md` → 1; `grep -c "write down what a successor needs" roles/runner.md` → 1; `grep -c "^- 2026-11-01 " decisions.md` → 2, both before the first `- 2026-10-31` line.
- B3 Residue: the three removal greps above → empty; the two moved-sentence counts → 1; `grep -n "300k\|200k" rules/global.md roles/*.md` → empty (the old clause is gone, the new text says 250k and 350k, and the C7 entry that names the old 300k lives in `decisions.md`, outside the search); `grep -n "250k\|350k" rules/global.md roles/*.md` → only lines of the C3 bullet and table (listed by number in the evidence file); `grep -rn "70 %" rules roles` → empty.
- B4 Commits: `git log --oneline e71e42b..HEAD` → exactly two, `feat(rules): the asker checks its own question before the user hears it` (C1 + its decisions entry) and `feat(rules,roles): context lifecycle per role, prepare at 250k and before a long wait` (C2–C6 + its decisions entry); `git status --short` empty; `git branch --show-current` → `main`.
- B5 Render note (read): the evidence file states that `~/.claude/CLAUDE.md` is the host's render and still shows the old text (`grep -c "Cache pays off" ~/.claude/CLAUDE.md` → 1 at task end), that the host must run `ai-knowledge sync --all` to push `main` and re-render, and that the table's rendering is confirmed by that render together with the roles' tables (decisions 2026-10-31, O6).

## Acceptance criterion

B1–B5 recorded with their output; after the two commits no sentence states a context threshold outside the C3 bullet and table, and `rules/global.md` reads as bullets with one table.

## After the change, on the host (user)

`ai-knowledge sync --all`: pushes `main`, re-renders `~/.claude/CLAUDE.md` and the role copies; running sandboxes read the new rules in their next session. Until then every lead works under the old wording.

## Open items for the user

- None. The one open item, the prepare threshold (proposed 200k or 210k), was closed by the user on 2026-11-01: 250k, with the ceiling raised to 350k.
