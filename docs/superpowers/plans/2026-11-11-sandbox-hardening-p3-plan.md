Task: 2026-11-11-sandbox-hardening
Class: phase
Refactor flag: yes (spec, "Phase 3": behaviour unchanged, proven by pins)
Status: approved by the user on 2026-11-13 ("tak, plan zatwierdzam, implementacja po merge'u fazy 1"); implementation starts after phase 1 is merged into `main`.

# Phase 3 plan: split of `create-ai-sandbox.sh`

Phase key: `2026-11-11-sandbox-hardening-p3`. Spec:
`docs/superpowers/specs/2026-11-11-sandbox-hardening-design.md`, block "Phase 3", contract
C-MODULES (S-2), assumptions A4 and A5, "Phases at a glance", the invariants (I4, I6 and
I3a's structural rule of C-GIT are the ones this phase touches), the section "Inputs" (what
committed text may hold), and C-INSTALL, which phase 4 writes against this phase's files.
Evidence directory: `docs/superpowers/evidence/2026-11-11-sandbox-hardening-p3/`; the searches
and probes behind this plan are in `2026-11-11-sandbox-hardening-p3-plan.md` there, each with
its exact command and output, and the two rule files `top-level-effect.yml` and
`sources-file.yml` beside it. Written by Ola (planner 3) on 2026-11-13.

**Tree.** Planned against phase 1's branch tip `273b538` (phase 1 with phase 2 merged in),
whose tree is what `main` holds after phase 1's merge (the user's decision of 2026-11-13).
Phase 1 is not merged yet. The pins are taken by T01 on `main` after phase 1's merge, never
earlier (spec: phase 1 closes before phase 3 takes its pins; phase 2's plan: phase 2 lands
before them, which it has). T01 starts with the evidence file's section "Re-check when phase 1
lands on `main`".

## Read this first (for the reviewer)

- **Spec change: none.** The contracts section of the spec says "Names given here are fixed;
  everything else is the phase plan's". The plan therefore decides, within C-MODULES, the
  three choices below. The spec's author accepted all three, N2 and both changes that are not
  moves on 2026-11-13, with no spec change (evidence `author-answers.md`):
  1. **Modules define, the entry runs.** A module's top level holds only comments, `readonly`
     constants and function definitions; the entry sources the eleven modules in C-MODULES
     order and then calls their stage functions in the base's order of execution. Reason:
     C-MODULES fixes the source order, and the base runs in a different one (it checks
     capacity before it builds the image, writes the display launchers after the compose
     file, interleaves memory, image name, display and timezone; evidence P8). Sourcing
     modules that run at their top level would reorder steps and output.
  2. **Parts C-MODULES does not name** are placed by concern ("Where each part of the base
     goes", below): the output helpers and `require` in `project.sh` (prerequisites), the
     knowledge sync call beside the render call in `rules.sh`, the IDE-extension store call
     in `project.sh` (the sync of shared stores), the image name in `image.sh`, the
     environment overrides `IDEA_HOST_DIR`, `HOST_ETC_DIR`, `HOST_SND_DIR` in the entry as
     option defaults. The entry also keeps its own location and the lib's sourcing line,
     which are the "sourcing lines" of the spec's "Commits" paragraph.
  3. **Values filled at generation.** A file in `image/` that needs a value known only when it
     is generated holds a placeholder `@NAME@` that `image.sh` fills; this is the base's own
     convention (the entrypoint's `@MARKETPLACE@`, evidence S5). It applies to the
     Dockerfile's head (the pinned versions in its `ARG` lines) and to the doctor's one
     generated line (the build-cache list). The author's reading, which binds T04: `image.sh`
     fills only the placeholders it names, and the byte identity of the filled files and of
     the build context under P1 is the proof; no further guard.
- **Two contract-mandated changes that are not moves**, both from C-MODULES and both accepted
  by the author as required by the spec: `bin/ai/ai-delegate` and
  `bin/ai/sandbox-knowledge-sync` move to `bin/ai/image/`, so a host whose `PATH` names the
  checkout's `bin/ai` no longer finds them there (PA5); and the C-GIT rule's exception changes
  from two named files to the `image/` directory, which changes the wording of named cases in
  `test-host-git.sh` (PA8, P2).
- **PA8, as the author reads the spec's "result must be the same":** per file the same number
  of cases, each with the same outcome, and the two cases that fail at the base (D15, A4)
  still the only failures. `test-host-git.sh` may change the wording and subject of the cases
  whose subject C-MODULES moves, and each edited case still asserts the property it asserted
  before: a git call in an in-image program is exempt; a git call in a host script outside
  `image/` is reported. P2 and O10 are written to this reading.
- **Unverified assumptions:** PA1 (A5 across the whole matrix; settled by T01), PA4 and PA5
  for the host's own scripts (guessed none), PA9 (the base's code equals `273b538`'s; T01
  checks).
- **Folded:** nothing. Deferred list unchanged (below).
- **A5's status cell** in the spec names `.seeded` as the only timestamp; `status/knowledge`
  line 1 (N2, since phase 1) and the stdout line that echoes `.seeded` on a later run (N3,
  evidence P11) are two more. The author accepted N2 under A5's fallback and updates the cell
  when T01 settles A5; N3 is N1's value echoed, so the same fallback covers it.

## Who uses it and the states the phase touches

The user on the host runs `create-ai-sandbox.sh`; the user's independent reviewers (other
agents and models, after this phase) read the toolchain; agents inside sandboxes use what the
image bakes in. The goal is that none of them sees a difference except the reviewers, who get
small files.

