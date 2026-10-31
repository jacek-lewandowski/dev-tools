# Evidence: a host memory budget for ai-sandbox (brief 2026-10-31)

Implementer: Stasiek (implementer 3). Brief:
`docs/superpowers/specs/2026-10-31-sandbox-memory-budget-brief.md`.
Base: 585c4a4. Commits, in the brief's order:

- 26f797c `feat(ai-sandbox): memory budget replaces the cap of three running sandboxes` (task 1)
- 8e25987 `feat(create-ai-sandbox): --memory=GB per sandbox, cores = ceil(GB/2)` (task 2)
- 5dbfe89 `docs(ai-sandbox): memory budget` (task 3)

Every brief fact was re-located by its text in the tree at 585c4a4; all held
at the brief's line numbers. shellcheck is not installed in this sandbox.

## Deviation from the brief's task split (reported, not silent)

The config rewrite at create:2618 (keep every line but `DEV_TOOLS_DIR`, temp
file beside it, `mv`) and its test B8 landed in task 1 (26f797c) instead of
task 2. Reason: with the brief's split, commit 1 would still truncate
`$AI_SANDBOX_ROOT/config` with `>` on every create, erasing the budget
`fake_home` seeds; `test-capacity.sh`, `test-build-caches.sh` and
`test-knowledge.sh` all start helpers after a create in the same fake home, so
every such start would be refused for a missing budget and the suite would not
be green after commit 1 (the brief's own rule), and on a host commit 1 alone
would erase the user's hand-written budget on every run. Everything else of
task 2 stayed in 8e25987.

## Baseline (585c4a4, this sandbox, 2026-10-31 10:00)

`bash tests/ai-sandbox/run-tests.sh` → `SOME SUITES FAILED`; 20 suites,
1031 run, 3 failed: `test-delegate.sh` cases 54 (`writer prompt has no-tools
line`) and 59 (`second-reviewer prompt has no-commands line`), `test-tools.sh`
case 39 (`a candidate without a default is skipped`, SDKMAN, fails only inside
a sandbox). `test-capacity.sh` 16 run 0 failed; `test-resources.sh` 34 run
0 failed; `test-options.sh` 15 run 0 failed; `test-helpers.sh` 12 run 0 failed.

## Red runs (tests written first)

- Task 1, after rewriting `test-capacity.sh`, extending `test-helpers.sh`, the
  docker stub (`DOCKER_STUB_MEMORY`) and `fake_home` (seeded budget), before
  any change under `bin/`:
  `bash tests/ai-sandbox/test-capacity.sh` → `52 run, 31 failed`;
  `bash tests/ai-sandbox/test-helpers.sh` → `17 run, 3 failed`
  (`config keeps the hand-written budget`, `a second create does not duplicate
  the budget`, `the budget value survives`).
- Task 2, after extending `test-resources.sh` and `test-options.sh`, before
  the create changes:
  `bash tests/ai-sandbox/test-resources.sh` → `47 run, 11 failed`;
  `bash tests/ai-sandbox/test-options.sh` → `27 run, 9 failed`.

## Obligations

### B1 — `bash tests/ai-sandbox/test-capacity.sh` (commit 26f797c; re-run on 5dbfe89)

Last line: `52 run, 0 failed`. No `AI_SANDBOX_MAX_RUNNING` assertion remains
(`grep -n AI_SANDBOX_MAX_RUNNING tests/ai-sandbox/test-capacity.sh` → empty).
Assertions present and passing: `ai-sandbox starts when the budget is exactly
filled` (budget 18, `DOCKER_STUB_PS=aaa-agent,bbb-agent` at 6 GB each, new
6 GB), `the start reaches compose up`; with `ccc-agent` also running:
`ai-sandbox refuses when the budget would be exceeded`, `the refusal names the
sandbox and its memory` (`Cannot start <name> (6 GB): 18 GB of the 18 GB memory
budget is in use.`), `the refusal lists the first running sandbox`
(`aaa-agent (6 GB)`), `the refusal lists the last running sandbox`
(`ccc-agent (6 GB)`), `the list is comma-separated in docker ps order`,
`a refused start does not reach compose up`.

### B2 — `bash tests/ai-sandbox/test-capacity.sh` (26f797c)

Last line: `52 run, 0 failed`. Assertions: `unrelated and stopped containers
are not counted` (running `stranger-agent` without a sandbox directory and
`ddd-agent` with a directory but not in `docker ps`; the start succeeds),
`restart does not count the sandbox itself` (down and up reached), `restart
refuses when the budget is full` + `a refused restart never takes the sandbox
down`, `create refuses to start over the budget` + `a refused create neither
builds nor starts`, `--no-start ignores the budget`.

### B3 — `bash tests/ai-sandbox/test-capacity.sh` (26f797c)

Last line: `52 run, 0 failed`. With `DOCKER_STUB_MEMORY` =
`aaa-agent=6442450945`, `bbb-agent=8589934592`, `ccc-agent=0`: `bytes are
summed as GB` (`15 GB of the 18 GB memory budget`), `8 GiB is listed as 8 GB`,
`a partial GB rounds up` (`aaa-agent (7 GB)`), `no limit is listed as such`
(`ccc-agent (no limit)`), `the over-budget start does not reach compose up`;
then `SANDBOX_MEMORY_GB=3` appended to the sandbox's `.env`: `the sandbox's
own .env size is what counts` (15 + 3 = 18 starts); the key deleted again:
`a sandbox without SANDBOX_MEMORY_GB counts 6 GB`, `and the refusal says 6 GB`.

### B4 — `bash tests/ai-sandbox/test-capacity.sh` (26f797c)

Last line: `52 run, 0 failed`. With the key deleted from
`$AI_SANDBOX_ROOT/config`: `ai-sandbox refuses without a budget`, `ai-sandbox
names the missing key` (`No memory budget is configured for this host:
AI_SANDBOX_MEMORY_BUDGET_GB is not set in <config>`), `ai-sandbox says what the
value means`, `ai-sandbox says what to write where`
(`echo 'AI_SANDBOX_MEMORY_BUDGET_GB=18' >> <config>`), `no budget: ai-sandbox
does not reach compose up`; `ai-sandbox-restart refuses without a budget`,
`no budget: restart never takes the sandbox down`; `create refuses without a
budget, --no-start included`, `a refused create writes no .env`, `a refused
create leaves the config alone` (`DEV_TOOLS_DIR=<repo>` still present). With
`AI_SANDBOX_MEMORY_BUDGET_GB=abc`: `the invalid value is quoted`
(`is 'abc' in <config>, not a whole number of GB.`); with `=0`: `zero is quoted
too`; a later `=18` line: `an appended budget takes effect` (last line wins).

### B5 — `bash tests/ai-sandbox/test-resources.sh` (8e25987; re-run on 5dbfe89)

Last line: `47 run, 0 failed`. Default create: `compose caps memory`
(`mem_limit: "6g"`), `compose forbids swap` (`memswap_limit: "6g"`), `compose
pins a cpuset` (`min(3, nproc)` cores, here nproc = 3 → `0,1,2`), `the default
size is remembered in .env` (`SANDBOX_MEMORY_GB=6`), `the shared brain states
the cap` (`capped at 6g of RAM with no swap`) + `the shared brain states the
CPUs` (`and 3 CPU core(s)`); `--memory=8`: `--memory=8 caps memory at 8g`,
`--memory=8 forbids swap at 8g`, `the set recorded for 6 is re-allocated to
ceil(8/2) cores` (`min(4, nproc)` cores; on this 3-core sandbox that is
`0,1,2`, on a host with ≥ 4 cores `0,1,2,3`), `--memory=8 is remembered in
.env`, `the shared brain states the new cap` (`capped at 8g of RAM with no swap
and <want> CPU core(s)`); `--memory=5`: `5g`, `min(3, nproc)` cores,
`SANDBOX_MEMORY_GB=5`; `--memory=1`: `1g`, `cpuset: "0"`, `SANDBOX_MEMORY_GB=1`,
`capped at 1g of RAM with no swap and 1 CPU core(s)`.

### B6 — `bash tests/ai-sandbox/test-options.sh` (8e25987; re-run on 5dbfe89)

Last line: `27 run, 0 failed`. Assertions: `memory recorded`
(`SANDBOX_MEMORY_GB=8`), `memory is sticky` (bare re-run keeps 8), `a bare
re-run says what it kept` (`keeping 8 GB of memory (pass --memory=... to change
it)`), `--memory=6 changes it`; `--memory=0 exits 2`, `--memory= exits 2`,
`--memory=6g exits 2`, each `is explained` (`Invalid --memory=<value>: a whole
number of GB`); `help documents --memory` (`--memory=GB`), `help names the
budget key`.

### B7 — `bash tests/ai-sandbox/test-resources.sh` (8e25987)

Last line: `47 run, 0 failed`; the existing assertions `shm is well under the
cap` (`shm_size: '1gb'`), `compose lowers CPU shares` (`cpu_shares: 256`),
`compose raises the OOM score` (`oom_score_adj: 500`), `compose limits
processes` (`pids_limit: 4096`) pass unchanged.

### B8 — `bash tests/ai-sandbox/test-helpers.sh` (26f797c; re-run on 5dbfe89)

Last line: `17 run, 0 failed`. Assertions: `config points at the repo`
(`DEV_TOOLS_DIR=<repo>`), `config keeps the hand-written budget` (one
`AI_SANDBOX_MEMORY_BUDGET_GB=` line), `config records the source dir once`,
after a second create: `a second create does not duplicate the budget`, `a
second create does not duplicate the source dir`, `the budget value survives`
(`AI_SANDBOX_MEMORY_BUDGET_GB=18`).

### B9 — residue, run from the repository root on 5dbfe89

    grep -rn 'AI_SANDBOX_MAX_RUNNING\|mem_limit_gb' bin tests PROJECT_MAP.md README.md

→ empty (exit 1).

    grep -rn "'6g'\|\"6g\"" bin/ai/create-ai-sandbox.sh

→ empty (exit 1).

    grep -rni 'at most three\|three sandboxes\|6 GB of RAM\|6g sandbox\|sandboxes run at once' bin/ai PROJECT_MAP.md

→ empty (exit 1).

Tests that keep `6g` as the default's expected value (`grep -rn 6g
tests/ai-sandbox`): `test-resources.sh:15` (`mem_limit: "6g"`), `:16`
(`memswap_limit: "6g"`), `:28` (`capped at 6g of RAM with no swap`);
`test-options.sh:32` (`6g` as an invalid `--memory` value); `stub/docker:26`
(comment: what a `mem_limit: "6g"` compose file yields). Allowed survivors of
`AI_SANDBOX_MAX_RUNNING` (`grep -rln AI_SANDBOX_MAX_RUNNING docs`), history and
the uncommitted supervisor spec the brief's note covers:
`docs/superpowers/specs/2026-10-31-sandbox-memory-budget-brief.md`,
`docs/superpowers/specs/2026-10-30-sandbox-supervisor-design.md`,
`docs/superpowers/specs/2026-10-30-sandbox-supervisor-brief.md`.

### B10 — full suite, the brief's gate, on 5dbfe89 after the last edit

    bash tests/ai-sandbox/run-tests.sh 2>&1 | tail -3

→

    76 run, 1 failed

    SOME SUITES FAILED

20 suites, 1097 run, 3 failed; the three failures are exactly the baseline's:
`test-delegate.sh` 54 and 59 (prompt wording; 69 run, 2 failed, as at the
baseline), `test-tools.sh` 39 (SDKMAN, sandbox-only; 76 run, 1 failed, as at
the baseline). Every other suite `0 failed`: account 32, build-caches 151,
capacity 52, create-identity 13, devices 17, display 5, gc 23, helpers 17,
idea 19, identity 17, image 14, knowledge 387, migrate 32, options 27,
plugins 33, resources 47, sdkman 27, shared 39. `ALL SUITES PASSED` is not
printed because of those three pre-existing failures. The same full run was
also made on the task 1 tree (26f797c) and the task 2 tree (8e25987), each with
the same three failures and nothing else, so the suite is green after every
commit in the brief's sense.

### B11 — syntax, on 5dbfe89

    for f in bin/ai/create-ai-sandbox.sh bin/ai/ai-sandbox-lib.sh bin/ai/ai-sandbox bin/ai/ai-sandbox-restart; do bash -n "$f" && echo "bash -n $f: ok"; done

→ four `ok` lines. `command -v shellcheck` → not installed in this sandbox;
no shellcheck baseline or result.

### B12 — needs the user, host

Cannot run here (no Docker daemon in this sandbox). The user runs, on the host,
with a running sandbox whose `docker-compose.yml` says `mem_limit: "6g"`
(`docker ps --format '{{.Names}}'` lists it):

    docker container inspect -f '{{.HostConfig.Memory}}' <running sandbox name>

Expected output: `6442450944` (6 GiB in bytes). Paste the command and its
output here to close B12. A container with no limit prints `0`.

## Acceptance criterion

B1–B11 recorded above with last lines and commits; B12 pending the host run.
`AI_SANDBOX_MAX_RUNNING` appears nowhere under `bin`, `tests`,
`PROJECT_MAP.md` (B9). The refusal of an 8 GB sandbox while two 6 GB
sandboxes run under a budget of 18 is the rule `12 + 8 > 18` proved by B1/B3
(`15 + 6 > 18` refused, `15 + 3 = 18` not) and by `--memory=8` being what the
start scripts read from `.env` (B5/B6, B3's `.env` cases); the exact scenario
on the host is the user's to confirm after step 1 of the brief's "After the
change" list.

## Fix round (review round 1, Arek: `2026-10-31-sandbox-memory-budget-review.md`)

Commit: f0da926 `fix(ai-sandbox): keep a config without a final newline intact, validate the remembered memory`.

### Important: config without a final newline

Regression test first, in `tests/ai-sandbox/test-helpers.sh`: the budget is
seeded with `printf 'AI_SANDBOX_MEMORY_BUDGET_GB=18'` (no newline, no
`DEV_TOOLS_DIR`), a create runs, then `grep -c '^AI_SANDBOX_MEMORY_BUDGET_GB='`
and `grep -c '^DEV_TOOLS_DIR='` must each be 1 and
`ai_sandbox_memory_budget_gb` under that root must print `18`.

Red (5dbfe89 + the tests): `bash tests/ai-sandbox/test-helpers.sh` →
`20 run, 3 failed`: `and gets the source dir on a line of its own`
(expected 1, got 0), `the budget still reads as a whole number` (got
`... AI_SANDBOX_MEMORY_BUDGET_GB is '18DEV_TOOLS_DIR=/home/jlewandowski/dev/public/dev-tools' in <config>, not a whole number of GB.`,
the glued line the review describes), and, as a consequence, the existing
`stale helper refreshed` (the next create was refused for lack of a budget).

Fix: `awk '!/^DEV_TOOLS_DIR=/'` in place of `sed '/^DEV_TOOLS_DIR=/d'` in
the config rewrite of `bin/ai/create-ai-sandbox.sh`.

Green: `bash tests/ai-sandbox/test-helpers.sh` → `20 run, 0 failed`.

### Minor: invalid SANDBOX_MEMORY_GB

Tests first. `tests/ai-sandbox/test-capacity.sh`: `SANDBOX_MEMORY_GB=abc` in
the sandbox's `.env`, 15 GB running: `an invalid SANDBOX_MEMORY_GB counts as
6 GB` (refused), `the invalid size is named with its file`
(`SANDBOX_MEMORY_GB is 'abc' in <dir>/.env, not a whole number of GB; counting
6 GB.`), `and the refusal counts 6 GB`, `no arithmetic error on an invalid
size`. `tests/ai-sandbox/test-options.sh`: the same value in `.env`, a bare
create: `an invalid remembered size falls back to 6`, `and is named with its
file` (the same line), `an invalid size is not reported as kept`.

Red: `bash tests/ai-sandbox/test-capacity.sh` → `56 run, 2 failed` (the two
message cases; the start was not an arithmetic error but worse: `$((used + gb))`
with `gb=abc` evaluates to 0, so the sandbox started over budget silently);
`bash tests/ai-sandbox/test-options.sh` → `30 run, 1 failed` (`and is named
with its file`).

Fix: one rule in the lib, `ai_sandbox_whole_gb <value>`, used by
`ai_sandbox_memory_budget_gb`, by `ai_sandbox_memory_gb` (a present but
invalid value warns once on stderr naming the `.env` and counts 6) and by
create's `--memory` validation (moved below the lib source, where the rule is
available); create's remembered read now calls `ai_sandbox_memory_gb` instead
of its own copy, logs `keeping` only when the stored value is what was
returned, and reads the `.env` only when it exists (a fresh sandbox has none,
and `ai_sandbox_env_value`'s pipeline fails under `set -eo pipefail`).

Green: `bash tests/ai-sandbox/test-capacity.sh` → `56 run, 0 failed`;
`bash tests/ai-sandbox/test-options.sh` → `30 run, 0 failed`;
`bash tests/ai-sandbox/test-resources.sh` → `47 run, 0 failed`.

### Checks after the last edit (tree of f0da926)

- `bash -n` on `bin/ai/create-ai-sandbox.sh`, `bin/ai/ai-sandbox-lib.sh`,
  `bin/ai/ai-sandbox`, `bin/ai/ai-sandbox-restart` → ok (B11); shellcheck still
  not installed.
- Gate (B10): `bash tests/ai-sandbox/run-tests.sh 2>&1 | tail -3` →
  `76 run, 1 failed` / `SOME SUITES FAILED`; 20 suites, 1107 run, 3 failed,
  exactly the baseline's test-delegate 54 and 59 and test-tools 39; every
  other suite 0 failed (capacity 56, helpers 20, options 30, resources 47,
  the rest as before).
- B1–B8 re-run on this tree are the four suite runs above (B1–B4 capacity 56/0,
  B5/B7 resources 47/0, B6 options 30/0, B8 helpers 20/0). B9 unaffected
  (no new literals; `grep -rn 'AI_SANDBOX_MAX_RUNNING\|mem_limit_gb' bin tests
  PROJECT_MAP.md README.md` still empty). B12 still awaits the host.
