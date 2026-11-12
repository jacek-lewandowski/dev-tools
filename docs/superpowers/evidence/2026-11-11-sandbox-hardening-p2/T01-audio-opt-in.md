Task: 2026-11-11-sandbox-hardening
Class: phase

# T01 audio-opt-in: evidence

Implementer: Wojtek, 2026-11-12. Worktree `.worktrees/2026-11-11-sandbox-hardening-p2`,
branch `2026-11-11-sandbox-hardening-p2`. Code and tests: commit `2b942bd`
(`feat: host audio is off by default in a new sandbox`) and `4dd41ad` (`test: audio request
without a display shares no sound device`: the case pair 83 and 84). The `82 run, 0 failed`
lines below are the run at `2b942bd`; the run after `4dd41ad` is `84 run, 0 failed` (last section). Plan:
`docs/superpowers/plans/2026-11-11-sandbox-hardening-p2-plan.md`. Texts name no daemon
command or module and no security-review input (S-1).

## Base check

`git rev-parse --short HEAD` printed `de1aa6d`; branch `2026-11-11-sandbox-hardening-p2`;
`git status --short` empty; `git diff --quiet dd0146a HEAD -- bin tests tools && echo BASE_OK`
printed `BASE_OK`.

## Red run (tests written first, on the unchanged base code)

`bash tests/ai-sandbox/test-devices.sh` with the new `test-devices.sh` and the base
`create-ai-sandbox.sh`: exit 1, summary `82 run, 42 failed`. Failing cases (by number and
name) include, for O1: 5 no flag and no stored value shares no sound socket, 6 the default is
recorded as off, 7 the default does not advertise capture tools, 8 and 9 the default log; 39,
40, 43 to 46 (a new sandbox with a display: socket mount, server variable, recorded value,
capture tools, output); for O2: 22 to 24 and 49 to 58 (a stored 1 is no request, rewritten as
off, one notice, not repeated), 28 and 29 (unknown stored value); for O3/O4: 11, 13, 16, 17,
27, 64 to 66, 68, 70 to 72 (`--audio` recorded as 2, warning, device directory and rule through
the seam, a kept request); for O5: 35 to 38 (help text); for O7: 47 (`a new sandbox: binds no
host socket but its display's`: the faked sound socket is a bind source on the base). Case 41
(`no sound device mount`) passes on the base only because the test machine has no `/dev/snd`
(P2); case 64 (device directory mounted from the faked directory) is red on the base, which is
the seam's check.

## Obligations

- **O1** (fresh sandbox, stubbed `xpra` display, faked sound socket and device directory).
  Cases 39 to 46 of `tests/ai-sandbox/test-devices.sh` (`a new sandbox: ...`): compose has no
  `sandbox-pulse`, no `PULSE_SERVER`, no `/dev/snd`, no `c 116:`; `.env` holds
  `SANDBOX_WITH_AUDIO=0`; the shared brain has no `parec`; output contains `not shared by
  default` and `--audio`. Also the `--display=none` cases 5 to 9. Command
  `bash tests/ai-sandbox/test-devices.sh`: `82 run, 0 failed`, exit 0. Commit `2b942bd`.
- **O2** (old remembered value). Cases 22 to 25 (stored 1; the notice is not repeated), 26 and 27 (`--audio` over
  a stored 1), 28 and 29 (unknown value), and 49 to 61 in the display mode: stored `1` gives no
  socket, no variable, no device mount, no rule, `.env` rewritten as `0`, exactly one notice
  (`used to be the default`, `Pass --audio`), a second bare run does not repeat it.
  `82 run, 0 failed`. Commit `2b942bd`. R1 is clean (the notice avoids the phrase).
- **O3** (`--audio`). Cases 10 to 14 and 62 to 68: socket mount, `PULSE_SERVER`, device
  directory mounted at `/dev/snd` from the faked directory, `c 116:* rwm`, `.env` `2`, a `warn`
  naming the sound socket and devices, the microphone, `act on its requests` and `outside`;
  `--display=none` mounts the socket and, with the faked device directory, no device and no
  rule (cases 10 to 14, and 83 and 84, commit `4dd41ad`);
  cases 30 and 31, `--audio` with no host socket: the warning `no sound socket at ...` and no
  mount. `82 run, 0 failed`. Commit `2b942bd`.
