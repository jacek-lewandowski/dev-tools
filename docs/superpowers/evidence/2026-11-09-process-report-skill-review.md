# Review: the process-report skill (Fiona, reviewer 1, 2026-11-09)

Object: brief diff. Brief `docs/superpowers/specs/2026-11-09-process-report-skill-brief.md`,
evidence `docs/superpowers/evidence/2026-11-09-process-report-skill.md`, `~/knowledge`
`b29e456..9f7c263` (ce6e89c, 9f7c263), dev-tools 33fe93d, 19b88ab.

**Verdict: not accepted. Two Important findings; both are figures that look plausible and
are wrong with no marker, on this project's own transcripts.**

Run by the reviewer: `cd /tmp && python3 -B -m unittest discover -s ~/knowledge/skills/process-report/scripts`
-> `Ran 33 tests in 0.888s / OK`. Spot checks on
`~/.claude/projects/-home-jlewandowski-dev-public-dev-tools` with scratch scripts (method
checked on the known case: session `4256d730` gives 190297 deduplicated, as the brief and
the evidence state). User rounds for 2026-11-03..09, counted independently per session,
equal the script's (2f29ba24 2 = 1 user line + 1 human `queued_command`; 34adc6b8 8;
5dd202bd 2; e6249da0 11). The dry-run report still passes `--check` (rc 0).

## Important

**I1. Message ids are deduplicated per transcript, not once per id; a resumed session
counts the copied history again.** `transcript_stats.py`, `Acc.ids` / `scan_line`, and
`collect` summing `main_accs` into `lead`. Session `7184d87f` is a resume of `4ded735d`: it
carries 135 of its assistant message ids with the same timestamps (198 279 output tokens),
and its 15 user rounds with the same timestamps and text. Run
`transcript_stats.py --project-dir ~/.claude/projects/-home-jlewandowski-dev-public-dev-tools --since 2026-10-28 --until 2026-10-31`:
`lead.output_tokens` 515560, of which 198 279 are counted twice (about 38% of the row);
`lead.user_rounds` 47 includes the 15 copies; `lead.wall_s` 549749 adds both sessions'
overlapping spans; per-role "output tokens are summed once per message" is then false. The
brief says "Sum once per id". No fixture has two session files sharing ids. Resolves: keep
one id set (message ids, user-line `uuid`s, tool_use ids for Bash/Agent/screenshot counts)
across all transcripts of the run; a fixture with two session files sharing ids and
rounds; the session wall from lines not seen before; a line in SKILL.md Known gaps and the
register row ("a resumed session repeats the earlier history with its ids and timestamps").
Search that would have found it: message ids occurring in more than one `*.jsonl` of the
project dir (135 here, all in this pair).

**I2. `cost-state` is labelled "main session only, subagents excluded"; on this project's
data it includes the subagents.** `session_record` (`cost_label`), `build_blocks`
captions `cost-session` ("USD is the main session only, subagents excluded") and `method`
("Cost per session is the recorded main-session total, subagents excluded"), JSON
`labels.cost_state`, the docstring and the register row. Last `cost-state`
`modelUsage.*.outputTokens` against deduplicated main + subagent transcripts: 01dcc66f
31048 vs 17504 + 13020; 5dd202bd 39379 vs 16737 + 22294; e6249da0 86658 vs 47384 + 38177;
6d7fbdd3 773323 vs 117674 + 660035 (main alone: 6.6 times less). The dry-run report prints
USD 3.23 and 6.43 for 5dd202bd and e6249da0 under "subagents excluded": a reader adding
subagent cost counts it twice. The brief made the label inferred and said "O1 tests it";
O1's session has 287 subagent output tokens, too few to tell, and the evidence does not
address the label. The 32% gap of `4256d730` is reported honestly as unexplained, but the
SKILL.md conclusion "read transcript tokens as a lower bound" is not supported: across the
16 sessions with a `cost-state` the ratio to the main transcript runs from 0.48 (4ded735d,
before the resume) to 6.57, and to main + subagents from 0.15 to 3.98. Resolves: label the
USD as the session process's recorded total, subagents and side calls included, a resumed
session counting only its own process; fix both captions, the JSON label, the docstring,
the register row; replace the "lower bound" sentence with the observed two-way spread and
the unexplained `4256d730` gap; a fixture asserting the caption text.

## Minor (not blocking)

- `build_tasks`/`work_rows`/`cost-session`: the lead row and per-session walls are
  first-to-last line spans with no `spans N days` marker (the 10-28..31 run shows the lead
  wall as 152h42m).
- `agent_record`: `You are (\w+)` names an agent `a`, `an` or `reviewing` when a prompt in
  another project has no name; restrict to a capitalised word.
- `check_report`: any line reading `none` anywhere lets the `eye` block go missing, and
  non-ui rows kept beside `none` pass; the dry-run report does both, against SKILL.md step 2.
- Register row and docstring list meta `finished`, which the script never reads.
- The dry-run files predate 9f7c263 (stated in the evidence).

## Round 2 (delta: `~/knowledge` f4740ec; dev-tools 4d5b1c2, 9a2f800)

**Verdict: accepted. I1 and I2 are fixed; nothing new blocks.**

Run by the reviewer: suite from `/tmp`, `Ran 40 tests in 0.910s / OK`. Reproducer
`--since 2026-10-28 --until 2026-10-31` on the real project dir: `lead.output_tokens` 317281
(515560 - 198279, the copied history exactly), `user_rounds` 32 (47 - 15), `wall_s` 283139,
as the evidence records. The new tests would have caught both findings:
`test_resumed_session_counts_shared_history_once` asserts 107, not the old 207;
`test_cost_caption_names_what_cost_state_covers` asserts the new caption and the absence of
"subagents excluded". The four minors are fixed with a test each, `finished` excepted
(text only).

Minor (not blocking):

- `collect` reads sessions in file-name order, so the dedup credits the shared history to
  whichever file sorts first; session ids are random, so about half of resumes go the other
  way. With copies of the two real files renamed so that the resumed one sorts first, totals
  for tokens and rounds stay right (218348, 17 either way) but `lead.wall_s` is 543149
  against 276543: the original keeps lines that carry no shared uuid (its first line has the
  resumed file's timestamp) and adds its full span again. The per-session rows also flip (the
  original shows 3 output tokens over 74 h). The `spans N days` marker flags this case; a
  short resume would not trip it. Resolves: read the session files in order of their first
  timestamp, plus a fixture with the resumed file named first.
- SKILL.md step 2 lost "Read the files the JSON points to", which the brief's step 2 asks
  for (judging kind and outcome needs the content); `--until` lost "default today"; "so for
  work outside Claude Code" does not read; a double space before "Kinds".
- O6 size cap: the brief the user approved says `du -sk` under 100. The lead changed the
  measure to `--apparent-size` and then accepted 103. That is a change to an approved
  obligation, so it goes to the user at merge rather than being decided by the lead alone.
  I make no finding against the code.
