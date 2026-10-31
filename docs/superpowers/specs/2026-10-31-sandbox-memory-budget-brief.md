# Brief: a host memory budget for ai-sandbox instead of the cap of three

Status: reviewed (Fiona, rounds 1–2); awaiting the user's approval.

Date: 2026-10-31. Task brief, no phase plan (class Brief: several commits, a
new stored key, no contract outside the repository). Implementer: Stasiek,
who owns `bin/ai/create-ai-sandbox.sh`. One review follows. Evidence file:
`docs/superpowers/evidence/2026-10-31-sandbox-memory-budget.md`.

Written by Bartek (planner 2) against the tree at b949751. Every line number
below was read in that tree; a claim marked *unverified* was not.

## Goal

A sandbox is created with a memory size of its own (`--memory=GB`, default
6, remembered per project) and gets `ceil(GB/2)` CPU cores, never fewer than 1
nor more than the host's `nproc`. Starting a sandbox is refused when its GB
plus the GB of every sandbox currently running would exceed the host's budget
in `~/.ai-sandbox/config`; the refusal lists the running sandboxes with their
GB. With no budget configured, creating or starting is refused with a message
that says what to write where. `AI_SANDBOX_MAX_RUNNING` is gone.

## User decisions (2026-10-31)

Items 1 to 6 of the task note, restated where the brief fixes a name:

- Config file `~/.ai-sandbox/config`, shell-style `KEY=VALUE`; budget key in
  GB; no default budget; missing file or key refuses create and start.
- `create-ai-sandbox.sh` option in GB, default 6, remembered in `.env`.
- Cores `ceil(GB/2)`, floor 1, ceiling `nproc`; the cpuset mechanism stays.
- Start refused when running GB + the new one's GB > budget; stopped sandboxes
  do not count; running memory read from Docker's `HostConfig.Memory`.
- `MEMORY_SWAP_LIMIT` stays equal to the memory limit. `SHM_SIZE` (`'1gb'`,
  line 79), `oom_score_adj: 500` and `pids_limit: 4096` (lines 2170, 2173)
  are literals, not derived from 6g, so they are untouched.

## Names chosen

- Config key `AI_SANDBOX_MEMORY_BUDGET_GB`: the `AI_SANDBOX_` prefix is what
  the lib's own settings carry (`AI_SANDBOX_ROOT`, lib line 9), and the file
  is already sourced by `ai-sandbox-migrate` (line 17), so a shell-style key
  with that prefix reads as one more lib setting.
- Option `--memory=GB` (whole number of GB): the `--name=value` shape of
  `--display=MODE` (line 251), the only valued option today.
- `.env` key `SANDBOX_MEMORY_GB`: the `SANDBOX_` prefix of every remembered
  key (`SANDBOX_WITH_DOCKER`, `SANDBOX_CPUSET`, lines 2112–2121).
- Lib symbols (contract, used by three callers and by the supervisor spec):

      AI_SANDBOX_CONFIG="$AI_SANDBOX_ROOT/config"     # defined once, in the lib
      ai_sandbox_memory_budget_gb                    # prints the budget; 1 + refusal on stderr when unset/invalid
      ai_sandbox_memory_gb <sandbox dir>             # SANDBOX_MEMORY_GB from .env, or 6 when the key is absent
      ai_sandbox_check_capacity <name> <gb>          # 0, or 1 + the over-budget refusal on stderr

## Facts the brief rests on (verified unless marked)

- `~/.ai-sandbox/config` already exists: create writes it with `>` at line
  2618 (`DEV_TOOLS_DIR=...`), the lib reads `DEV_TOOLS_DIR` with `sed` at line
  106, `ai-knowledge` at line 163, `ai-sandbox-migrate` sources it at line 17.
  **The `>` at 2618 would erase a hand-written budget on every re-run**; the
  write must become a rewrite of the `DEV_TOOLS_DIR` line that keeps every
  other line, written to a temp file in the same directory and moved into
  place with `mv`, so a concurrent `ai-sandbox` (migrate sources the file at
  line 17, the lib reads it at 106) never sees a truncated file. The `.env`
  block at 2103–2136 is the model for which lines are kept, not for the
  in-place truncation it does.