- Normal: every option combination prints the same output, writes the same files with the
  same modes and builds the same build context, so the image's build hash is unchanged and an
  existing image is reused (P1). No sandbox is re-created for this phase (I6 holds trivially).
- Invalid input (unknown option, `--with-docker` with `--no-docker`, `--audio` with
  `--no-audio`, a bad `--display` or `--memory`): the same message and exit status (K14).
- Failure (no budget or an invalid one, a missing prerequisite, a failing `docker compose`, a
  running container, a `,` in a cache path, no `tools/` directory, no display backend or a
  display variable missing, a full budget, a display that does not start): the same message,
  exit status and what the refused run leaves under the root, because each refusal is a pin
  case driven through its real input (K15 to K27, K30), and P1 compares them. Several of these
  checks print nothing when they pass, so only a refused run shows where they run (evidence
  P11).
- Interruption and retry: a run stopped part-way leaves what the base leaves at that point,
  since the steps run in the same order (the refusal cases pin where each check runs); every
  run stays idempotent, and a second run over an existing root is pinned by K11 and K28.
- A state the change could reach and the base cannot: the entry finds no `create.d/` beside
  its resolved path. Trigger: a copy of `create-ai-sandbox.sh` alone, outside the checkout;
  none found (PA4). It fails at once with the shell's "No such file" for the first module.
  No guard is added (left out, below).
- The user on the host who types `ai-delegate` or `sandbox-knowledge-sync` from a `PATH` entry
  naming the checkout's `bin/ai`: no longer found. Both run only in the image (C-MODULES;
  phase 1, PA9: no documented host use).
- The phone: nothing changes; no host command is added.

## Deferred list

- E1 (egress): **keep**, phase 10 (open).
- E2 (`bin/ai/MANIFEST` ignored by git): **keep**, phase 4 (open); re-verified on 2026-11-13,
  `.gitignore:27` still ignores it (evidence P6).

Nothing added.

## Where the work happens

