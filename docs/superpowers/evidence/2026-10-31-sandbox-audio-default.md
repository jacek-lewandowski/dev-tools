# Evidence: host audio on by default (create-ai-sandbox.sh)

Implementer: Stasiek. Instruction-only change, no brief: a sandbox created
without `--audio`/`--no-audio` and with no stored `SANDBOX_WITH_AUDIO` shares
the host's audio; `--no-audio` and a stored `0` keep it off; a stored `1`
keeps it on. Commit: b94975175116d0b9eff504f64f01a72f762fdadb
(`feat(ai-sandbox): host audio on by default`).

## Regression test (red, then green)

Test: `tests/ai-sandbox/test-devices.sh`. The default run now gets a fake
PulseAudio socket under `XDG_RUNTIME_DIR` so the mount can be observed; the
former "opt-in" assertions became default-on / `--no-audio` off / stored 0
stays off / `--audio` back on / stored 1 stays on.

Baseline before any change:

    $ bash tests/ai-sandbox/test-devices.sh 2>&1 | tail -1
    16 run, 0 failed

Red run (test rewritten, script untouched):

    $ bash tests/ai-sandbox/test-devices.sh 2>&1 | grep -E "^(ok|not ok|[0-9]+ run)"
    ok 1 - compose does not mount /dev/bus/usb
    ok 2 - compose has no wildcard rule on the USB major
    ok 3 - the shared brain lists the other host mounts
    ok 4 - the shared brain does not claim USB passthrough
    not ok 5 - no flag and no stored value mounts the pulse socket
    not ok 6 - the default is recorded as on
    not ok 7 - the default advertises capture tools
    not ok 8 - the default log tells how to drop audio
    ok 9 - --no-audio turns it off
    ok 10 - --no-audio is recorded
    ok 11 - --no-audio does not advertise capture tools
    ok 12 - a stored 0 keeps audio off
    ok 13 - --audio turns it back on
    ok 14 - --audio is recorded
    ok 15 - a stored 1 keeps audio on
    ok 16 - both audio flags exit 2
    ok 17 - help documents --audio
    17 run, 4 failed

Green run (after the script change):

    $ bash -n bin/ai/create-ai-sandbox.sh && echo SYNTAX_OK
    SYNTAX_OK
    $ bash tests/ai-sandbox/test-devices.sh 2>&1 | grep -E "^(ok|not ok|[0-9]+ run)"
    ok 1 .. ok 17 (same names as above, all ok)
    17 run, 0 failed

## Full ai-sandbox suite

    $ bash tests/ai-sandbox/run-tests.sh   (rc=1)
    # test-account.sh          32 run, 0 failed
    # test-build-caches.sh    151 run, 0 failed
    # test-capacity.sh         16 run, 0 failed
    # test-create-identity.sh  13 run, 0 failed
    # test-delegate.sh         69 run, 2 failed
        not ok 54 - writer prompt has no-tools line
        not ok 59 - second-reviewer prompt has no-commands line
    # test-devices.sh          17 run, 0 failed
    # test-display.sh           5 run, 0 failed
    # test-gc.sh               23 run, 0 failed
    # test-helpers.sh          12 run, 0 failed
    # test-idea.sh             19 run, 0 failed
    # test-identity.sh         17 run, 0 failed
    # test-image.sh            14 run, 0 failed
    # test-knowledge.sh       387 run, 0 failed
    # test-migrate.sh          32 run, 0 failed
    # test-options.sh          15 run, 0 failed
    # test-plugins.sh          33 run, 0 failed
    # test-resources.sh        34 run, 0 failed
    # test-sdkman.sh           27 run, 0 failed
    # test-shared.sh           39 run, 0 failed
    # test-tools.sh            76 run, 1 failed
        not ok 39 - a candidate without a default is skipped
    SOME SUITES FAILED

Totals: 1031 run, 3 failed, none in the files this task touched.

The three failures are independent of this change:

- `test-delegate.sh` 54 and 59 check prompt text in `bin/ai/ai-delegate`,
  which neither reads nor writes anything audio-related (`grep -ci audio`
  on `bin/ai/ai-delegate`, `tests/ai-sandbox/test-delegate.sh` and
  `tests/ai-sandbox/test-tools.sh` returns 0 for each). Re-run on a clean
  `git worktree add --detach <scratch> HEAD` without my edits:
  `69 run, 2 failed` with the same two cases. Those files were modified in
  the working tree before this task and were committed separately as
  b35a5d4 (`chore(ai-delegate): preflight limit 30 s`).
- `test-tools.sh` 39 (`a candidate without a default is skipped`) is the
  SDKMAN case known to fail only inside a sandbox (`/etc/ai-sandbox-release`
  exists here); recorded in the project memory since 2026-10-17.

## Places changed in `bin/ai/create-ai-sandbox.sh`

- `WITH_AUDIO="yes"` initial value (was `"no"`).
- Usage text of `--audio` ("On by default; ...") and `--no-audio` ("Keep the
  host's sound out of the sandbox. Remembered.").
- Stored-value case: `1` keeps on (unchanged log), `0` keeps off and now logs
  `keeping host audio off (pass --audio to share it)`; no stored value falls
  through to the default `yes`.
- Audio section comment and log lines: shared log says
  `(pass --no-audio to drop it)`; the not-shared log names `--no-audio`; the
  missing-socket warning no longer blames `--audio`.
- No change to what is mounted (`PULSE_SERVER`, the socket volume, `/dev/snd`
  and the ALSA cgroup rule) or when.
