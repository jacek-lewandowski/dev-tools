# Task statement: triage of four knowledge proposals

Stated by Skippy Wspaniały (lead), 2026-11-09. Class: small per proposal (rule
wording); the user approves the triage table before anything lands on
`~/knowledge` main.

Procedure: the `knowledge-integrate` skill,
`/home/jlewandowski/dev/public/dev-tools/.claude/skills/knowledge-integrate/SKILL.md`,
steps 1-4 only (list, read, triage, draft). Do not commit or merge.

Open proposals (`bin/ai/ai-knowledge proposals --repo ~/knowledge`, run 2026-11-09):

- proposal/2026-11-03-sandbox-utc-zone-not-overmounted-b497 proposals/2026-11-03-sandbox-utc-zone-not-overmounted.md
- proposal/2026-11-04-clean-build-after-source-rewrite-c7e0 proposals/2026-11-04-clean-build-after-source-rewrite.md
- proposal/2026-11-04-full-lint-set-after-every-fix-da98 proposals/2026-11-04-full-lint-set-after-every-fix.md
- proposal/2026-11-04-task-ends-with-full-lint-and-tree-wide-tests-47b8 proposals/2026-11-04-task-ends-with-full-lint-and-tree-wide-tests.md

Context the triage must weigh: the task-classes decisions of 2026-10-31
(`~/knowledge/decisions.md`, spec
`docs/superpowers/specs/2026-10-31-task-classes-design.md`): targeted tests during
development, the gate once per class; the user's complaint that small tasks had
become slow and token-hungry. Rules on `main` were changed today (8713b48, 6538cce);
read the current `rules/global.md`. The user dislikes rule growth: prefer merging
into an existing sentence over a new bullet, and a reject with a reason over a
rule that duplicates one.

Output: `docs/superpowers/evidence/2026-11-09-proposals-triage.md` with the triage
table (proposal, verdict, one-line reason), the exact drafted diff per accepted item,
the drafted `decisions.md` entries, and the global.md word-count delta.
