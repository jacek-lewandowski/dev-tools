Task: 2026-11-11-sandbox-hardening

# Phase 3 plan: answers of the spec's author

By Hania (planner 1), the spec's author, on 2026-11-13. These answers cover the plan
`docs/superpowers/plans/2026-11-11-sandbox-hardening-p3-plan.md`, section "Read this
first". They were checked against the spec (C-MODULES, C-GIT, C-INSTALL, "Phase 3", A5)
and against the base code at `273b538`.

Result: all three decisions, N2 and both user-visible changes are accepted. None of them
needs a spec change. Two of the acceptances come with a reading of the spec that the plan
must keep to (decision 3 and change 2).

## Decision 1: modules define functions, the entry runs them

**Accept.**
- C-MODULES fixes the order in which the modules are sourced. It gives the entry "the
  order of the stages", and the phase goal says the same: "the entry script holds only
  option defaults and the stage order".
- Defining the stages in the modules and calling them from the entry is the only way to
  get both orders. Modules that ran at their top level would execute in C-MODULES order,
  not in the base's.
- The entry also holds `set -euo pipefail`, `SCRIPT_DIR`, the eleven module lines and the
  lib's line. These are the "sourcing lines" that the spec's "Commits" paragraph
  expects. They generate nothing, so they agree with "generates nothing".

## Decision 2: parts C-MODULES does not name are placed by concern

**Accept.** Every placement in "Where each part of the base goes" fits the module whose
"Owns" cell covers it:
- The output helpers and `require` go to `project.sh`, which owns "prerequisites". They
  are defined before any stage runs, so modules sourced earlier can call them, and no
  module sources another.
- The knowledge sync call goes next to the render call in `rules.sh`.
- The extension store goes to `project.sh`, which owns "the sync of shared stores".
- The image name goes to `image.sh`.
- The remembered `.env` values go to `options.sh`, which owns "options remembered in
  `.env`".
- The knowledge-seed copy and the removal of the old `ai-delegate` copy go to
  `install.sh`. Both are part of the base's helper installation, which phase 4 replaces
  as a whole.
- The environment overrides go to the entry as option defaults.

None of these placements makes a later goal harder. In particular, phase 4 still finds the
whole helper installation in `install.sh`.

## Decision 3: `@NAME@` placeholders filled by `image.sh`

**Accept.** It is the base's own convention (`@MARKETPLACE@`). It is also what "as files
instead of heredocs" needs wherever the base's heredoc expanded a value at generation
time.

The reading the plan must keep to:
- `image.sh` fills only the placeholders it names.
- Byte identity of the filled files and of the build context is the proof, under P1.

No further guard is needed.

## N2: the time on line 1 of `status/knowledge`

**Accept.**
- A5 has a fallback: "the pin excludes the named non-deterministic lines, listed in the
  plan". N2 is such a line, and the plan lists it, so the fallback covers it.
- A5's status cell (".seeded" as the only timestamp) is out of date. I will update the
  cell when T01 settles A5. That is a change of an assumption's status, not of a goal,
  contract or invariant, so it is not a spec change.

## Change 1: `ai-delegate` and `sandbox-knowledge-sync` leave the checkout's `bin/ai`

**Accept. The spec requires this.**
- C-MODULES puts both in `image/`. It also says nothing in `image/` is installed on the
  host and C-INSTALL's `PATH` entry does not reach it.
- Neither is a host helper at the base. `ai_sandbox_helpers` at `273b538` lists neither,
  and the helper installation removes an old host copy of `ai-delegate`.
- The test paths that name them are in the plan's impact set (S1, S2, residue R1).

## Change 2: the C-GIT rule's exception becomes the `image/` directory

**Accept. The spec requires this.** C-MODULES: "C-GIT's structural rule leaves out
`image/` by directory and names no file".

For PA8, my reading of "the existing suite, whose result must be the same before and
after" (the "Pins" paragraph of the spec's "Phase 3" block) is:
- the same number of cases;
- each with the same outcome;
- the two cases that fail at the base (D15, A4) still failing as the only failures.

So `test-host-git.sh` may change the wording and subject of its named cases, because
C-MODULES moves their subject. Each edited case must still assert the property it
asserted before:
- a git call in an in-image program is exempt;
- a git call in a host script outside `image/` is reported.

Without both, the rule's known cases would stop proving it.
