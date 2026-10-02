# Phase 2 plan: build-cache overlay volumes and the reset on start

Date: 2026-10-02. Plans only the spec's phase 2
(`docs/superpowers/specs/2026-10-02-ai-sandbox-build-caches-design.md`), per
the phase 2 brief. Approach only; no spec change. Planned against the tree
after the locale task landed (uncommitted `LANG=C.UTF-8` in
`bin/ai/create-ai-sandbox.sh`'s Dockerfile `ENV` block and the matching
assertion in `tests/ai-sandbox/test-image.sh`).

## Contracts (copied verbatim from the spec; binding)

```bash
# ai-sandbox-lib.sh -- table: <key>|<path under $HOME, host and container>
ai_sandbox_build_caches()        # prints the three rows of the table above
ai_sandbox_caches_volume()       # <container name> <key> -> "<container name>-<key>"
ai_sandbox_caches_opts()         # <sandbox dir> <key> <host lower path>
                                 #   -> "lowerdir=<lower>,upperdir=<sandbox dir>/build-caches/<key>/upper,workdir=<sandbox dir>/build-caches/<key>/work"
ai_sandbox_caches_enabled()      # <sandbox dir> -> 0 when .env has SANDBOX_BUILD_CACHES=1
ai_sandbox_caches_prepare()      # <sandbox dir> -> mkdir -p the three lowers and every upper/work; never empties anything
ai_sandbox_caches_check()        # <sandbox dir> <container name> -> 0, or 1 with the D2 message on stderr
ai_sandbox_caches_repair()       # <sandbox dir> <container name> -> D2 repair; precondition: container not running;
                                 #   used only by create-ai-sandbox.sh
ai_sandbox_caches_reset()        # <sandbox dir> -> D4; caller holds the lock and has seen the container not running
```
Every function except the first three is a no-op returning 0 when
`ai_sandbox_caches_enabled` is false (I8).

Compose shape and on-disk layout: exactly as in the spec's "Contracts"
section (three `volumes:` entries named `<container>-<key>`, `driver: local`,
`driver_opts` per `ai_sandbox_caches_opts`; `<sandbox dir>/build-caches/{.lock,.trash,<key>/{upper,work}}`).

## Baseline (verified: `bash tests/ai-sandbox/run-tests.sh`, this run)