- **O4** (remembered request). Cases 15 to 21 (display `none`) and 69 to 82 (stubbed display):
  a bare run after `--audio` keeps the mounts, `.env` `2` and repeats the warning with
  `--no-audio`; `--no-audio` removes all four and records `0`; a bare run after keeps off.
  `82 run, 0 failed`. Commit `2b942bd`.
- **O5** (options' text). Cases 33 to 38 run `create-ai-sandbox.sh --help` and assert on its
  output: `Off by default`, `microphone included`, `act on its requests`, `Remembered until
  --no-audio` (for `--audio`), `Drop a remembered --audio` (for `--no-audio`). `82 run, 0
  failed`. Commit `2b942bd`.
- **O6** (the device directory seam). Read `bin/ai/create-ai-sandbox.sh`: `readonly
  HOST_SND_DIR="${HOST_SND_DIR:-/dev/snd}"` with its comment directly after `HOST_ETC_DIR`
  (line 87); the device branch (`[ -d "$HOST_SND_DIR" ]`, `add_vol "\"${HOST_SND_DIR}:/dev/snd\""`,
  rule `c 116:* rwm`) near line 907; the bind target stays `/dev/snd`. R5 below. Commit `2b942bd`.
- **O7** (a default sandbox binds no host socket but its display's). Case 47 `a new sandbox:
  binds no host socket but its display's` (function `daemon_binds` in the test: every bind
  source of the compose `volumes:` block that is a socket on the machine, is the faked sound
  socket or a directory holding it, with the display's per-sandbox X directory excepted) and case
  48 (the display's directory is bound, so the exception is exercised). Red on the base (the faked
  socket is a bind source there), green now. S16 re-run on the result:
  `command grep -naE 'XDG_RUNTIME_DIR|/run/user/|/tmp/\.X11-unix|\.sock\b' bin/ai/create-ai-sandbox.sh`
  prints 29 lines, as on the base. Every host-side hit is in the display section (556, 574 to
  608, 677 to 733) or the audio branch (789, runs only on a request); the rest are inside the
  image or container (1434 to 1488, 1606, 1851, 2112, 2180 to 2182, 2326, 2519, 2543), unchanged.
  No hit is neither. Commit `2b942bd`.

## Residue (the plan's R1 to R5, run from the worktree root on commit `2b942bd`)

- R1 `command grep -naiE 'on by default' bin/ai/create-ai-sandbox.sh`: empty (exit 1).
  (First attempt matched my own comment at line 507; reworded before the commit.)
- R2 `command grep -rnaE '"SANDBOX_WITH_AUDIO": *"1"|SANDBOX_WITH_AUDIO=1' bin tests`: three
  lines, all of `tests/ai-sandbox/test-devices.sh`, each putting the old value into a `.env`
  (the fixture of old data): 78, 85, 162. The writer in create no longer matches.
- R3 `command grep -naE '^WITH_AUDIO="yes"' bin/ai/create-ai-sandbox.sh`: empty (exit 1).
- R4 `command grep -naE 'default is recorded as on|default advertises capture|no flag and no stored value mounts|stored 1 keeps audio on|default log tells how to drop' tests/ai-sandbox/test-devices.sh`: empty (exit 1).
- R5 `command grep -naE -- '-d /dev/snd|"/dev/snd:' bin/ai/create-ai-sandbox.sh`: empty (exit 1).

## Checks after the last edit of the first round (tree at `4dd41ad`; the first run at `2b942bd`)

- `bash tests/ai-sandbox/test-devices.sh`: `84 run, 0 failed`, exit 0 (the base has 17 cases).
- `bash tests/ai-sandbox/run-tests.sh` (second run, after the last edit, tree at `4dd41ad`):
  20 files; per-file summaries 32, 151, 56, 13, 69 (`test-delegate.sh`: `69 run, 2
  failed`), 84 (`test-devices.sh`), 5, 23, 20, 19, 17, 14, 473, 32, 30, 33, 65, 27, 39 and 82
  cases, `0 failed` in each except `test-delegate.sh`; total 1284 run (the base's 1217 plus the 67
  new cases of `test-devices.sh`), 2 failed; exit 1. The two failures are cases 54 (`writer
  prompt has no-tools line`) and 59 (`second-reviewer prompt has no-commands line`) of
  `test-delegate.sh`, the known D15 cases of the plan (PA5). (The first run, at `2b942bd`, gave
  1282 run, the same 2 failed.)
- `shellcheck -S warning` on create: 2 findings, as on the base (2); `test-devices.sh`: none
  (after the last edit).
- `/tmp/.X11-unix` holds no leftover directory of the stubbed display runs.

## Deviations from the plan

None in what is built. Choices the plan left open: the old-value notice and the `--audio`
warning are `warn` (standard error); the previous `log "keeping host audio off"` line for a
stored `0` is gone, since the default line already says audio is not shared; the `--audio`
warning is printed whenever audio is on, also when no host socket exists, followed by the
existing no-socket warning. `PROJECT_MAP.md` says nothing about audio, so it is unchanged.

## Fix round (phase review, `phase-review.md`)

Base check: tip `11347c3`, clean tree. Tests were written first; commit `d547566`
(`fix: audio texts state what is given and what this run shares`). The case numbers quoted
in the entries above are those of the runs at `2b942bd` and `4dd41ad`; the new cases below
renumber the file (now 100 cases), so they are cited by name from here on.

- **I1** (the texts promise more than I3e). Red first: cases `help states the promise as what a
  sandbox is given`, `help does not promise what a sandbox can reach`, `--audio promises what a
  sandbox is given in the warning` and `the warning does not promise what a sandbox can reach`
  failed on `11347c3`. The usage and the warning now say "outside the promise that a sandbox is
  given no host daemon's socket but its display's", on one line each so the cases pin the whole
  phrase (`given no host daemon's socket but its display's`); the cases also assert that
  `reachable` does not appear in the help or the warning. Green after the fix.
- **M1** (the warning overstates what is shared). Red first: `--audio with no display: the
  warning names the socket` and `... names no sound devices`, `--audio with no display and no
  socket: the warning promises no sharing`, `--audio with a display and no socket: the warning
  names the devices` and `... names no socket it lacks`. Now one variable, `AUDIO_DEVICES`,
  decides whether the devices are mounted (read by the warning and by the device branch, so the
  rule lives once); the warning names the socket only if one exists and the devices only if they
  are mounted; the sentence about the sound server acting on requests appears only with a
  socket; with neither, only the existing no-socket warning is printed. Cases cover: display
  `none` with socket and faked devices (socket named, no devices), display `none` and no socket
  (no sharing claim, missing socket named), display with socket and devices (both named), display
  with devices and no socket (devices named, device directory mounted, no socket claimed).
- **M2** ("not shared by default" only where true). Red first: `--no-audio says audio is not
  shared`, `--no-audio does not say audio is off by default`, `a stored 0 says audio is not
  shared`, `a stored 0 does not say audio is off by default`. After an explicit `--no-audio` or
  with a stored `0` the line is "Audio: not shared; pass --audio ..."; otherwise ("not shared by
  default") as before. The fresh-sandbox cases of O1 still pass.
- **M3** (evidence heading). Corrected: the final-checks heading now names `4dd41ad` and the
  first run at `2b942bd`.

Red run of the new cases on `11347c3`'s create script (new tests): `100 run, 13 failed` (4 cases
of I1, 5 of M1, 4 of M2). Green on `d547566`:
`bash tests/ai-sandbox/test-devices.sh`: `100 run, 0 failed`.

Residues R1 to R5, re-run from the worktree root on `d547566`: R1 empty (exit 1); R2 three
lines, all fixtures of old data in `tests/ai-sandbox/test-devices.sh` (82, 89, 170); R3, R4, R5
empty (exit 1). O3 and O5 entries above stand with the new wording; O7 untouched (the
display section and the bind-source case are unchanged).

Checks after the last edit (tree at `d547566`):
- `bash tests/ai-sandbox/test-devices.sh`: `100 run, 0 failed`.
- `flock .../suite.lock bash tests/ai-sandbox/run-tests.sh`: 20 files, `0 failed` in each
  except `test-delegate.sh` (`69 run, 2 failed`: cases 54 and 59, the known D15 cases);
  `test-devices.sh` 100; exit 1. Total 1300 run (1284 plus the 16 new cases), 2 failed.
- `shellcheck -S warning`: create 2 findings (as on the base), `test-devices.sh` none.
- `/tmp/.X11-unix` holds no leftover directory.
