# Evidence: report sync through refs/reports

## R9 host smoke on the real GitHub remote (run by the user, 2026-11-09)

Run on the host in `~/.ai-sandbox/knowledge/main`, the brief's R9 block wrapped in
`bash <<'EOF'` (only so that `set -e` does not close the user's shell). Output as
pasted by the user, abridged to the lines that settle each step:

- push: `* [new reference] 83609236d2834f31002aeaa57b7058c6aa3dda0f -> refs/reports/9999-12-31-smoke-test-0000`
- `ls-remote origin 'refs/reports/*'`: `83609236... refs/reports/9999-12-31-smoke-test-0000`
- `fetch --prune origin` in the host checkout: no report ref taken (it pruned 30 stale
  `origin/proposal/*` tracking refs of already-deleted remote branches); the following
  `for-each-ref refs/reports` printed nothing.
- scratch repo `fetch origin 'refs/reports/*:refs/reports/*'`: `* [new ref] refs/reports/9999-12-31-smoke-test-0000`;
  `for-each-ref`: `83609236... commit refs/reports/9999-12-31-smoke-test-0000`
- leased delete: `- [deleted] refs/reports/9999-12-31-smoke-test-0000`
- final `ls-remote origin 'refs/reports/*'`: printed nothing.

Result: GitHub accepts push, fetch by explicit refspec and leased delete of a custom
`refs/reports/*` namespace; default fetch does not take it. The brief's feasibility
assumption holds. Recorded by Skippy Wspaniały (lead).

## Implementation (Zuzia, implementer 1)

Commits, dev-tools: 4ec9305 (fix: prune host checkout), d3a3bd7 (feat: sync reports),
16c33f7 (doctor + sandbox note + comments), 44898fa (integrator skill, shared-knowledge.md,
PROJECT_MAP), 6f70d42 (seed README). ~/knowledge: 756f196 (process-report skill + README).

### B0 baseline (base tree 8bcbfdc)
`bash tests/ai-sandbox/test-knowledge.sh` -> `387 run, 0 failed`. `agent_log_trimmer` is not
installed in this sandbox (`No module named agent_log_trimmer`), so the log was read directly.
`ai-knowledge proposals` output saved (478 bytes).

### R1
After: `454 run, 0 failed`; `cmp` of `ai-knowledge proposals` before/after: identical. `git diff
8bcbfdc -- tests/ai-sandbox/test-knowledge.sh | grep '^-[^-]'` shows exactly two removed lines: the
two assertions on the manual-fetch hint text, edited for the prune fix (extra entry below; the
coordinator asked for the HINT_FETCH text to change, so those two had to change). Everything else is
additions. Also asserted in the suite: "proposals listing unchanged by reports".

### R2, R3, R4, R5 (tests written first; red run 27 failed of 452 before the host code, then green)
Section "reports: refs/reports/<name>" of tests/ai-sandbox/test-knowledge.sh, `report_in` helper:
pushed in-scope report; refused: path outside reports/, path in proposals/, off-pattern name, orphan,
proposal branch touching reports/ (each named in the status, none on the remote); mixed proposal+report
run; offline pending (`offline:`, count, hint printed, ref kept) then pushed and dropped when online;
integrator receives the ref and `reports --repo` lists it; tombstone hides it; writer-clone tombstone
ignored; offline close keeps all, next sync completes (remote, integrator ref, tombstone gone); stale
lease keeps all and reports the name in the status; off-pattern tombstone ignored; hook: report/*
bad path 1, good path 0, proposal/* with reports/ 1 with the old text, main 1 naming propose-rule.
R5: existing and fresh (`git clone file://...`; a plain-path clone hardlinks all objects, so it cannot
be used) clones have no `refs/reports` and `cat-file -e` fails; host KNOWLEDGE_MAIN has no report ref;
`git log --full-history main -- reports/` empty on remote and integrator after a file/sync/close/sync cycle.
Final run of this suite after the last edit: `454 run, 0 failed`.

### Extra: host checkout prune (coordinator's request, 4ec9305)
Test first: "host checkout drops the tracking ref of a deleted proposal" failed red (`not ok 385`),
then green with `--prune` on the fetches at the old lines 221 and 408 and in the HINT_FETCH text.
Hint assertions at two sites edited (see R1). Reports are never fetched there (R5 assertion).

### R6
- seed README and ~/knowledge/README.md: `diff` empty.
- process-report body: `awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' skills/process-report/SKILL.md | wc -w` -> 499.
  Cut: Known gaps bullets on output-token summing, the USD/token ratio figures and the task-key
  sources (named in 756f196's message).
- Ref name, path rule, invariant, close command are present in: knowledge-integrate Reports section,
  process-report step 6 (ref, path, never on main; close command is the integrator's, not the writer's),
  READMEs, docs/shared-knowledge.md, KNOWLEDGE_NOTE (name + invariant; the close command is not in the
  note, which is the writer's view). Asserted in the suite: note names `refs/reports/<date>-<project>-<hex>, outside main and every branch`.
- `grep -n 'proposal/\*\|ai-knowledge proposals' docs/shared-knowledge.md`: 189 (reports row added after),
  191 propose-specific, 313 (hook, report arm added), 326 (step 5 added for reports), 342-343 (integrator
  paragraph extended), 395 proposal-specific (empty-branch repair), 446-447 (reports paragraph added
  after), 475 (table row names both).

### R7 residue
Command: `grep -rIn --exclude-dir=.git --exclude-dir=.tmp -e 'proposal/\*' -e 'proposal/<' -e 'PROPOSAL_RE' -e 'ai-knowledge proposals' .`
-> 102 hits, hits under docs/superpowers/ ignored. Remaining non-docs hits are proposal-specific on
purpose: ai-knowledge header/usage lines, `PROPOSAL_RE`, the proposal fetch/loops/lease deletion,
`cmd_proposals`, `cmd_propose`, the hook `proposal/*` arm; ai-sandbox-migrate-knowledge (legacy
conversion); create-ai-sandbox.sh 210/1053/1603 (each followed by a report counterpart: help text,
KNOWLEDGE_NOTE, doctor loop); seed propose-rule skill and proposals/README.md; knowledge-integrate
proposal steps (Reports section added); PROJECT_MAP rows (reports added); tests/stub lease-timeout
(`:refs/heads/proposal/*` only, no amend path for reports); test lines are proposal tests.
`grep -n "PROPOSAL_RE\|proposal/\*\|proposals/" bin/ai/ai-knowledge`: all in proposal code, unchanged.

### R8 gate
`bash tests/ai-sandbox/run-tests.sh` after the last edit: all suites `0 failed` except test-delegate
`69 run, 2 failed` (not ok 54 "writer prompt has no-tools line", 59 "second-reviewer prompt has no-commands
line"). Not touched by this change (ai-delegate prompts); memory notes record test-delegate as
pre-existing failing. test-knowledge `454 run, 0 failed`. Not fixed.

## Fix round (review 2026-11-09-report-sync-review.md)

Commit: see `git log` subject "fix: close a report whose remote ref is gone, stop re-pushing fetched reports".
- I1: tests first (red: 7 failed of 467 before the code change): own report closed before any push,
  remote ref deleted but local cleanup missed, moved remote ref still kept and reported. Fix: on
  "stale info" the host runs `ls-remote origin refs/reports/<name>`; empty counts as closed. docs/shared-knowledge.md
  close paragraph aligned. Green.
- M1: the integrator reads one `ls-remote origin 'refs/reports/*'` and skips refs whose tip matches; tests:
  second no-op sync has no `reports pushed`; an integrator-written report the remote lacks is pushed,
  counted and kept. (One red line, 459, came from my own leftover `Odd_Name` remote ref from an earlier
  test; that test now removes it.)
- M2: doctor reads `.git/ai-knowledge-role`; integrator reports are labelled "open: close it with a
  refs/reports-closed tombstone". Asserted only that the doctor script reads the role file.
- M3: left as is.
Suite after the last edit: `bash tests/ai-sandbox/test-knowledge.sh` -> `467 run, 0 failed`.

Gate re-run on c60c3c0: `bash tests/ai-sandbox/run-tests.sh` (exit 1). Per-suite lines in order:
32, 151, 56, 13 run 0 failed; test-delegate `69 run, 2 failed` (not ok 54 writer prompt has no-tools line,
not ok 59 second-reviewer prompt has no-commands line; pre-existing, same as the first gate); then
17, 5, 23, 20, 19, 17, 14 run 0 failed; test-knowledge `467 run, 0 failed`; then 32, 30, 33, 65, 27, 39, 79 run
0 failed; final line `SOME SUITES FAILED` (only the two test-delegate cases).