- The cap is enforced in exactly three places: `ai_sandbox_check_capacity`
  called from `create-ai-sandbox.sh:2661` (after the `--no-start` exit at 2654–2657),
  `ai-sandbox:32`, `ai-sandbox-restart:19`. Source: `grep -rn
  ai_sandbox_check_capacity bin tests` → 3 callers + the definition + 1 test.
  `grep -n 'compose up\|up -d' bin/ai/*` finds no other start path.
- `CPU_LIMIT` is computed at lines 89–91, before options are parsed (249) and
  before the remembered `.env` values are read (468–482); the cpuset is
  allocated at 567–616 and `cpuset_valid` (578–587) already re-allocates when
  the recorded set's size differs from `CPUSET_WANT`, so a changed `--memory`
  gets a new set without new code. `HOST_CPUS` capping exists at 576–577.
- The emitted rules text names the limits through `${MEMORY_LIMIT}` and
  `${CPUSET_WANT}` at line 1010; the compose file at 2162–2166; the start
  summary at 2748–2749; the usage text at 236–243; the header comment at
  48–70; the lib comment at 11–14.
- Docker reports the limit in bytes: `6g` → `6442450944` = 6 GiB exactly
  (*unverified: this sandbox has no daemon*). The evidence file must hold one
  `docker container inspect -f '{{.HostConfig.Memory}}' <running 6g sandbox>`
  run on the host, with its output; the user runs it when asked, as part of
  the task's host requests (obligation B12). A container with no limit
  reports `0`.
- The test stub `tests/ai-sandbox/stub/docker` answers `container inspect`
  only with `{{.State.Running}}` (`true`/`false`) and takes the name from
  `$5`; `ps` prints `DOCKER_STUB_PS`. It must learn `HostConfig.Memory`.
- 17 of 20 test files run `create-ai-sandbox.sh` through `fake_home`
  (harness.sh), whose `$AI_SANDBOX_ROOT` holds no config until create writes
  one. With create refusing on a missing budget, `fake_home` must seed
  `AI_SANDBOX_MEMORY_BUDGET_GB=18` into `$AI_SANDBOX_ROOT/config`, or 17 suites
  fail. `test-helpers.sh:20–22` asserts the file *contains* `DEV_TOOLS_DIR=`,
  so extra lines are fine. `test-migrate.sh:120` overwrites the file with
  `DEV_TOOLS_DIR` only; migrate never starts anything, so it stays.
- Baseline: `test-capacity.sh` 16 run 0 failed; `test-resources.sh` 34 run
  0 failed (this sandbox, 2026-10-31).

## Behaviour

- Budget read: `sed -n 's/^AI_SANDBOX_MEMORY_BUDGET_GB=//p'` on
  `$AI_SANDBOX_CONFIG`, last line wins; never `source` the file from the lib
  (the lib is sourced by every helper and the file is user-written). A value
  that is not a whole number ≥ 1 is treated as unset, with the value quoted
  in the refusal.
- Create reads the budget right after the lib is sourced (line 345) and
  before anything is written, `--no-start` included: a missing budget refuses
  the create outright. The over-budget check stays where it is (2661), so
  `--no-start` still ignores capacity.
- `--memory=GB`: whole number ≥ 1, else `Invalid --memory=<value>: a whole
  number of GB` and exit 2 like `--display`. Not given and `SANDBOX_MEMORY_GB`
  in `.env`: keep it, with a `keeping N GB of memory (pass --memory=... to
  change it)` log line like the Docker/audio ones. Neither: 6.
