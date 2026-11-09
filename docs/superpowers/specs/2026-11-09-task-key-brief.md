# Brief: explicit task key (2026-11-09-task-key)

Task: 2026-11-09-task-key
Class: brief
Evidence file: `/home/jlewandowski/dev/public/dev-tools/docs/superpowers/evidence/2026-11-09-task-key.md`
Repository: `~/knowledge` (rules, skill script, tests, decisions). Refactor flag: none.
Written by Bartek (planner 2). Not a spec change: no goal, invariant or contract of an existing spec moves; the rule is an addition.

## Goal

The process-report script can assign every spawn and commit of a task to that task, and read its class, in any project, because the rule says how a task is keyed. Unassigned share in the 2026-11-09 reports (omega-psir 203/203 spawns and 227/227 commits, ukf 210/210 commits, analogiesio 36/36 spawns, nodespool 163/487 commits, class `unknown` on every nodespool row) goes to zero for tasks that follow the rule.

Premise (decided by the lead): an explicit, tool-neutral key convention in `rules/global.md`; the script reads it first and keeps today's heuristics as the fallback for history.

Verified cause: `PATH_KEY` matches only `evidence|plans|specs|briefs/YYYY-MM-DD-slug`; `ISSUE` matches only `#n` and `GH-n` and `spawn_key` accepts an issue only if it appears in a commit subject (`known_issues`); `class_index_of` reads `Class:` only from `*-brief`/`*-plan` files under `plans|specs|briefs`. Observed keys that none of this matches: `OMDEV-n`, `quality-impl/<tool>/evidence.md`, `evidence/phase-N/`, `p1-T5`. `rules/global.md` names no task key (grep `Task:` finds nothing).

## Target files

