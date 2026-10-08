# Task brief: lower the sandboxes' priority on the host

Date: 2026-10-08. Small task, no spec. User request: sandboxes must not be able
to clog the host.

## Problem

The generated docker-compose.yml (`bin/ai/create-ai-sandbox.sh`, around the
`mem_limit` / `cpuset` block) caps memory and pins a cpuset, but inside its
cores a sandbox competes with host processes at equal CPU and I/O priority, the
kernel's OOM killer treats it like any host process, and nothing limits the
number of processes.

## Goal

Every sandbox's compose service also sets:

- `cpu_shares: 256` (default 1024): the host wins CPU under contention; no cap
  when the host is idle.
- `blkio_weight: 100` (default 500): lower disk I/O weight under contention.
  Effective on cgroup v2 only with the BFQ scheduler; say so in the comment and
  in the user-facing notes, do not make the script fail without it.
- `oom_score_adj: 500`: under host-wide memory pressure a sandbox is killed
  before host applications.
- `pids_limit: 4096`: a runaway build or fork bomb cannot exhaust the host's
  process table. Check first that nothing in the sandbox normally needs more
  (e.g. IntelliJ plus a Gradle build); raise the number if the tree suggests
  it and say why.

Each with a one-line "why" comment, matching the surrounding style. If the
script has a status/summary output or `sandbox-doctor` that reports limits,
add the new values there only if that is a one-line change; otherwise leave it.

## Tests

Regression test first in `tests/ai-sandbox/` (the suite that asserts on the
generated compose file): the four keys with these values are present in the
generated service. Run that test file, then `bash tests/ai-sandbox/run-tests.sh`
once (known sandbox-only failure: test-tools.sh case 30).

## Acceptance

- The test fails before and passes after; the full suite shows no new failure.
- The compose file still parses (`docker compose config` if available in the
  sandbox, otherwise a YAML parse with python3).
- Existing sandboxes pick the change up only after `create-ai-sandbox.sh` is
  re-run on the host; that is expected.
- Do not commit; the lead commits after review.
