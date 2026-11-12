Task: 2026-11-11-sandbox-hardening
Class: phase

# Phase 2 plan: host audio off by default

Phase key: `2026-11-11-sandbox-hardening-p2`. Spec:
`docs/superpowers/specs/2026-11-11-sandbox-hardening-design.md`, block "Phase 2", with
I3e, I4, I6, I8, the user's decision U1, "Host commands and phone work" and the
section "Inputs" as changed by S-1 (what committed text may hold). Evidence directory:
`docs/superpowers/evidence/2026-11-11-sandbox-hardening-p2/`; the searches and probes
behind this plan are in `2026-11-11-sandbox-hardening-p2-plan.md` there, each with the
exact command, so it can be re-run unchanged. Written by Ola (planner 3) on 2026-11-12.

**Status: approved** by the user on 2026-11-12 with S-4 option (a) ("a"); verified on 2026-11-12 against `dd0146a` (`main`; its
`bin/`, `tests/` and `tools/` are those of `4d6f677`), the base phase 2 starts from in
parallel with phase 1 ("Base and branches"), and against phase 1's branch tip
`7156737` for the overlap. The evidence file's section "Re-run on the chosen base"
records the re-run. Findings are named by key, inputs by class (S-1).

## Read this first (for the reviewer)

- **Spec change: one proposed, not applied.** S-4 narrows I3e to "no host daemon's
  socket but the display's", with residual-risk lines for what that leaves out (the
  display server, and host services reachable at the address a sandbox reaches the
  host by), and, as part of the same option, writes down in the phase 2 block that a
  request made with `--audio` after this phase is remembered (O4 rests on it). Text
  and options: `spec-change-I3e.md` in the evidence directory, by the spec's author.
  The plan is written on its option (a) (PA7); under (b) the phase goal changes and
  the plan is redone. This is the user's one open decision.
- **Unverified assumptions:** PA7 (pending S-4) and PA2's part about project code
  inside sandboxes. PA1 is settled by the spec (the author's answer to Q1); PA5 holds
  at `7156737` and is re-checked when the other branch lands on `main`.
- **Base:** `dd0146a`, not phase 1's tip; phase 2 merges independently of phase 1, in
  either order ("Base and branches").
- **Folded:** nothing. Deferred list unchanged (below).
- **One task.** The phase is a default, a remembered value that no longer counts as a
  request, the options' text and the closing check, all in one file and its test.

## Who uses it and the states the phase touches

The user on the host creates and re-creates sandboxes with `create-ai-sandbox.sh`;
agents inside use sound only in a sandbox the user opted in. The user on the phone is
unaffected: no host command is added (table of host commands, below).

- Normal: a new sandbox has no host sound socket, no sound device and no device rule;
  the output says audio is not shared and names `--audio` (O1). A sandbox created with
  `--audio` shares both and the output says what that shares, microphone included,
  and that I3e does not hold for it (O3).
- Empty: `.env` without the audio key (trigger: a sandbox created before the key
  existed and never re-created; tree: create reads the key only when present). Off,
  with the default line of O1; no extra notice (left out, below).
- Invalid input: `--audio` with `--no-audio`: exit 2, as today. A hand-edited value
  other than the data shape's (trigger: the user's edit of `.env`): read as no
  request, so off; the safe reading of an unknown value.
- The old remembered value: `SANDBOX_WITH_AUDIO=1`, written by every run before this
  phase whether audio was on by default or by `--audio` (evidence S2). Not a request:
  the run turns audio off, records `0` and prints one notice saying so (O2). A user who
  had asked for audio passes `--audio` again.
- Failure: `--audio` and no sound socket on the host: today's warning, no socket
  mount (O3). Nothing new can fail: the phase adds no host process.
- Interruption: a sandbox running when this phase lands keeps its sound until the user
  stops and re-creates it; it is not refused (I6; batch B lists those that still share
  sound). A create run stopped before it rewrites `.env`: the next run reads the old
  value again and acts as O2.
- Retry: every run is idempotent; after the first re-creation `.env` holds `0` or `2`,
  so the notice of O2 appears once.

What the user of a re-created sandbox sees: on the host, the line of O1 or the notice
of O2 in the create output; inside, no `PULSE_SERVER`, programs that play or record
find no sound server, `sandbox-doctor` shows `audio  unavailable` (its meaning
unchanged: the line already says so for `--no-audio`), and the agents' environment
block lists no capture tools. An opted-in sandbox behaves as today, and every create
run for it repeats the warning of O3.

