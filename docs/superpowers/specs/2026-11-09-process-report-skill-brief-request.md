# Task statement: a skill that writes a process report

Stated by Skippy Wspaniały (lead), 2026-11-09. Class: **brief** (a new skill
directory in `~/knowledge/skills/`, probably with a small helper script and its
test; no contract, no stored data; this sandbox is the integrator and commits
on `~/knowledge` `main`, the host pushes on sync). The planner writes the brief;
a reviewer checks it; the user approves; one implementer lands it; one diff
review follows.

## What the user asked (2026-11-09, translated from Polish)

"I need a skill that generates a summary of the process over the last days of
work: what kind of work it was, how it went, how fast, whether it was
economical, what was unnecessary, what to improve: everything you need to
improve the process. Note: new kinds of tasks may appear that will need
separate roles."

Context the user added: this week many tasks were UI/UX work: building web
pages, visual refactoring of web sites and of React Native mobile apps. It was
very slow and generally poor. The user suspects that a mockup should be
prototyped quickly as HTML and judged by the user in a short interactive loop,
instead of going through brief, spec, plan, implementation, review, fixes and
tests; the accepted mockup then becomes the design to fill with real data. The
user also asks whether UI/UX design and refactoring should be a separate kind
of task. Those questions are answered after the reports arrive; the skill must
collect the data that answers them.

## How the reports are used

The skill runs in each project sandbox, by that project's lead, over a period
the user names (default: since a date or the last N days). The user carries
the resulting file to the integrator sandbox (dev-tools), where the lead
compares reports across projects and proposes rule changes. So reports must be
comparable across projects, in English, and short enough to read several at
once.

## Prior round to learn from (2026-10-31)

- The prompt the leads got then is quoted in full at the end of this file.
- The four reports it produced: `dev-tools/.tmp/process-report1.md`,
  `process-repor2t.md`, `process-report3.md`, `process-report4.md`; the
  synthesis: `dev-tools/.tmp/process-report-synthesis.md`. The spec that came
  out of them: `docs/superpowers/specs/2026-10-31-task-classes-design.md`.
- What went wrong then, visible in those files: every lead re-derived the token
  method from transcripts on its own (report 1 "Sources and method"); the
  notification field `subagent_tokens` turned out to be the final context size,
  not a total; output tokens are missing in older transcripts; agy delegation
  usage was not recorded; report 4 ran to about 10 900 words. A shared,
  tested extraction method would remove the re-derivation and make figures
  comparable. Prior art for reading transcripts:
  `dev-tools/tools/context_statusline/statusline.py` and its fixtures.
- That prompt said "facts only, no proposals". The user now explicitly wants
  "what to improve" as well: keep facts and the lead's suggestions in separate
  sections.

## What the report must answer that the 2026-10-31 prompt did not

- The kind of each task in a taxonomy wide enough for work the classes do not
  fit yet (UI/UX design, visual refactoring, mockups, mobile), and where a task
  did not fit the class it was given, or the roles it went through.
- For UI/UX and other work judged by eye: how many rounds with the user until
  the result was accepted, time to the first thing the user could look at,
  whether any agent looked at a rendered result (screenshot) before the user
  did, rework caused by a visual miss rather than a defect, and which steps of
  the process produced no change to what the user saw.
- Time, tokens and agents per step, as in the prior round, by a method checked
  on a known case (global rules, section 4).

## The prompt of 2026-10-31

```
Write a process cost report for the last 5 to 8 tasks closed in this project
(or all since 2026-10-25, whichever is more), to <path>/process-report.md.
Build it from files, not from memory: evidence files, review reports,
delegation reports (their `usage` field), task notifications with token
counts, git log. One table row per task with: task id or commit; kind of
change (text/asset, config value, bug fix, feature, refactor, contract);
diff size (files, lines); the tier it went through (instruction in message,
brief, phase plan); agents spawned per role and the number of review rounds;
wall-clock from first spawn to "done"; tokens per role where known; number of
obligations and evidence entries; how many of those the reviewer re-ran;
findings per round with severity, and how many turned out not to hold.
Below the table, three lists: (1) the five most expensive single steps across
all tasks, each with the rule sentence (file and quote) that required it;
(2) steps repeated by two agents on the same tree (which, how often);
(3) what you would drop for tasks of each kind without losing a defect the
reports show was actually caught. Facts only; no proposals for new rules.
```
