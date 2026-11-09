# 2026-11-09-ui-track-fixes

Commit (~/knowledge main, unpushed): fab0379. Base abbc2b9. git diff --stat: decisions.md, roles/planner.md, roles/reviewer.md, rules/global.md only.
Method: script /tmp/claude-1000/s/land.py extracts each Old/New block from the spec's Amendment A1 and replaces in the file. Known case: before applying, the extracted Old blocks were counted in the tree (check mode) and each matched exactly once, proving the extraction reproduces the landed text byte for byte.

| Block | File | Old before/after | New before/after |
|---|---|---|---|
| G8 | rules/global.md | 1 / 0 | 0 / 1 |
| P1 | roles/planner.md | 1 / 0 | 0 / 1 |
| P2 | roles/planner.md | 1 / 0 | 0 / 1 |
| R1 | roles/reviewer.md | 1 / 0 | 0 / 1 |

decisions.md entry prepended under "## Entries" (landing date 2026-11-09).
wc -w rules/global.md: before 6912, after 6912.
