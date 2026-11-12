Task: 2026-11-11-sandbox-hardening

# Phase 2 review (host audio off by default)

Reviewer: Fiona (reviewer 1), 2026-11-12. Object: `git diff de1aa6d..11347c3` in
`.worktrees/2026-11-11-sandbox-hardening-p2` (commits 2b942bd, dcbb249, 4dd41ad, 11347c3),
against the plan's O1 to O7 and R1 to R5, the spec's phase 2 block and I3e as changed by
S-4, and `T01-audio-opt-in.md`. Hand-edit commits read in full.

**Verdict: blocked on one Important finding (I1).** 1 Important, 3 Minor. No fixes made
by the reviewer (the lead's brief forbids edits in the worktree).

## Important

**I1. The help text and the `--audio` warning state a wider promise than I3e.**
`bin/ai/create-ai-sandbox.sh:154-155` (usage of `--audio`: "outside the promise that no
host daemon's socket but the display's is reachable from it") and `:798-799` (the warning:
"outside the promise that no host daemon's socket but the display's is reachable from
it"). I3e as S-4 words it promises that the toolchain *gives* a sandbox no host daemon's
socket but its display's; S-4 moved what a sandbox can *reach* on the host network into
an accepted residual risk ("A network service the host offers on the address by which
every sandbox reaches the host"). Every compose file maps `host.docker.internal` to the
host gateway (`:2306-2307`, unconditional), so in every default sandbox a host daemon
listening on that address is reachable through its socket. Scenario: the user reads the
help or the warning, concludes that a sandbox without `--audio` reaches no host daemon,
and runs a host service bound to the bridge or `0.0.0.0` without authentication; every
sandbox reaches it. This is a user-facing statement of a security property the code does
not deliver (global rule: a text telling users what the code does is derived from the
code, not from a paraphrase), and the spec's requirement is to say that I3e does not
hold, not a stronger promise. Correction: word both places as I3e is worded, e.g.
"outside the promise that a sandbox is given no host daemon's socket but its display's";
no test asserts the phrase, so cases 37 and the warning cases (`act on its requests`,
`outside`) are unaffected. Re-run `bash tests/ai-sandbox/test-devices.sh`.

## Minor

**M1. The `--audio` warning overstates what is shared in two states.**
`bin/ai/create-ai-sandbox.sh:796` prints "the sandbox gets the host's sound socket and
sound devices" also under `--display=none` (devices are not mounted, `:907`) and when no
host socket exists (then followed by the no-socket warning, `:805`). Errs on the safe
side; no user is harmed, but the text is not what the code does. Correction (needs a
wording choice, so for the implementer): name the devices only when the device branch
mounts them, or say "sound socket, and sound devices when a display is used".

**M2. "not shared by default" after an explicit `--no-audio`.** `:794` prints "Audio: not
shared by default; pass --audio ..." for every off state, including `--no-audio` and a
stored `0` that `--no-audio` wrote; the base said "(--no-audio; ...)" there. O1 asks for
this line only in the default case. Correction: say "not shared" without "by default"
when `WITH_AUDIO_EXPLICIT=yes` or the stored value is `0`, or accept as is.

**M3. Evidence labels the final runs with the wrong commit.**
`T01-audio-opt-in.md`, heading "Last step: checks after the last edit (tree at
`2b942bd`)", while its first bullet (`84 run, 0 failed`) and the `run-tests.sh` bullet are
the runs at `4dd41ad`; at `2b942bd` the file had 82 cases. Correction: heading "(tree at
`4dd41ad`; the first run at `2b942bd`)".

## Checked, with result

- Remembered value (create `:504-513`, `:790-806`, writer `:2240`), traced for every
  stored value with no option, `--audio` and `--no-audio`: absent/no key → off, `0`, no
  notice; `0` → off, `0`; `1` → off, `0`, one notice, none on the next run; `2` → on, `2`,
  warning repeated; other (incl. `bogus`, `2 `) → off, `0`, silent; `--audio` over any →
  on, `2`, no notice; `--no-audio` over any → off, `0`, no notice (an explicit choice; the
  spec's "says so" applies to a run without an explicit option). Matches the data shape
  and O2/O4. Tests cover absent, 0, 1, 2, bogus, `--audio` over 1; `--no-audio` over 1 is
  untested but follows from the explicit branch.
- O7 against I3e as S-4 words it: case 47 (`daemon_binds`) detects a socket bind source,
  the faked sound socket and any directory holding it, excepting only the per-sandbox X
  directory by equality; its known case is the red run on the base (case 47 red because
  the base binds the faked socket). The parser covers the compose template's volume
  format (all entries `      - "src:dst"`, `:2352-2420`, `:672`). It proves the property
  under `xpra`; the other modes rest on the S16 read, which I re-ran: 29 lines, host-side
  binds only in the display section (wayland binds the single socket file, `:686`, `:733`)
  and the audio branch. With I1 corrected, O7 proves what I3e claims.
- `HOST_SND_DIR` (O6): readonly, default `/dev/snd`, commented, after `HOST_ETC_DIR`
  (`:84-87`); test and bind source of the device branch, target `/dev/snd` (`:907-908`);
  compose unchanged with the default. Case 84 exports the seam into the run (bash
  exports prefix assignments for a function call), so it pins the display condition
  independent of the machine. Cases 83/84 were written after the change but pin
  behaviour the phase keeps (O3 "as today"), not a fix; no regression-test claim.
- O5 text read from the test's `--help` assertions and the usage block; matches O5 except
  I1.
- Residues, run from the worktree root at `11347c3`: R1 empty; R2 three lines, all
  `tests/ai-sandbox/test-devices.sh` fixtures of old data (78, 85, 162); R3 empty; R4
  empty; R5 empty. Known cases: R1 and R5 patterns return 2 lines each on `de1aa6d`.
- `AGENT-MARK 2026-11-11-sandbox-hardening-p2`: no hit.
- Security-review inputs: no committed text in the diff or commit messages names a
  reproduction step, command, module or host detail from `.tmp/security/` (`git grep` at
  `11347c3` for the review's specific terms: no hit; known case `pactl info` at create
  1719 found). The rewrapped comment `:787-788` names the sound servers as on the base.
- Recorded test runs (`84 run, 0 failed` for `test-devices.sh`; `run-tests.sh` 1284 run,
  2 failed, both D15) settle the suite claims; not re-run.

## Coverage against the phase goal

Every observable part of the spec's phase 2 goal has an obligation: no socket/device
unless asked (O1, O7), the old value is no request and is announced (O2), a request is
remembered until `--no-audio` (O4), `--audio` says what it shares, microphone included,
and that I3e does not hold (O3, O5; wording per I1), the closing check's three cases
(O1-O3 in the stubbed display mode). No gap.

## Round 2 (delta `11347c3..19705ad`: d547566, 19705ad)

**Verdict: accepted. 0 Critical, 0 Important, 1 Minor.** I1, M1, M2 and M3 are closed.

- **I1 closed.** The usage text (`bin/ai/create-ai-sandbox.sh:154-156`) and the warning
  (`:812-814`) now say "outside the promise that a sandbox is given no host daemon's socket
  but its display's", which is I3e's wording. New cases pin the phrase in the help and in the
  warning, and check that "reachable" is absent from both. The red run is recorded on
  `11347c3`.
- **M1 closed.** One variable, `AUDIO_DEVICES` (`:798-799`), decides the device mount (`:925`)
  and the warning's wording. `DISPLAY_MODE` is final before that point (`:549-564`). The
  warning names the socket only when it exists and the devices only when they are mounted.
  The I3e sentence is printed only with a socket. A devices-only sandbox gives no host
  daemon's socket, so I3e holds for it, and the per-run text is accurate. With neither, only
  the no-socket warning is printed. Cases cover all four states.
- **M2 closed.** After `--no-audio` or a stored `0` the line reads "Audio: not shared; ...".
  The fresh case, an absent key and an unknown value keep "by default". Cases cover
  `--no-audio` and a stored `0`.
- **M3 closed.** The evidence heading now names `4dd41ad`.
- Residues re-run at `19705ad`: R1, R3, R4 and R5 are empty. R2 returns three lines, all
  fixtures of old data in `tests/ai-sandbox/test-devices.sh` (82, 89, 170). The
  `AGENT-MARK` search has no hit. The delta adds no committed text from the security-review
  inputs. O7's case and the display section are unchanged.
- Recorded runs settle the suite claims: `test-devices.sh` `100 run, 0 failed`, and
  `run-tests.sh` 1300 run, 2 failed, both D15. I did not re-run them.

Minor (new, not blocking):

- **N1. The `--audio` warning prints as three separate `!!` blocks.**
  `bin/ai/create-ai-sandbox.sh:811-816` calls `warn` three times. `warn` (`:308`) starts each
  call with a blank line and `!! `, so the text reads "!!    A program in the sandbox ..." and
  "!!    Pass --no-audio to drop it.", each on its own after a blank line. The content is
  correct; only the layout is off. Correction (implementer's choice): build the message in
  one variable and call `warn` once.