1. `~/knowledge/rules/global.md`, §2, bullet "Every task has a class" (line 35): append the rule below to it. No new section, no other clause changed.
2. `~/knowledge/decisions.md`: one entry at the top of "Entries", format of the file, rationale (the four reports, unassigned figures, why a trailer and a spawn line).
3. `~/knowledge/skills/process-report/scripts/transcript_stats.py`, section "task keys" (`spawn_key`, `commit_key`, `class_index_of`, `git_commits_of`, `assign_commits`'s use of `commit_key`; callers in `collect`).
4. `~/knowledge/skills/process-report/scripts/test_transcript_stats.py`: new cases.
5. `~/knowledge/skills/process-report/SKILL.md`: one or two sentences saying keys come from the `Task:` line/trailer first, then the old heuristics (body stays under 500 words; it was 497 on 2026-11-09, so trim an equal amount). Update the reads-outside comment at the top of the script for the new line kinds.

## Rule text to land (contract, reviewed as written)

Append to the "Every task has a class" bullet:

> Every task has one key, set when its class is: the tracker id where a
> tracker holds the task, otherwise the `YYYY-MM-DD-slug` stem of its brief,
> plan or evidence file. A phase has one key, its plan's stem or its tracker
> id; every task of the phase, every agent spawned for it (planner,
> implementer, reviewer, runner) and the gate commit carry that same key. The
> file that states the task starts with a `Task: <key>` line and a
> `Class: small|brief|phase` line; a task that lives only in a tracker carries
> the `Class:` line as a trailer of its first commit. Every commit of the task
> has a `Task: <key>` trailer, and every message that spawns or continues an
> agent for it has a `Task: <key>` line right after the name line. A commit or
> spawn that serves no task has no `Task:` line.

Operative sentences only; rationale goes to decisions.md. The name line stays the first line ("Agents carry names" is unchanged).

## Script behaviour

How the lines are read (verified on real files):
- Spawn: main-session transcript, `type: assistant` line, `message.content[]` block `type: tool_use`, `name: Agent`, `input.prompt` (keys `subagent_type`, `description`, `prompt`); verified in `~/.claude/projects/-home-jlewandowski-dev-public-dev-tools/4256d730-c936-45ca-9d59-929c2ad58735.jsonl`, whose prompt begins `"You are Fiona, reviewer 1. Open your report with that name.\n\n..."`. The script already stores it as `spawn["prompt"]`. A continued agent's later prompts and an unmatched agent's first prompt come from `acc.first_prompt` (subagent transcript's first `type: user` entry, `message.content`, verified in `.../subagents/agent-abcd45e7fc9fa326d.jsonl`); later prompts arrive as `isMeta` coordinator entries and are already split by `prompt_title`/segments.
  Read rule: the first line of the prompt text matching `^Task:[ \t]*(\S+)[ \t]*$` (multiline, whole prompt, so it survives the name line, a blank line and the coordinator preamble). That is the key.
- Commit: git trailer `Task`, read in `git_commits_of` with one more `%(trailers:key=Task,valueonly,separator=%x1e)` field next to the existing Co-Authored-By one (git's own parser, so only a real trailer block counts); same for `Class` (stored as `c["class"]`). Several distinct `Task` trailers: lexically first key and `ambiguous`, as today.
- Class: a file ending `.md`, outside `SKIP_DIRS`, whose first 200000 bytes hold a line `^Task:[ \t]*(\S+)` and a `CLASS_RE` match gives `idx[key]`; the old `*-brief`/`*-plan` path rule stays as the fallback (`setdefault`, explicit wins). For a key with no file, the `Class` trailer of the earliest commit with that key. Otherwise `unknown`, as today.
- Key shape: the rule names two shapes, a tracker id (`OMDEV-5600`, `#12`) or a `YYYY-MM-DD-slug` stem; a phase has one key and per-task cost inside a phase is out of scope. The script accepts any non-space token for history (`p1-T5` in analogiesio stays one row). Every explicit key, from a spawn line, a commit trailer or a file's `Task:` line, goes through `strip_suffix` (a no-op for ids), and the class index stores the same stripped key, so a brief, a plan and their evidence collapse to one row and one class lookup.
- Signature change: `class_index(repos)` has no commits; it becomes `class_index(repos, commits)` (called in `collect` after `git_commits`), reading the `Class` trailer of the earliest commit per key from `commits`; `class_index_of(repo)` is unchanged apart from the explicit-`Task:` file rule.
- Order: explicit key first; if absent, today's path/issue heuristics unchanged; then today's by-time trailer match unchanged. `known_issues` gating applies only to the heuristic.

Tests (write first, red on base, then green; follow the `Proj`, `commit`, `git` helpers in the test file):
- T1 spawn with `Task: OMDEV-1` as line 3 after name line keys that spawn and its agent, with no matching commit subject.
- T2b commit with a `Task: X` trailer and a differing path key (touches `plans/2026-11-02-y-plan.md`) or `#5` subject: key is `X`, not ambiguous.
- T2 spawn prompt with both `Task: X` and a `plans/2026-11-02-y` path: explicit wins.
- T3 commit with `Task:` trailer and no path/subject hint is keyed; commit with two different `Task` trailers is `ambiguous`.
- T4 a `Task:` text in the commit body that is not in the trailer block is ignored.
- T5 file `evidence/phase-1/notes.md` with `Task: 2026-11-09-phase-one` and `Class: phase`, plus a spawn (reviewer) and a gate commit carrying that same key, give one row `2026-11-09-phase-one` with class `phase`, both counted; a file stem `2026-11-09-phase-one-plan` as `Task:` value collapses to the same row; a tracker-only key gets its class from the `Class` trailer of its first commit.
- T6 old shapes still key as before (existing tests stay green unchanged, plus one explicit fallback case: no `Task:` anywhere, path key and `#n` key as today).
- T7 continued-agent later prompt carrying its own `Task:` line is keyed by it.

## Obligations

- O1 Rule text: `grep -n "Task: <key>" ~/knowledge/rules/global.md` shows the bullet; read lines 35-60 to confirm the text equals the block above and that no other clause changed (`git -C ~/knowledge diff --stat rules/` shows only `rules/global.md`).
- O2 Red then green: the new tests fail on the base (`python3 -m unittest test_transcript_stats` in `skills/process-report/scripts`, failures named) and the whole module passes after (existing 48 tests plus new; expected `OK`).
- O3 Lint: pinned ruff 0.17.3 (venv in the scratchpad as in the 2026-11-09 evidence): `ruff check --no-cache .` and `ruff format --no-cache --check .` clean.
- O4 Fallback unchanged: run the script on the same window before and after on this repository (`--git dev-tools --git ~/knowledge --since 2026-11-09 --until 2026-11-09`), before commit (1) lands (the two commits carry `Task:` trailers and fall in the window, so a later run differs by exactly their row); the JSON work table is identical (diff empty), since no earlier commit carries `Task:`.
- O5 Real data: on a temp git repo with three commits (two `Task: A`, one none) and a synthetic transcript spawn with `Task: A`, the row `A` shows 2 commits and the spawn; unassigned shows 1. Record the command and rows.
- O6 SKILL.md body under 500 words (`awk` count excluding front matter, as in the 2026-11-09 evidence) and `golden-skeleton.md`/`good-report.md` fixtures still pass `check_report` (covered by O2).
- O7 `decisions.md` has the entry in file format, in the same commit as the rule (`git -C ~/knowledge show --stat <commit>` lists both).
- Residue: none; an addition, old heuristics kept on purpose (history).

Impact set: `spawn_key`/`commit_key`/`class_index*` are module-internal; grep `rg -n "spawn_key|commit_key|class_index|known_issues" ~/knowledge --glob '!*.pyc'` must list only `transcript_stats.py` and its test (implementer records the count). Outside the repository: process reports in `dev-tools/.tmp` are unaffected (generated). Projects adopt the rule by reading rules; no migration of their history.

## Commits

Two: (1) rule + decisions entry; (2) script + tests + SKILL.md. Trailer on both: `Task: 2026-11-09-task-key`. Conventional Commits, `Co-Authored-By` per the session reminder.

## Stays out

- Tracker reads, backfilling old history, rewriting commits.
- Any change to the issue-tracker-workflow skill, roles, or "Agents carry names".
- Enforcing the key by a hook or check; the report's unassigned row is the signal.
- Renaming the heuristics or removing them.

## Question for the user (closed)

Q1. Tracker-only tasks have no file for a `Class:` line. Options: (a) a `Class:` trailer on the task's first commit, as written above; (b) class stays `unknown` for them. Recommendation: (a), a one-line cost that makes omega-psir (OMDEV-n) measurable. If (b), drop the trailer sentence from the rule and the tracker-class part of the script and T5.

## Not verified

- Whether every sandbox renders `rules/global.md` with a size check (README mentions no limit; not run). The implementer reads `~/knowledge/README.md` for a render or word-count check before committing.
- Adoption: projects whose agents ignore the rule stay unassigned; the report shows that.
