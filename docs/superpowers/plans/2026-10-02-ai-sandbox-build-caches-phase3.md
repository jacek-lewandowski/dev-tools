# Phase 3 plan: build caches -- rm, gc, doctor, tool notes, help

Date: 2026-10-02. Phase planner, from the spec and the phase 3 brief.
Spec: [2026-10-02-ai-sandbox-build-caches-design.md](../specs/2026-10-02-ai-sandbox-build-caches-design.md).
Brief: [2026-10-02-ai-sandbox-build-caches-phase3-brief.md](2026-10-02-ai-sandbox-build-caches-phase3-brief.md).
This plan details the approach only; no spec change. All assumptions it rests
on are the spec's, already verified (see "Assumptions" below).

## Contracts used (none new)

Phase 3 adds no lib function and changes no signature. It reads the phase 2
table (`ai_sandbox_build_caches`: rows `gradle-caches`, `gradle-wrapper-dists`,
`m2-repository`, each `<key>|<path under $HOME>`) and the on-disk layout
`build-caches/<key>/{upper,work}` and `build-caches/.trash/` under each sandbox
directory. `ai_sandbox_caches_check`/`_repair` keep their signatures and return
codes; A4 changes only which process sees which stderr message.

## Groups and write ownership

- **Group A** -- `bin/ai/create-ai-sandbox.sh`, `bin/ai/ai-sandbox-lib.sh`
  (one line), `bin/ai/ai-sandbox-rm`, `tests/ai-sandbox/test-build-caches.sh`.
  One implementer, tasks A1-A5 in order (`test-build-caches.sh` is appended to
  sequentially, `Task 16` through `Task 20`, following the file's existing
  convention).
- **Group B** -- `bin/ai/ai-sandbox-gc`, `tests/ai-sandbox/test-gc.sh`. One
  implementer, independent of Group A.
- **Group C** -- `PROJECT_MAP.md`. One implementer, independent of A and B.

Groups A, B and C can run in parallel (disjoint files). Within Group A, tasks
are sequential (shared test file). After all three groups close, run the whole
suite once.

## Group A -- create-ai-sandbox.sh, ai-sandbox-rm

**A1. Tool notes.** In `SANDBOX_BLOCK`'s "Environment notes" list, the
sentence "The only other host paths mounted are the ... IntelliJ IDEA and
SDKMAN (read-only, when present)." gains a clause naming the host's Gradle and
Maven caches as overlaid: read-only underneath, writes kept in the sandbox
until its next start. Keep the substring `The only other host paths mounted
are the` intact (`test-devices.sh` asserts it literally). Separately, add one
unconditional bullet to `TOOL_NOTES` (shown to every sandbox regardless of the
stamp, since the block is rendered once and shared): `./gradlew --offline`
works for what the host has downloaded and the network stays available;
writes are discarded at the next container start; the host's
`gradle.properties`, `init.d` and Maven settings are absent; if
`sandbox-doctor` reports the caches as not mounted, ask the user to re-run
`create-ai-sandbox.sh` on the host.
Test first: extend `test-build-caches.sh` (`Task 16`) -- render the rules
block into the fake `$HOME/.gemini/GEMINI.md` (as `test-devices.sh` already
does) and assert it still contains `The only other host paths mounted are the`,
now also names `Gradle` and `Maven`, and contains the bullet's distinctive
phrases (`--offline`, `discarded`, `gradle.properties`, `sandbox-doctor`).
Run: `bash tests/ai-sandbox/test-build-caches.sh && bash tests/ai-sandbox/test-devices.sh`.
Acceptance: both green.

**A2. `sandbox-doctor`: one row per cache mount.** In the `DOCTOR_EOF`
heredoc, add one `status` row per key from `ai_sandbox_build_caches`, using
`findmnt -no FSTYPE "$HOME/<path>"` as the existing IDE-index check does:
`overlay` with the note that writes are discarded at the next start, or
`not mounted -- re-run create-ai-sandbox.sh on the host` (spec's exact
wording). Note in the commit/PR: this changes the image build hash, so the
shared image rebuilds once on the next start of any sandbox.
Test first: `test-build-caches.sh Task 17` -- the generated
`$AI_SANDBOX_ROOT/image/build/sandbox-doctor` contains the three row labels
and both wordings (`overlay`, `not mounted -- re-run create-ai-sandbox.sh`).
Acceptance: `bash tests/ai-sandbox/test-build-caches.sh` and
`bash tests/ai-sandbox/test-image.sh` (hash logic is generic, unaffected)
green.

