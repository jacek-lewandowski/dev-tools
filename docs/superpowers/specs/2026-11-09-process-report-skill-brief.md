# Brief: the `process-report` skill

Written by Hania (planner 1), 2026-11-09. Class: **brief**, no refactor flag.
Task statement: `docs/superpowers/specs/2026-11-09-process-report-skill-brief-request.md`
(read it first). Evidence file: `docs/superpowers/evidence/2026-11-09-process-report-skill.md`.
One implementer lands it in one pass and runs the full checks below at the end.

## Goal

A skill in the shared knowledge repository that a project's lead runs over a
period and that yields one short, fixed-shape, English report, so reports from
different projects can be put side by side. Everything computable is computed by
a tested script (the user: "whatever can be computed should be computed by static
tools"); the lead only judges, and a fresh reviewer checks the report for
misleading statements before the user sees it.

Users: the lead of a project sandbox (runs it), the user (carries the file to
the integrator sandbox), the integrator lead (compares reports). Flows settled
here: an empty period gives a one-line report saying so; an unparsable transcript
is skipped and counted; a figure the script cannot know (agy delegation usage,
work outside Claude Code) is `unknown`, never estimated.

## Files (all new; nothing existing in `~/knowledge` is edited)

`~/knowledge/skills/process-report/` (copied whole into `~/.agents/skills/` by
`ai-knowledge`, `dev-tools/bin/ai/ai-knowledge` render and `wire_host`):
`SKILL.md`; `report-template.md` (the one source of the headings and prose-section
prompts, read by the script); `scripts/transcript_stats.py` (stdlib, python3,
runnable by path from any cwd); `scripts/test_transcript_stats.py`
(`python3 -m unittest`); `scripts/fixtures/` (small hand-made transcripts, a golden
skeleton, a good report).

Also in dev-tools: one row in the `PROJECT_MAP.md` coupling register (transcript
fields read by `process-report`, beside the statusline rows). Commits: one
`feat(skills):` on `~/knowledge` main (integrator sandbox; no push), one `docs:`
in dev-tools. No `decisions.md` entry (a skill is not a rule). Nothing
project-specific in the skill directory.

## SKILL.md

- `name: process-report`; `description` third person, a verb first, then "Use
  when the user asks for a process report, a summary of how the work went over
  the last days, its cost, speed or waste, or what to improve in the process."
  Under 500 characters, no steps (superpowers:writing-skills).
- Body under 500 words. Inputs: `--since YYYY-MM-DD` or `--days N` (default 7),
  project dir derived from cwd. Period rule: per-line timestamps. Steps:
  1. run `transcript_stats.py ... > .tmp/process-stats-<project>-<from>_<to>.json`
     (stdout is the JSON) and `--markdown <report path>` for the skeleton;
  2. fill only the judgement cells and prose sections, reading the files the
     JSON points to;
  3. `--check REPORT --stats JSON` until it passes;
  4. review: the lead gives a fresh `reviewer` agent (cheaper tier) the report,
     the JSON and the cited sources. It checks that figures trace to the JSON or a
     cited file, claims are supported, and no wording misleads (an upper bound
     written as a count, an `unknown` dropped, a suggestion written as fact). It
     may sample: every Suggestion, every figure in Waste, ten other cells. At most
     two rounds; the lead fixes findings;
  5. append the `Review:` line to "Method and gaps", run `--check` again.
  Rules: facts and suggestions apart; `unknown` instead of estimates; agy usage
  from delegation reports; no raw logs; English, no persona; create `.tmp/` if
  missing.

## Report: fixed shape, 1 500 words in total including tables

Default path `<project>/.tmp/process-report-<project>-<from>_<to>.md`, not
committed. Headings, exactly, in order (`report-template.md`):

1. `# Process report: <project>, <from> to <to>` and a header block: model,
   script version, Claude Code versions seen, sessions read, transcripts skipped,
   share of spawns and of commits `unassigned`.
2. `## Work done`: at most 15 rows ranked by wall-clock (rest: one line "N more
   in the JSON"), then a final row `(lead, all tasks)`. Script-filled columns:
   task key; commits, files, lines; class given; agents per role; reviewer
   spawns; output tokens "agents only"; wall-clock; user rounds in the window.
   The lead's own tokens are not in any task: they appear only in the final row.
   Cell markers: `ambiguous` (the key was chosen among several), `spans N days`
   (window over 48 h, probably not working time), `overlap` (another task's
   window overlaps), `unknown`. Lead's columns, headed `?`: `kind?`, `fit?`
   (`fit`, `too heavy`, `too light` or `no class`, against the class given and the
   global rules' class definitions), `outcome?` (`accepted`, `reworked`,
   `dropped`). If more than half of the spawns are `unassigned`, the script
   labels the table `unreliable: most work unassigned`. A row is at most 25 words.
3. `## Cost`: per role (agents, wall, output tokens, fresh input + cache-write
   tokens, cache-read tokens); per session (main-session USD as recorded, which
   excludes subagents; wall). "Output tokens" is the deduplicated sum of
   `usage.output_tokens`, the same everywhere.
4. `## Work judged by eye`: only when a task has kind `ui-*`, `mockup` or
   `mobile-ui`, else `none`. Script-filled: user rounds in the window; first
   `Artifact` publish time; number and first time of screenshot/image reads;
   `rounds_before_first_screenshot` (user rounds before it; `none`, never 0, when
   there is no screenshot in the window). Lead's: time to first thing the user
   could look at where there is no `Artifact` publish (marked `lead's reading`);
   rework by visual miss or defect; steps that changed nothing the user saw, each
   with the rule sentence that required it.
5. `## Waste`, facts only. Script-filled: five most expensive agent runs by output
   tokens and five longest by wall-clock; a table labelled "candidate repeats, not
   verified waste": build/test/lint commands run identically by two or more agents
   in one cwd. Lead's: the rule file and quote behind each expensive run; steps
   droppable for a kind of task without losing a defect the reports show was caught.
6. `## Fit of kinds and roles`: tasks that fit no class or role, and what they
   needed (data for "does this kind need its own role").
7. `## Suggestions`: the lead's, at most seven, each citing a section and row,
   each `process`, `rule` or `new role`.
8. `## Method and gaps`: what was read; what could not be known; any unchecked
   method; `Review: verdict=<accepted|accepted with notes|not reviewed>;
   rounds=<0-2>; fixed=<n>` and the findings fixed (`not reviewed` needs a stated
   reason).

**The lead's judgement, and why it cannot be computed:** `kind`, `fit`,
`outcome` (they need content and the user's reaction); whether a screenshot round
concerned the visual result; rework cause; steps that changed nothing the user
saw; the rule quote (matched by meaning); droppable steps; unassigned items; fit
of kinds and roles; suggestions. Everything else above is script-filled.

Task kinds (fixed; `other:<word>` is listed in section 6): `text-asset`,
`config`, `bugfix`, `feature`, `refactor`, `contract`, `ui-design` (new screens
or pages), `ui-refactor` (visual rework of existing UI), `mockup` (a prototype for
the user to judge, before the implementation), `mobile-ui`, `spike`, `ops`,
`rules-docs`.

## Script: `scripts/transcript_stats.py`

`transcript_stats.py [--project-dir DIR] (--since D | --days N) [--until D] [--git REPO] [--markdown PATH] [--stats JSON --check REPORT] [--version]`.
Default prints the JSON to stdout. Period: by each line's own `timestamp` (local
date, `--until` inclusive, default today), never by session file, because
sessions here run for days: a straddling session contributes only its lines
inside, agents likewise. Default project dir: `~/.claude/projects/` plus cwd with
`/` and `.` replaced by `-`; if absent or without `.jsonl`, exit 1 listing the
nearest-named directories (worktrees map to other names); an empty period in an
existing directory is not an error.

`--markdown PATH` writes the skeleton: headings, script-filled tables inside
`<!-- script:<id> -->` markers, `TODO` in judgement cells and prose sections.
`--check` fails, with each reason, on: a missing or misordered heading; more than
1 500 words; a leftover `TODO`; a script-filled cell differing from the JSON
(judgement `?` columns are not compared); a malformed `Review:` line (format only,
the verdict is the lead's attestation). One formatting function renders every
cell in both modes, no thousands separators, so a hand-reformatted number fails.

Reads (real files, Claude Code 2.1.x, checked 2026-11-09):

- `<project-dir>/<session>.jsonl`, `<session>/subagents/agent-<id>.jsonl` and
  `.meta.json` (`agentType`, `description`, `toolUseId`, `finished`); lines carry
  `type`, `timestamp`, `isSidechain`, `version`.
- `assistant` lines: `message.id`, `message.model`, `message.usage` (the three
  input fields and `output_tokens`), `tool_use` blocks (`name`, `id`, `input`).
  **One assistant message is written once per content block with the same
  `message.id` and usage** (session `4256d730-...jsonl`: 258 lines, 140 ids, naive
  output sum 430 859 against 190 297 deduplicated). Sum once per id; skip
  `<synthetic>` and all-zero usage. This is the known case the method is checked on.
- Rounds with the user, main session only (`isSidechain` false), with timestamps
  and 120 characters each: (a) a `user` line, `isMeta` not true, content a string
  or a list of only `text` blocks, text not starting `<task-notification`,
  `<agent-message`, `<command-`, `<local-command-` or `<system-reminder`; plus
  (b) an `attachment` line `attachment.type` `queued_command`,
  `attachment.origin.kind` `human` (a prompt typed while an agent was busy; in
  `2f29ba24-...jsonl` its `queue-operation` `enqueue` has no matching `user`
  line). A queued prompt also delivered as a `user` line is counted once
  (identical text, same session, within 120 s; not observed for a typed prompt, the 6
  such lines in `4256d730-...jsonl` are subagent hand-backs). `queue-operation`
  lines are not counted. The count is an upper bound ("ok" counts).
- `system` `turn_duration`; top-level `type: "cost-state"` (last per session:
  `totalCostUSD`, `modelUsage`), labelled `main_session_only` (inferred; O1 tests it);
  `system` `subtype: "compact_boundary"` as compactions (as `statusline.py` reads it).
- `Agent` tool uses in the parent (`input.subagent_type`, `description`, `prompt`),
  matched to the subagent by `meta.toolUseId`: role, name (first `You are <Name>`),
  parent.
- Visual: tool names containing `screenshot`, and `Read` of `.png/.jpg/.jpeg/.webp`,
  per agent with timestamps; `Artifact` uses with timestamps. Heuristic, labelled.
- `--git REPO`: `git log --numstat` for the period: hash, subject, files,
  insertions, deletions, time.

Derived by rule (labelled heuristic in the JSON, one fixture each):

- **Task key**, two sources. (a) The `<date>-<slug>` stem of a path under a
  directory named `evidence`, `plans`, `specs` or `briefs`, trailing `-brief`,
  `-review`, `-plan`, `-design`, `-spec` removed (70 of 109 `Agent` prompts here
  name such a path; `...-gitleaks-hooks-brief.md`, `...-gitleaks-hooks.md`,
  `...-gitleaks-hooks-review.md` give one key). (b) `#<n>` or `GH-<n>` in a commit
  subject, for projects that keep tasks in a tracker; in a spawn prompt it counts
  only when the same number appears in a commit subject in the period (so a
  quoted `#333` stays unassigned). A spawn takes the most frequent key in its
  prompt, and a path key wins over `#<n>` when it has both; a commit the key of a changed path or
  its subject (several: first alphabetically, cell marked `ambiguous`); no key:
  `unassigned`. No other linking and no key map.
- **Task row**: commits, files, lines; agents, output tokens and reviewer spawns
  (`agentType` `reviewer`) per role; window from first spawn or commit to last
  agent line or commit; user rounds in it; class given = first
  `Class:\s*\**(small|brief|phase)` (case-insensitive) in the task's brief or plan
  files, else `unknown` (this project's format; no more formats are added). The
  lead's tokens in the final row are the sum over the main-session
  (`isSidechain` false) assistant lines, deduplicated by id, not `cost-state`.
- **Top five** by output tokens and by wall-clock.
- **Repeated commands**: `Bash` commands, whitespace-normalised, whose first word
  (or first two, for `python3 -m`, `npm run`, `./gradlew`) is one of a listed
  test/build/lint runner (`pytest`, `unittest`, `gradlew`, `mvn`, `npm`, `ruff`,
  `make`, ...; one constant), identical, same line `cwd`, two or more distinct
  agents. A reviewer re-running what the plan requires is also listed, hence the label.

Per agent the JSON has role, name, description, model, first/last timestamp, wall,
messages, the four token sums, peak context, tool counts, compactions; per session
the same plus lead totals; `skipped` counts unreadable lines and files. Not read:
agy `ai-delegate` usage and tool-result content. The module docstring carries a
`# reads-outside:` comment naming the layout and fields above, as
`tools/context_statusline/statusline.py` does; the versions seen are printed.

## Obligations

All discharged by the one task, recorded in the evidence file by key.

- **O1 dedup, known case (executable).** Fixture `dup-usage.jsonl`: 3 assistant
  lines, 2 distinct ids (one repeated), 1 synthetic zero line; hand-counted output
  tokens asserted. `python3 -m unittest discover -s ~/knowledge/skills/process-report/scripts`
  green. Record the script's output total for session
  `4256d730-c936-45ca-9d59-929c2ad58735` against its `cost-state.modelUsage.*.outputTokens`
  (251 368), the difference explained or stated unexplained; the known difference
  goes into SKILL.md's gaps. They need not match; the claim is a second-source check.
- **O2 derived figures (executable).** Fixtures and asserts for: agent linking
  (role, name, parent, tokens); screenshot count (one `browser_take_screenshot`,
  one `Read` of a `.png`) and `Artifact` times; the round count (must count: plain
  string, text-block list, human `queued_command`; must not: task-notification,
  `<agent-message`, `<command-name>`, `<local-command-stdout>`, `isMeta`, tool
  result, sidechain user line, `queue-operation`, a queued prompt also delivered as
  a `user` line, counted once); a session straddling `--since` (only inside lines
  count; `--until` inclusive); task rows with two tasks keyed from paths, one
  keyed only by `#<n>` (matched by a commit subject), one prompt with an unmatched `#333` (`unassigned`), one prompt with both a path key and `#<n>` (path wins), one spawn and one commit with no key (`unassigned`), one
  commit touching two keys (`ambiguous`), reviewer spawns, a window over 48 h
  (`spans N days`), the `Class:` match and its `unknown`, the lead's final row,
  the `>half unassigned` label; top five by both rankings; a repeated
  `python3 -m unittest` by two agents in one cwd versus two cwds (candidate once
  versus none), and `git commit -m "add test"` not matching;
  `rounds_before_first_screenshot` with a screenshot and with none (`none`);
  `--markdown` equal to a stored golden file.
- **O3 robustness (executable).** Malformed line, empty file, missing `subagents`
  dir, missing `usage`, empty period (valid JSON, empty lists), unreadable meta:
  no traceback, correct `skipped`; nonexistent project dir: exit 1 with near misses.
- **O4 real data (executable).** From `/tmp`: `python3 -I <skill>/scripts/transcript_stats.py --project-dir ~/.claude/projects/-home-jlewandowski-dev-public-dev-tools --days 7 --git /home/jlewandowski/dev/public/dev-tools`;
  valid JSON (`python3 -m json.tool`), `skipped` reported, agents with a line in the
  period equal the `subagents/*.meta.json` whose transcript has one (counted
  separately). Record counts and the `unassigned` shares.
- **O5 check (executable).** `--check REPORT --stats JSON` passes on fixture
  `good-report.md` (golden skeleton, judgement and prose filled, `Review:` line)
  and fails with the named reason on: missing heading, wrong order, 1 501 words,
  leftover `TODO`, one script-filled cell changed, `1,234` for `1234`, a missing or
  malformed `Review:` line; a changed judgement cell still passes.
- **O6 skill text and install path (read).** `report-template.md` has the eight
  headings in order; SKILL.md `name` equals the directory, `description` under 500
  characters, no steps; body under 500 words (`wc -w`); it states the period rule,
  the five steps with the reviewer's sample and two-round limit, the output path,
  `unknown`, agy usage from delegation reports; `SKILL.md` sits at the directory
  top; `du -sk` under 100.
- **O7 no project content (executable).**
  `grep -rniE 'dev-tools|amen|skippy|krzysiu|jlewandowski' ~/knowledge/skills/process-report --include='*.md'`
  returns nothing outside `scripts/fixtures/` (list any fixture place by name); no
  absolute home path in the script.
- **O8 format (executable).** `ruff check` and `ruff format --check`, version
  pinned in `dev-tools/requirements-dev.txt`, pass on the three Python files.
- **O9 register (read).** `dev-tools/PROJECT_MAP.md` coupling register has the
  row (including `queued_command` and `cost-state`) with the `# reads-outside:`
  prefix that `grep -rn 'reads-outside:' ~/knowledge/skills/process-report` finds.
- **O10 dry run (executable).** Following SKILL.md steps 1 to 3 for this
  project's last 7 days, produce a report in `.tmp/` (untracked) that passes
  `--check`; record the skeleton's word count on real data (if over about 900,
  reduce the row cap or the columns, not the prose budget) and what in SKILL.md
  was unclear. Step 4 needs a spawned reviewer, which an implementer cannot do:
  proved only by the O6 read and by first real use.

Impact set: none outside the new directory and the register row. The implementer
runs `grep -rn 'process-report' ~/knowledge dev-tools --include='*.md' --include='*.sh' --include='*.py'`
before starting and records the count (expected: this brief and the task
statement). No residue obligation: an addition has no old shape.

## Assumptions

- Verified (real files, 2026-11-09): transcript layout, duplicate assistant lines,
  `cost-state` and `meta.json` fields, the `queued_command` attachment,
  `ai-knowledge` copying the whole directory.
- Inferred: the Claude Code format stays as seen (versions are printed so a change
  shows); `cost-state` covers the main session only (O1); `.tmp/` is a good default
  place.
- Decided by the lead, 2026-11-09, for the user's approval: report not committed;
  1 500-word budget; `mockup` apart from `ui-design`.
- Guessed, no decision rides on it: the 25-word row, 15-row, 48 h and
  seven-suggestion limits, the half-unassigned threshold.
- Left out for lack of a trigger: automatic task kind, a price table, a key map,
  more plan formats, tool-result analysis, an `--output` option.

## Open questions

None new.
