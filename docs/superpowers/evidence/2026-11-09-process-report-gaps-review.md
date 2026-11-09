# Review: process-report gaps (2026-11-09)

Reviewer: Fiona, reviewer 1. Object: small changes, ~/knowledge dffc87c (repeatable --git) and 75a7a95 (continued agents split per prompt). Evidence: docs/superpowers/evidence/2026-11-09-process-report-gaps.md. Skeletons: .tmp/process-report-dev-tools-2026-11-09_2026-11-09{,-v2}.md and the v2 JSON.

Verdict: not accepted, three Important findings. Delta re-review after the fix.

Suite re-run once: `cd ~/knowledge/skills/process-report/scripts && python3 -B -m unittest test_transcript_stats` gave `Ran 44 tests ... OK`; ~/knowledge tree clean.

## Important

1. Segments are counted as agents under unchanged labels (transcript_stats.py `collect` `agents_read`, `build_tasks` `agents` and `reviewer_spawns`, `build_blocks` cost-role `agents` column, method line). Since 75a7a95 every prompt segment is an entry in `stats["agents"]`, so each count over that list now counts prompts. v2 JSON: 44 entries from 14 transcript files (`Counter(a["id"].split(".")[0])` has 14 keys). The report then says "Read 1 sessions and 44 agent transcripts" (true: 14), cost-role agents implementer 17, planner 11, reviewer 16 (true: 4, 3, 7 transcripts), lead row `implementer:17,planner:11,reviewer:16` and rev 16, task rows such as `planner:6` for one brief writer (ad26d2ca640906fa1, six prompts). The same header shows "spawns unassigned 1 of 14", so 14 spawns and 44 "agent transcripts" sit side by side with no marker. The new test asserts keys, tokens and wall per segment but none of these counts. Resolve: count distinct base ids (`id.split(".")[0]`) for agents_read, the role counts and rev, or rename every affected label to say prompts/segments; either way add asserts on agents_read, the task's `agents` and `reviewer_spawns` for the continued agent in `test_continued_agent_is_split_at_each_later_prompt`.

2. Knowledge commits are read but none can be assigned, and nothing marks it (`commit_key`, `build_blocks` unreliability label). All 16 ~/knowledge commits of the day carry no evidence path or issue key (checked with `git -C ~/knowledge log --branches --no-merges --since=2026-11-09T00:00 --name-only`: rules/global.md, decisions.md, skills/...), so every one goes to `unassigned`: per-task commits in v2 are identical to v1 (3, 1, 4, 7, 3) and the unassigned share rises from 10/28 (36%) to 26/44 (59%). The over-half label exists only for spawns, and the method line now says "git log read from dev-tools, knowledge", which reads as if per-task commits, files and lines include knowledge. Suggestion 3's complaint (per-task figures understate the work) is therefore still true and now less visible. Resolve: apply the existing over-half rule to commits (e.g. "unreliable: most commits unassigned") and/or state per repository how many commits stayed unassigned in the method line; record in SKILL.md Known gaps that a repository whose commits name no task path contributes only to the lead total.

3. Build artefacts committed and no diff check recorded (small-class obligation). dffc87c adds and 75a7a95 updates `skills/process-report/scripts/__pycache__/test_transcript_stats.cpython-310.pyc` and `transcript_stats.cpython-310.pyc`; ~/knowledge has no .gitignore. The evidence file has no diff showing that only the intended parts changed. Resolve: a new commit that removes the two .pyc files from the index and ignores `__pycache__/`; record `git show --stat` of both commits in the evidence.

## Minor (not blocking)

- Top-output and longest-wall tables render later segments with an empty description cell (v2: `| Zuzia | implementer | 2026-11-09-report-sync | 6396 | 3m57s |  |`); `agent_rows` could show `(continued)` or `-`.
- `--git` given the same repository twice (as `test_cli_git_flag_repeats` does) counts its commits twice; deduplicate by realpath.
- dffc87c also rewords SKILL.md steps 4 and 6 and folds the ".tmp/ copy stays" rule into step 6 to stay under 500 words; no change of meaning found.

## Checked and holding