## Deferred list

- E1 (egress): **keep**, phase 10 (open).
- E2 (`bin/ai/MANIFEST` ignored by git): **keep**, phase 4 (open).

Nothing added.

## Base and branches

- **Area and slot.** The ai-sandbox toolchain (`bin/ai/create-ai-sandbox.sh`,
  `tests/ai-sandbox/test-devices.sh`). One implementer in slot 2 (Wojtek): slot 1
  (Zuzia) holds phase 1, whose T09, T10 and T12 are still open.
- **Worktree and branch.** `.worktrees/2026-11-11-sandbox-hardening-p2` on branch
  `2026-11-11-sandbox-hardening-p2` (`.worktrees/` is already in `.git/info/exclude`).
  Why a worktree: until phase 4 the host runs `create-ai-sandbox.sh` from the main
  checkout's working tree (H3).
- **Base: `main` at the commit that carries this plan, whose code is `dd0146a`'s**, not
  phase 1's tip. The implementer checks it before the first edit:
  `git diff --quiet dd0146a HEAD -- bin tests tools && echo identical`. Reasons:
  - The overlap is small (evidence, "Re-run on the chosen base"). Phase 1 has not
    touched `test-devices.sh`, `test-resources.sh` or `harness.sh`; its one stub
    change (`docker run`) is not reached under `--no-start`; in create it changes no
    audio line, and its only hunk near one is the `.env` writer, where one unchanged
    line separates its change from `SANDBOX_WITH_AUDIO`. The expected merge is clean
    or one small hunk there.
  - The host batches. Phase 1's merge waits for B1 (X1 and A3 on every host), for
    T09 and T10, which wait for X1, and for RP1. Phase 2 needs no experiment. On
    phase 1's tip, the fix of a Critical finding (C2) would wait for X1. On
    `dd0146a`, phase 2's RP and batch B can come before or after phase 1's B2, and
    both orders end in the same state (batch B, below).
- **When phase 1 adds commits.** Nothing happens to phase 2's branch while phase 1 is
  unmerged: it does not follow phase 1's branch. Whichever phase lands on `main`
  second follows this procedure on its own branch (the second-landing procedure):
  1. take `main` in with a merge commit (no rebase: evidence cites commit ids) and
     resolve any conflict;
  2. run `bash tests/ai-sandbox/test-devices.sh` and `bash tests/ai-sandbox/run-tests.sh`;
  3. re-run this plan's evidence section "Re-run when the other branch lands on
     `main`";
  4. if the merge comes before that phase's review, the review and the gate cover the
     merged tree; if after, the merge commit's delta gets a review of its own and the
     gate runs again on the new tip;
  5. the read point is taken again on every tip the gate runs on (RP below; RP1 for
     phase 1).
- **Machine.** This sandbox has 1 CPU and 2 GB: the two worktrees never run a suite at
  the same time; the lead serialises suite runs across phases 1 and 2. Neither
  worktree stashes (shared stash).
- **Order with phase 3.** Phase 2 merges **before phase 3's pins are taken** (spec,
  "Timing"): the lead does not start phase 3's pin task on a commit without phase 2's
  merge, so phase 3's pins record audio off as the default.
- **Read point RP.** After the review accepts the tree and G has passed, and before
  the merge, the user reads at the host what the host will execute, first every
  changed path, then `bin/ai`:
  `B=$(git -C ~/dev/public/dev-tools merge-base main <tip>); git -C ~/dev/public/dev-tools --no-pager diff --no-ext-diff --no-textconv --stat $B <tip>`
  and
  `git -C ~/dev/public/dev-tools --no-pager diff --no-ext-diff --no-textconv $B <tip> -- bin/ai`
  (`<tip>`: the commit G ran on). The merge base is the commit on `main` the branch
  started from or last merged, so the read holds phase 2's change only, including
  any conflict resolution, in either order. RP is taken again on every tip G runs on,
  so a merge commit made after the first reading (procedure step 5) is read too. A
  path outside `bin/ai` in the `--stat` list that the host runs is read as well.
- **For phase 1, carried by the lead to that plan.** If phase 2 lands first, the
  second-landing procedure above binds phase 1's branch, with the re-run of this
  plan's evidence section "Re-run when the other branch lands on `main`" (its items
  read the same in that direction), and phase 1's RP1 takes the same `merge-base`
  form: its range `<base>..<tip>` from its plan's commit would otherwise also list
  phase 2's commits. Not changed here: it is phase 1's plan.
- Batch B follows the merge. It does not gate phase 3.

