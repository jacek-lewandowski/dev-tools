# Evidence: the sandbox uses the host's timezone (small change, 2026-10-31)

Implementer: Stasiek (implementer 3). Instruction: the lead's message (no
brief). Base: f0da926. Commit: 7f75ba2 `feat(ai-sandbox): sandbox uses the host's
timezone`. Files: `bin/ai/create-ai-sandbox.sh`, `tests/ai-sandbox/test-resources.sh`.

## Facts checked in the tree (f0da926)

- No timezone was passed before: `grep -n 'TZ\|localtime\|timedatectl\|timezone' bin/ai/create-ai-sandbox.sh tests/ai-sandbox/*.sh` → only the `date -u` of the doctor (line 1471).
- Environment and volume entries of the compose file are added through `add_env`/`add_vol` (lines 654–655, used by the display and audio sections); the image's first apt-get list is at line 1865–1867; the rules block's "Environment notes" at 1039; the "Ready" summary at 2786–2798, printed only after a build and start.
- This test host (a sandbox) has no `/etc/localtime`, no `/etc/timezone`, no `/usr/share/zoneinfo`, and `timedatectl` without systemd, so the tests fake every source: a `timedatectl` stub on PATH (the harness's existing PATH-stub style) and `HOST_ETC_DIR`, a new override of `/etc` in the `IDEA_HOST_DIR` pattern, pointed at a fake directory.

## Regression tests first: `bash tests/ai-sandbox/test-resources.sh`

Cases added (timezone section): `TZ follows timedatectl`, `the host's zoneinfo
file is mounted read-only, symlink resolved`, `the shared brain states the
zone`, `the image installs tzdata`, `the log names the zone and the file`,
`the zone is not remembered in .env`, `TZ falls back to /etc/timezone`
(timedatectl exits 1), `TZ falls back to the localtime symlink` (timedatectl
prints an empty line, no /etc/timezone, symlink to
/usr/share/zoneinfo/Asia/Tokyo), `a dangling localtime is not mounted`, `and
the skipped mount is warned about`, `no source means UTC`, `and a warning
about the zone`, `nothing is mounted at /etc/localtime`.

Red: the committed test run against f0da926 (the reviewer, in a scratch
worktree): `60 run, 10 failed`, cases 32–36, 38, 39, 41–43 for the guarded
reasons (no TZ entry, no mount, no rules line, no tzdata, no log line, no
fallbacks, no warnings); 37, 40 and 44 hold trivially on the old tree (no
`TZ` in `.env`, nothing mounted). My own red run before the change was of a
first draft of the test (`61 run, 11 failed`) whose two expectations were then
aligned to the tree's conventions without changing substance: `add_env` emits
unquoted entries (`- TZ=Europe/Warsaw`, like `- DISPLAY=:99`), and the "Ready"
summary is not printed by a `--no-start` run, so the test asserts the timezone
step's log line instead; the summary's Timezone line is therefore only seen
on the host (see "Look at the result").

Green (after the change): `60 run, 0 failed`.

## Checks after the last edit (tree of 7f75ba2)

- `bash -n bin/ai/create-ai-sandbox.sh` → ok.
- Touched suite: `bash tests/ai-sandbox/test-resources.sh` → `60 run, 0 failed`.
- Full gate: `bash tests/ai-sandbox/run-tests.sh` → 20 suites, 1120 run,
  3 failed, exactly the known pre-existing test-delegate 54 and 59 and
  test-tools 39; every other suite 0 failed (resources 60, the rest as before).

## Diff: only the intended parts

`git diff --stat f0da926..7f75ba2` → `bin/ai/create-ai-sandbox.sh | 42 +-`,
`tests/ai-sandbox/test-resources.sh | 55 +`. In the script: the `HOST_ETC_DIR`
constant beside `IDEA_HOST_DIR`; the "Timezone" section after "Audio"
(detection chain, `add_env "TZ=..."`, resolved `add_vol` of the zoneinfo file
or a warning); one rules-text line under "Environment notes"; `tzdata` in the
first apt-get list; two summary lines at 7f75ba2, one after the fix round below (the second claimed a `--rebuild` was needed, which is wrong: see "Fix round"). Nothing else.

## Look at the result (this host, no timezone sources)

A `--display=none --no-start` create in a fake home, with the real sources of
this sandbox host (none present):

    !! Could not determine the host's timezone (timedatectl, /etc/timezone, /etc/localtime); the sandbox uses UTC.
    !! No zoneinfo file behind /etc/localtime: /etc/localtime is not mounted, the sandbox relies on TZ=UTC alone.

docker-compose.yml: `- TZ=UTC` under `environment:`, no `/etc/localtime`
mount; Dockerfile line 24: `curl wget gnupg ca-certificates tzdata \`;
`~/.gemini/GEMINI.md` line 59: `- The sandbox uses the host's timezone
(TZ=UTC); \`date\` agrees with the host.`; `.env` has no `TZ` line. The
named-zone and mounted paths are what the test cases above exercise with the
fakes (`TZ=Europe/Warsaw`, `<zoneinfo file>:/etc/localtime:ro`).

## On the host (user)

1. Re-run `create-ai-sandbox.sh <project>` for each sandbox: the compose file
   gains `TZ=<zone>` and the `/etc/localtime` mount at once.
2. That next create rebuilds the shared image by itself, because the build
   hash changes: `BUILD_HASH` is `ai_sandbox_build_hash` over the build
   directory, the regenerated Dockerfile with `tzdata` included, and
   `need_build` is set when it differs from the image stamp (create lines
   2757–2767 at 7f75ba2). No `--rebuild` is needed; `date +%Z` in the sandbox
   shows the host's zone abbreviation after that rebuild.
3. Expected on the host: `timedatectl show -p Timezone --value` prints the
   zone (e.g. `Europe/Warsaw`), and the create log line reads
   `Timezone: <zone> (TZ), zoneinfo mounted read-only from /usr/share/zoneinfo/<zone>`.

## Fix round (review of 7f75ba2, one Important finding)

Finding: the summary's note that an image built before tzdata needs one
`--rebuild` is wrong. Confirmed in the tree: `BUILD_HASH=$(ai_sandbox_build_hash
"$BUILD_DIR" ...)` (create 2757–2758 at 7f75ba2) hashes the build directory,
the regenerated Dockerfile included, and `need_build` becomes `yes` when it
differs from `IMAGE_STAMP` (2765–2766), so the first create after this change
rebuilds the image by itself; `--rebuild` would only add `--no-cache`, and the
note would have printed on every create forever.

Commit: dbcef3a `fix(ai-sandbox): drop the --rebuild note, the build hash already
triggers the rebuild`. Change: the second Timezone summary line removed; the
first is now `$TZ_SUMMARY`, set in the Timezone section to
`<zone> (the host's, by TZ and /etc/localtime)` when the zoneinfo file was
mounted and `<zone> (the host's, by TZ)` when the mount was skipped. No test
asserted the removed line (the summary is not printed by `--no-start`); the
test comment that mentioned the `--rebuild` note was corrected. The "On the
host" step 2 and the red-run figure above were corrected as the lead asked.

Checks after the last edit (tree of dbcef3a): `bash -n bin/ai/create-ai-sandbox.sh`
→ ok; `bash tests/ai-sandbox/test-resources.sh` → `60 run, 0 failed`; full
gate `bash tests/ai-sandbox/run-tests.sh` → 20 suites, 1120 run, 3 failed,
exactly the known test-delegate 54 and 59 and test-tools 39, every other suite
0 failed.