- `MEMORY_LIMIT="${MEMORY_GB}g"`, `MEMORY_SWAP_LIMIT=$MEMORY_LIMIT`;
  `CPU_LIMIT=$(( (MEMORY_GB + 1) / 2 ))`, floor 1; `CPUSET_WANT` capped at
  `HOST_CPUS` as today. The `readonly` constants at 77–78 and the derivation
  at 81–91 move below the remembered-option resolution; `mem_limit_gb` goes.
- Running memory: one `docker container inspect -f '{{.HostConfig.Memory}}'`
  per running sandbox name from `docker ps`, same filter as today (a name is a
  sandbox only when `$AI_SANDBOX_ROOT/<name>` is a directory; the sandbox being
  started never counts). Bytes → GB by `ceil(bytes / 1073741824)`; `0` (no
  limit) counts 0 GB and is listed as `no limit`.
- The sandbox being started: create passes `$MEMORY_GB`; `ai-sandbox` and
  `ai-sandbox-restart` pass `ai_sandbox_memory_gb "$AI_SANDBOX_DIR"`, which
  returns 6 for a sandbox created before this change (its compose file says
  `mem_limit: "6g"`, so 6 is what Docker will apply).

## Refusal messages (exact)

Missing or invalid budget, from `ai_sandbox_memory_budget_gb`, on stderr,
`<config>` being the expanded `$AI_SANDBOX_CONFIG`:

    No memory budget is configured for this host: AI_SANDBOX_MEMORY_BUDGET_GB is not set in <config>.
    Write the RAM, in GB, that all running sandboxes together may use, for example:
        echo 'AI_SANDBOX_MEMORY_BUDGET_GB=18' >> <config>

With an invalid value the first line ends `is '<value>' in <config>, not a
whole number of GB.` instead. Create prefixes nothing; the helpers prefix
nothing; the message is the same from the three callers (create:2661,
ai-sandbox:32, ai-sandbox-restart:19).

Over budget, from `ai_sandbox_check_capacity <name> <gb>`, on stderr:

    Cannot start <name> (<gb> GB): <used> GB of the <budget> GB memory budget is in use.
    Running: aaa-agent (6 GB), bbb-agent (8 GB)
    Stop one first, with 'ai-sandbox-stop' from its project directory, or raise AI_SANDBOX_MEMORY_BUDGET_GB in <config>.

`Running:` lists every counted sandbox, comma-separated, in `docker ps` order;
a `0` reports as `aaa-agent (no limit)`.

## Tasks, in commit order

1. **lib** (`bin/ai/ai-sandbox-lib.sh`): remove `AI_SANDBOX_MAX_RUNNING` and
   its comment (11–14); add `AI_SANDBOX_CONFIG`, `ai_sandbox_memory_budget_gb`,
   `ai_sandbox_memory_gb`; rewrite `ai_sandbox_check_capacity` to the new
   signature and the sum rule; the comment above it (226–231) states the rule.
   The key's definition carries a one-line comment that the user writes it by
   hand (the only reader outside the repository is the user). Extend the docker
   stub with a `DOCKER_STUB_MEMORY` lookup (`<name>=<bytes>` lines, default
   `6442450944`) for `{{.HostConfig.Memory}}`; seed the budget in `fake_home`.
   Update `ai-sandbox:32` and `ai-sandbox-restart:19` to pass the GB; both
   call `ai_sandbox_memory_budget_gb` before the capacity check so a missing
   budget refuses the start with the first message. So that the suite is
   green after this commit, `create-ai-sandbox.sh` gets its two smallest
   changes here too: the budget read after line 345, and the call at 2661
   becomes `ai_sandbox_check_capacity "$CONTAINER_NAME" "$(mem_limit_gb
   "$MEMORY_LIMIT")"`; `mem_limit_gb` is removed in task 2. (The alternative,
   moving the create cases of B2 and B4 into task 2's tests, was declined: it
   would leave create calling with one argument between the commits and hide
   it.) Rewrite `test-capacity.sh` (B1–B4). Commit `feat(ai-sandbox): memory
   budget replaces the cap of three running sandboxes`.
