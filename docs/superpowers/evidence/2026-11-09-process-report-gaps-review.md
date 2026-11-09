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
