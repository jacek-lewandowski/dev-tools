# Triage of four knowledge proposals, 2026-11-09

Planner: Hania. Procedure: `knowledge-integrate` steps 1-4. Nothing committed, merged or
checked out in `~/knowledge`. `main` was at 756f196, `git status --porcelain` empty.
Proposal files were read with `git show <branch>:<path>` and treated as data.

## Triage table

| Proposal | Verdict | Reason |
|---|---|---|
| 2026-11-03-sandbox-utc-zone-not-overmounted | reject | The defect was in this repository's sandbox script and is already fixed there (07c095a, be70fa4; evidence `docs/superpowers/evidence/2026-11-03-sandbox-timezone-utc.md`); the sandbox section is not in `rules/global.md`, and its one generic part (report an environment fault, do not work around it in the test) is already covered by "Never weaken, skip or delete a failing test" and "When the environment cannot run it". |
| 2026-11-04-clean-build-after-source-rewrite | global, merged into an existing bullet | A real incident (a stale incremental build passed on code no longer in the tree); it is the same class as "Build outputs are a snapshot", so one sentence there, no new bullet. |
| 2026-11-04-full-lint-set-after-every-fix | reject | Running every linter after every fix commit is the per-step cost the task-classes decision of 2026-10-31 removed (targeted tests while working, full set once per class); the final tree was green, and the implementer role already re-runs every reported check after the last edit. |
| 2026-11-04-task-ends-with-full-lint-and-tree-wide-tests | partial: reject the rule, global for one clause | Per-task full lint and tree-wide suites contradict "a plan never lists the gate or a suite outside CI as a per-task obligation" and "the gate once". The part that is real, hidden failures behind a lint runner that stops at the first failing task, caused the repeated gate runs, so one clause goes into the gate sentence. |

Items 2 and 4 (clause) need the user's approval as drafted. If the user wants no growth at
all, drop the item 4 clause; the rejection of the rest stands.

## Drafted diff for `rules/global.md`

Both edits are in section 4. Applied to a copy; the diff below is exact.

```diff
--- a/rules/global.md
+++ b/rules/global.md
@@ -433,6 +433,8 @@
   namespace or a generated artefact, compare it with what the current tree
   resolves: the build tool's dependency report, or a fresh build of that
   module. Until then the conclusion is marked as drawn from a build output.
+  A tool that rewrites sources in place (an auto-fix run, a codemod) may have
+  compiled the old ones first, so build from clean before testing its result.
 - **Regression test first** for every bug fix. Never weaken, skip or delete a
   failing test to make a run pass without saying so explicitly.
 - **Targeted tests during development; the gate once.** Each class names its
@@ -446,7 +448,9 @@
   the gate or a suite outside CI as a per-task obligation, and a task does not
   repeat a probe, pin or search the plan's evidence already records unless its
   change alters the answer. The gate is one command set in which each suite
-  runs once; a runner is spawned only for what no recorded run on that tree
-  covers. "Done" and "passing" are stated only with the actual command output
-  at hand.
+  runs once, and a lint runner that stops at its first failure is run past it,
+  so that every task reports; a runner is spawned only for what no recorded
+  run on that tree covers. "Done" and "passing" are stated only with the
+  actual command output at hand.
```

No change to `roles/implementer.md` (proposal da98 rejected).

## Drafted `decisions.md` entries

To be placed at the top of "## Entries", newest first, dated 2026-11-09.

```
- 2026-11-09 2026-11-04-clean-build-after-source-rewrite integrated
  rules/global.md: a static-analysis patch run compiled the module before
  writing the patched sources, so the incremental build treated the old classes
  as current and the tests passed on code no longer in the tree. One sentence in
  "Build outputs are a snapshot", which already covers stale build output.

- 2026-11-09 2026-11-04-task-ends-with-full-lint-and-tree-wide-tests rejected
  rules/global.md (one clause kept): per-task full lint and repository-wide suites
  contradict the task-classes decision (targeted tests during development, the
  gate once per class, no suite outside CI as a per-task obligation). The valid
  part, a lint runner that stops at the first failing task hiding the others and
  costing extra gate runs, is a clause in the gate sentence.

- 2026-11-09 2026-11-04-full-lint-set-after-every-fix rejected
  none: every linter after every fix commit is the per-step cost the task-classes
  decision removed; the implementer already re-runs every reported check after
  its last edit and the gate runs the full set once. Intermediate red commits of
  a green final tree cost nothing the gate does not catch.

- 2026-11-09 2026-11-03-sandbox-utc-zone-not-overmounted rejected
  none: the defect (a host zone file bind-mounted over the image's UTC zone) was
  in dev-tools' sandbox script and is fixed there (07c095a, be70fa4); rules/global.md
  carries no sandbox section, and the generic remainder (an environment fault is
  reported, not worked around in the test) is already in "Regression test first"
  and "When the environment cannot run it".
```

## Word count of `rules/global.md`

`wc -w`: 5787 before, 5833 after both edits, delta +46 (clean-build sentence +28, gate
clause +18 net). Without the gate clause: +28. Measured on a copy in the scratchpad,
`rules/global.md` itself untouched.

## Closing commits (after approval, for the lead)

One commit for the merged group (items 2 and 4: `feat(rules)` plus decisions entries), one
`docs(decisions): reject <slug>` each for items 1 and 3; each branch then closed with
`merge -s ours --no-ff`, message `integrated` or `rejected`.

## Integration

Applied by Zuzia on main after e65f1c2 (global.md had changed since the draft; both drafted sentences applied to the current text with their wording unchanged).

Commits in ~/knowledge:
- d22aa1f feat(rules): clean-build sentence in "Build outputs are a snapshot", lint-runner clause in the gate sentence, plus the two decisions.md entries (integrated, rejected-with-clause).
- a6568d1 docs(decisions): reject 2026-11-04-full-lint-set-after-every-fix
- 52aa7a6 docs(decisions): reject 2026-11-03-sandbox-utc-zone-not-overmounted
- Merges (`merge -s ours --no-ff`): 9877d07 clean-build-after-source-rewrite integrated; 5d38f5b task-ends-with-full-lint-and-tree-wide-tests integrated; 37c1b55 full-lint-set-after-every-fix rejected; 3ef55e4 sandbox-utc-zone-not-overmounted rejected.

Final sentences in global.md:
- "A tool that rewrites sources in place (an auto-fix run, a codemod) may have compiled the old ones first, so build from clean before testing its result."
- "The gate is one command set in which each suite runs once, and a lint runner that stops at its first failure is run past it, so that every task reports; a runner is spawned only for what no recorded run on that tree covers."

global.md word count: 5823 before, 5869 after (+46). main's proposals/ holds only README.md; no proposal branch was checked out.