## Data shape

Stored on every host, in each sandbox's `.env` (and through `env_file` in the
container's environment, evidence S11). Phase 10's playback-only path may add a value.

```
# <sandbox dir>/.env, managed key, rewritten by every create-ai-sandbox.sh run
SANDBOX_WITH_AUDIO=0   # host audio off: the default, or --no-audio
SANDBOX_WITH_AUDIO=2   # host audio on: --audio at this run, or kept from a run that wrote 2
# 1 is the old shape: written before phase 2 for audio on by default and by --audio alike;
#   read as no request (O2), never written again
```

`2` exists so that a request made after this phase can be told apart from the old
default, which wrote `1` in both cases (the spec author's answer to Q1).

## Obligations

Each task cites the keys it discharges. Evidence: one file per task, `T<NN>-<slug>.md` (as phase 1: `T01-audio-opt-in.md`)
in the evidence directory, one entry per key. Committed texts (messages, test names,
assertion messages, comments) state the property only and name no daemon command or
module (S-1).

- **O1 A new sandbox gets no host audio** (closing check, first case; I3e, U1). A
  create run with no audio option and no `.env`, in a display mode other than `none`
  (stubbed as `test-resources.sh` does for `xpra`, evidence S13), with a host sound
  socket and a sound-device directory both faked: the compose file holds no mount of
  the socket, no `PULSE_SERVER`, no mount at `/dev/snd` and no `c 116:` rule; `.env`
  records `SANDBOX_WITH_AUDIO=0`; the agents' environment block lists no capture
  tools; the output says audio is not shared by default and names `--audio`. Check:
  `bash tests/ai-sandbox/test-devices.sh` ends `0 failed`, with these cases.
- **O2 The old remembered value is no request** (closing check, second case). The
  same setting with `.env` holding `SANDBOX_WITH_AUDIO=1` and no audio option: the
  compose file holds none of O1's four; `.env` records `0`; the output has one notice
  that host audio was on for this sandbox because it used to be the default, is now
  off, and that `--audio` shares it again. A second bare run keeps audio off and does
  not repeat the notice. With `--audio` over a stored `1`, O3 holds. Check: as O1.
  The notice avoids the phrase "on by default", which R1 searches for; "used to be
  shared by default" or similar passes R1.
- **O3 `--audio` shares, and says what** (closing check, third case; I3e's stated
  exception). The same setting with `--audio`: the compose file holds the socket mount,
  `PULSE_SERVER`, the faked device directory mounted at `/dev/snd` and the rule
  `c 116:* rwm`; `.env` records `2`; the output carries a warning (`warn`, as for
  `--with-docker`'s reduced isolation, evidence S14) that names the host's sound
  socket and sound devices, says the microphone is included, and says that a program
  in the sandbox can make the host's sound server, which runs as the user, act on its
  requests, so the sandbox is outside I3e. With `--display=none` and `--audio`: the
  socket, `PULSE_SERVER` and the warning, no device and no rule (as today). With
  `--audio` and no host socket: today's warning and no socket mount. Check: as O1.
- **O4 A request is remembered** (PA1, settled by the spec: Q1). After an `--audio`
  run, a bare run keeps O3's compose content and `.env` value and repeats O3's warning
  with how to drop it; `--no-audio` then removes all four and records `0`, and a bare
  run after that keeps audio off. Check: as O1.
- **O5 The options' text** (U1; "says so when the option is given"). The output of
  `create-ai-sandbox.sh --help`: `--audio` says it is off by default, what it shares
  (the sound socket and devices, microphone included), the I3e sentence of O3, and
  that it is remembered; `--no-audio` says it drops a remembered `--audio`. Check: as
  O1, cases on the `--help` output (what the code prints, not the source).
- **O6 The device directory is a seam.** A readonly `HOST_SND_DIR`, default `/dev/snd`,
  defined and commented beside `HOST_ETC_DIR` (evidence S9), is the existence test
  and the bind source of the device branch; the bind target stays `/dev/snd`, so with
  the default the compose file is unchanged. Read: the definitions next to
  `HOST_ETC_DIR` and the device branch of the devices section; R5.
- **O7 A default sandbox binds no host socket but its display's** (I3e as S-4 words
  it; the check the spec's author named). In O1's fresh case, with the faked sound
  socket inside a faked runtime directory (`XDG_RUNTIME_DIR`): no bind source of the
  compose file is a socket on the test machine, and none is the faked sound socket or
  a directory that holds it, except the display mode's own bind (under the stubbed
  `xpra`, the per-sandbox X socket directory). Check: as O1. Read: S16 (evidence) re-run
  on the result; every host-side hit is in the display section, or is the audio branch,
  which runs only on a request; a hit that is neither is named in the task's evidence.

Phase-level, cited by no task:

- **G The gate**, once on the tree the phase review accepts, by the implementer the
  lead names or a runner: `bash tests/ai-sandbox/run-tests.sh` (every file `0 failed`
  except `test-delegate.sh`, whose only failures are cases 54 and 59, D15),
  `bash tests/ai-sync/test-sync.sh`, `bash tests/git-hooks/test-hooks.sh` (needs
  gitleaks; present in this sandbox), `python3 -m unittest tools.context_statusline.test_statusline`.
  On the base the suite has 20 files (A4); if phase 1 has been merged in first, its
  files run too, and its recorded runs (T08, T11 evidence on its branch) show the
  same two cases as the only failures.
- **R1 to R5, residue**, run by the phase review from the repository root:
  - R1 the old default's wording: `command grep -naiE 'on by default' bin/ai/create-ai-sandbox.sh`:
    empty. Base: 2 lines, both audio (evidence S5).
  - R2 the old value written: `command grep -rnaE '"SANDBOX_WITH_AUDIO": *"1"|SANDBOX_WITH_AUDIO=1' bin tests`:
    only the lines of `test-devices.sh` that put the old value into a `.env` (the
    fixture of old data, kept on purpose), named by line in the review. Base: create's
    writer and test-devices.sh 45, 60 (evidence S2).
  - R3 the default: `command grep -naE '^WITH_AUDIO="yes"' bin/ai/create-ai-sandbox.sh`:
    empty. Base: 1 line (evidence S1).
  - R4 cases pinning the old default: `command grep -naE 'default is recorded as on|default advertises capture|no flag and no stored value mounts|stored 1 keeps audio on|default log tells how to drop' tests/ai-sandbox/test-devices.sh`:
    empty. Base: 5 lines.
  - R5 the fixed device path: `command grep -naE -- '-d /dev/snd|"/dev/snd:' bin/ai/create-ai-sandbox.sh`:
    empty. Base: 2 lines (evidence S3).

## Impact set

Searches are in the evidence file under these names, with their exact commands and
counts; bash has no compiler, so the text searches are the static enumeration, each
with its known case.

| Changed | Category | Search | Result | Dependants and their fate |
|---|---|---|---|---|
| The default and the option state (`WITH_AUDIO`, `WITH_AUDIO_EXPLICIT`) | static, one file | S1 | 12 | all in create: default, parsing, remembered value, socket branch, device branch, environment block, `.env` writer (T01). Residue R3 |
| `SANDBOX_WITH_AUDIO` values | strings, stored data | S2, S11, P1 | 5 | create's reader and writer (T01); test-devices.sh 3 (T01). Outside: every existing sandbox's `.env` holds `1` (P1 here): read as the old shape (O2), re-created in batch B; the container's environment through `env_file`: no reader in the repository (S2) or the knowledge repository (S7); project code inside a sandbox, guessed none (PA2). Residue R2 |
| Mount and rule strings | strings | S3 | 15 | create's socket and device branches (T01); the doctor's `audio` line reads `PULSE_SERVER`, unchanged; test-devices.sh 5 (T01). Residue R5 |
| Option names and their texts | strings | S4, S5 | 25; 2 | usage, messages and comment in create (T01); test-devices.sh 12 (T01). The names stay. Residue R1 |
| Other wording about audio | strings | S6 | none outside create and its test | `bin/video/recode-video` is unrelated; no document states the default; `docs/superpowers/` keeps its history |
| Tests relying on the default | static | S8 | 0 outside test-devices.sh | none. Residue R4 for test-devices.sh |
| Outside: the agents' environment block in each sandbox | outside, generated | S1 (the capture-tools line) | 1 | regenerated by each create run; absent by default (O1) |
| Outside: the knowledge repository | outside | S7 | 0 | none |
| Duplicated logic: where the default is decided | duplicated | S1, S5 | 1 default line | no second copy; the remembered-value branch is the other place that sets audio on, changed in T01 |
| New names `HOST_SND_DIR`, value `2` | strings | S10 | 0 | additions, no residue |
| Host sockets a default sandbox is given (O7; I3e as S-4 words it) | outside, enumerated | S16 | 29 hits; host-side binds only in the display section and the audio branch | T01 changes only the audio branch; the display section is untouched. No residue: nothing is renamed |
| Reliance on an invariant | - | none possible | - | programs inside a sandbox that assume a sound server; nothing enumerates them; I3e and test-devices.sh are the net |

## Tasks

The task ends with `bash tests/ai-sandbox/test-devices.sh` and
`bash tests/ai-sandbox/run-tests.sh`, and commits on the branch with its evidence file.

- **T01 audio-opt-in.** In `create-ai-sandbox.sh`: the default becomes off; the
  remembered-value block reads the data shape (`1` as the old shape with O2's notice,
  `2` as a request, PA1); `--audio` and a kept request print O3's warning; the `.env`
  writer writes `0` or `2`; the usage text, the "not shared" line and the comments of
  the option defaults and the audio section say off by default; the device branch
  takes its directory from `HOST_SND_DIR`. In `test-devices.sh`: the cases that pin
  the old default are replaced, and the closing check's three cases (fresh, old value,
  `--audio`) run in a stubbed display mode with a faked socket and device directory,
  and the fresh case also carries O7's bind-source check; write those first, they fail
  on the base for O1 and O2. Discharges O1 to O7. Host runs: `create-ai-sandbox.sh`.