- Split format against real data: across all 107 local subagent transcripts (`~/.claude/projects/*/*/subagents/agent-*.jsonl`), every later prompt is a `type: user`, `isMeta: true`, `origin: {"kind": "coordinator"}` entry (133 such entries, no other `origin` form); no transcript has a second non-meta, non-tool_result user entry, so `continues` misses no prompt in the current format.
- Single-prompt agents: ids keep no suffix and meta is untouched (ada8ebf926c84d606, aea5d12fb7de0c454 in v2); the golden skeleton is unchanged by 75a7a95 and passes. Main sessions never split (`not main`). Repeated-command agents use the base id.
- Wall-clock: no-process-narration falls from 3h18m to 3m38s; per-role wall now sums segments.

## Round 2

Delta: ~/knowledge 46b4585 and fe3c971, the "Fix round" section of the evidence file, the regenerated v2 skeleton and JSON.

Verdict: accepted. No Critical or Important finding; the review is closed.

Suite re-run once: `python3 -B -m unittest test_transcript_stats` gave `Ran 47 tests ... OK`. ~/knowledge tree clean; `git ls-files | grep -c pycache` = 0.

Round 1 findings:
- I1 closed. `agents_read`, the task `agents`/`reviewer_spawns`, the lead row and the cost-role column count distinct base ids. v2: "15 agent transcripts" (15 files, this round's reviewer included), lead row `implementer:4,planner:3,reviewer:8`, cost-role 4/3/8, process-report-skill `implementer:1,planner:1,reviewer:2`. The continued-agent test now asserts agents_read and per-task agents; a continued reviewer has its own test.
- I2 closed. The over-half label also covers commits. The method line gives unassigned commits per repository. Commits that name no task are assigned by Co-Authored-By name plus segment window, marked `by-time`; zero or several matches stay unassigned (tested).
- I3 closed. 46b4585 removes both .pyc files and adds `skills/process-report/.gitignore` (`__pycache__/`). The evidence records `git show --stat` of all four commits.

By-time spot-check. I re-ran `collect` and `assign_commits` in-process on dev-tools + ~/knowledge, 2026-11-09, and compared each commit's time and trailer with the segment windows and prompts:
- 2026-11-09-process-report-skill holds 11 commits:
  - 7 keyed by path: 85b9c88, 33fe93d, 19b88ab, 4d5b1c2, 9a2f800, 2de8dd7, 8fb06ba.
  - 4 by-time: ce6e89c (in Zuzia ae493ea605f787e30), f4740ec (in .3), a99164c and 0f62a65 (both in .4).
  - Each of these is a process-report skill commit made inside that implementer's segment for that task. None is wrong.
- Other tasks:
  - no-process-narration: 8713b48 and 6538cce, from aef295321c6258e3c segments 1 and 2.
  - report-sync: Zuzia's dev-tools and knowledge commits from abe69abf419228cf2 and .2.
  - proposals-triage: d22aa1f, 52aa7a6 and a6568d1, from aef29.4.
  - idle-handover: e65f1c2, e76335c and 9a274ef from aef29.3, .5 and .6; Wojtek's 9b92435, 28f417a, 72681ef and a66f3b0 from a5266a07c9886b72d. These run in parallel with Zuzia's and are told apart by the trailer.
  - process-report-gaps: dffc87c, 75a7a95, 46b4585 and fe3c971.
  - All match the prompts. One borderline case: 9a274ef rewords the lint clause that d22aa1f (proposals-triage) introduced, but its prompt is R2-I2 of the idle-handover review, so it is correct by the stated rule.
- 9f7c263 stays unassigned. It falls inside ae493ea605f787e30.2, a segment keyed unassigned, so this is a conservative miss, not a wrong attribution.
- v2 shows knowledge 2 of 18 unassigned, while my run shows 1. v2 was generated while aef29.8 was still running, before its last line passed fe3c971's time.

Minor (not blocking):
- Method line, `build_blocks` and `unassigned_by_repo`: a repository given with `--git` that has no commits in the period is not named. With `--git . --git ~/knowledge` and no knowledge commits, the line reads as if only dev-tools was read. Building `by_repo` from `git_repos` would name it with `0 of 0`.
- SKILL.md step 4 lost "(cheaper tier)" in fe3c971's word trim. That changes which model the report review runs on, which is outside the findings. Restore it and cut words elsewhere.
