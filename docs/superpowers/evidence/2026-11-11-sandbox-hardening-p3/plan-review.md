Task: 2026-11-11-sandbox-hardening

# Phase 3 plan review, round 1

Fiona (reviewer 1), 2026-11-13. Object: `docs/superpowers/plans/2026-11-11-sandbox-hardening-p3-plan.md`
and its evidence file, against the spec ("Phase 3", C-MODULES, A4, A5, D15, "Inputs") and the tree
`273b538` (exported to a scratch directory; read only).

Re-run unchanged, same results: S1 (12 lines), S2 (2), S3 (per-file list), S4 (1, `test-tools.sh:32`),
S-src (empty, rc 1; known case 32), S5 (14), S7 (105 lines, three `declare` sites 608/653/884),
P7 (238, 9, sources-file line 366), P9 (`d56fcf0`..`273b538` code diff empty), the heredoc count (37).
S6 is recorded with an elided command; a reconstruction gives the same 22 names, 15 used nowhere else.

**Verdict: blocking, one Important finding.** PA8 (the plan asks the reviewer): accepted, since
C-MODULES mandates the change to `test-host-git.sh`'s exception and P2 names those cases.

## Important

**I1 The pin does not detect a misplaced silent gate.** Place: "Pin matrix" (K1 to K14), O1, P1, and
the "Failure" state (plan lines 72-73), which has no settling check. T04 writes the order of the
stage calls by hand. Several base steps print nothing when they pass: the budget gate (create 376), the
prerequisite checks (340-344), the I10 running-container refusal (406), the D9 path check (413), the
tools-directory lookup (491-494), the display-backend and display checks (575, 688-732) and the
capacity check (2872). Where such a step runs only changes what a *refused* run leaves behind. Every
matrix case except K14 is a success path, and K14 fails during option parsing.
Scenario: T04 calls the project stage, which creates `<sandbox dir>` and writes `project-path` (base
455), before the budget gate. On a host with no budget, create now leaves a sandbox directory behind. K1
to K14 stay byte-identical, and the suite still passes, because `test-capacity.sh` 164-168 asserts only
that no `.env` exists. I10 and D9 are covered by `test-build-caches.sh`. Nothing covers the others.
Correction: add refusal cases to the matrix, each driven through its real input, so the manifest
records the exit status, the output and what was left under the root. The cases are: no budget; an
invalid budget; a missing prerequisite (a `PATH` without `rsync`); a failing `docker compose`; a
running container, with and without `--no-start`; a `,` in `HOME`; `--display=xpra` with no backend;
`wayland` without `WAYLAND_DISPLAY`; `host` without `DISPLAY`; a full budget on the K13 path. Then
extend O1's method check: move the budget gate after project resolution and show that the manifest
differs.

## Minor (not blocking; left to the planner unless marked fixed)

- **M1 PA2 misses one difference between top-level code and a function.** Under `set -e`, a function
  whose last command is a failed `&&`-list returns 1, and the entry's plain call then ends the script
  silently. At top level the same line does not. Probe:
  `bash -c 'set -euo pipefail; f(){ X=1; [ "$X" = 2 ] && echo two; }; f; echo after-f'` exits 1
  without printing; the same line at top level continues. Base sites: create 651 (`[ -f "$ENV_FILE" ] &&
  CPUSET=...`) and 808 (the audio-devices `&&` chain). K1 takes the false branch of both, so P1 would
  catch the failure. Still, PA2 is marked "verified". Correction: add this to PA2 and S7 with the probe,
  and have T03 state how a stage that ends on such a line keeps the base's status.
- **M2 The rule for O7 lets some side effects through.** `top-level-effect.yml` reports nothing for
  `[[ -n "$X" ]]`, `unset Y`, `readonly Z=$(date)`, `export W=1` or `declare -g A=$(touch ...)` at a
  module's top level (probe file with all five: only `((n++))` was reported). Correction: add
  `test_command`, `unset_command`, and declaration commands that contain a command substitution or use
  `export`. Add each as a known case in P7.
- **M3 Untested branches on the success path.** No case covers:
  - `--rebuild` (2886, 2897);
  - the image-up-to-date path (2890), which B3 relies on;
  - `--audio --no-audio` in K14;
  - a start with a display mode (the display starts before `compose up`, 2878).

  Correction: add these cases, or name them in "Left out" with the reason.
- **M4 O4 does not check file modes.** `diff -r --no-dereference` ignores modes, so the mechanical
  commit's modes are not shown to come from the script. Correction: also compare modes, for example
  with `find . -printf '%m %y %p\n' | LC_ALL=C sort` on both exports.
