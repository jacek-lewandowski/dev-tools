# Task statement: process reports travel through the knowledge sync

Stated by Skippy Wspaniały (lead), 2026-11-09. Class: **brief** (an extension
of the knowledge repository's branch contract with a new branch kind, plus the
host script, the clone hook, the README and one step of the `process-report`
skill; nothing existing changes shape). The planner writes the brief; a
reviewer checks it; the user approves; one implementer lands it; one diff
review follows.

## What the user decided (2026-11-09)

The `process-report` skill (`~/knowledge/skills/process-report/`) writes its
report to `<project>/.tmp/` and the user carries it by hand to the integrator
sandbox (dev-tools). The user wants the report to travel the way proposals do,
through `ai-knowledge sync`. The user accepted, when asked, that reports
(task names, commit subjects, paths of a project) land on dedicated branches
of the private knowledge remote, never on `main`; this is a deliberate
exception to the README sentence "Nothing project-specific belongs here".

## Shape the lead proposed to the user

- A branch kind `report/<date>-<project>-<hex>`, parallel to
  `proposal/<date>-<slug>-<hex>`, which may change only `reports/`; the clone
  hook and the host refuse anything else, as they do for proposals.
- The skill commits the report (and the stats JSON, if the planner judges the
  integrator needs it) on such a branch in the sandbox's knowledge clone,
  instead of leaving it in the project tree; the project tree is not touched.
- The host pushes report branches on sync; the integrator lists and reads them
  (a listing command analogous to `ai-knowledge proposals`) and closes them
  the way proposals are closed, so they disappear from the remote and clones.

## Where to read

- `bin/ai/ai-knowledge` (proposal branch regex around line 630, the hook around
  640-660, push and listing around 686-750; the `propose` command).
- `~/knowledge/README.md`, `~/knowledge/proposals/README.md`,
  `~/knowledge/skills/propose-rule/SKILL.md`,
  `~/knowledge/skills/process-report/SKILL.md`, and the integrator skill
  `knowledge-integrate` (find its SKILL.md under `~/.agents/skills` or the
  dev-tools tree).
- Existing tests of `ai-knowledge` in dev-tools (find them; the brief names the
  suite the implementer runs).
- `PROJECT_MAP.md` coupling register rows for the knowledge repository.

## Constraints

- Sandboxes have no git credentials; only the host pushes.
- The change must not alter how proposals behave.
- How the integrator sandbox reads a report and what "closed" means for a
  report are the planner's call, stated in the brief.