- **Area and slot.** The ai-sandbox toolchain (`bin/ai/`, `tests/ai-sandbox/`,
  `PROJECT_MAP.md`). One implementer, T01 to T06 in order, the slot the lead names (slot 1,
  Zuzia, once phase 1's unit is closed).
- **Worktree and branch.** `.worktrees/2026-11-11-sandbox-hardening-p3` on branch
  `2026-11-11-sandbox-hardening-p3`, created from the first commit on `main` that has both
  phase 1's merge and this plan (the base). Why a worktree: until phase 4 the host runs the
  main checkout's working tree (H3).
- **Machine.** 1 CPU, 2 GB: suite runs and pin runs take the shared suite lock the lead
  names; no stash.
- **Commits.** T01 (pin tool, base records), T02 (one hand commit), T03 (the split script in
  its own commit, then the mechanical commit it produces and nothing else), T04 and T05 (hand
  commits), T06 (documents). Each commit carries `Task: 2026-11-11-sandbox-hardening`.
- **Read point RP3**, after the phase review accepts the tree and G passes, before the lead
  merges. The user reads at the host, first the changed paths, then whether the moved code
  arrived unchanged (P3), then the hand commits to `bin/ai`. `<tip>` is the commit G ran on,
  `<mech>` the mechanical commit (both given by the lead):

  ```
  R=~/dev/public/dev-tools; B=$(git -C $R merge-base main <tip>)
  git -C $R --no-pager diff --no-ext-diff --no-textconv --stat $B <tip>
  diff <( for f in bin/ai/create-ai-sandbox.sh bin/ai/ai-delegate bin/ai/sandbox-knowledge-sync; do git -C $R cat-file -p "$B:$f"; done | LC_ALL=C sort ) \
       <( git -C $R ls-tree -r --name-only <tip> -- bin/ai/create-ai-sandbox.sh bin/ai/create.d bin/ai/image | while IFS= read -r f; do git -C $R cat-file -p "<tip>:$f"; done | LC_ALL=C sort )
  for c in $(git -C $R rev-list --reverse $B..<tip> -- bin/ai); do [ "$c" = "$(git -C $R rev-parse <mech>)" ] || git -C $R --no-pager show --cc --no-ext-diff --no-textconv $c -- bin/ai; done
  ```

  The second command prints only the lines P3 lists by kind. RP3 is taken again on every tip
  G runs on.
- **Batch B3** follows RP3 and the merge (below). It does not gate phase 4's planning.

## Contracts

The shape later phases plan against (phase 4 writes C-INSTALL's manifest against literal
file names; phases 5 to 8 add stages to `compose.sh`, `seed.sh`, `devices.sh` and `image/`):

```
# bin/ai/create.d/<module>.sh, the eleven modules of C-MODULES; mode 0644; sourced, never run
#   top level: comments, readonly constants, function definitions; nothing that runs
#     (rule: evidence/.../top-level-effect.yml); sources no file (rule: sources-file.yml)
#   stage functions: <module>_<what>, e.g. display_launchers; no arguments, except the
#     option-parsing stage, which takes "$@"; they read and set the script's globals as the
#     base's top-level code did; an array the base declared at top level is declared -g
# bin/ai/create-ai-sandbox.sh, the entry; mode 0755
#   set -euo pipefail; the option defaults (the base's "Options" block) and the environment
#   overrides IDEA_HOST_DIR, HOST_ETC_DIR, HOST_SND_DIR; SCRIPT_DIR from its own path,
#   symlinks resolved; eleven literal lines  . "$SCRIPT_DIR/create.d/<module>.sh"  in
#   C-MODULES order; then one stage call per line in the base's order, with
#   . "$SCRIPT_DIR/ai-sandbox-lib.sh" at the base's position among them;
#   no heredoc, no redirection into a file
# bin/ai/image/<file>: copied into the build context by image.sh, each by its literal name;
#   a value known only at generation is a placeholder @NAME@ that image.sh fills
```

Not a contract: the names of individual stage functions, the split of a module into stages,
the names of the Dockerfile part files.

## Where each part of the base goes

By the base's section headings (create at `273b538`). Execution order stays the base's, with
one deliberate exception: the self-location block ("Resolve this script's own location" up to
`SCRIPT_DIR`), which the base runs after option parsing and the prerequisite checks, runs in
the entry before the sourcing lines, because they need `SCRIPT_DIR`. It prints nothing, writes
nothing and changes directory only in subshells, so no output or file changes; P1 confirms.

| Base section or part | Module |
|---|---|
| Header comment, `set -euo pipefail`; the "Options" defaults; `IDEA_HOST_DIR`, `HOST_ETC_DIR`, `HOST_SND_DIR`; "Resolve this script's own location" up to `SCRIPT_DIR`; the lib's sourcing line | entry |
| `MARKER_BEGIN`, `MARKER_END` | `rules.sh` |
| `BASHRC_BEGIN`, `BASHRC_END` | `install.sh` |
| Pinned upstream versions; `CLAUDE_PLUGINS*` (also read by `rules.sh`) | `image.sh` |
| The resource-limits comment; `SHM_SIZE` | `resources.sh` |
| `usage`, the two parsing loops, the conflict checks, the `--display` check, the `--memory` check after the lib | `options.sh` |
| "Small helpers" (`log`, `step`, `warn`, `die`, `require`, `safe_rsync`); "Host prerequisites"; `DEV_TOOLS_DIR` | `project.sh` |
| The memory-budget gate before anything is written | `resources.sh` |
| "Resolve the project" whole (migration call, root, names, id, I10 and D9 refusals, paths, sandbox directory, `project-path`, shared stores, state directories, knowledge directory and origin); "Locate the host tools/ directory" | `project.sh` |
| The `step "Selecting display mode"` line and the remembered Docker, audio, memory and display-mode values read from `.env` | `options.sh` |
| `MEMORY_LIMIT`, `MEMORY_SWAP_LIMIT`, `CPU_LIMIT`; "CPU set"; "Timezone" | `resources.sh` |
| `IMAGE_VARIANT`, `IMAGE_NAME`, `IMAGE_STAMP` | `image.sh` |
| `auto` resolution; X socket directory and display number; display environment and mount lines; X authority; "Nested display launcher", "xpra overrides", `start-display.sh`, `stop-display.sh` | `display.sh` |
| "Audio"; "Devices" (serial, cgroup rules, sound devices, Docker devices, `security_opt`) | `devices.sh` |
| "Shared brain" (directories, `GEMINI.md`, the `CLAUDE.md` fold and link, the retired file), the knowledge sync call, the environment block, the render call, the `.agentrules` retirement | `rules.sh` |
| "Copy tool state into the sandbox", "IntelliJ IDEA", "SDKMAN" | `seed.sh` |
| "Build context": the baked files (as files under `image/`, filled and copied by `image.sh`), `claude-plugins.list`, the copies of `ai-delegate`, `sandbox-knowledge-sync` (from `image/`) and `context-statusline` (from `bin/ai`), the Dockerfile; in "Build and start" the build hash, the build and the stamp | `image.sh`, `image/` |
| ".env" (the secrets template, the host's git identity, the managed keys), `ai_sandbox_caches_prepare`; "docker-compose.yml" | `compose.sh` |
| "Shell helpers" (helper install, the old `ai-delegate` copy's removal, the knowledge seed, the config line, the `~/.bashrc` block) | `install.sh` |
| In "Build and start": the `--no-start` exit, the capacity check, starting the isolated display, the start under the cache lock, the summary and hints | `start.sh` |
| In "Build and start": `ai-sandbox-extensions` | `project.sh` |

## Pin matrix

`tests/ai-sandbox/split/pin-artefacts.sh <tree> <out>` (T01) runs `<tree>`'s create with
`<tree>`'s test stubs for each case below, at one fixed root path (the same for every run it
is compared with: the project id hashes the absolute path, evidence P3 and P11), under a
fixed environment it lists in its evidence (`env -i` with `HOME`, `USER`, `PATH`, `LANG`, a
fixed `umask 022`, a fake `HOST_ETC_DIR` and a failing `timedatectl`, fixed `GIT_AUTHOR_DATE`
and `GIT_COMMITTER_DATE`, `IDEA_HOST_DIR` and `HOST_SND_DIR` at paths that do not exist
unless the case makes them, `XDG_RUNTIME_DIR` an empty directory under the root unless the
case fills it; P11 found `/opt/idea-IU`, `/run/user/<uid>` and a working `timedatectl` on this
machine). The manifest's header records, under the base `PATH`, what `command -v` finds for
`rsync`, `xpra`, `Xvfb`, `Xephyr`, `xauth`, `mcookie`, `timedatectl`, `git` and `python3`, so
two manifests from different machines differ visibly.

Each case runs twice, each time from a fresh root at the same path: the first run records the
exit status, stdout and stderr as separate streams, the stub docker log, and every directory,
file and link the run left under the root (path, mode, SHA-256 or link target) plus the X
socket directory it made under `/tmp/.X11-unix` (removed after each run); the second run
records stdout and stderr as one stream (`2>&1`), which pins their interleaving (plan review
M5). A case of several invocations repeats all of them in each run. The root path and the
tree's path are replaced by placeholders. Left out of the manifest: the inside of git
repositories (their ref names are listed instead). Named non-deterministic lines (A5's
fallback): **N1** the content of `<sandbox dir>/.seeded`; **N2** the first field (the time) of
line 1 of `<sandbox dir>/status/knowledge`; **N3** the time in the stdout line
`already seeded on <time>`, printed by every run over a root seeded before (K11, K28;
evidence P11), in the separate stdout and in the combined stream. A further one found by T01 is added here by the planner before T02.

A refusal case is driven through its real input, never by editing the tree under test, except
K22, whose input is the tree's own layout: the tool copies `<tree>` without `tools/` to a
fixed path of its own, replaced by its own placeholder. A case whose input is a `PATH` checks,
before it runs, that the program it removes is not found under that `PATH`, and fails the
tool if it is.

| Case | Options and environment | Covers |
|---|---|---|
| K1 | `--display=none --no-start`, nothing present | the defaults |
| K2 | `--display=xpra --no-start`, display stubs as `test-resources.sh` | xpra launchers, `xpra.conf`, cookie |
| K3 | `--display=nested --no-start`, display stubs | Xephyr launcher |
| K4 | `--display=wayland --no-start`, `WAYLAND_DISPLAY` and a socket file in a fake `XDG_RUNTIME_DIR` | wayland lines |
| K5 | `--display=host --no-start`, `DISPLAY=:0`, stub `xauth` | host display, its warning |
| K6 | `--no-start`, no Wayland, display stubs | `auto` resolving to xpra |
| K7 | `--display=none --with-docker --no-start` | Docker variant, its Dockerfile part, `security_opt` |
| K8 | `--display=xpra --audio --no-start`, a fake sound socket and `HOST_SND_DIR` | sound socket, devices, cgroup rule |
| K9 | `--display=none --no-start`, knowledge configured as `test-knowledge.sh` does (`ai-knowledge init` on a local bare remote, stub images) | knowledge mounts, render, status, stamp `2` |
| K10 | `--display=none --no-start`, a fake IntelliJ (`IDEA_HOST_DIR`) and a fake `~/.sdkman` as `test-idea.sh`, `test-sdkman.sh` do | seed, IntelliJ, SDKMAN farm |
| K11 | K8's root again with no option, then `--memory=8 --no-docker --no-audio` | remembered options, their messages |
| K12 | `--display=none --no-start` over a `.env` holding `SANDBOX_WITH_AUDIO=1` | the old remembered value |
| K13 | `--display=none` without `--no-start` (stub docker, no image) | capacity check, build, cache lock, `compose up`, summary |
| K14 | `--help`; `--with-docker --no-docker`; `--audio --no-audio`; `--display=bogus`; `--memory=x`; `--bogus` | usage and option errors |
| K15 | K1 with no `config` file under `~/.ai-sandbox` | the budget gate: refused before anything is written |
| K16 | K1 with `AI_SANDBOX_MEMORY_BUDGET_GB=x` | the budget gate, invalid value |
| K17 | K1 with a `PATH` in which `rsync` is not found (the stub directory's other programs linked into a case directory, then the system part) | the prerequisite checks |
| K18 | K1 with a `docker` ahead of the stub that exits 1 for `compose version` and passes every other call to the stub | the `docker compose` prerequisite |
| K19 | K1 with `DOCKER_STUB_RUNNING=true` | I10, refused before anything is written |
| K20 | K19 without `--no-start` | I10 on the start path |
| K21 | K1 with `HOME=<root>/ho,me` | D9's path check |
| K22 | K1 run from a copy of `<tree>` without `tools/`, nothing at `~/dev/public/dev-tools/tools` or `~/tools` | the tools-directory lookup |
| K23 | `--no-start`, no display program on `PATH` and no Wayland | `auto` with no backend |
| K24 | `--display=xpra --no-start`, no `xpra` on `PATH` | the xpra requirements |
| K25 | `--display=wayland --no-start`, no `WAYLAND_DISPLAY` | the Wayland checks |
| K26 | `--display=host --no-start`, no `DISPLAY` | the host-display check |
| K27 | K13 with a budget of 8 and another sandbox of 4 GB running (its directory under the root, `DOCKER_STUB_PS`, `DOCKER_STUB_MEMORY`) | the capacity check refuses after the files are written and before the build |
| K28 | K13, then K13's root again with `DOCKER_STUB_IMAGES` naming the image | the image-up-to-date path (no build; what B3 relies on) |
| K29 | K13 with `--rebuild` | the forced build, `--no-cache` |
| K30 | `--display=xpra` without `--no-start`, display stubs as K2 (no socket is made) | the display starts after the capacity check and before the image step and `compose up`; its launcher's failure |

## Obligations

Each task cites the keys it discharges. Evidence: one file per task, `T<NN>-<slug>.md`, one
entry per key; T01 also writes `pin-base.manifest` there. Committed text names no finding's
input (spec, "Inputs"); this phase has none to name.

- **O1 The pin, and A5 settled.** `pin-artefacts.sh` run twice on an export of the base at the
  same root gives two manifests that `diff` finds equal except N1 to N3 (and any line T01
  adds to the list above, with its source). Method checks, each on a scratch copy of the base
  compared with the base's manifest at the same root:
  - one character changed in the compose writer and one baked file's mode changed: the
    manifest differs in exactly those lines, in every case that writes them;
  - the budget gate moved after the line that writes `project-path` (evidence P11's command):
    the manifest differs in K15 and K16 only (the "== Project" lines in stdout and in the
    combined stream, one `container inspect` in the docker log, the sandbox directory and its
    `project-path` left under the root), and in no success case;
  - the `--display=host` warning moved after the next `log` that K5 runs: K5's combined
    stream differs and its separate streams do not.

  Check: the commands in T01's evidence.
- **O2 The base is recorded.** `pin-base.manifest` (the manifest of the base, committed) and
  the suite's result on the base: `bash tests/ai-sandbox/run-tests.sh` per file `N run, M failed`
  and the failing cases by number and description; expected 22 files, 1793 run, 2 failed,
  `test-delegate.sh` 54 and 59 (evidence P9, spec D15). Check: the run's own summary lines in
  T01's evidence; the evidence file's re-check list run first, its results recorded.
- **O3 Arrays the base declares at top level stay global.** After T02,
  `command grep -nE '^[[:space:]]*(declare|typeset)[[:space:]]' bin/ai/create-ai-sandbox.sh` shows
  the three sites of evidence S7, each with `-g`; at the end,
  `command grep -nE '^[[:space:]]*(declare|typeset)[[:space:]]' bin/ai/create.d/*.sh | command grep -vE -- '[[:space:]]-g[A-Za-z]*[[:space:]]'`
  is empty. Base: 3 sites, none with `-g`.
- **O4 The mechanical commit is the script's output.** `<mech>`'s parent holds
  `tests/ai-sandbox/split/split-create.sh`; on an export of the parent,
  `bash <d>/tests/ai-sandbox/split/split-create.sh <d>` (no git needed, under `umask 022`)
  yields a tree that `diff -r --no-dereference` finds equal to an export of `<mech>`, and whose
  modes are equal too: `(cd <d> && find . -printf '%m %y %p\n' | LC_ALL=C sort)` and the same
  on the export of `<mech>` give no `diff`; `git show --stat <mech>` lists only create,
  `create.d/`, `image/`, the two moved programs and the S1 lines' files.
- **O5 The modules and their sourcing.** `ls bin/ai/create.d` lists exactly the eleven files
  of C-MODULES; `command grep -nE '^\. "\$SCRIPT_DIR/create\.d/[a-z]+\.sh"$' bin/ai/create-ai-sandbox.sh`
  gives eleven lines in the order options, project, display, resources, devices, rules,
  seed, image, compose, install, start; `ast-grep scan --rule docs/superpowers/evidence/2026-11-11-sandbox-hardening-p3/sources-file.yml bin/ai/create.d`
  finds nothing (exit 0); its known case is evidence P7.
- **O6 The entry holds defaults and the stage order only.** Read `bin/ai/create-ai-sandbox.sh`:
  the contract block's content and nothing else; its stage calls in the base's order
  (checked by P1 and P3). `command grep -nE '<<|(^|[^0-9&<])>' bin/ai/create-ai-sandbox.sh`:
  empty.
- **O7 Nothing runs when a module is sourced.**
  `ast-grep scan --rule docs/superpowers/evidence/2026-11-11-sandbox-hardening-p3/top-level-effect.yml bin/ai/create.d`:
  no finding, exit 0; known cases in evidence P7 (base create 246, lib 9, and the probe file
  of tests, `unset`, `export`, `local` and declarations holding a substitution: 10 of 15
  lines).
- **O8 Each concern and each generated file has one owner.** Read: every write site in
  `bin/ai/create.d` (`command grep -nE '>>? *"\$|python3 - "\$|install -m|(^|[[:space:]])cp |rsync |mkdir' bin/ai/create.d/*.sh`)
  listed in T04's evidence by module, against "Where each part of the base goes"; no
  generated file is written from two modules.
- **O9 `image/` holds the in-container programs as files.** `bin/ai/image/` holds
  `entrypoint.sh`, `sandbox-doctor`, `sandbox-knowledge-sync`, `ai-delegate`,
  `sandbox-desktop`, `sandbox-idea`, `xdg-open`, `sandbox-bashrc.sh`, `sandbox-env.sh`,
  `sandbox-sdk`, `claude-managed-settings.json` and the Dockerfile parts; `image.sh` names
  each by its literal name; the doctor's generated line and the Dockerfile head's `ARG`
  values are `@NAME@` placeholders filled by `image.sh`, through the same means as the
  entrypoint's marketplace; `context-statusline` stays in `bin/ai`. Nothing on the host runs
  or sources a file there: `command grep -rnaE 'image/' bin/ai --exclude-dir=image` gives only
  `image.sh`'s copy and fill lines and comments, besides the two hits of the base, which stay:
  the usage text's `image/` line (base create 205, then in `options.sh`) and `ai-sandbox-rm`
  line 2 (a comment). The build context's names, bytes and modes
  are P1's.
- **O10 The C-GIT rule leaves out `image/` by directory and names no file.**
  `bash tests/ai-sandbox/test-host-git.sh` ends `0 failed` with the base's number of cases
  (PA8); each case whose subject moved is listed in T05's evidence with its base and new
  description and still asserts its base property (a git call in an in-image program is
  exempt; a git call in a host script outside `image/` is reported). Known cases, run in T05's
  evidence as evidence P5's planting command against the result's `sgconfig.yml` and the
  file's coverage check, not as new suite cases: a git start planted in a file under a planted
  `bin/ai/image/` is neither reported nor required to be parsed; one planted in
  `bin/ai/create.d/x.sh` is reported;
  `command grep -naE 'ai-delegate|sandbox-knowledge-sync' tests/ai-sandbox/test-host-git.sh tests/ai-sandbox/sg/sgconfig.yml tests/ai-sandbox/sg/rules/host-git.yml`
  is empty.
- **O11 The tests follow the moved files.** `test-delegate.sh`, `test-knowledge.sh`,
  `stub/docker` run the programs from `bin/ai/image/`; `test-tools.sh` reads
  `GITLEAKS_VERSION` from the module that defines it. Check:
  `bash tests/ai-sandbox/run-tests.sh`, per file as O2, at the end of T05; residues R1, R3.
- **O12 The map.** Read `PROJECT_MAP.md`: the create row says it is the entry (defaults and
  stage order); one row for `bin/ai/create.d/` naming the eleven modules' concerns in one or
  two sentences; one for `bin/ai/image/`; the `ai-delegate` and `sandbox-knowledge-sync` rows
  and the coupling register's "Marked in" cell at their `image/` paths.

Phase-level, cited by no task:

- **P1 The artefact pin is unchanged.** `pin-artefacts.sh <result tree> <out>` at the root of
  T01's run: its manifest and `pin-base.manifest` are equal except N1 to N3. So the build
  context's names and bytes are the base's, `ai_sandbox_build_hash` gives the same hash, and
  an existing image is reused. Run with G.
- **P2 The suite's result is the same** (PA8, the author's reading). `bash tests/ai-sandbox/run-tests.sh`
  on the result: per file the same `N run, M failed` as O2, the same failing cases
  (`test-delegate.sh` 54, 59) and no other failure; in `test-host-git.sh` the cases whose
  subject moved may carry new descriptions (O10, listed in T05's evidence), with the same
  count and all passing. Run with G.
- **P3 Moved, not rewritten.** RP3's second command, run in the sandbox against the result:
  every line it prints is of one of these kinds, read one by one by the phase review: a stage
  function's opening or closing line; a `return 0` before a closing line, only after one of
  the sites of evidence S7's `and-tail` row (T03); a module's header comment (at most five
  lines); an entry
  sourcing line or stage call; a copy or fill line in `image.sh` with the heredoc opener or
  closer it replaced; a `@NAME@` placeholder with the interpolation it replaced; a `-g` flag;
  the copy lines of the two moved programs; a path in the doctor's or the head's fill. Any
  other line is a finding.
- **G The gate**, once on the tree the phase review accepts, by the implementer the lead
  names or a runner, under the suite lock: `bash tests/ai-sandbox/run-tests.sh` (P2),
  `bash tests/ai-sync/test-sync.sh`, `bash tests/git-hooks/test-hooks.sh` (needs gitleaks),
  `python3 -m unittest tools.context_statusline.test_statusline`, and P1.
- **R1 to R3, residue**, run by the phase review from the repository root:
  - R1 the old paths: `git grep -nE 'bin/ai/(ai-delegate|sandbox-knowledge-sync)' -- . ':(exclude)docs/superpowers'`:
    empty. Base: 12 (evidence S1).
  - R2 heredocs into the build context: `command grep -rnaE '"\$BUILD_DIR/[^"]+" *<<' bin/ai`:
    empty. Base: 14 (evidence S5).
  - R3 tests reading create's text: `command grep -rnaE '(sed|grep|awk|cat|head|tail)\b[^|;]*bin/ai/create-ai-sandbox\.sh' tests`:
    empty. Base: 1 (evidence S4).
- **H Host acceptance**, from batch B3, the lead records the verdict in `host.md`: one
  stopped sandbox's generated files and the build context are byte-identical before and after
  the merge.

## Impact set

Bash has no compiler; the searches are the static enumeration, each with its known case in
the evidence file under the name given.

| Changed | Category | Search | Result | Dependants and their fate |
|---|---|---|---|---|
| `bin/ai/ai-delegate`, `bin/ai/sandbox-knowledge-sync` move to `bin/ai/image/` | names in strings | S1, S2 | 12; 2 | `PROJECT_MAP.md` 17, 24, 54; `stub/docker` 203; `test-delegate.sh` 7; `test-host-git.sh` 21; `test-knowledge.sh` 57, 738, 1366, 1484, 1488, 1492: the literal path rewritten by T03's script (a rename by tool); `test-host-git.sh` 21 then becomes the directory exclusion (T05); create's two `cp` lines move into `image.sh` (T03, T04). Residue R1 |
| The same two, by command name | names in strings | S3 | 14 files | none: command names and in-image paths (`/usr/local/bin/...`), which do not change (P1 holds the Dockerfile) |
| The C-GIT rule's exception | static (a guard) | P5, read `test-host-git.sh` | 1 variable naming 2 files | T05 (O10). The rule still covers the modules unchanged: they are `.sh` (P5) |
| create's text read as data | static | S4, S-src | 1 reader (`test-tools.sh` 32); 0 that source create | T05 re-points the reader. Residue R3 |
| create's functions | static | S6 | 22 names; none used by another file (other files' `log`, `die`... are their own; nothing sources create) | `require` keeps its name: the C-GIT rule exempts it (`host-git.yml`) |
| The 14 heredocs that write the build context | format, stored data | S5 | 14 | become files under `image/` (T03) and fills (T04); bytes and modes of the result pinned (P1). Residue R2 |
| What create writes on the host: compose file, `.env`, launchers, `xpra.conf`, X authority, environment block, `~/.bashrc` block, config line, installed helpers, build context | outside: stored data, the image | the pin matrix | K1 to K30 | unchanged bytes and modes (P1): existing sandboxes and images are untouched, nothing is re-created or rebuilt |
| How the host invokes create | outside | read "Resolve this script's own location"; `PROJECT_MAP.md`; `verify-ai-sandbox-on-host.sh` (executes it by path) | - | the entry finds `create.d/` through its resolved path (PA4) |
| Phase 4's manifest check and installed revision | outside: a later phase | spec C-INSTALL | - | literal module and `image/` names (O5, O9) let its check enumerate them; `rev/<commit>/` exports `bin/ai/**`, which includes both directories |
| The knowledge repository, `.agents`, `.claude` | outside | P10 | 0 paths that move | none |
| Duplicated logic | duplicated | P3 | - | no rule changes in a move; P3 shows every line of the base in one place. The fill of `@NAME@` values is one means in `image.sh` (O9) |
| Reliance on one shell scope | reliance on an invariant | none possible | - | code of one part reading variables another part set; nothing enumerates it. Net: decision 1 (stage functions over globals), O3, P1, P2 |

## Tasks

Each task ends with its targeted tests and, from T04 on, the files of
`tests/ai-sandbox/` it touched; T05 ends with the whole suite and the pin. The review
spot-checks the mechanical commit (O4, P3) and reads every hand commit in full.

- **T01 pins.** Area: `tests/ai-sandbox/split/`, the evidence directory. First the evidence
  file's re-check list on the base; any difference goes to the planner before T02. Then
  `pin-artefacts.sh` as "Pin matrix" says, its two runs on the base and the method checks
  of O1;
  then the base's suite run. Commits the script, `pin-base.manifest` and the evidence;
  changes nothing under `bin/`. Discharges O1, O2.
- **T02 declarations.** Area: `bin/ai/create-ai-sandbox.sh`. The three top-level array
  declarations of evidence S7 take `-g`, which changes nothing at top level; one hand commit.
  Targeted: `test-capacity.sh`, `test-resources.sh`, `test-devices.sh`, `test-display.sh`.
  Discharges O3 (its first half).
- **T03 mechanical split.** Area: `bin/ai/`, `tests/ai-sandbox/split/`. Write
  `split-create.sh`: from a tree's create it writes the entry's remaining text, the eleven
  modules (the base's parts placed as "Where each part of the base goes" says, each run of
  one module's code wrapped as a stage function, function definitions of the base kept or
  placed at the module's top level), the quoted build-context heredocs as files under
  `image/` (bodies byte for byte), moves the two programs into `image/`, and rewrites the
  literal old paths in the S1 files; deterministic, no git needed. A stage keeps the base's
  status: a stage whose last statement is a top-level list whose last operator is `&&`
  (evidence S7 and P2: base 651, 808) closes with `return 0` after it, so a false list does not
  end the script where the base went on; the evidence names each such stage or states there is
  none. Commit the script alone;
  then run it and commit its output alone (`refactor:`, the commit message names the script
  and its parent). The tree need not run yet. Discharges O4.
- **T04 entry and image.** Area: `bin/ai/`. Hand edits that make the result run as the base
  did: the entry per the contract block (sourcing lines, the lib's line at its base position,
  the stage calls in the base's order, `"$@"` to the option stage, `SCRIPT_DIR` kept in the
  entry); in `image.sh` the copies from `image/` by literal name with the base's file modes,
  the doctor's line and the Dockerfile head as `@NAME@` fills; module header comments; any
  other remainder P3 shows, each named in the evidence. Targeted: the suite files that run
  create, and a pin run compared with `pin-base.manifest`. Discharges O3 (second half), O5,
  O6, O7, O8, O9.
- **T05 tests follow.** Area: `tests/ai-sandbox/`. `test-host-git.sh` and, if needed, the
  rule's configuration: the exception becomes `bin/ai/image/` by directory, with O10's known
  cases; `test-tools.sh` reads `GITLEAKS_VERSION` from its module; any test the suite shows
  still bound to the old layout. Last step: the whole suite and a pin run. Discharges O10,
  O11.
- **T06 documents.** Area: `PROJECT_MAP.md`. The rows of O12. Discharges O12.

## Batch B3 for the user (set-up, at one host)

Host commands of this phase against "Host commands and phone work": reading at RP3 (set-up,
before the merge) and this check (set-up, around the merge). Nothing is added to everyday
work and nothing a phone could need.

1. Before the lead merges, after RP3, on a host whose checkout is at `main`: pick one sandbox
   that is stopped (`docker ps` does not list it), refresh it with the code before this phase
   and keep a copy of its generated files and of the build context:

   ```
   d=~/.ai-sandbox/<id>-agent; c=$(mktemp -d); p=$(head -1 "$d/project-path")
   (cd "$p" && create-ai-sandbox.sh --no-start) >/dev/null
   for f in .env docker-compose.yml start-display.sh stop-display.sh xpra-conf/xpra.conf; do [ -e "$d/$f" ] && mkdir -p "$c/$(dirname "$f")" && cp -a "$d/$f" "$c/$f"; done
   cp -a ~/.ai-sandbox/image/build "$c/build"
   ```
2. The lead merges; on this host the checkout is then at the merged `main`.
3. Run the same create again and compare by name only (`.env` may hold secrets, so nothing
   prints its content):

   ```
   (cd "$p" && create-ai-sandbox.sh --no-start) >/dev/null
   for f in .env docker-compose.yml start-display.sh stop-display.sh xpra-conf/xpra.conf; do [ -e "$c/$f" ] && { cmp -s "$c/$f" "$d/$f" && echo "same: $f" || echo "DIFFERS: $f"; }; done
   diff -rq "$c/build" ~/.ai-sandbox/image/build && echo "same: build context"
   rm -rf -- "$c"
   ```
   Paste back the `same:`/`DIFFERS:` lines. Expected: every line `same:`. The next
   `create-ai-sandbox.sh` run that starts a sandbox prints that the image is up to date.

## Assumptions

| # | Assumption | Status | Settled by |
|---|---|---|---|
| PA1 | A5: what create writes and prints is a function of options and environment, except N1 to N3 | inferred: probe P3 (cases K1, K2), the read of P4, and probe P11 (two runs per list at one root differ only in N3) | T01 (O1), every matrix case |
| PA2 | Top-level code behaves the same as a stage function body, except array declarations (now `-g`), `BASH_SOURCE` (kept in the entry), `"$@"` (passed to the option stage), and a false `&&`-list or `!` command as the body's last statement, which becomes the stage's status and ends the script at the entry's call (base sites 651 and 808, none with `!`; T03 closes such a stage with `return 0`) | verified by probe P2, the `and-tail` and `!` searches with their known cases, and the read of S7 | P1, P2 (K1 takes the false branch of both sites) |
| PA3 | Nothing in the repository sources create or reads its text, except `test-tools.sh` 32 | verified (S4, S-src) | - |
| PA4 | The host runs create from the checkout's `bin/ai`, by `PATH` or path, symlinks resolved; no copy of create alone exists | first half verified (the self-location code, `PROJECT_MAP.md`); second half guessed | if it fails, that copy stops at its first module with "No such file"; the user calls the checkout's create |
| PA5 | Nothing on the host runs `ai-delegate` or `sandbox-knowledge-sync` from the checkout's `bin/ai` | verified intent (phase 1's PA9 and the author's answer there); guessed for the user's own scripts | if it fails, that call reports "command not found"; both programs belong in the image |
| PA6 | The suite at the base: 22 files, 1793 cases, 2 failing (`test-delegate.sh` 54, 59) | verified at `d56fcf0`, code-equal to `273b538` (P9) | T01 on the real base (O2) |
| PA7 | The C-GIT rule parses `create.d/*.sh` and, without a directory exclusion, reports in-image programs | verified (P5, ast-grep 0.51.0) | - |
| PA8 | The spec's "result must be the same" means per file the same number of cases, each with the same outcome, the two base failures the only ones; it admits new wording and subject for the cases of `test-host-git.sh` whose subject C-MODULES moves, each still asserting its base property | verified: the spec's author's reading (`author-answers.md`, 2026-11-13) | O10, P2 |
| PA9 | The base of phase 3 has `273b538`'s code | inferred (phase 1 is reviewed and gated at that code) | T01, the re-check list |

## Left out (no trigger found, or a failure no user reaches)

A check that the entry finds its modules (trigger: a copy of create alone, none found, PA4;
the shell's own error is immediate). A suite test for C-MODULES' structure: the suite's
result is pinned for this phase (P2), the rules of O5 and O7 are recorded commands, and phase
4's manifest check enumerates the sourced files. Rewording text inside generated files that
still names `create-ai-sandbox.sh` (the Dockerfile's pointer to the comment on
`sandbox-env.sh`, the "see create-ai-sandbox.sh" in `sandbox-env.sh`, the "Generated by"
headers): byte identity forbids it here, and the entry is still the command that generates
them. Re-pointing comments in other files that say "create-ai-sandbox.sh" for a part of it:
still the command that does it. A shell linter (spec: not part of a refactor). Moving
`context-statusline` (it also runs on the host, C-MODULES).

Pin cases left out (plan review M3, I1): a display start that succeeds on the start path,
which needs a stub that serves an X socket; K30's failing launcher already pins where the
display starts relative to the capacity check, the image step and `compose up`, and K2 and
K3 pin the launchers' bytes. A missing Wayland socket with `WAYLAND_DISPLAY` set, and
`--display=nested` without `Xephyr`: the same check position as K25 and K24, so they add no
ordering a refusal case does not already pin.

## Questions for the spec's author

None open. Decisions 1 to 3, N2 and the two changes that are not moves were accepted on
2026-11-13 (`author-answers.md`); N3 is N1's value echoed and falls under the same fallback
of A5.
