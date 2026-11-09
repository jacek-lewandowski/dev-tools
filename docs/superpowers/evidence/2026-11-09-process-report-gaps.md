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
