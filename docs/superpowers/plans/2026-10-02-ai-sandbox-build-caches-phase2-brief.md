# Phase 2 brief: build-cache overlay volumes and the reset on start

Date: 2026-10-02. Written by the spec author for a fresh phase planner.
Spec: [docs/superpowers/specs/2026-10-02-ai-sandbox-build-caches-design.md](../specs/2026-10-02-ai-sandbox-build-caches-design.md).
The spec is approved. Its goals, invariants (I1-I10), decisions (D1-D9) and
contracts are fixed. The phase 2 block in its "Phases" section is the goal and
the test list for this plan.

## What to plan

The spec's phase 2, and only that. Phase 3 owns `ai-sandbox-rm`,
`ai-sandbox-gc`, `sandbox-doctor`, the tool notes, `usage()` and
`PROJECT_MAP.md`. Leave them alone, except where a phase 2 change would make
their current text false; name any such spot in the plan. The plan goes to
`docs/superpowers/plans/2026-10-02-ai-sandbox-build-caches-phase2.md`.

## State after phase 1

Phase 1 (host smoke test) is closed. Every assumption the phase rests on is
verified (see the spec's assumption table): overlay volumes mount and unmount
with the container (A1, A2), lowers can be shared (A3), host-user ownership and
removal work (A4), the filesystem fits (A5), wrapper and dependencies resolve
offline (A6), volume removal is refused while a stopped container holds the
volume (A14), and the parents of in-container mount points come out root-owned
unless the image creates them (A9, so D6 is required). No spike is needed.

Out of scope: the image's missing `LANG` broke one host build on a non-ASCII
file name. It is a separate task
(`docs/superpowers/specs/2026-10-02-ai-sandbox-locale-brief.md`), not part of
this phase. Do not fold it in. That task edits `bin/ai/create-ai-sandbox.sh`
and `tests/ai-sandbox/test-image.sh`; both were uncommitted when this brief was
written. Plan against the tree after it has landed, so the two changes do not
conflict in the Dockerfile block.

## Where the work lands (verified in the tree)

- `bin/ai/ai-sandbox-lib.sh`: the functions under the spec's "Contracts",
  next to `ai_sandbox_state_dirs` and `ai_sandbox_check_capacity`. Copy their
  names and arguments from the spec exactly.
- `bin/ai/create-ai-sandbox.sh`:
  - the I10 refusal goes early, after the project is resolved and before
    `project-path` and any other write;
  - the D9 path check;
  - the `.env` stamp goes into the managed-key Python block (D7);
  - the volumes go in the compose generator (the `COMPOSE_VOLS` heredocs, plus
    a new top-level `volumes:` section);
  - the directories go into the Dockerfile's home `mkdir -p ... chown -R`
    list (D6);
  - in the start section before `docker compose ... up -d`: check, repair,
    reset under the lock (D2, D5). Keep the capacity check and the image build
    in their current order.
- `bin/ai/ai-sandbox`: the not-running branch, around `ai_sandbox_compose up -d`
  (after `ai_sandbox_require_current` and the capacity check).
- `bin/ai/ai-sandbox-restart`: the check goes before `down`, like
  `ai_sandbox_require_current` (a refusal leaves the sandbox running); the reset
  goes between `down` and `up`.
- `tests/ai-sandbox/stub/docker` and a new `tests/ai-sandbox/test-build-caches.sh`.

## Known traps

- **The stub's running state is fixed.** It answers `container inspect` with
  `DOCKER_STUB_RUNNING` whatever happened before. `test-knowledge.sh` runs
  `ai-sandbox-migrate-knowledge` with `DOCKER_STUB_RUNNING=true`. That script
  runs `compose down` and then `create-ai-sandbox.sh --no-start`, which I10 will
  refuse while the stub still says "running". On a real host the container is
  gone by then. The plan has to deal with this without weakening the
  assertions, for example by having the stub remember a `down` or `stop`. The
  design of that is the planner's choice.
- **The stub has no `volume` command yet.** Today it exits 0 with no output,
  which the check must not read as "the volume exists with empty options". The
  stub has to report a missing volume as missing and return seeded options
  otherwise.
- **Old sandboxes (I8).** Every caches function is a no-op without the stamp.
  The existing suites set up sandboxes without it, and they must pass unchanged.
- **Formatting.** There is no shell formatter configured in this repository.
  Match the surrounding style and do not reformat untouched lines.

## Tests and acceptance

The tests are the spec's phase 2 list. Run them with
`bash tests/ai-sandbox/test-build-caches.sh`, and the whole suite with
`bash tests/ai-sandbox/run-tests.sh`. The whole suite must pass apart from
test-tools case 20, which is known to fail only inside a sandbox; record its
output before the change. Docker cannot run in the sandbox, so the real mounts
are checked by phase 4, not here.

## Deferred list

Empty at the time of writing. Any entry this phase adds must meet the spec's
rules (a failure a user or operator can reach, or a broken invariant).