## Batch B, after RP and the merge (set-up, at every host with sandboxes)

Steps 0 to 2 run on every host that has sandboxes; the order cases below apply to each
host by where that host stands. Every order ends with each sandbox re-created at least
once on code that has this phase:
- Phase 1 not merged yet: run steps 0 to 2 now. Every existing sandbox shares sound
  today (the old default), so step 1 lists them all. Phase 1's B2 later re-creates
  them again with a bare command, which keeps `0` or `2` (O4). Waiting for B2 instead
  saves one re-creation and leaves C2 open on each sandbox until then.
- Phase 1 merged and that host's B2 already run: run steps 0 to 2 now (B2's
  re-creation, on code without this phase, wrote the old value again).
- Phase 1 merged and that host's B2 not run yet: run B2 instead, adding `--audio` to
  B2's command for a sandbox in which you want sound (B2's commands are bare, so such a
  sandbox would otherwise lose it, and O2's notice would say so); its re-creation
  applies this phase too. Then step 2 here.

0. Bring the host's checkout to the merged `main` (on this host the lead's merge does
   it), as phase 1's B2 step 1 does. Until then a re-creation on that host runs the
   code from before this phase and keeps sharing sound.
1. Print a re-create command for every sandbox whose compose file still shares host
   sound, then run each at a time that suits (it ends the sessions inside; other
   options are remembered). Add `--audio` to the command of a sandbox in which you want
   sound; its output says what that shares.
   `for d in ~/.ai-sandbox/*-agent; do [ -f "$d/docker-compose.yml" ] && command grep -qE 'sandbox-pulse|/dev/snd' "$d/docker-compose.yml" && printf 'cd %q && ai-sandbox-stop && create-ai-sandbox.sh\n' "$(head -1 "$d/project-path")"; done`
