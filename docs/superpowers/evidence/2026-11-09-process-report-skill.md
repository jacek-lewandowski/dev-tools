# Evidence: the process-report skill (Zuzia, implementer 1, 2026-11-09)

Brief: `docs/superpowers/specs/2026-11-09-process-report-skill-brief.md`. Skill commit in
`~/knowledge` main: `ce6e89c` (feat(skills)); fix round `9f7c263` (fix(skills), see below). Register row and this file: the dev-tools
`docs:` commit that contains this file. ruff 0.17.3 (pinned in `requirements-dev.txt`) was
installed in a scratch venv; the sandbox python is 3.10.12.

## Impact set (before starting)

`grep -rln 'process-report' ~/knowledge /home/jlewandowski/dev/public/dev-tools --include='*.md' --include='*.sh' --include='*.py'`
returned 17 files, all in dev-tools, none in `~/knowledge`: the brief, the task statement,
the brief review, the earlier supervisor design/brief/review (`prompts/process-report.md`, a
shelved design, unrelated to this skill's path), the task-classes spec and evidence, and
`.tmp/` reports. The brief expected only its own two files; the others are older mentions of
the *report*, not of this skill. Nothing to change in them.

## Red run

Test file written first; `python3 -m unittest discover -s .` before the script existed:
`Ran 1 test in 0.000s / FAILED (errors=1)` (ImportError on `transcript_stats`).
Mutation check of the dedup: removing the `mid not in acc.ids` guard made 9 tests fail
(`test_known_case_output_tokens`, `test_agent_linking`, `test_task_rows`, golden, ...).

## Full suite on the final tree

`python3 -B -m unittest discover -s ~/knowledge/skills/process-report/scripts -v` (run from `/tmp`):
`Ran 32 tests in 0.818s / OK`; after the fix round `Ran 33 tests in 0.825s / OK`, ruff check `All checks passed!`, ruff format `4 files already formatted`. Groups: TestDedup 2, TestDerived 10, TestRobust 5, TestReport 15 (33 tests, 11 derived, after the fix round).

## O1 dedup, known case

- `fixtures/dup-usage.jsonl` (4 lines: id A twice, id B, one synthetic zero line):
  `test_known_case_output_tokens` asserts 140 (naive sum 240), input 5, cache-write 10,
  cache-read 50, messages 2, peak context 33: green.
- Real session `4256d730-c936-45ca-9d59-929c2ad58735`, from `/tmp`:
  `python3 -I transcript_stats.py --project-dir ~/.claude/projects/-home-...-dev-tools --since 2026-10-25 --until 2026-10-25`
  gives `output_tokens` 190297, `messages` 139 (139 distinct ids; the brief's 190 297 is
  reproduced). `cost_output_tokens` (sum over all models of the last `cost-state`) = 251779:
  fable 251368 (the brief's 251 368 is this model alone) + haiku 411. Difference 61482
  (+32%). Checked: no id has differing `output_tokens` across its lines (first, last and
  max sum are all 190297), so the dedup is not the cause; the 3 subagent transcripts add 287.
  **Unexplained**: cost-state counts output the transcript lacks (candidates: thinking
  tokens 109831 recorded separately, calls not logged). Stated in SKILL.md "Known gaps" (32%).

## O2 derived figures

Tests in `test_transcript_stats.py`, all green: `test_agent_linking` (role, name, parent,
tokens 1334 with a duplicated line), `test_visual_and_artifact` (one screenshot tool, one
`.png` Read, `Artifact` list action not counted), `test_user_rounds_matrix` (counts: string,
text-block list, human queued_command, a queued prompt also delivered as a user line once;
does not: task-notification, `<agent-message`, `<command-name>`, `<local-command-stdout>`,
`<system-reminder`, isMeta, tool_result, sidechain user line, non-human queued, queue-operation),
`test_period_by_line_timestamp_and_until_inclusive`, `test_task_rows` (two path keys, `#12`
matched by a commit subject, an unmatched `#333` unassigned, path key beats `#12`, a no-key
spawn and commit unassigned, one commit touching two keys `ambiguous`, reviewer spawns, window
73 h -> `spans 4 days`, `overlap`, `Class:` match `brief` and `unknown`),
`test_lead_row_tokens_are_main_session_only`, `test_unassigned_majority_label`,
`test_top_five_by_both_rankings`, `test_repeated_commands` (`python3 -m unittest` by two agents
and the lead in one cwd listed once; two other cwds none; `git commit -m "add test"` never),
`test_screenshot_rounds_none` and the alpha row (`none`), `test_markdown_equals_golden`.

## O3 robustness

`test_bad_inputs_do_not_raise` (malformed line, empty file, missing `subagents` dir, missing
`usage`, broken meta: no traceback; `skipped` = lines 1, files 1, metas 1),
`test_empty_period_is_valid` (valid JSON, empty lists, one-line report that passes `--check`),
`test_empty_period_in_existing_dir_exits_0`, `test_missing_dir_exit_1_with_near_misses`: green.

## O4 real data

From `/tmp`: `python3 -I .../transcript_stats.py --project-dir ~/.claude/projects/-home-jlewandowski-dev-public-dev-tools --days 7 --git /home/jlewandowski/dev/public/dev-tools --until 2026-11-09`
-> exit 0 in 0.17 s, `python3 -m json.tool` accepts it. Period 2026-11-03 to 2026-11-09:
4 sessions, 7 agents, 5 commits, `skipped` = lines 0, files 0, metas 0; unassigned spawns
0 of 7, commits 0 of 5; 4 task rows; Claude Code version 2.1.316. Independent count (a
separate script reading the raw text with a regex for `"timestamp"`): 95 `*.meta.json`
files, 7 whose transcript has a line in the period = the script's 7.

## O5 check

Fixtures `golden-skeleton.md` (generated by the script from the test scenario, then read) and
`good-report.md` (judgement cells, prose and a `Review:` line filled). Tests: passes on good;
fails with the named reason on skeleton (`leftover TODO`), missing heading
(`missing heading: ## Waste`), wrong order, 1501 words (1500 passes), a changed script cell
(`script:work row ... column 'agent out': expected '1534', got '1535'`), `1,534` for `1534`,
missing/malformed `Review:` (also `rounds=3`, bad verdict, `not reviewed` without reason),
a row over 25 words; a changed judgement cell passes; eye rows may be removed, not changed.

## O6 skill text and install path

`head -4 SKILL.md`: `name: process-report` = directory; description 343 characters, no steps;
body (`sed -n '5,$p' SKILL.md | wc -w`) 495 words (486 after the fix round); `report-template.md` headings (`grep -n '^#'`):
title + Work done, Cost, Work judged by eye, Waste, Fit of kinds and roles, Suggestions, Method
and gaps (eight, in order; `test_template_headings_in_order`). SKILL.md has the period rule,
five steps with the reviewer's sample and two-round limit, output path, `unknown`, agy usage
from delegation reports. `SKILL.md` at the directory top. `du -sk` is 112 (116 after the fix round) because of 4 KB block rounding of 9 files and 3 directories; `du -sk --apparent-size` is 98 (99 after). The lead accepted `du -sk --apparent-size` as the measure of this obligation (2026-11-09), so it is met: 99, under 100.

## O7 no project content

`grep -rniE 'dev-tools|amen|skippy|krzysiu|jlewandowski' ~/knowledge/skills/process-report --include='*.md'`
-> no output (rc 1), also none in fixtures. `grep -n '/home' scripts/transcript_stats.py` -> none.

## O8 format

`ruff check --no-cache .` -> `All checks passed!`; `ruff format --no-cache --check .` ->
`4 files already formatted` (ruff 0.17.3, run in `scripts/`). One `# noqa: UP017` on
`dt.timezone.utc` (`dt.UTC` needs python 3.11; the sandbox has 3.10).

## O9 register

`PROJECT_MAP.md` coupling register row added (transcript layout, `queued_command`,
`cost-state`, tool names, meta fields). `grep -rn 'reads-outside:' ~/knowledge/skills/process-report`
-> two hits, `scripts/transcript_stats.py:8` and `:14`.

## O10 dry run (untracked, `dev-tools/.tmp/`)

Steps 1 to 3 for 2026-11-03 to 2026-11-09:
`python3 .../transcript_stats.py --days 7 --git . --markdown .tmp/process-report-dev-tools-2026-11-03_2026-11-09.md > .tmp/process-stats-dev-tools-2026-11-03_2026-11-09.json`
then judgement cells and prose filled, then `--check` -> `report check passed`, rc 0 (filled
report 484 words). Skeleton on real data: 541 words by the script's count (tokens with a
letter or digit, comments excluded; `--check`'s limit uses this count), 1027 by plain `wc -w`
(counts every `|` and `---`). Under 900 either way: no cut of rows or columns needed.
Unclear in SKILL.md / found on real data: (1) the eye table lists all work rows and the lead
must delete the non-ui ones (now stated in step 2); (2) the empty "candidate repeats" table
shows only its header (this project's runs are single-agent); (3) 7 days means today and the
six before; (4) a commit touching `<key>.md` and `<key>-brief-request.md` was `ambiguous` because
`-request` was not a stripped suffix; fixed in the fix round below. `<key>-review-fixes` stays a task
of its own (lead's decision). Step 4 needs a spawned reviewer: not run.

## Fix round (lead decisions of 2026-11-09)

1. `-request` added to `KEY_SUFFIXES`. Test first: `test_request_file_shares_the_task_key`
   (a commit touching `<key>.md`, `<key>-brief-request.md`, `<key>-brief.md` gives one key, not
   ambiguous) failed on the old code (`Ran 33 tests ... FAILED (failures=1)`), then passed:
   `Ran 33 tests in 0.825s / OK`. The SKILL.md note about `-request` keys was removed. Commit
   `9f7c263`. The O10 dry-run report was produced before the fix and is untouched.
2. Size cap: see O6.

## Fix round 2 (review of 2026-11-09, `...-process-report-skill-review.md`)

Commit `f4740ec` in `~/knowledge` (fix(skills)); register row updated in the dev-tools commit
that carries this section. Regression tests written first: 7 failed on the old code
(`Ran 40 tests ... FAILED (failures=7)`), then `Ran 40 tests in 1.028s / OK`; ruff check
`All checks passed!`, ruff format `4 files already formatted`.

- I1: one id set (line uuids, message ids, tool_use ids) across all transcripts of a run.
  Tests `test_resumed_session_counts_shared_history_once` (two session files sharing uuids,
  message ids, a round and a Bash tool use: 107 tokens, 1 round, wall 1 s, 2 messages) and
  `test_resumed_message_ids_without_uuid_counted_once`. The reviewer's reproducer
  (`--since 2026-10-28 --until 2026-10-31`): `lead.output_tokens` 515560 -> 317281 (-198279,
  exactly the copied history), `lead.user_rounds` 47 -> 32 (-15), `lead.wall_s` 549749 -> 283139.
  SKILL.md Known gaps and the register row name the search.
- I2: `cost_label` `session_process_total`, both captions, the JSON `labels.cost_state`, the
  docstring and the register row relabelled; `test_cost_caption_names_what_cost_state_covers`
  asserts the caption and that "subagents excluded" is gone. The lower-bound sentence is
  replaced by the review's spread (0.48 to 6.57 of the main transcript, 0.15 to 3.98 of main
  plus subagents, 16 sessions; 32% above in 4256d730, unexplained). The spread figures are
  copied from the review, not re-measured by me.
- Minor: `spans N days` on the lead row and per-session notes (`test_spans_marker_on_lead_row_and_sessions`);
  agent name needs a capitalised word (`test_agent_name_needs_a_capitalised_word`); `--check`
  requires the eye block unless the eye section has a `none` line, and rejects `none` beside the
  block (`test_eye_block_missing_without_none_fails`, `test_eye_none_replaces_block_but_not_beside_it`);
  `finished` dropped from docstring and register row (the script never read it).
- O10 re-run on the fixed tree: report regenerated, eye block replaced by `none`, `--check`
  -> `report check passed`, rc 0, 457 words (untracked, `.tmp/`).
- Size: SKILL.md body 498 words. **`du -sk --apparent-size` is now 103 (disk usage 120)**: the
  fixes added about 5 KB (tests, code, SKILL.md gaps); over the accepted cap of 100. Not
  trimmed further; the lead decides.

## Lead decision on the O6 size cap (2026-11-09)

The 100 KB cap in the brief was a guessed bound against shipping bulk into every
sandbox. 103 KB apparent size after fix round 2 is accepted as meeting its purpose;
no code or tests are cut for it. — Skippy Wspaniały (lead)

## Fix round 3 (review Round 2 lesser findings)

`~/knowledge` a99164c and 0f62a65. Sessions are read oldest first by (first, last) timestamp, not by name
(`test_sessions_read_oldest_first_not_by_name`: a resumed file sorting first and last by name gives the
same walls; failed with the sort disabled, passes with it). SKILL.md: "Read the files the JSON points to"
restored, `--until` "default today", agy/outside-Claude-Code sentence and double space fixed, body 499 words.
Suite: `Ran 41 tests / OK`; ruff check passed, format unchanged.
