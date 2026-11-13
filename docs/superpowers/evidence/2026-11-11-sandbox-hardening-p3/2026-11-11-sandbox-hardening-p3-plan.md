Task: 2026-11-11-sandbox-hardening
Class: phase

# Phase 3 plan: searches and probes

Evidence behind `docs/superpowers/plans/2026-11-11-sandbox-hardening-p3-plan.md`. Written by
Ola (planner 3) on 2026-11-13 against phase 1's branch tip `273b538` (phase 1 with phase 2
merged in, merge `d56fcf0`), read only. Every command is given so it can be re-run
unchanged; outputs are copied, long ones cut where marked. Each method was first run on a
case whose answer was known, stated beside it. Updated the same day after the plan review's
round 1: P2 (exit status of a stage), S7 (one row), P4 (one row), S6 (exact command), P7 (the
extended rule), P11 (new), and the re-check list.

Conventions for re-running:

- `R=/home/jlewandowski/dev/public/dev-tools` (the main checkout; `git grep <commit>` reads
  the object database and checks nothing out).
- `B` is an export of the base: `B=$(mktemp -d); git -C "$R" archive 273b538 | tar -x -C "$B"`.
  On the real base of phase 3 (the commit on `main` after phase 1's merge) replace `273b538`
  by that commit.
- `E=$R/docs/superpowers/evidence/2026-11-11-sandbox-hardening-p3` (the two rule files below live there).

## P9 The base's code, and the suite record that applies to it

`git -C "$R" diff --stat d56fcf0 273b538 -- bin tests tools verify-ai-sandbox-on-host.sh PROJECT_MAP.md README.md .githooks`:
empty, rc 0 (273b538 only adds evidence). So phase 1's gate run on `d56fcf0`
(`docs/superpowers/evidence/2026-11-11-sandbox-hardening-p1/M01-merge-main.md`, section 4)
is a run of this code: `bash tests/ai-sandbox/run-tests.sh`: 22 files, every one `0 failed`
except `test-delegate.sh` `69 run, 2 failed` (cases 54 and 59, spec D15); sum 1793 run, 2
failed. `tests/ai-sync/test-sync.sh` 37/0, `tests/git-hooks/test-hooks.sh` 19/0,
`python3 -m unittest tools.context_statusline.test_statusline` 30 OK.
Known case for the diff: `git -C "$R" diff --stat 3b650b9 337961d -- bin tests tools` is
empty as well (337961d is a documents-only commit on `main`), and
`git -C "$R" diff --stat main 273b538 -- bin tests tools | tail -1` is
`19 files changed, 2709 insertions(+), 1060 deletions(-)` (phase 1's code, not yet on `main`),
so the command does report a code difference where there is one.

`wc -l` of `bin/ai/create-ai-sandbox.sh` at 273b538: 2994 (spec G4 counted 2898 at `96540a5`).

## P8 Why the modules hold stage functions (the order of the base)

`command grep -naE '^ai_sandbox_check_capacity|^    docker build|^cat > "\$SANDBOX_DIR/start-display.sh"|^\} > "\$COMPOSE_FILE"|^step "Installing helper commands"|^step "Image"|^    "\$SANDBOX_DIR/start-display.sh"|^ai_sandbox_memory_budget_gb|^step "Selecting display mode"|^CPU_LIMIT=|^IMAGE_NAME=|^HOST_TZ=' "$B/bin/ai/create-ai-sandbox.sh"`:

```
376:ai_sandbox_memory_budget_gb >/dev/null || exit 1
502:step "Selecting display mode"
549:CPU_LIMIT=$(( (MEMORY_GB + 1) / 2 ))
554:IMAGE_NAME=$(ai_sandbox_image_name "$IMAGE_VARIANT")
850:HOST_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || true)
2524:} > "$COMPOSE_FILE"
2581:cat > "$SANDBOX_DIR/start-display.sh" <<DISPLAYEOF
2795:step "Installing helper commands"
2872:ai_sandbox_check_capacity "$CONTAINER_NAME" "$MEMORY_GB" || exit 1
2878:    "$SANDBOX_DIR/start-display.sh"
2881:step "Image"
2898:    docker build "${docker_build_flags[@]+"${docker_build_flags[@]}"}" \
```

C-MODULES sources `display.sh` before `compose.sh` and `image.sh` before `start.sh`. The base
writes the display launchers after the compose file (2524, 2581), checks capacity before it
builds the image (2872 before 2898, the comment there: "a full host should cost a message,
not a build"), and interleaves memory, the image name, the display and the timezone (549, 554,
850). Sourcing modules whose top level runs, in the table's order, would reorder these steps
and their output. With modules that only define functions, the source order is free and the
entry keeps the base's order of execution. Read in the tree; no run needed.

## P2 Bash: what changes when top-level code becomes a function body

Known behaviour checked on this machine's bash (`GNU bash, version 5.1.16(1)-release`):

`bash -c 'set -u; f(){ X=1; readonly X; readonly Y="y"; declare -A A=([k]=1); declare -a B=(1); }; f; echo "X=$X Y=$Y"; declare -p X Y; echo "A:${A[k]:-unset} B:${B[0]:-unset}"'`

```
X=1 Y=y
declare -r X="1"
declare -r Y="y"
bash: line 1: k: unbound variable
```

`bash -c 'f(){ declare -A A=([k]=1); declare -a B=(1); }; f; echo "A:${A[k]:-unset} B:${B[0]:-unset}"; h(){ D["c 1:* rwm"]=1; }; h; echo "h rc=$?"'`

```
A:unset B:unset
environment: line 1: c 1:* rwm: syntax error in expression (error token is "1:* rwm")
```
(exit 1)

So `readonly` inside a function still makes a global; `declare -A`/`declare -a` inside a
function makes a local, and a later string key on the then undeclared name aborts the shell.

A function's exit status under `set -e` (raised by the plan review, M1):

```
bash -c 'set -euo pipefail; f(){ X=1; [ "$X" = 2 ] && echo two; }; f; echo after-f'; echo "rc=$?"
bash -c 'set -euo pipefail; X=1; [ "$X" = 2 ] && echo two; echo after-top'; echo "rc=$?"
bash -c 'set -e; f(){ ! true; }; f; echo after'; echo "rc=$?"
```

Output: `rc=1` with nothing printed; `after-top` and `rc=0`; `rc=1` with nothing printed. A
false `&&`-list (or a `!` command) as the last statement does not stop the script at top
level, but it becomes the function's status, and the entry's plain call then ends the script
silently. The sites in the base, the top-level lists whose last operator is `&&`:

`ast-grep scan --inline-rules '{id: and-tail, language: bash, rule: {pattern: "$A && $B", inside: {kind: program}}}' "$B/bin/ai/create-ai-sandbox.sh" --json=stream`:
2, lines 651 (`[ -f "$ENV_FILE" ] && CPUSET=$(...)`) and 808 (the `AUDIO_DEVICES` chain).
Known case: on a file holding `a && b`, `c || d`, `e && f || g`, `h && i && j`,
`[ -f x ] && Y=$(sed -n p f | tail -n 1)`, `k || l && m` (one per line) it reports lines 1, 4,
5, 6 and not 2, 3. Top-level `!` commands:
`ast-grep scan --inline-rules '{id: neg, language: bash, rule: {kind: negated_command, inside: {kind: program}}}' "$B/bin/ai/create-ai-sandbox.sh" --json=stream | wc -l`:
0; known case: on `! false` followed by `f() { ! true; }` it reports 1 (the first line).

## S7 The constructs of the base that a function body treats differently

`command grep -naE '(^|[^A-Za-z_])(declare|typeset|local|readonly|return|trap|shift|BASH_SOURCE|LINENO|FUNCNAME|caller|\$@|"\$@"|\$#|\$\*|\$0)([^A-Za-z_]|$)' "$B/bin/ai/create-ai-sandbox.sh"`:
105 lines. Classified by reading each (lines inside heredocs whose body runs in the
container, and lines inside functions the base already defines, are not top-level code and
are left out of the list below):

| Construct at the base's top level | Lines | Inside a stage function |
|---|---|---|
| `readonly` of the constants at the head (versions, plugins, markers, `IDEA_HOST_DIR`, `HOST_ETC_DIR`, `HOST_SND_DIR`, `SHM_SIZE`) | 19-89 | stay at a module's or the entry's top level; unchanged |
| `readonly` in the flow (`MEMORY_GB`, `MEMORY_LIMIT`, `MEMORY_SWAP_LIMIT`, `CPU_LIMIT`, `HOST_TZ`) | 546-551, 863 | global as before (P2) |
| `declare -A CLAIMED_DISPLAY`, `declare -a CPU_LOAD`, `declare -A SEEN_CGROUP` | 608, 653, 884 | would become locals (P2); `SEEN_CGROUP` is read by `add_cgroup`, called again in the device section (audio devices, Docker devices) |
| `for arg in "$@"` (option parsing, twice) | 268, 286 | needs the script's arguments passed to that stage |
| `SCRIPT_PATH="${BASH_SOURCE[0]}"` | 352 | in a sourced module would name the module: stays in the entry |
| `$0` in the message of the display-backend `die` | 580, 581 | unchanged: `$0` is the shell's, not the function's |
| A list whose last operator is `&&` (the `and-tail` search under P2) | 651, 808 | as a stage's last statement it becomes the stage's status, and the entry's call ends the script where the base went on (P2) |
| `return`, `local`, `shift` | 326-330, 641-645, 888-895, 1193-1196, 1350, 1439, 2626-2645 | already inside functions of the base |

Known case for the pattern: it reports line 352 (`BASH_SOURCE`) and line 268 (`"$@"`), both
known from reading the file. No `trap`, `LINENO`, `FUNCNAME` or `caller` at the top level.

## P3 A5: two runs with the same paths

Stubs as `tests/ai-sandbox/test-resources.sh` makes them for `xpra` (`xpra`, `Xvfb`, `Xephyr`
exiting 0; `xauth` exiting 0; `mcookie` printing a fixed cookie). Two rounds, each case in a
fresh root at one fixed path `$P/x`, moved aside after the run (no removal), then compared:

```
P=<scratch>/p3probe; mkdir -p $P/xstub $P/r1 $P/r2
for t in xpra Xvfb Xephyr; do printf '#!/bin/sh\nexit 0\n' > $P/xstub/$t; done
printf '#!/bin/sh\nexit 0\n' > $P/xstub/xauth
printf '#!/bin/sh\necho 0123456789abcdef0123456789abcdef\n' > $P/xstub/mcookie; chmod +x $P/xstub/*
for run in r1 r2; do for mode in none xpra; do
  mkdir $P/x || exit 1; mkdir -p $P/x/home/.ai-sandbox $P/x/work/p
  printf 'AI_SANDBOX_MEMORY_BUDGET_GB=18\n' > $P/x/home/.ai-sandbox/config; : > $P/x/docker.log
  ( export HOME=$P/x/home AI_SANDBOX_ROOT=$P/x/home/.ai-sandbox DOCKER_STUB_LOG=$P/x/docker.log \
           PATH="$B/tests/ai-sandbox/stub:$P/xstub:$PATH"
    cd $P/x/work/p && bash $B/bin/ai/create-ai-sandbox.sh --display=$mode --no-start $P/x/work/p \
      > $P/x/stdout 2> $P/x/stderr; echo "rc=$?" > $P/x/rc )
  mv $P/x $P/$run/$mode
done; done
diff -r --no-dereference $P/r1/none $P/r2/none; diff -r --no-dereference $P/r1/xpra $P/r2/xpra
```

Result: both runs `rc=0`. `none`: one difference, `home/.ai-sandbox/p-ad638099-agent/.seeded`
(`2026-11-13T14:31:02+01:00` against `...:03`); stdout, stderr, the compose file, `.env`,
the build context and `GEMINI.md` identical. `xpra`: no difference (the two runs fell in the
same second). A first comparison with `diff -r` (following links) reported
`home/.claude/CLAUDE.md: No such file or directory` on both sides: the link's target is an
absolute path under the root that was moved, so the pin must record links by their target
and run every case at one fixed root path (the project id is a hash of the absolute project
path, so a different root also changes every sandbox name).

The `xpra` case creates `/tmp/.X11-unix/.ai-sandbox-p-ad638099-agent` outside the root (the
display's socket directory, base `display` section); removed after the probe with `rmdir`.

## P4 Sources of non-determinism in what create writes

`command grep -rnaE '\bdate\b|mktemp|\$RANDOM|mcookie|uuidgen|/proc/sys/kernel/random' "$B/bin/ai/create-ai-sandbox.sh" "$B/bin/ai/ai-sandbox-lib.sh" "$B/bin/ai/ai-knowledge"`
(26 lines; known case: it reports line 1256, the `.seeded` writer A5 names). Read one by one:

| Where | What it writes | In the pin |
|---|---|---|
| create, seed section: `date -Iseconds > "$SANDBOX_DIR/.seeded"` | `.seeded`, first seed only | N1, named by A5 |
| create, seed section: `log "already seeded on $(cat "$SANDBOX_DIR/.seeded")"` (found by P11, not by this search) | a stdout line of every later run on the same root | N3 |
| ai-knowledge, `status_context` (`printf '%s %s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" ...`) | line 1 of `<sandbox dir>/status/knowledge`, written by the sync create calls when knowledge is configured (phase 1, after the spec's tree) | N2: the first field of line 1 |
| create, shared brain: `backup="${CLAUDE_MD}.pre-ai-sandbox.$(date +%Y%m%d%H%M%S)"` | a backup's name, only when `~/.claude/CLAUDE.md` is a non-empty regular file that differs from `GEMINI.md` | no matrix case creates that file |
| create, display: `$(mcookie)` | the X cookie, `xpra` and `nested` | stubbed to a fixed value |
| create, install: `mktemp "$AI_SANDBOX_CONFIG.XXXXXX"`; lib and ai-knowledge `mktemp`, `$RANDOM` | temporary names, renamed or removed | not in any written content |
| ai-knowledge `date` in proposal and branch names, `ai-knowledge init` | only in the knowledge set-up of the matrix case, not by create | the set-up fixes `GIT_AUTHOR_DATE`, `GIT_COMMITTER_DATE`; git internals are left out of the manifest |
| the rest (`date` inside heredocs of the image, `dbus-uuidgen` in the Dockerfile) | run in the container, not by create | text only |

## S5 Heredocs that write the build context, and the names C-MODULES gives `image/`

`command grep -rnaE '"\$BUILD_DIR/[^"]+" *<<' "$B/bin/ai"`: 14 lines, all in
`create-ai-sandbox.sh`:

```
1457 entrypoint.sh 'ENTRYPOINT_EOF'      1830 xdg-open 'XDGOPEN_EOF'
1617 sandbox-doctor 'DOCTOR_EOF'         1851 sandbox-bashrc.sh 'BASHRC_EOF'
1741 sandbox-doctor (>>) 'DOCTOR_EOF'    1887 sandbox-env.sh 'ENVFILE_EOF'
1775 sandbox-desktop 'DESKTOP_EOF'       1927 sandbox-sdk 'SDK_EOF'
1792 sandbox-idea 'IDEA_EOF'             1954 claude-managed-settings.json 'MANAGED_EOF'
1973 Dockerfile DOCKERFILE_HEAD (unquoted: the ARG defaults take the pinned versions)
1997 Dockerfile (>>) 'DOCKERFILE_EOF'
2181 Dockerfile (>>) 'DOCKERFILE_DOCKER' (only with --with-docker)
2206 Dockerfile (>>) 'DOCKERFILE_TAIL'
```

Known case: line 1457 is the entrypoint, which `test-plugins.sh` runs from the build
directory. Every quoted delimiter means the body is written as it stands. Two places put a
value in at generation time:

- between the two `sandbox-doctor` heredocs, a `{ printf ... } >> "$BUILD_DIR/sandbox-doctor"`
  block writes one `for _bc in "key:path" ...; do` line from `ai_sandbox_build_caches`;
- `DOCKERFILE_HEAD`, unquoted, expands `${NODE_MAJOR}` and eight other pinned versions into
  `ARG` lines and writes `\\` as `\`.

The base already has a convention for such a value: the entrypoint's body holds
`@MARKETPLACE_SOURCE@` and `@MARKETPLACE@`, filled after writing by
`sed -i -e "s|@MARKETPLACE_SOURCE@|...|" -e "s|@MARKETPLACE@|...|" "$BUILD_DIR/entrypoint.sh"`
(line 1614). `claude-plugins.list` is printed from `CLAUDE_PLUGINS` (line 1615); C-MODULES
does not list it under `image/`.

Other writes into the build context (`command grep -naE 'BUILD_DIR' "$B/bin/ai/create-ai-sandbox.sh"`, 26 lines):
`cp "$SCRIPT_DIR/ai-delegate"`, `cp "$SCRIPT_DIR/sandbox-knowledge-sync"`,
`cp "$SCRIPT_DIR/context-statusline"` (1967-1969). Every name C-MODULES gives `image/`
exists in the base as one of these heredocs or files; `context-statusline` stays in `bin/ai`
(it also runs on the host, C-MODULES).

All heredocs of create: `git -C "$R" grep -nE '<<-? *'"'"'?[A-Z_]+'"'"'?' 273b538 -- bin/ai/create-ai-sandbox.sh | wc -l`: 37
(the other 23 are host-side: `usage`, Python helpers, the `.env` and compose writers, the
launchers, `xpra.conf`, the summary and hints; they stay in their modules).

## S1, S2, S3 References to the two programs that move to `image/`

S1, the repository paths, history excluded:
`git -C "$R" grep -nE 'bin/ai/(ai-delegate|sandbox-knowledge-sync)' 273b538 -- . ':(exclude)docs/superpowers'`: 12

```
PROJECT_MAP.md:17, 24 (their rows), 54 (coupling register, "Marked in")
tests/ai-sandbox/stub/docker:203 (runs .../../../bin/ai/sandbox-knowledge-sync)
tests/ai-sandbox/test-delegate.sh:7 (DELEGATE=)
tests/ai-sandbox/test-host-git.sh:21 (NAMED_EXCEPTIONS=)
tests/ai-sandbox/test-knowledge.sh:57, 738, 1366, 1484, 1488, 1492
```

Known case: the same search over `docs/superpowers` finds 29 lines (the plans and evidence of
phase 1 name these paths).

S2, paths relative to the script:
`git -C "$R" grep -nE '(SCRIPT_DIR|\$here|dirname[^)]*\))/+(\.\./)*(ai-delegate|sandbox-knowledge-sync)' 273b538 -- .`: 2,
create lines 1967 and 1968. Known case: with `|context-statusline` added to the names it also
reports line 1969.

S3, every mention of either name, history excluded, per file:
`git -C "$R" grep -cE '(ai-delegate|sandbox-knowledge-sync)' 273b538 -- . ':(exclude)docs/superpowers'`:
`.agents/skills/knowledge-integrate/SKILL.md:1`, `PROJECT_MAP.md:5`, `bin/ai/ai-delegate:11`,
`bin/ai/ai-knowledge:2`, `bin/ai/ai-sandbox-lib.sh:1`, `bin/ai/create-ai-sandbox.sh:19`,
`bin/ai/sandbox-knowledge-sync:2`, `docs/shared-knowledge.md:4`, `tests/ai-sandbox/stub/docker:3`,
`tests/ai-sandbox/test-delegate.sh:12`, `tests/ai-sandbox/test-helpers.sh:9`,
`tests/ai-sandbox/test-host-git.sh:1`, `tests/ai-sandbox/test-knowledge.sh:16`,
`tests/ai-sandbox/test-tools.sh:8`. The lines outside S1 and S2, read: command names
(`ai-knowledge` runs `/usr/local/bin/sandbox-knowledge-sync` through `docker exec`, line 764),
comments, the image's `COPY` and `chmod` lines, and test assertions on the host install and
the Dockerfile. None is a repository path; the paths inside the image do not change.

Self-location inside the two programs:
`command grep -naE 'BASH_SOURCE|dirname|\$0|SCRIPT_DIR|\.\./' "$B/bin/ai/ai-delegate" "$B/bin/ai/sandbox-knowledge-sync"`:
three lines in `ai-delegate` (an `awk` `$0`, a `dirname` of the exclude file, an `awk` `$0`),
none locating the program itself. Known case: the same pattern on create reports line 352.

`reads-outside:` markers that move: `command grep -naE 'reads-outside' "$B/bin/ai/create-ai-sandbox.sh" "$B/bin/ai/sandbox-knowledge-sync" "$B/bin/ai/ai-delegate"`:
one, `sandbox-knowledge-sync:39` (the old-shape role file). Its coupling-register row names
the file by path (S1, PROJECT_MAP.md:54).

## S4, S-src Readers of create's text, and whether anything sources create

S4: `command grep -rnaE '(sed|grep|awk|cat|head|tail)\b[^|;]*bin/ai/create-ai-sandbox\.sh' "$B/tests"`: 1,
`tests/ai-sandbox/test-tools.sh:32` (reads `readonly GITLEAKS_VERSION='...'` from create's
text to compare the copies in `.githooks` and `README.md`). Known case: that line is known
from reading the file. Path variables in tests:
`command grep -rnaE '^[[:space:]]*[A-Za-z_]+=.*bin/ai' "$B/tests"`: `CREATE=` in
`test-idea.sh` (only executed, lines 12, 41, 85), `DELEGATE=` in `test-delegate.sh` (only
executed), the S1 lines, and command lines that execute a program.
`verify-ai-sandbox-on-host.sh` sets `S=.../bin/ai/create-ai-sandbox.sh` and only executes it
(lines 27, 51-57).

S-src: `command grep -rnaE '(^|[;&|[:space:]])(\.|source)[[:space:]]+[^#]*create-ai-sandbox' "$B/bin" "$B/tests" "$B/tools" "$B/verify-ai-sandbox-on-host.sh" "$B/.githooks"`:
empty (rc 1). Known case: the same pattern for `ai-sandbox-lib` finds 32 lines.

S6, functions create defines, used by name elsewhere (run in `$B`; prints each name and the
number of other files that contain it as a word):

```
for f in $(command grep -oE '^[a-z_]+\(\)' bin/ai/create-ai-sandbox.sh | tr -d '()' | sort -u); do printf '%s %s\n' "$f" "$(command grep -rlw -- "$f" bin tests tools verify-ai-sandbox-on-host.sh .githooks .agents | command grep -v 'bin/ai/create-ai-sandbox.sh' | wc -l)"; done
```

Output (re-run 2026-11-13): `die 2`, `log 22`, `require 3`, `status 31`, `step 7`, `usage 16`,
`warn 2`, every other name `0`. Known case: `bin/ai/ai-knowledge` defines its own `log()`
(`command grep -lE '^log\(\)' bin/ai/*` lists it and create), and the command counts that
file for `log`. 22 names; `_human`, `_sandbox_git_branch`, `add_cgroup`, `add_device`, `add_env`, `add_vol`,
`cpuset_valid`, `display_num_default`, `pass_through_tty`, `safe_rsync`, `screen_geometry`,
`seed_rsync`, `sync_sdkman_farm`, `wait_for_socket`, `x_server_running`: no other file.
`die`, `log`, `require`, `status`, `step`, `usage`, `warn`: other files define or mention
their own (nothing sources create, S-src); one dependant on a name: the C-GIT rule
`tests/ai-sandbox/sg/rules/host-git.yml` exempts a command named `require` (or `hint`) from
reporting, so `require` keeps its name.

## The lib and the helpers on the host

Top-level statements of the lib, by the rule of P7 below:
`ast-grep scan --rule "$E/top-level-effect.yml" "$B/bin/ai/ai-sandbox-lib.sh" --json=stream`: 9
(`AI_SANDBOX_ROOT=...` and eight other assignments; every one a plain assignment, reading
`HOME` once). So sourcing the lib before option parsing would change `--help` only when
`HOME` is unset; the plan keeps the lib's base position instead.

`ai_sandbox_helpers` (lib) lists `ai-sandbox-lib.sh` and ten commands; create is not among
them, so no copy of create is installed into `~/.ai-sandbox/bin` and `ai-sandbox-migrate`
refreshes none (read). The host runs create from the checkout: `SCRIPT_PATH` is resolved
through symlinks before `SCRIPT_DIR` is taken (create, "Resolve this script's own location"),
and `PROJECT_MAP.md` says each `bin/` subdirectory is meant for `PATH`.

File modes in git: `git -C "$R" ls-tree 273b538 bin/ai/ | awk '{print $1, $4}'`: every
program `100755`, `ai-sandbox-lib.sh` `100644` (sourced, not run).

## P5 What the C-GIT rule parses in the planned directories

```
mkdir -p $P/cov/bin/ai/create.d $P/cov/bin/ai/image
printf 'f() {\n  git status\n}\n' > $P/cov/bin/ai/create.d/x.sh
for f in sandbox-doctor entrypoint.sh ai-delegate; do printf '#!/bin/bash\ngit status\n' > $P/cov/bin/ai/image/$f; done
ast-grep scan -c "$B/tests/ai-sandbox/sg/sgconfig.yml" $P/cov/bin/ai --json=stream
```

(ast-grep 0.51.0) reports `bin/ai/create.d/x.sh:2`, `bin/ai/image/ai-delegate:2`,
`bin/ai/image/entrypoint.sh:2`; `image/sandbox-doctor` is not parsed (no `.sh`, not in
`languageGlobs`). So the modules are covered by the rule as they stand, and without an
exclusion by directory the rule would report programs under `image/` and the coverage check
(`bash_files` by shebang in `test-host-git.sh`) would call `image/sandbox-doctor` uncovered.
Known case: the planted `create.d/x.sh` start, which must be reported, is.

## P7 Two structural rules for the modules

`$E/top-level-effect.yml` reports a statement directly under the file's `program` node:
a command, pipeline, list, loop, `if`, `case`, plain assignment, compound statement,
subshell, `!` command, test (`[ ]`, `[[ ]]`), `unset`, and a declaration that is `export` or
`local` or holds a command or process substitution; other declarations (`readonly`,
`declare`, `typeset` of plain values), function definitions and comments pass. Extended on
2026-11-13 after the plan review (M2), whose probe found `[[ ]]`, `unset`,
`readonly Z=$(date)`, `export W=1` and `declare -g A=$(touch ...)` passing.
`ast-grep scan --rule "$E/top-level-effect.yml" <files> --json=stream | wc -l`:

| Input | Findings | Expected |
|---|---|---|
| `$B/bin/ai/create-ai-sandbox.sh` | 246 | many: the base runs at its top level (238 before the extension; the 8 added are its top-level `unset` lines) |
| `$B/bin/ai/ai-sandbox-lib.sh` | 9 | its nine top-level assignments (read) |
| a file `readonly A=1`, `readonly -a B=(x)`, `f() { echo hi; }`, a comment | 0 | 0 |
| a file `f() { :; }`, `echo side`, `X=1` | 2 (lines 2, 3) | 2 |
| a file, one per line: `[[ -n "$X" ]]`, `unset Y`, `readonly Z=$(date)`, `export W=1`, `declare -g A=$(touch x)`, `((n++))`, `[ -n "$X" ]`, `readonly C=1`, `readonly -a D=(x y)`, `declare -gA E=()`, `f() { :; }`, `# c`, `readonly P=<(true)`, `local L=1`, `typeset T=$(id)` | 10 (lines 1-7, 13, 14, 15) | the same: lines 8-12 are constants, a definition and a comment |

The scan exits 1 with findings and 0 without.

`$E/sources-file.yml` reports a command named `.` or `source` outside heredoc bodies:
`ast-grep scan --rule "$E/sources-file.yml" "$B/bin/ai/create-ai-sandbox.sh" --json=stream`:
1, line 366 (`. "$SCRIPT_DIR/ai-sandbox-lib.sh"`), the one sourcing line of the base; the
`. /etc/ai-sandbox-env.sh` and SDKMAN lines inside the image's heredocs are not reported, nor
are prose lines with "source" that a text search returns
(`command grep -nE '(^|[;&|[:space:]])(\.|source)[[:space:]]+["$~/A-Za-z]' ...`: 10 lines, 9
of them text or heredoc bodies). Both rules read `.sh` files without a configuration, which
is what the modules are.

## P6 Planned paths and `.gitignore`

`for p in bin/ai/create.d/options.sh bin/ai/create.d/image.sh bin/ai/image/entrypoint.sh bin/ai/image/sandbox-doctor bin/ai/image/ai-delegate bin/ai/image/sandbox-knowledge-sync bin/ai/image/Dockerfile bin/ai/image/Dockerfile.head bin/ai/image/Dockerfile.docker bin/ai/image/claude-managed-settings.json bin/ai/image/sandbox-env.sh bin/ai/MANIFEST tests/ai-sandbox/split/split-create.sh tests/ai-sandbox/split/pin-artefacts.sh; do git -C "$R" check-ignore -v --no-index "$p" || echo "$p not ignored"; done`:
every planned path `not ignored`; `bin/ai/MANIFEST` -> `.gitignore:27:MANIFEST` (the known
case, deferred entry E2, still true).

## P10 Outside the repository

- This sandbox's knowledge clone (`~/knowledge`, `fab0379`, 2026-11-09):
  `command grep -rnaE 'bin/ai/(ai-delegate|sandbox-knowledge-sync|create)' ~/knowledge --exclude-dir=.git`:
  empty; `README.md:5` names `dev-tools/bin/ai/ai-knowledge`, which does not move. Known
  case: the same search for `bin/ai/` finds that line.
- Inside this sandbox `PATH` has no `bin/ai` of a checkout; `command -v ai-delegate` is
  `/usr/local/bin/ai-delegate` (the image's copy, whose path does not change).
- `.agents/skills/knowledge-integrate/SKILL.md` runs `bin/ai/ai-knowledge` (lines 21, 79),
  which does not move; `.claude/settings.local.json` allows `bash -n bin/ai/create-ai-sandbox.sh`,
  whose path stays.
- The host's own scripts and shell configuration: not readable from here (guessed, plan PA4,
  PA5).

## P11 Refusal and start paths, through their real inputs (plan review I1, M3)

Probe: `2026-11-11-sandbox-hardening-p3-plan.p11-probe.sh` beside this file, run as
`bash "$E/2026-11-11-sandbox-hardening-p3-plan.p11-probe.sh" <tree> <fixed dir> refusals|start`.
It runs `<tree>`'s create once per case in a fresh root `<fixed dir>/run/x` under `env -i`
(`HOME`, `USER=u`, `LANG=C.UTF-8`, `PATH`, `DOCKER_STUB_LOG`, plus the case's variables),
and appends per case the exit status, stdout, stderr, the stub docker log, every path the run
added under the root, and any directory it added under `/tmp/.X11-unix` (then removed). This
is a probe of the base, not the pin: T01 writes the pin. Raw output of the four runs below:
`2026-11-11-sandbox-hardening-p3-plan.p11-output.txt`.

On this machine `command -v rsync xpra Xvfb Xephyr` under `/usr/bin` finds none; `rsync` comes
from the stub directory. Not stubbed and present here: `/opt/idea-IU` (create's default
`IDEA_HOST_DIR`, so the start path printed "installation /opt/idea-IU"), `/run/user/1000`
(the default `XDG_RUNTIME_DIR`), and a working `timedatectl` (the timezone line). The pin must
fix all three (plan, "Pin matrix").

Results on the base (`B`, export of `273b538`), "left" = paths added under the root:

| Case | Real input | rc | First line of stderr | Left |
|---|---|---|---|---|
| R1 | no `config` file | 1 | No memory budget is configured ... is not set | nothing |
| R2 | `AI_SANDBOX_MEMORY_BUDGET_GB=x` | 1 | ... is 'x' ..., not a whole number of GB | nothing |
| R3 | `PATH` of the stub directory's links without `rsync`, then `/usr/bin` | 1 | 'rsync' is required but not installed. | nothing |
| R4 | a `docker` ahead of the stub that exits 1 for `compose version` | 1 | 'docker compose' (v2 plugin) is required. | nothing |
| R5 | `DOCKER_STUB_RUNNING=true`, `--no-start` | 1 | `<id>-agent` is running. Stop it first | nothing |
| R6 | the same without `--no-start` | 1 | the same | nothing |
| R7 | `HOME=<root>/ho,me` | 1 | Cannot use '...ho,me' for build caches | nothing |
| R8 | a copy of the tree without `tools/`; nothing at `~/dev/public/dev-tools/tools`, `~/tools` | 1 | Cannot locate the dev-tools 'tools' directory | 26: the sandbox directory with `project-path` and its state directories, `image/build`, `shared/*` |
| R9 | `auto`, no display program on `PATH` | 1 | No isolated display backend available. | the same 26 |
| R10 | `--display=xpra`, no `xpra` on `PATH` | 1 | 'xpra' is required but not installed. | the same 26 |
| R11 | `--display=wayland`, no `WAYLAND_DISPLAY` | 1 | --display=wayland but WAYLAND_DISPLAY is not set. | the same 26 |
| R12 | `--display=host`, no `DISPLAY` | 1 | --display=host but DISPLAY is not set. | the same 26 |
| R13 | budget 8; `other-agent` running with 4 GB (`DOCKER_STUB_PS`, `DOCKER_STUB_MEMORY`, its directory under the root); no `--no-start` | 1 | Cannot start `<id>-agent` (6 GB): 4 GB of the 8 GB memory budget is in use. | 111: every generated file, no build, no `compose up` |
| S1 | `--display=none`, no image | 0 | (IDE extension warnings) | 114; docker log: `build`, `compose ... up -d` |
| S2 | S1's root again, `DOCKER_STUB_IMAGES=ai-sandbox:base-u<uid>` | 0 | (IDE extension warnings) | 1 more; stdout "... is up to date", no `build` in the docker log |
| S3 | `--display=none --rebuild` | 0 | (IDE extension warnings) | 114; docker log: `build --no-cache` |
| S4 | `--display=xpra`, display stubs (exit 0, no socket) | 1 | the xpra configuration warning; then "Xvfb did not start; see .../xvfb.log" | 116 and the X socket directory; docker log: `compose version` only, so the display is started before the image step and `compose up` |

Each refusal is reachable through its input, and the steps that print nothing when they pass
(the budget, the prerequisites, I10, D9, the tools lookup, the display checks, the capacity
check) leave three different footprints (nothing; 26 paths, the same list for R8 to R12; 111
paths), and within one footprint stdout differs by the steps passed before the refusal (the
"tools", "mode:" and "CPU set" lines), so moving one of them changes what a refused run leaves
or prints.

New non-deterministic line: S2 prints `already seeded on <the content of .seeded>` (create's
seed section, `log "already seeded on $(cat ...)"`), so a case that runs create twice on one
root (K11, K28) carries N1's time in stdout. The plan names it N3. P4's search missed it
because the line reads `.seeded` rather than calling `date`.

Method check (the moved budget gate): a copy of the base with the gate moved after the line
that writes `project-path`:

```
BM=$(mktemp -d); cp -a "$B/." "$BM"; f=$BM/bin/ai/create-ai-sandbox.sh
sed -i '376d' "$f"; sed -i '454a ai_sandbox_memory_budget_gb >/dev/null || exit 1' "$f"
diff "$B/bin/ai/create-ai-sandbox.sh" "$f"     # 376d375 and 455a455: only the gate moved
F=<one fixed dir>; for t in "$B" "$BM"; do for l in refusals start; do rm -rf "$F"; bash "$E/2026-11-11-sandbox-hardening-p3-plan.p11-probe.sh" "$t" "$F" $l >/dev/null 2>&1; cp "$F/result" "<out>/$(basename "$t")-$l"; done; done
```

`diff` of the two `refusals` results: R1 and R2 only, each gaining the "== Project" lines in
stdout, one `container inspect` in the docker log, and two paths left (the sandbox directory
and its `project-path`); every other case identical. The two `start` results differ only in
S2's `already seeded on` time (N3). So refusal cases detect a moved silent gate that every
success case misses; a different fixed dir gives a different project id and differs
everywhere, which is why the pin runs every compared tree at one root.

## Re-check when phase 1 lands on `main`

The first task (T01) runs these on the real base before it pins, and reports to the planner
any result that differs; the plan is corrected before T02 starts.

1. `git -C <worktree> diff --stat 273b538 <base> -- . ':(exclude)docs/superpowers'`:
   expected empty (the scope of S1 and S3, which also covers `PROJECT_MAP.md`, `README.md`,
   `.agents`, `docs/shared-knowledge.md` and `.gitignore`). If it is empty, items 2 to 7a hold
   unchanged and are recorded as such; if not, they are re-run.
2. S1, S2, S3, S4, S-src, S5, S6 (counts 12, 2, per-file list, 1, 0, 14, 22 names of which 15
   are used nowhere else).
3. S7 and its classification (three `declare` sites, `"$@"` twice, `BASH_SOURCE` once), and
   the `and-tail` and `!` searches under P2 (2 sites, 651 and 808; 0).
4. P8 (the order: capacity check before the build, launchers after the compose file).
5. P4 and P11 (non-deterministic sources: N1 to N3 only, within the matrix).
6. P5 and P7 (the rules' known cases), if `tests/ai-sandbox/sg/` or ast-grep changed.
7. P6 (`.gitignore`).
7a. P11's `refusals` and `start` lists on the base (the same rc, first stderr line and footprint
   per case as the table), if item 1 is not empty.
8. The suite record of P9 is replaced by T01's own run on the base (O2).
