# 2026-11-09-ai-delegate-read-denied - diff review (Marta, reviewer 3)

Object: small diff, commit a064e70. Evidence: 2026-11-09-ai-delegate-read-denied.md.

## Verdict
Accepted. No Critical or Important finding.

## Checks
- Scope: the only new grant is `read_file(<home>/knowledge)` (bin/ai/create-ai-sandbox.sh, agy grants
  block). No write grant, no wildcard, no `--dangerously-skip-permissions`. The test asserts no
  `write_file` entry and keeps the write-capable command check.
- Home path: `os.path.expanduser("~/knowledge")` reads the same `HOME` the block already uses for the
  settings path (`$HOME/.gemini/...`), and `~/knowledge` is where the compose file mounts the clone
  (`${CONTAINER_HOME}/knowledge`). Works for any user.
- Merge: unchanged `missing`-only append keeps other keys, `deny` and mode; idempotent for a fixed HOME.
- Red before fix: recorded (`not ok 71`, `not ok 72`, 81 run, 2 failed with the old script); green 81/0.
  The live check with the plain directory form and a real ai-delegate run (rc=0) are recorded.
- Comment states why there is no glob (not accepted by agy 1.4.0, plain directory path is).

## Lesser finding (fixed, 7bb3592)
- tests/ai-sandbox/test-tools.sh, "merge is idempotent": the second merge ran under the real HOME, so
  it appended a second, different read_file entry (reproduced: 2 entries) and the idempotency of the
  new grant was never checked. Now re-run with `HOME="$mh"` plus an assertion of one read_file entry.
  `bash tests/ai-sandbox/test-tools.sh`: 82 run, 0 failed.