**A3. `usage()`.** Add a "Build caches" paragraph next to the SDKMAN one, and
`build-caches/` in the "Layout under ~/.ai-sandbox" list.
Test first: `test-build-caches.sh Task 18` -- `--help` output contains a
"Build caches" paragraph and `build-caches/`.
Acceptance: `bash tests/ai-sandbox/test-build-caches.sh` green.

**A4. D2 message fix (user's decision, 2026-10-02).** At the
`create-ai-sandbox.sh` call site
(`if ! ai_sandbox_caches_check ...; then ai_sandbox_caches_repair ...; fi`),
the check's own stderr message ("If it is running, run: ai-sandbox-stop /
Then run: create-ai-sandbox.sh ...") must not reach this script's output -- it
is misleading here, since this script is already past I10 and is about to
repair the volume itself. Suppress it only at this call site and let the
repair step say, per volume, that it is repairing/recreating it.
`ai_sandbox_caches_check`/`_repair` keep their signatures and return codes;
`ai-sandbox` and `ai-sandbox-restart` must still show the original check
message verbatim. Design work: the repair line's exact wording is the
implementer's choice.
Test first: `test-build-caches.sh Task 19` -- extend the existing
differing-volume start test (current `Task 8` section) so that
`create-ai-sandbox.sh`'s own stdout+stderr does NOT contain `ai-sandbox-stop`
but does name the differing volume together with a repair/recreate word; the
existing `ai-sandbox`/`ai-sandbox-restart` refusal tests (`Task 9`) are
unchanged (still show `ai-sandbox-stop` and `create-ai-sandbox.sh`).
Acceptance: `bash tests/ai-sandbox/test-build-caches.sh` green, no regression
in `Task 8`/`Task 9`.

**A5. `ai-sandbox-rm`: report instead of aborting.** Today
`rm -rf "$AI_SANDBOX_DIR"` runs under `set -euo pipefail`, so a root-owned
leftover (left by the container user's sudo, spec assumption A4) aborts the
script before its final messages. Instead: attempt the removal, and if
anything remains, list it and print the `sudo rm -rf <path>` command to
finish, rather than failing mid-way. The final message also states,
unconditionally, that the host's Gradle and Maven caches were not touched.
Design work: exit 0 or non-zero when something remains is the implementer's
choice (see "Spec questions"); the test asserts on output text, not exit code.
Test first: `test-build-caches.sh Task 20` -- same chmod-000-leftover fixture
style as the reset test (skip under root, `id -u = 0`): `ai-sandbox-rm` with
`y` on stdin against a sandbox whose `build-caches/` holds an undeletable
entry names the leftover path and `sudo rm -rf`, and still prints that shared
assets and the host's caches were left untouched. Keep the existing
happy-path case: `y` on stdin with no leftovers logs `down -v` and removes the
directory.
Acceptance: `bash tests/ai-sandbox/test-build-caches.sh` green.

## Group B -- ai-sandbox-gc

**B1. List and remove trash leftovers.** `ai-sandbox-gc` gains a third
category, alongside "Duplicated directories" and "Shared stores no sandbox
mounts any more": every `*/build-caches/.trash/*` entry under
`$AI_SANDBOX_ROOT/*-agent`, listed with size like the other categories, then
removed after the existing confirmation (or `--yes`), naming `sudo rm -rf`
for any entry plain removal cannot delete (same leftover scenario as A5 and
as the spec's D4 reset). Orphan volumes are not collected (D8; unchanged).
The "Nothing to reclaim." branch must also require no trash entries, and the
confirmation prompt's wording should account for them.
Test first, in `tests/ai-sandbox/test-gc.sh`: seed one `build-caches/.trash/x`
directory with a file under an existing sandbox fixture; `ai-sandbox-gc` with
no args lists it; `--yes` removes it; a second run with nothing left reports
"Nothing to reclaim."; a chmod-000 leftover inside the trash entry (skip under
root) is reported with `sudo rm -rf` rather than aborting the whole gc run.
Run: `bash tests/ai-sandbox/test-gc.sh`.
Acceptance: green, including the pre-existing assertions in that file
(duplicates, stale stores, kept stores, legacy images) unchanged.

## Group C -- PROJECT_MAP.md

**C1. One clause each** on the `create-ai-sandbox.sh`, `ai-sandbox-lib.sh` and
`ai-sandbox-gc` rows, naming the host build-cache overlays / their reclaim in
gc. No test; acceptance is a human read: the clauses are accurate against the
Group A/B diffs and stay within the existing one-to-two-sentence-per-row
style.

## Final verification (after A, B, C all close)

Run the whole suite: `bash tests/ai-sandbox/run-tests.sh`. Acceptance: every
suite green except `test-tools.sh` case 23 (pre-existing, `~/.sdkman` on
`PATH` inside a sandbox -- not this phase's to fix). No marker of the phase
(no "TODO", no stray debug output) left in any touched file.

## Spec questions

- The spec does not state whether `ai-sandbox-rm` should exit non-zero when a
  leftover remains after its confirmed removal. Left to the implementer (A5);
  flagging since a later phase or a user script that checks `ai-sandbox-rm`'s
  exit code could be surprised either way.
- `ai-sandbox-gc`'s existing confirmation prompt text ("Remove the duplicates,
  stale stores and images listed above...") does not mention trash leftovers;
  D8 only says they must be listed and removable. Updating the prompt wording
  to include them is assumed, not specified.
- D8 names three `PROJECT_MAP.md` rows to update; it does not say whether the
  combined `ai-sandbox-stop/-restart/-attach/-rm` row also needs a clause for
  `ai-sandbox-rm`'s new leftover-reporting behaviour. Left out per D8's literal
  list; low risk either way.

## Assumptions

All verified in the spec's table; phase 3 adds none. A4 (plain `rm -rf` works
in the ordinary case; sudo-owned leftovers are the untested case) bears only
on the wording of A5's and B1's messages, as the phase 3 brief already notes.

## Deferred list

Empty before this phase; nothing surfaced here to add. Cap ten, unaffected.

## Phase 4 request (deliverable; no implementer action -- text only)

The exact host commands for the spec's phase 4, to send the user in one
batch, modeled on phase 1's request. `P` must be a git repository with a
committed `./gradlew`, built on this host before; ideally the same project
used in phase 1's run so the offline build is already known to need no
network. A copy with a non-ASCII file name (A6) is a bonus check of the locale
fix (8d724a1), not a requirement.

```bash
P="$HOME/dev/CHANGE-ME"   # git repo with ./gradlew, built on this host before
T="assemble"              # Gradle task to run offline
set -u
LOG="$HOME/build-caches-acceptance.log"
{
echo "== 1 create-ai-sandbox.sh refuses while the sandbox runs"
( cd "$P" && ai-sandbox true ) || true   # ensure the sandbox exists and is up
create-ai-sandbox.sh "$P" 2>&1; echo "exit=$? (expect non-zero, naming ai-sandbox-stop)"
echo "== 2 stop, then accepted"
( cd "$P" && ai-sandbox-stop )
create-ai-sandbox.sh "$P"; echo "exit=$? (expect 0)"
echo "== 3 sandbox-doctor shows three overlay rows"
( cd "$P" && ai-sandbox sandbox-doctor ) | grep -i -E 'gradle-caches|gradle-wrapper-dists|m2-repository|overlay'
echo "== 4 offline build"
( cd "$P" && ai-sandbox "cd '$P' && ./gradlew --offline --no-daemon $T" ); echo "gradle exit=$?"
echo "== 5 probe survives entry and a stopped container's reset; gone after restart and after stop+start"
( cd "$P" && ai-sandbox "echo probe > \$HOME/.gradle/caches/sandbox-probe-check" )
( cd "$P" && ai-sandbox "test -f \$HOME/.gradle/caches/sandbox-probe-check && echo PROBE_SURVIVES_ENTRY" )
( cd "$P" && ai-sandbox-restart )
( cd "$P" && ai-sandbox "test -f \$HOME/.gradle/caches/sandbox-probe-check || echo PROBE_GONE_AFTER_RESTART" )
( cd "$P" && ai-sandbox "echo probe > \$HOME/.gradle/caches/sandbox-probe-check" )
( cd "$P" && ai-sandbox-stop )
touch "$HOME/.build-caches-mark"; sleep 1
( cd "$P" && ai-sandbox "test -f \$HOME/.gradle/caches/sandbox-probe-check || echo PROBE_GONE_AFTER_STOP_START" )
echo "== 6 host directories unchanged since the mark"
find "$HOME/.gradle/caches" "$HOME/.gradle/wrapper/dists" "$HOME/.m2/repository" \
     -cnewer "$HOME/.build-caches-mark" | head -20
echo "(expect nothing printed above)"
rm -f "$HOME/.build-caches-mark"
echo "== 7 ai-sandbox-rm leaves nothing behind, on a throwaway project"
TP="$HOME/dev/build-caches-throwaway-$$"; mkdir -p "$TP" && git -C "$TP" init -q
create-ai-sandbox.sh --display=none "$TP"
( cd "$TP" && yes y | ai-sandbox-rm )
[ -d "$HOME/.ai-sandbox"/*"$(basename "$TP")"*-agent ] 2>/dev/null \
    && echo "LEFTOVER DIRECTORY REMAINS" || echo "throwaway sandbox directory gone: ok"
rm -rf "$TP"
} 2>&1 | tee "$LOG"
```

Paste back the whole of `~/build-caches-acceptance.log`.