2. After the last one:
   `command grep -lE 'sandbox-pulse|/dev/snd' ~/.ai-sandbox/*-agent/docker-compose.yml || echo none`
   Expected: `none`, or only the sandboxes you re-created with `--audio`. Paste back
   the output of each host, named by host. The output names sandboxes and projects,
   so the lead keeps it untracked under `.tmp/security/` and records in `host.md` in
   the evidence directory only the verdict per host: `none`, or the number of
   opted-in sandboxes and that you confirmed each, as phase 1 does with its host logs
   (spec, "Files of this work").

Host commands of this phase against "Host commands and phone work": reading the diff
at RP, on every tip G runs on (set-up, at the host, before the merge); bringing each
host's checkout to the merged `main`, `create-ai-sandbox.sh` and re-creation (set-up,
at each host, once per sandbox; an opted-in sandbox keeps its choice, O4). Nothing is
added to everyday work, and nothing a phone could need.

## Assumptions

| # | Assumption | Status | Settled by |
|---|---|---|---|
| PA1 | A request made with `--audio` after this phase is remembered like every other option of create; the spec's "does not count as a request" applies to the value remembered "from the time when on was the default" | verified: settled by the spec (the author's answer to Q1: U1 "on per sandbox", C-MODULES "options remembered in `.env`", no exception for audio; tree: a stored `--display` is kept for the same reason) | - |
| PA2 | Nothing reads the value of `SANDBOX_WITH_AUDIO` but create | verified for the repository (S2) and the knowledge repository (S7); guessed for project code inside a sandbox | if it fails, such code sees `2` instead of `1` in an opted-in sandbox |
| PA3 | The test environment has no `/dev/snd`, so the device case needs the seam | verified (P2); the seam makes the case independent of the machine | - |
| PA4 | A stubbed `xpra` mode generates the compose file under `--no-start` | verified in the tree (S13; `test-resources.sh` passes on the base, spec A4) | - |
| PA5 | Phase 1 changes no audio line in create or test-devices.sh | verified at `7156737` (evidence, "Re-run on the chosen base", item 2: empty, known case 25); T09, T10 and T12 are still to come | the evidence file's last section, when the other branch lands on `main` |
| PA6 | `.env` reaches the container's environment | verified (S11, P1) | - |
| PA7 | I3e, for this phase, concerns the host sockets a sandbox is given, the display's excepted | the spec's author: the wording is wider than the phase and is the defect (`author-answers.md`, Q2); rests on S-4, not yet approved | the user's decision on `spec-change-I3e.md` |