Every suite passes except `test-tools.sh` case 23 ("a candidate without a
default is skipped"), which fails here because the real `~/.sdkman` leaks
onto `PATH` — see Spec questions for the discrepancy with the spec's text.

## Tasks

Every task's new assertions live in one new file,
`tests/ai-sandbox/test-build-caches.sh`, run with
`bash tests/ai-sandbox/test-build-caches.sh`. Default acceptance for every
task below is "these new assertions pass, and nothing already in that file
regresses"; only a different or additional acceptance is stated per task.

**1. Docker stub: volume inspect and real stop/start state.**
Files: `tests/ai-sandbox/stub/docker`. Design work, needed before tasks 3, 8
and 9, and to resolve a known trap: `test-knowledge.sh`'s migrate scenarios
set `DOCKER_STUB_RUNNING=true` for a whole test, then run `compose down`
followed by `create-ai-sandbox.sh --no-start`; once task 5 adds the I10
refusal, that second call must see the container as stopped.
Add: (a) `docker volume inspect <name>` answers "missing" (exit 1) unless
seeded, otherwise exposes its stored options so a caller can diff them
against `caches_opts`; the stub's inspect output should mimic the real
shape confirmed on the host (phase 1 smoke test, Run 4, in
`build-caches-phase1-logs.md`): `.Options` is `{"device":"overlay","o":"lowerdir=...,upperdir=...,workdir=...","type":"overlay"}`,
alongside a `.Labels` object carrying compose's own
`com.docker.compose.*` keys that the lib function must ignore. Define the
seeding mechanism (an env var, like `DOCKER_STUB_IMAGES`). (b) A state file
next to `DOCKER_STUB_LOG` (so it
resets with every `fake_home`) records names stopped by `compose
down`/`stop`/`rm`; `container inspect` reports "false" for a recorded name
regardless of `DOCKER_STUB_RUNNING`, and `compose up`/`start` clears it.
Tests: seeded options round-trip through `volume inspect`; an unseeded name
reads as missing; a stubbed `compose down` then `container inspect` reports
not-running. Extra acceptance: `test-knowledge.sh` still passes unchanged.

**2. Lib: pure cache functions.**
Files: `bin/ai/ai-sandbox-lib.sh`, next to `ai_sandbox_state_dirs`:
`ai_sandbox_build_caches`, `ai_sandbox_caches_volume`, `ai_sandbox_caches_opts`,
`ai_sandbox_caches_enabled`, `ai_sandbox_caches_prepare` — names and
arguments exactly as the contract.
Tests: the table has exactly the design summary's three rows and paths;
`caches_volume`/`caches_opts` format strings match the contract exactly;
`caches_enabled` is true only with `SANDBOX_BUILD_CACHES=1` in `.env`;
`caches_prepare` creates the three `$HOME` lowers and every `upper`/`work`
idempotently, touching nothing else, and is a no-op (no `build-caches/`) on
a sandbox dir whose `.env` lacks the stamp.

**3. Lib: check and repair (D2).**
Files: `bin/ai/ai-sandbox-lib.sh`. Depends on task 1's stub.
Design work: `ai_sandbox_caches_check` diffs each volume's stored options
(via `docker volume inspect`, reading `.Options.o` out of the real JSON
shape task 1's stub mimics) against `caches_opts`; a missing volume is not
a difference. On a difference it returns 1 with the D2 message: names the
volume, tells the caller to run `ai-sandbox-stop` if running then
`create-ai-sandbox.sh <project>`. `ai_sandbox_caches_repair` assumes the
container is already stopped: `compose down` (no `-v`), `docker volume rm`
of exactly the differing volumes, logging each one removed.
Tests: a matching stubbed volume: check passes, nothing logged; a stubbed
difference: check fails naming the volume and the repair instructions,
repair logs `down` then `volume rm` of exactly that name, nothing else; on
an unstamped sandbox both are no-ops, no volume queries logged.

**4. Lib: reset (D4).**
Files: `bin/ai/ai-sandbox-lib.sh`. No docker needed; filesystem only.
Design work: for each key, rename `build-caches/<key>` to
`build-caches/.trash/<key>-<unique suffix>` (creating `.trash` as needed),
`mkdir -p` a fresh `<key>/upper` and `<key>/work`, then delete the trashed
copy; a failed deletion only warns (phase 3 collects leftovers).
Tests: a probe file placed in `upper` is gone after reset; `upper` and
`work` both exist afterward; a root-owned leftover that cannot be deleted
only warns and reset still returns 0; a no-op on an unstamped sandbox.

**5. create-ai-sandbox.sh: I10 refusal and the D9 path check.**
Files: `bin/ai/create-ai-sandbox.sh`, right after `CONTAINER_NAME` is set
(after line 338), before `mkdir -p "$SANDBOX_DIR"`. If
`ai_sandbox_container_running "$CONTAINER_NAME"`, exit non-zero naming
`ai-sandbox-stop` before writing anything, with or without `--no-start`; if
`$HOME` or `$SANDBOX_DIR` contains `,`, `:`, or whitespace, exit non-zero
with that reason.
Tests: a running container (both with and without `--no-start`) exits
non-zero, names `ai-sandbox-stop`, writes no compose file and no `.env`; a
`,` in a faked `$HOME` is refused before any directory is created. Extra
acceptance: `test-migrate.sh` and `test-knowledge.sh` (stopped containers
already) do not regress.

**6. create-ai-sandbox.sh: Dockerfile D6 and the `.env` stamp D7.**
Files: `bin/ai/create-ai-sandbox.sh`: add `~/.gradle`, `~/.gradle/wrapper`,
`~/.m2` to the Dockerfile tail's `mkdir -p ... chown -R` list (~line 1845);
add `"SANDBOX_BUILD_CACHES": "1"` to the managed `.env` dict (~line 1908),
unconditional (D7).
Tests: Dockerfile text contains the three directories; a fresh sandbox's
`.env` contains `SANDBOX_BUILD_CACHES=1`. Extra acceptance:
`test-image.sh`'s Dockerfile assertions still pass.

**7. create-ai-sandbox.sh: compose volumes.**
Files: `bin/ai/create-ai-sandbox.sh`, inside the `COMPOSE_VOLS` block
(~lines 1996-2018, using task 2's functions) and a new top-level `volumes:`
section appended before the block writing `$COMPOSE_FILE` closes (after line
2080): per-service mounts `<lower under $HOME>:<same path>` for the three
caches, and `volumes:` exactly per the spec's "Compose shape" (name,
`driver: local`, `driver_opts` from `caches_opts`).
Tests: the compose file carries exactly the three volumes with the
contract's options, nothing else under `~/.gradle` or `~/.m2` (no
`gradle.properties`, `init.d`, `settings`).

**8. create-ai-sandbox.sh: start-section wiring.**
Files: `bin/ai/create-ai-sandbox.sh`. Call `ai_sandbox_caches_prepare` where
the other per-sandbox bind sources are created (around line 402), so
`--no-start` gets it too. In "Build and start" (after the `NO_START` early
exit, lines 2405-2451), under a `flock` on `$SANDBOX_DIR/build-caches/.lock`:
`ai_sandbox_caches_check`; on failure `ai_sandbox_caches_repair`;
`ai_sandbox_caches_reset`; then the existing `docker compose ... up -d`.
Keep the capacity check and image build in their current order.
Tests: `--no-start` creates `build-caches/<key>/{upper,work}` with no volume
query; an actual start logs `down` (no `-v`), `volume rm` of exactly a
stubbed differing volume, then `up`.

**9. `ai-sandbox` and `ai-sandbox-restart`: D5 wiring.**
Files: `bin/ai/ai-sandbox` (not-running branch, after
`ai_sandbox_check_capacity`, before `ai_sandbox_compose up -d`),
`bin/ai/ai-sandbox-restart` (check before `down`, like
`ai_sandbox_require_current`; reset under the lock between `down` and `up`).
Both call `ai_sandbox_caches_check`; on failure, exit non-zero naming
`create-ai-sandbox.sh` (never `ai-sandbox-rm`), with no `up`/`down`/`volume
rm` logged; otherwise reset, then proceed. `ai-sandbox` entering a running
container calls neither.
Tests: a stubbed difference makes both exit non-zero naming
`create-ai-sandbox.sh`, logging nothing; a stopped container's `ai-sandbox`
start empties a probe in `upper`; a running one leaves it;
`ai-sandbox-restart` empties it.

**10. Whole-suite verification.** No new files. Run
`bash tests/ai-sandbox/run-tests.sh`. Acceptance: every suite passes except
`test-tools.sh` case 23 (baseline above, not this phase's to fix);
`test-knowledge.sh`'s migrate scenarios (lines ~529-558) still pass with I10
wired in.

## Phase-3-owned text this phase makes false

The tool-notes block in `bin/ai/create-ai-sandbox.sh` (~lines 939-943,
"The only other host paths mounted are ...") stops being complete once task 7
adds the three cache mounts; `tests/ai-sandbox/test-devices.sh` only checks
the sentence's presence, not its completeness, so it will not catch this.
Phase 2 does not edit that sentence — it is phase 3's D8 to update.

## Spec questions

- The spec/brief name "test-tools.sh case 20 ... inside a sandbox" as the
  pre-existing failure; this tree, in this environment, shows case 23
  instead (`~/.sdkman` leaking onto `PATH`), per the Baseline run above. Tree
  wins; this plan's acceptance uses case 23. Not a user decision; flagged so
  the spec's text can be corrected.

## Verified since the first draft

- `docker compose up` creates the overlay volume from a top-level `volumes:`
  block with no extra flag, the container sees an overlay mount, and
  `compose down -v` removes it — **verified**, host run, Run 4 in
  `build-caches-phase1-logs.md` (scratchpad). That run also pins the real
  `docker volume inspect` output shape used in tasks 1 and 3 above: `.Options`
  as `{device, o, type}`, `.Labels` carrying `com.docker.compose.*` keys.

## Unverified assumptions this plan rests on

- Extending the stub's `container inspect` (task 1) changes no existing
  suite's observable behaviour beyond fixing the named trap — checked only
  by the whole-suite run in task 10, not before.