2. **script** (`bin/ai/create-ai-sandbox.sh`): `--memory=GB` parsed, validated,
   remembered (`SANDBOX_MEMORY_GB` in the managed `.env` keys), logged when
   kept; limits and `CPU_LIMIT` derived from it below the remembered options,
   `mem_limit_gb` gone; the call at 2661 passes `"$MEMORY_GB"`; the config
   write at 2618 keeps other lines (temp file beside it, then `mv`); usage
   (118–160, 236–243), header comment (48–70), the CPU-set log line (613) and
   the summary (2748–2749) say GB from the option, not 6g; the emitted rules
   text (1010) already interpolates. Extend `test-resources.sh` and
   `test-options.sh` (B5–B7), `test-helpers.sh` (B8). Commit
   `feat(create-ai-sandbox): --memory=GB per sandbox, cores = ceil(GB/2)`.
3. **docs**: `PROJECT_MAP.md:13` (the "6 GB memory cap with at most three
   sandboxes running at once" clause) and `README.md` if it mentions the cap
   (grep found nothing there today). Commit `docs(ai-sandbox): memory budget`.
   The supervisor spec and brief are not edited by this task (see Note for
   the lead).

## Obligations (tests and acceptance)

Each is `bash tests/ai-sandbox/<file>`; expected: `N run, 0 failed` with the
named assertions present and passing. Record each command's last line.

- B1 `test-capacity.sh`: no `AI_SANDBOX_MAX_RUNNING` assertion; with a budget
  of 18 and `DOCKER_STUB_PS=aaa-agent,bbb-agent` at 6 GB each, a 6 GB
  `ai-sandbox` start succeeds (12 + 6 = 18 is not over) and reaches `up -d`;
  with `ccc-agent` also running (18 GB used) it is refused, the refusal names
  `aaa-agent (6 GB)`, `ccc-agent (6 GB)` and `18 GB memory budget`, and
  `compose up` is never reached.
- B2 `test-capacity.sh`: a running `stranger-agent` (no sandbox directory) and
  a stopped sandbox are not counted; `ai-sandbox-restart` does not count the
  sandbox itself and a refused restart never reaches `down`; create is refused
  before `build`; `--no-start` ignores capacity (the four existing cases, kept
  with the new list format).
- B3 `test-capacity.sh`: a running sandbox stubbed at `8589934592` bytes
  counts 8 GB (so 6 + 8 + a new 6 > 18 is refused while 6 + 8 + 4 is not);
  a sandbox whose `.env` has no `SANDBOX_MEMORY_GB` is started as 6 GB.
- B4 `test-capacity.sh`: with the key absent from `$AI_SANDBOX_ROOT/config`,
  `ai-sandbox`, `ai-sandbox-restart` and `create-ai-sandbox.sh --no-start` all
  exit non-zero, print the three-line missing-budget message naming
  `AI_SANDBOX_MEMORY_BUDGET_GB` and the config path, write no `.env`, and
  `DEV_TOOLS_DIR=` still stands in the config afterwards (create must not
  clobber the file on refusal); with `AI_SANDBOX_MEMORY_BUDGET_GB=abc` the
  message quotes `abc`.
- B5 `test-resources.sh`: default create yields `mem_limit: "6g"`,
  `memswap_limit: "6g"`, `cpuset` of `min(3, nproc)` cores, `SANDBOX_MEMORY_GB=6`
  in `.env`, the rules text `capped at 6g of RAM with no swap and <want> CPU
  core(s)`; `--memory=5` yields `5g`, `min(3, nproc)` cores and
  `SANDBOX_MEMORY_GB=5`; `--memory=1` yields `1g` and 1 core; `--memory=8`
  yields `8g`, `min(4, nproc)` cores, rules text `capped at 8g`, and the
  cpuset recorded for 6 is re-allocated to the new size.
- B6 `test-options.sh`: `--memory=8` recorded; bare re-run keeps 8 and logs
  `keeping 8 GB`; `--memory=6` changes it; `--memory=0`, `--memory=` and
  `--memory=6g` exit 2 with `Invalid --memory`.
- B7 `test-resources.sh`: `shm_size: '1gb'`, `cpu_shares: 256`,
  `oom_score_adj: 500`, `pids_limit: 4096` unchanged (existing assertions).
- B8 `test-helpers.sh`: after a create, `$AI_SANDBOX_ROOT/config` holds both
  `DEV_TOOLS_DIR=<repo>` and the seeded `AI_SANDBOX_MEMORY_BUDGET_GB=18`, each
  once; a second create does not duplicate either line.
- B9 Residue, run from the repository root, expected empty:
  `grep -rn 'AI_SANDBOX_MAX_RUNNING\|mem_limit_gb' bin tests PROJECT_MAP.md
  README.md`; `grep -rn "'6g'\|\"6g\"" bin/ai/create-ai-sandbox.sh`
  (the tests may keep `6g` as the default's expected value, listed by name in
  the evidence file); and the prose literals:
  `grep -rni 'at most three\|three sandboxes\|6 GB of RAM\|6g sandbox\|sandboxes run at once' bin/ai PROJECT_MAP.md`
  → empty (today it hits create 53, 60, 236, 241, 242, lib 11 and
  PROJECT_MAP.md 13, and not the lib's "three fields"/"three lowers" at 168,
  352, 366; checked 2026-10-31).
  Allowed survivors: `docs/superpowers/specs/*` and
  `docs/superpowers/evidence/*` (history), listed in the evidence file.
- B10 Full suite: `bash tests/ai-sandbox/run-tests.sh 2>&1 | tail -3` →
  `ALL SUITES PASSED`. Pre-existing failures, if any, named with their
  baseline (the memory notes name one SDKMAN case that fails only inside a
  sandbox; `test-delegate.sh` had 43/48 pre-existing failures on 2026-10-28).
- B11 `bash -n` on `bin/ai/create-ai-sandbox.sh`, `bin/ai/ai-sandbox-lib.sh`,
  `bin/ai/ai-sandbox`, `bin/ai/ai-sandbox-restart` and `shellcheck` on the lib
  if it is installed: no new warnings versus the baseline.
- B12 Read: the evidence file quotes `docker container inspect -f
  '{{.HostConfig.Memory}}' <name>` for a running sandbox whose compose file
  says `mem_limit: "6g"`, run on the host by the user, and its output is
  `6442450944`. This is the one check the sandbox cannot run; it goes into the
  task's single batched request to the user.

## Acceptance criterion

B1–B12 recorded in the evidence file with their last output lines and commit
hashes; `AI_SANDBOX_MAX_RUNNING` appears nowhere under `bin`, `tests`,
`PROJECT_MAP.md`; a sandbox created with `--memory=8` on a host whose config
says 18 is refused by `ai-sandbox` while two 6 GB sandboxes run, with the
refusal listing both.

## Impact set

- `AI_SANDBOX_MAX_RUNNING` (removed): `grep -rn AI_SANDBOX_MAX_RUNNING --include=* .`
  excluding `.tmp` → lib:14 (definition), create:69, create:242 (comments),
  `test-capacity.sh:2,17`, supervisor design:1034 and brief:149 (uncommitted
  specs, see Note for the lead), one evidence file (history). Residue
  obligation B9.
- `ai_sandbox_check_capacity` (signature gains `<gb>`): callers create:2661,
  ai-sandbox:32, ai-sandbox-restart:19; test-capacity.sh exercises all three.
  Named in the supervisor design D6 (234–250) and D16 (684–690) as "unchanged"
  and "rewritten to use `ai_sandbox_running`": that spec must learn the new
  signature. Residue: none needed, bash has no callers the grep misses here
  (`grep -rn check_capacity` → the same 3 + definition + 1 test).
- `~/.ai-sandbox/config` (format extended, one more key): readers lib:106,
  ai-knowledge:163, migrate:17, test-helpers:20–22, test-migrate:120, writer
  create:2618. Only the writer changes. Outside the repository: the user's
  hand-written key; no other consumer (no coupling register exists in
  `PROJECT_MAP.md` today; the comment at the key's definition is the note).
- `.env` (one more managed key): readers of `SANDBOX_*` keys are
  `ai_sandbox_env_value` callers; an addition has no old shape.
- Duplicated logic: `grep -rn '/ 2\b' bin/ai/create-ai-sandbox.sh` → line 89 (the derivation) and 613 (the log text that quotes it)
  ; no second copy of the rule. Both change in task 2.
- Literal `6g`/`6 GB`/`three` in prose: create 51–53, 60–61, 236–243, 613;
  lib 11–13; PROJECT_MAP.md:13; `2026-10-02-ai-sandbox-build-caches-design.md`
  271, 335 (history, kept). Memory notes `ai-sandbox-limits-2026-09-09` and
  `ai-sandbox-priority-2026-10-08` state the cap; the lead updates memory,
  not this task.

## After the change, on the host (user)

1. `echo 'AI_SANDBOX_MEMORY_BUDGET_GB=<GB>' >> ~/.ai-sandbox/config` once
   (the file exists; append, do not overwrite the `DEV_TOOLS_DIR` line).
   Until then every `ai-sandbox`, `ai-sandbox-restart` and
   `create-ai-sandbox.sh` is refused with the missing-budget message, also for
   sandboxes created before this change.
2. Re-run `create-ai-sandbox.sh [--memory=GB] <project>` for each sandbox to
   pick up the new compose limits, cpuset and rules text. An existing `.env`
   has no `SANDBOX_MEMORY_GB`, so the first re-run without `--memory` writes
   and applies the default 6, and the emitted rules text then says `6g` and
   3 cores as today. Until a sandbox is re-run it keeps `mem_limit: "6g"` and
   counts as 6 GB under the budget (the `.env` fallback), which matches what
   Docker applies to it.
3. Installed helpers under `~/.ai-sandbox/bin` are refreshed by the first
   `create-ai-sandbox.sh` run (install loop at 2607–2611), so the lib with
   the new check is live from then on; `ai-sandbox` also refreshes them
   through `ai-sandbox-migrate` when `DEV_TOOLS_DIR` is recorded.

## Open items for the user (both decided 2026-10-31)

- **Decided: a legacy sandbox counts as a fixed 6 GB** at start when its
  `.env` lacks `SANDBOX_MEMORY_GB` (matches its compose file's
  `mem_limit: "6g"`). Declined alternatives: (a) refuse the start until the
  sandbox is re-created, like the knowledge stamp does
  (`ai_sandbox_require_current`); (b) read the sandbox's own limit from its
  `docker-compose.yml` `mem_limit:` line or from `HostConfig.Memory` of its
  stopped container.
- **Decided: a running container reporting `HostConfig.Memory` 0 counts
  0 GB** and is listed as `no limit`. Declined alternatives: count it as the
  whole budget; refuse every start until that sandbox is re-created. The
  doctor already tells such a sandbox to re-run create (line 1483).

## Note for the lead (not a user decision)

`2026-10-30-sandbox-supervisor-design.md` D-U1 ("the control sandbox counts
under `AI_SANDBOX_MAX_RUNNING`, or the constant becomes 4") becomes moot: the
control sandbox gets its own `--memory` and counts under the budget like any
sandbox. D6 (234–250) and D16 (684–690) and the supervisor brief at 148–150
name `ai_sandbox_check_capacity` with the old signature and the cap of three.
That spec is uncommitted and awaiting approval; its author should fold this in
before supervisor phase 1 is planned. Not changed by this task.
