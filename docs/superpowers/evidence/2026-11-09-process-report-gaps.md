# Evidence: process-report gaps (2026-11-09)

Two small changes in ~/knowledge/skills/process-report, one commit each. Ruff 0.17.3 (pinned) from a venv in the scratchpad.

## 1. Repeatable --git (commit dffc87c)

Red (tests written first, baseline 41 tests OK): `python3 -m unittest test_transcript_stats` -> `ERROR: test_cli_git_flag_repeats`, `ERROR: test_git_is_repeatable_and_the_report_names_the_repositories`, `FAIL: test_continued_agent_is_split_at_each_later_prompt`, `Ran 44 tests ... FAILED (failures=1, errors=2)` (the third is change 2, committed separately).
Green: `Ran 43 tests in 1.230s / OK`; `ruff check --no-cache .` -> `All checks passed!`; `ruff format --no-cache --check .` -> `4 files already formatted`. Golden and good-report fixtures changed from "git log read." to "git log read from repo."; SKILL.md body 496 words (<500).
Real check: `--git dev-tools --git ~/knowledge --since 2026-11-09 --until 2026-11-09` -> `git_repos ["dev-tools","knowledge"]`, `lead.commits 44`, git_error null. dev-tools alone: 28; `git -C ~/knowledge log --branches --no-merges --since=2026-11-09T00:00 --oneline | wc -l` = 16; 28 + 16 = 44. (The report excludes merges, as before; `git log --since` without `--no-merges` gives 20 here, 4 of them the ours-merges of the proposals.) Header line: "Read 1 sessions and 44 agent transcripts; git log read from dev-tools, knowledge."

## 2. Continued agents split (commit 75a7a95)

Format fixed from real data: agent aef295321c6258e3c (subagents/agent-aef295321c6258e3c.jsonl) has six prompts. The first is a plain user entry; each later one is a `type: user` entry with `isMeta: true` and `origin: {"kind": "coordinator"}`, text "The coordinator sent a message while you were working: ...", a new `promptId`. Counter of `origin` over the file: 142 none, 6 `{"kind":"coordinator"}`. Gaps between prompts reach three hours (06:25 -> 09:32).
Red: same test as above failed with `AssertionError: Lists differ: ['2026-11-02-alpha'] != ['2026-11-02-alpha', '2026-11-03-beta']`.
Green: `Ran 44 tests in 1.284s / OK`, ruff check and format clean.
Real check: before, the report showed 3h18m under 2026-11-09-no-process-narration (lead's dry-run report, Suggestions 3 and 4). After: row `2026-11-09-no-process-narration ... 3m38s`. Segment ids are `<agent id>.<n>` (n from 2).

## Regenerated skeleton

`.tmp/process-report-dev-tools-2026-11-09_2026-11-09-v2.md` (and `.json`), untracked. Work-table rows are in the report to the lead.

## Fix round

Review: process-report-gaps-review.md. Red first: 47 tests, 5 new/changed tests failing before the fix (agent counts, reviewer spawns, description, by-time one/two/none matches, method line and commit label, realpath dedupe); green after: `Ran 47 tests in 1.461s / OK`, ruff check and format clean, SKILL.md body 497 words.

Commits: 46b4585 (.gitignore, .pyc removed from the index), fe3c971 (code, tests, fixtures, SKILL.md). `git show --stat` of all four commits of this task:
```
dffc87c feat(skills): process-report reads every repository given with a repeatable --git

 skills/process-report/SKILL.md                     |  15 +++----
 .../test_transcript_stats.cpython-310.pyc          | Bin 0 -> 35466 bytes
 .../__pycache__/transcript_stats.cpython-310.pyc   | Bin 0 -> 45346 bytes
 .../scripts/fixtures/golden-skeleton.md            |   2 +-
 .../process-report/scripts/fixtures/good-report.md |   2 +-
 .../scripts/test_transcript_stats.py               |  34 +++++++++++++++
 skills/process-report/scripts/transcript_stats.py  |  47 +++++++++++++++------
 7 files changed, 78 insertions(+), 22 deletions(-)
75a7a95 fix(skills): process-report splits a continued agent at each later prompt

 .../test_transcript_stats.cpython-310.pyc          | Bin 35466 -> 37179 bytes
 .../__pycache__/transcript_stats.cpython-310.pyc   | Bin 45346 -> 46300 bytes
 .../scripts/test_transcript_stats.py               |  37 +++++++++++++++++
 skills/process-report/scripts/transcript_stats.py  |  45 ++++++++++++++++-----
 4 files changed, 73 insertions(+), 9 deletions(-)
46b4585 fix(skills): process-report ignores __pycache__ and drops the committed .pyc files

 skills/process-report/.gitignore                        |   1 +
 .../__pycache__/test_transcript_stats.cpython-310.pyc   | Bin 37179 -> 0 bytes
 .../__pycache__/transcript_stats.cpython-310.pyc        | Bin 46300 -> 0 bytes
 3 files changed, 1 insertion(+)
fe3c971 fix(skills): process-report counts agents once, assigns unkeyed commits by trailer and time

 skills/process-report/SKILL.md                     |  10 +-
 .../scripts/fixtures/golden-skeleton.md            |   2 +-
 .../process-report/scripts/fixtures/good-report.md |   2 +-
 .../scripts/test_transcript_stats.py               | 107 ++++++++++++++++++++-
 skills/process-report/scripts/transcript_stats.py  | 105 ++++++++++++++++----
 5 files changed, 196 insertions(+), 30 deletions(-)
```

Real run (dev-tools + knowledge, 2026-11-09): commits unassigned 2 of 47 (before 26 of 44); method line: "git log read from dev-tools (0 of 29 unassigned), knowledge (2 of 18 unassigned)"; "15 agent transcripts" (was 44), lead row implementer:4,planner:3,reviewer:8.