## Left out (no trigger found, or a failure no user reaches)

Refusing at start a sandbox that still shares sound (I6 lets it keep working; batch B
lists such sandboxes). A notice for a `.env` without the audio key (trigger: a sandbox
never re-created since the key was added; phase 1's B2 re-creates every sandbox, and
O1's line still says audio is not shared). Rewording the doctor's `audio unavailable`
(it already means "no sound server reachable" for `--no-audio`). The agents'
environment-block sentence on what is visible under `/dev`, inexact only in an
opted-in sandbox with a display, as today. A host check of whether the sound server
acts on a sandbox's request: this phase removes the reach by default, and an opted-in
sandbox is accepted residual risk (spec). Removing the sound client packages from the
image (opted-in sandboxes use them). A playback-only path (phase 10).

## Phase 1's overlap (re-run on 2026-11-12)

Phase 1's branch at `7156737` (T09, T10 and T12 still to come) against `dd0146a`,
recorded in the evidence file's section "Re-run on the chosen base": no audio line
changed; `test-devices.sh`, `test-resources.sh` and `harness.sh` untouched; one stub
change for `docker run`, not reached under `--no-start`; S1 to S5, S15, S16 and R1 to
R5 keep their counts, with create's line numbers shifted by up to 31. T12 will edit
create's usage text and comments again (phase 1 plan); the knowledge parts, not the
audio options, are its subject, and the merge commit's re-run (item 2) shows it. The
impact set and line numbers above are those of `dd0146a`.

## Questions settled by the spec's author

`author-answers.md` in the evidence directory (Hania, 2026-11-12):

- **Q1 Is an `--audio` given after this phase remembered?** Settled by the spec:
  yes, answer (a). U1 makes audio a choice of the sandbox; C-MODULES gives the options
  of creation one convention, "options remembered in `.env`", with no exception for
  audio; the phase 2 block's sentence concerns only
  the value the old default wrote, which cannot be told apart from a request. PA1,
  O4 and the data shape stand. Because O4 rests on this reading, the wording edit
  that writes it into the phase 2 block is part of S-4's option (a)
  (`spec-change-I3e.md`, change 2).
- **Q2 Does I3e reach the display servers?** A gap in the spec's text: read literally
  no phase establishes I3e, since every display mode but `none` talks to a server on
  the host. Recommended: narrow I3e (change S-4, `spec-change-I3e.md`), with O7 as
  its check. This is the user's decision below.

## Decision for the user

- **S-4, the narrowing of I3e** (`spec-change-I3e.md`).
  - (a) Approve both changes. I3e then covers the host sockets the toolchain gives a
    sandbox, the display's excepted, and the phase 2 block states that a request made
    with `--audio` from this phase on is remembered until `--no-audio` (change 2, which
    O4 rests on). Two things the old wording covered leave the invariant and become
    accepted residual risk, each with its own line: the display server a sandbox
    talks to by default (the host's compositor under `wayland`, which `auto` picks on
    a Wayland host; a server the host starts under `xpra` and `nested`), and host
    services listening on the address by which every sandbox reaches the host
    (`host.docker.internal`, mapped to the host gateway in every sandbox's compose
    file). Phase 2 proceeds as planned.
  - (b) Keep I3e as worded. Phase 2 must then also take the display servers, and the
    sandbox's route to services on the host, out of the default; for the display that
    is in effect `--display=none` by default, so windows of programs in a sandbox no
    longer appear unless asked for. The phase is re-planned.
  - **Recommended: (a).**