- **M5 The order between the two output streams is not pinned.** stdout and stderr are recorded
  separately, so a `warn` moved past a `log` passes P1. Correction: also record a combined stream per
  case.
- **M6 S6 is not re-runnable unchanged.** Its command is elided ("...grep -rlw..."). The reconstruction
  used here was
  `for f in $(command grep -oE '^[a-z_]+\(\)' bin/ai/create-ai-sandbox.sh | tr -d '()' | sort -u); do command grep -rlw -- "$f" bin tests tools verify-ai-sandbox-on-host.sh .githooks .agents | command grep -v 'bin/ai/create-ai-sandbox.sh' | wc -l; done`.
  Correction: record the exact command.
- **M7 One step's order does change.** The self-location block (base 352-361) runs after option parsing
  and the prerequisite checks in the base. The contract moves it before the sourcing lines, so it runs
  before every stage. Nothing observable changes (no output, `cd` only in subshells). Still, "Execution
  order stays the base's" should name this move as the one deliberate exception.
- **M8 Fixed: the re-check list's first item was too narrow.** Its pathspec `bin tests tools
  verify-ai-sandbox-on-host.sh .githooks` did not cover what S1, S3 and P6 read (`PROJECT_MAP.md`,
  `README.md`, `.agents`, `docs/shared-knowledge.md`, `.gitignore`). An empty diff there would have
  marked those as unchanged without checking them. Changed in the evidence file: item 1 now uses
  `-- . ':(exclude)docs/superpowers'`, and S6 is added to item 2. Known case: the same pathspec between
  `273b538` and `main` lists 22 files (phase 1's code).
- **M9 Fixed: O9's expected result missed two hits in the base.** `command grep -rnaE 'image/' bin/ai
  --exclude-dir=image` finds create 205 (usage text, which moves to `options.sh`) and `ai-sandbox-rm:2`
  (a comment). O9 now names both as hits that stay.

Committed text: the plan and evidence name finding H3 by its key only. Nothing from
`.tmp/security/` and no finding's input appears.

## Round 2

Fiona (reviewer 1), 2026-11-13. Delta read: the plan, the plan evidence file (P2, S6, S7, P7,
P11, re-check list), `top-level-effect.yml`, the P11 probe script and its output, and
`author-answers.md`.

**Verdict: not blocking.** Critical 0, Important 0, Minor 2 (both fixed here).

Re-run unchanged, same results:
- the `and-tail` search: lines 651 and 808; known-case file lines 1, 4, 5, 6;
- the `!` search: 0;
- `top-level-effect.yml` on the base: 246; on the lib: 9; on P7's 15-line file: lines 1-7, 13, 14, 15; on round 1's probe file, all five constructs it missed are now reported;
- the method check, read from the recorded probe output: `B` and `Bmoved` refusals differ in R1 and R2 only (the "== Project" lines, one `container inspect`, the sandbox directory and `project-path`). The start runs differ only in the `already seeded on` time.

How each round-1 finding closed:
- I1: refusal cases K15-K27 and K30, each driven through its real input. Probe P11 records how each one ends on the base and what it leaves behind, and O1 gains the moved-gate method check.
- M1: PA2, S7 and P2 now cover a false `&&`-list or `!` command as a stage's last statement. T03 closes such a stage with `return 0`, and P3 lists that line kind.
- M2: the rule is extended and gets known cases.
- M3: K28, K29 and K30 are added, and K14 gets `--audio --no-audio`. A display start that succeeds is left out, with a reason I accept: K30 already pins where the display starts.
- M4: O4 also compares modes.
- M5: every case runs a second time with stdout and stderr combined, and O1 has a method check for it.
- M6: the exact S6 command is recorded.
- M7: the moved self-location block is now named as the one deliberate change of order.

New material:
- N3 (the `already seeded on <time>` line) and the added environment pins (`IDEA_HOST_DIR`, `HOST_SND_DIR`, `XDG_RUNTIME_DIR`) add nothing blocking. N3 is N1's value printed again, and the pins close the host dependence that P11 found.
- I checked the committed files, the probe output included. Paths are replaced by placeholders, and no scratch path, real home or `.tmp/security` content remains. The output does show the uid 1000, `/opt/idea-IU` and the timezone `Europe/Warsaw`. All three are already committed in `main` (tests, evidence, create).

Minor, fixed:
- **M10:** the re-check list's item 5 still said "N1 and N2 only". It now reads "P4 and P11 ... N1 to N3".
- **M11:** N3 was defined for stdout only. The second run's combined stream carries the same line, so the plan now names both streams.
