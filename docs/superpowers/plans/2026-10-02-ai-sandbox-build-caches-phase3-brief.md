# Phase 3 brief: build caches -- rm, gc, doctor, tool notes, help

Date: 2026-10-02. Written by the spec author for a fresh phase planner.
Spec: [docs/superpowers/specs/2026-10-02-ai-sandbox-build-caches-design.md](../specs/2026-10-02-ai-sandbox-build-caches-design.md).
The spec is approved. Its invariants (I1-I10), decisions (D1-D9) and contracts
are fixed. This plan covers the spec's phase 3 block, with D8 as its design.
The plan goes to
`docs/superpowers/plans/2026-10-02-ai-sandbox-build-caches-phase3.md`.

## State of the tree

Phase 2 is committed (613078c, plan in eebea2b). The whole suite
(`bash tests/ai-sandbox/run-tests.sh`) passes at that commit except
`test-tools.sh` case 23, which is known to fail inside a sandbox (`~/.sdkman`
on `PATH`) and is not this phase's to fix.

Landed in phase 2, and to be used as they are, not re-planned:
- The lib functions under the spec's "Contracts" (`bin/ai/ai-sandbox-lib.sh`).
- The layout `<sandbox dir>/build-caches/{.lock,.trash/,<key>/{upper,work}}`.
- The `.env` stamp `SANDBOX_BUILD_CACHES=1`.
- `ai_sandbox_caches_reset` already prints a `sudo rm -rf <path>` hint when it
  cannot delete a trashed layer. Phase 3 adds collection, not that warning.
- The stub `docker` (`tests/ai-sandbox/stub/docker`) gained
  `DOCKER_STUB_VOLUMES`, `DOCKER_STUB_VOLUME_TYPE`/`_DEVICE`/`_NULL_OPTIONS`,
  `DOCKER_STUB_RUNNING_FROM_CALL`, and tracking of `compose stop`/`start`/`down`.
  Reuse it; extend it only where a test needs it.

## Tasks to plan (spec D8)

1. **Tool notes, the sentence phase 2 left false.** In
   `bin/ai/create-ai-sandbox.sh`, the `SANDBOX_BLOCK` "Environment notes" list
   has this sentence:
   "The only other host paths mounted are the shared AI rules file, the
   Antigravity brain and conversations, this project's Claude Code history and
   memory, and ~/.gitignore (read-write), plus the dev-tools helpers, IntelliJ
   IDEA and SDKMAN (read-only, when present)."
   It must also name the host's Gradle and Maven caches, overlaid: read-only
   underneath, with writes kept in the sandbox until its next start.
   `tests/ai-sandbox/test-devices.sh` asserts the substring
   `The only other host paths mounted are the`. Keep that substring or update
   the assertion deliberately.
2. **Tool notes, the Gradle bullet.** Add one unconditional bullet to
   `TOOL_NOTES`. It says:
   - `./gradlew --offline` works for what the host has downloaded, and the
     network stays available;
   - writes are discarded at the next container start;
   - the host's `gradle.properties`, `init.d` and Maven settings are absent;
   - if `sandbox-doctor` reports the caches as not mounted, ask the user to
     re-run `create-ai-sandbox.sh` on the host.

   The block is shared by every sandbox through the rendered rules, so
   sandboxes not yet re-created read it too.
3. **`sandbox-doctor`** (the `DOCTOR_EOF` heredoc): one row per cache mount,
   using `findmnt` as the doctor already does. Either `overlay` with the note
   that writes are discarded at the next start, or
   `not mounted -- re-run create-ai-sandbox.sh on the host`. The doctor is baked
   into the shared image, so this changes the build hash and rebuilds the image
   once; say so in the plan.
4. **`usage()`:** a "Build caches" paragraph next to the SDKMAN one, and
   `build-caches/` in the "Layout under ~/.ai-sandbox" list. Update the
   `ai-sandbox-gc` line if its scope grows.
5. **`bin/ai/ai-sandbox-rm`:** `compose down -v` already removes the volumes
   (verified on the host in phase 2, Run 4). Today `rm -rf "$AI_SANDBOX_DIR"`
   under `set -e` aborts mid-way if something root-owned is left. Instead it
   reports what remains, with the `sudo rm -rf` command to finish. The final
   message also says the host's caches were not touched.
6. **`bin/ai/ai-sandbox-gc`:** list `*/build-caches/.trash/*` as reclaimable,
   remove them after the existing confirmation (or `--yes`), and name
   `sudo rm -rf` for any that plain removal cannot delete. The "Nothing to
   reclaim." path must account for them. Orphan volumes are not collected (D8).
7. **`PROJECT_MAP.md`:** the `create-ai-sandbox.sh`, `ai-sandbox-lib.sh` and
   `ai-sandbox-gc` rows mention the build caches, one clause each.
8. **Phase 4 request.** Write the exact host commands for the spec's phase 4,
   batched into one request with what to paste back. The locale fix is landed
   (8d724a1), so the offline build may use a project with non-ASCII file names.
   This is text in the plan, not code.

## Tests

- `tests/ai-sandbox/test-gc.sh`: trash entries listed, removed with `--yes`,
  and "Nothing to reclaim." when there are none. Run with
  `bash tests/ai-sandbox/test-gc.sh`.
- `tests/ai-sandbox/test-build-caches.sh`, extended:
  - the rendered rules block (`$HOME/.gemini/GEMINI.md` with knowledge
    unconfigured) contains the Gradle bullet, and the mounted-paths sentence
    names the caches;
  - `--help` shows the paragraph and `build-caches/`;
  - the generated `sandbox-doctor` contains the three rows;
  - `ai-sandbox-rm` given `y` on stdin logs `down -v` and removes the sandbox
    directory.

  Run with `bash tests/ai-sandbox/test-build-caches.sh`.
- Then the whole suite. Acceptance is every suite passing except
  `test-tools.sh` case 23.

## Assumptions

All verified (spec table). A4 says plain removal works in the ordinary case;
the sudo hint is for root-owned entries left by the container user's sudo,
which phase 1 did not exercise.

## Out of scope

- Any change to the start paths, the lib's contracts or the compose shape.
- Collecting orphan volumes.
- `ai-sandbox-migrate`.

## Deferred list

Empty. Add only what meets the spec's rule.

## Added by the user's decision (2026-10-02)

- In `create-ai-sandbox.sh`, an options mismatch currently prints the check's
  message ("If it is running, run: ai-sandbox-stop / Then run:
  create-ai-sandbox.sh ...") just before the script repairs the volume
  itself. There, print instead that the named volume is being repaired
  (the check's user-facing message stays as is for `ai-sandbox` and
  `ai-sandbox-restart`). Covered by a test.
- The spec's wording updates after phase 2 are approved.
