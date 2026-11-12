Task: 2026-11-11-sandbox-hardening
Class: phase

# Phase 2 plan: searches and probes behind the impact set

Written by Ola (planner 3) on 2026-11-12 inside the dev-tools sandbox, against `dd0146a`
(`main`). Plan: `docs/superpowers/plans/2026-11-11-sandbox-hardening-p2-plan.md`.
The first draft planned phase 2 after phase 1's merge; the plan now starts phase 2
from `dd0146a` in parallel with phase 1. The list was re-run on that base and on phase
1's tip ("Re-run on the chosen base" below, which supersedes the draft-time section
"Re-run at phase 1's close"); what is re-run when the other branch lands on `main` is
the last section.

Method. Every search was run from the repository root with `command grep` and `-a`:
the interactive `grep` in this sandbox is a shell function that skips ignored and
binary files (`type grep` prints `grep is a function`), so `command` bypasses it and
`-a` reads every file as text. Findings are named by key and inputs by class only (the
spec's section "Inputs", change S-1).

## Tree

- `git diff --quiet 4d6f677 dd0146a -- bin tests tools PROJECT_MAP.md README.md verify-ai-sandbox-on-host.sh && echo identical`
  prints `identical`: the code is the spec's base plus nothing; `dd0146a` adds only
  documents (the spec's changes S-1 to S-3 and E2, the phase 1 plan).

`T` below stands for the search scope
`bin tests tools .agents PROJECT_MAP.md README.md docs/shared-knowledge.md verify-ai-sandbox-on-host.sh`
(every tracked place outside `docs/superpowers/`, whose design documents keep their
history on purpose), and `C` for `bin/ai/create-ai-sandbox.sh`.

## Searches

- **S1, the audio variables in create.** `command grep -naE '\bWITH_AUDIO(_EXPLICIT)?\b' $C`:
  12 lines. 95 default `WITH_AUDIO="yes"`, 96 `WITH_AUDIO_EXPLICIT="no"`; 256, 257 the
  two options; 494, 497, 498 the remembered value; 775 the socket branch; 883 the
  device branch; 1020 the agent environment block's capture-tools line; 2197, 2214 the
  `.env` writer. The `\b` keeps `SANDBOX_WITH_AUDIO` out (an underscore is a word
  character); S2 counts it.
- **S2, the stored key.** `command grep -rnaE 'SANDBOX_WITH_AUDIO' $T`: 5. Create 495
  (reader), 2214 (writer: `"1"` when audio is on, whether by default or by `--audio`,
  else `"0"`; the spec's "written for both cases"); `tests/ai-sandbox/test-devices.sh`
  45, 50, 60. No other reader in the repository.
- **S3, the mounts and the rule.** `command grep -rnaE 'sandbox-pulse|PULSE_SERVER|PULSE_SOCKET|/dev/snd|116:\*' $T`:
  15. Create 10: 774, 777-779, 782 (socket), 883-886 (device and rule, only when the
  display mode is not `none` and the directory exists), 1695 (the doctor's `audio`
  line, inside the image); test-devices.sh 5: 44, 49, 57, 59, 62.
- **S4, the option names.** `command grep -rnaE -- '--(no-)?audio\b' $T`: 25. Create
  13: usage 143, 147; parsing 256, 257, 273, 274, 282; messages 497, 498, 776, 780,
  782; comment 771. test-devices.sh 12. Nothing else in the repository.
- **S5, "on by default".** `command grep -naiE 'on by default' $C`: 144 (usage of
  `--audio`) and 771 (comment of the audio section). Both concern audio; no other
  feature of create uses the phrase.
- **S6, audio wording anywhere else.** `command grep -rlaiE 'audio|pulse|microphone' $T`:
  `bin/ai/create-ai-sandbox.sh`, `bin/video/recode-video` (an ffmpeg bitrate, unrelated),
  `tests/ai-sandbox/test-devices.sh`. `PROJECT_MAP.md`, `README.md`,
  `docs/shared-knowledge.md`, `.agents` and `verify-ai-sandbox-on-host.sh` say nothing
  about audio, so no document states the old default. Inside create,
  `command grep -naiE 'pulse' $C` gives 11 lines: the audio lines of S3 and S4, the
  section comment (772), the image's sound client packages (1971, kept: an opted-in
  sandbox uses them) and the host xpra server's own sound forwarding, switched off
  (2610, unrelated to the shared socket).

## Residue searches on the base

The plan's R1 to R5, run on `dd0146a` with the commands as the plan states them:
R1 2 lines (144, 771); R2 3 lines (create 2214, test-devices.sh 45, 60); R3 1 line
(95); R4 5 lines (test-devices.sh 44, 45, 46, 47, 62); R5 2 lines (883, 884). Each
returns the old shape on the base, so each is shown able to find it.
- **S7, outside the repository: the knowledge repository.**
  `command grep -rlaE 'SANDBOX_WITH_AUDIO|--audio|--no-audio|sandbox-pulse' ~/knowledge`:
  no file (exit 1). Known case, same method: `command grep -rlaE 'sandbox' ~/knowledge`
  lists 7 files, so the search reads the clone.
- **S8, other tests.** `command grep -rnaE 'parec|paplay|pactl|/dev/snd|116:|pulse' tests/ | command grep -v test-devices.sh`:
  empty (exit 1). Known case: `command grep -rnac 'pulse' tests/ai-sandbox/test-devices.sh`
  gives 7. Only `test-devices.sh` depends on the audio default.
- **S9, the test-seam convention.** `command grep -naE '^readonly [A-Z_]+="\$\{[A-Z_]+:-' $C`:
  80 `IDEA_HOST_DIR`, 83 `HOST_ETC_DIR` (comment: "Overridable so the tests can stand
  in a fake"). `tests/ai-sandbox/test-resources.sh` sets `HOST_ETC_DIR` for its
  timezone cases.
- **S10, new name.** `command grep -rnaF 'HOST_SND_DIR' bin tests tools`: empty
  (exit 1). Known case, same command with `HOST_ETC_DIR`: 8 lines.
- **S11, `.env` reaches the container.** Create's compose writer (`COMPOSE_ENVFILE`
  heredoc, 2320-2322) gives the service `env_file: - .env`, so every managed key,
  `SANDBOX_WITH_AUDIO` included, is in the container's environment.
- **S12, how the suite finds files.** `tests/ai-sandbox/run-tests.sh` runs every
  `test-*.sh` in its directory; a case added to `test-devices.sh` needs no
  registration.
- **S13, the display mode in tests.** `tests/ai-sandbox/test-resources.sh` (the
  "xpra" block): stubs for `xpra`, `Xvfb`, `xauth` and `mcookie` on `PATH` let
  `--display=xpra --no-start` generate the compose file. The audio cases of
  `test-devices.sh` all use `--display=none`, under which the device branch never
  runs.
- **S14, output helpers.** `command grep -naE '^(log|warn|step)\(\)' $C`: 296 `log`
  (standard output), 297 `step`, 298 `warn` (standard error, `!!` prefix). The
  reduced-isolation notice of `--with-docker` is a `warn` (the devices section).
- **S15, other host sockets by display mode** (for question Q2 of the plan).
  `command grep -naE 'WAYLAND_DISPLAY|X11-unix' $C`: 24 lines; read with the display
  section. The `auto` mode picks `wayland` when the host has a Wayland session (543),
  and the `wayland` branch mounts the host compositor's socket (`add_vol` of
  `host_wl`, 673); the `xpra` and `nested` branches mount a
  per-sandbox X socket directory (686, 699); `host` mounts the host's X socket
  directory (714) and, with a Wayland session, its socket (716-720).

## Probes

- **P1, the old value in a running sandbox.** In this sandbox (created before phase 2,
  no audio option): `env | command grep -E '^SANDBOX_WITH_AUDIO=|^PULSE_SERVER='` prints
  `SANDBOX_WITH_AUDIO=1` and `PULSE_SERVER=unix:/run/sandbox-pulse`, and
  `ls -l /run/sandbox-pulse` shows a socket. The old default is live here, and S11's
  `env_file` is confirmed.
- **P2, no sound device directory in the test environment.** `ls -ld /dev/snd`:
  "No such file or directory". The device branch tests the fixed path `/dev/snd`, so
  without a seam the suite cannot show the device mount or the rule in the `--audio`
  case, which the spec's closing check needs.

Not run: the suite, and `create-ai-sandbox.sh` itself (the phase 1 implementer runs
the suite in this 1-CPU sandbox). The base suite result is the spec's A4 (20 files,
1217 cases, 2 failing in `test-delegate.sh`, cases 54 and 59), measured on `4d6f677`,
whose code `dd0146a` carries unchanged.

## Phase 1's overlap with the files this phase touches

Read in `docs/superpowers/plans/2026-11-11-sandbox-hardening-p1-plan.md` (tasks and
impact set): phase 1 edits `create-ai-sandbox.sh` in T01 (identity, image tag, helper
install), T02 (project resolution), T04 (the doctor's status lines), T05 (knowledge
directories), T07 (the `.env` writer's `SANDBOX_KNOWLEDGE` value, the doctor), T12 (the
usage text and comments), and adds test files and stubs (T03, T09, T11). No task names
audio. Phase 1's impact-set row "Knowledge strings in create" lists the usage lines
175-211, the environment block 1050-1056, the doctor 1598-1623, `.env` 2215-2218 and
the compose lines 2306, 2361-2372: neighbours of S1 to S3, not the audio lines.

## Re-run at phase 1's close (draft-time list, superseded below)

Against the merged tree, before the plan goes to review:
1. S1 to S6, S8 to S11, S13 to S15 unchanged as commands; expected: the same lines
   with new numbers, the same counts (S1: 12, S2: 5, S3: 15, S4: 25, S5: 2, S15: 24).
2. `git diff <phase 1 base> <phase 1 merge> -- bin/ai/create-ai-sandbox.sh tests/ai-sandbox/test-devices.sh | command grep -naiE '^[-+].*(audio|pulse|snd|116:)'`:
   expected empty (phase 1 changes no audio line).
3. The phase 1 gate's summary for `test-devices.sh` (`0 failed`) and the
   `test-delegate.sh` failures by case number (the D15 cases), for this plan's gate G.
4. Whether phase 1 changed `fake_home`, the stubs or `log`/`warn` in a way the audio
   cases use (`git diff <phase 1 base> <phase 1 merge> --stat -- tests/ai-sandbox/harness.sh tests/ai-sandbox/stub`).

## Re-run on the chosen base (2026-11-12, Ola)

Phase 2 starts from `main` with the code of `dd0146a`, in parallel with phase 1 (the
plan, "Base and branches"), so the list above was re-run on that tree rather than on a
merge of phase 1, and once more on phase 1's branch tip `7156737` to see what phase 1
moves. Same method: `command grep -a`, from each tree's root, `T` and `C` as above.

- **Tree.** Main checkout at `dd0146a`, `git status --short -- bin tests tools` empty;
  `git diff --quiet 4d6f677 dd0146a -- bin tests tools PROJECT_MAP.md README.md verify-ai-sandbox-on-host.sh && echo identical`
  prints `identical`.
- **Item 1, S1 to S15, on `dd0146a`.** Every command as recorded above, unchanged.
  Every count and every line number equals the list above: S1 12, S2 5, S3 15, S4 25,
  S5 2 (144, 771), S6 the same three files and 11 `pulse` lines in create, S7 no file
  (exit 1; known case 7 files), S8 empty (exit 1; known case 7), S9 lines 80 and 83,
  S10 empty (exit 1; known case 8), S11 2320-2323, S14 296-298, S15 24. Nothing in the
  plan changes on this base.
- **R1 to R5 on `dd0146a`.** R1 144, 771; R2 create 2214, test-devices.sh 45, 60;
  R3 95; R4 test-devices.sh 44, 45, 46, 47, 62; R5 883, 884. As above.
- **The same on phase 1's tip `7156737`** (in its worktree, read-only). Every count
  unchanged; create's line numbers move by +1 to +31: S1 95 96 257 258 501 504 505 780
  888 1025 2222 2240; S2 create 502, 2240, test-devices.sh 45, 50, 60; S3 15 (create
  779-787, 888-891, 1715; test-devices.sh unchanged); S4 25; S5 145, 776; S11
  2351-2354; S14 297-299; S15 24; R1 145, 776; R2 create 2240 and test-devices.sh 45,
  60; R3 95; R4 unchanged; R5 888, 889.
- **Item 2, phase 1's audio lines.**
  `git diff dd0146a 7156737 -- bin/ai/create-ai-sandbox.sh tests/ai-sandbox/test-devices.sh | command grep -naiE '^[-+].*(audio|pulse|snd|116:)'`:
  empty (exit 1). Known case, the same filter on a diff that holds audio lines:
  `git diff 4b825dc642cb6eb9a060e54bf8d69288fbee4904 dd0146a -- tests/ai-sandbox/test-devices.sh | command grep -ciE '^[-+].*(audio|pulse|snd|116:)'`
  gives 25. Phase 1 so far changes no audio line (PA5 holds at `7156737`; T09, T10
  and T12 are still to come).
- **Phase 1's overlap, by file.** `git diff --stat dd0146a 7156737 -- tests/ai-sandbox/test-devices.sh tests/ai-sandbox/test-resources.sh`:
  empty. `git diff --stat dd0146a 7156737 -- bin/ai/create-ai-sandbox.sh`: 84 lines
  changed. Its hunks, as base line ranges
  (`git diff -U0 dd0146a 7156737 -- bin/ai/create-ai-sandbox.sh | command grep -E '^@@'`):
  108-109 (the usage paragraph on project resolution; the audio options are 143-147),
  369 (project resolution), after 462 (the knowledge origin), 526-530 (the image
  name), after 1489 (the entrypoint's knowledge sync), 1598-1623 (the doctor's status
  and knowledge lines; the doctor's `audio` line is 1695), after 1899, 2074 and 2084
  (the image's copy of the in-sandbox sync command), 2188-2189 (the host identity for
  git), after 2203 (a `KNOWLEDGE_STAMP` variable for the `.env` writer), 2216-2218
  (the `SANDBOX_KNOWLEDGE` comment and value; `"SANDBOX_WITH_AUDIO": ...` is 2214, with
  one unchanged line, 2215, between), after 2306, 2311, 2358, 2372 (compose
  environment, status and origin mounts) and after 2712 (the helper install). Only the
  `.env` writer's hunk is near a line phase 2 changes.
- **Item 4, the harness.** `git diff dd0146a 7156737 --stat -- tests/ai-sandbox/harness.sh tests/ai-sandbox/stub`:
  `tests/ai-sandbox/stub/docker | 19 +` only, a `run)` branch for the confined git
  container. `create-ai-sandbox.sh --no-start` starts no container, so the audio
  cases do not reach it; `harness.sh` (`fake_home`) is unchanged.
- **Item 3, the D15 cases.** Not a gate run of mine. Phase 1's recorded suite runs at
  T08 and T11 (`docs/superpowers/evidence/2026-11-11-sandbox-hardening-p1/T08-remove-migration.md`,
  `T11-host-git-rule.md` on its branch) list `test-delegate.sh` cases 54 and 59 as the
  only failures, the same numbers as the spec's A4 on the base.
- **P3, the base's audio cases.** `bash tests/ai-sandbox/test-devices.sh` on `dd0146a`
  in the main checkout: `17 run, 0 failed` (exit 0).

## S16, host sockets a sandbox's compose file can bind (for O7)

The spec's author proposes narrowing I3e to "no host daemon's socket but the
display's" (`author-answers.md`, Q2); the plan's O7 checks it. Run on `dd0146a`:
`command grep -naE 'XDG_RUNTIME_DIR|/run/user/|/tmp/\.X11-unix|\.sock\b' $C`: 29 lines
(29 on `7156737` too). Read one by one:

- Host-side binds or the paths they are built from: 543 (the `auto` mode's Wayland
  test), 566 and 595 (the per-sandbox X socket directory of `xpra` and `nested`),
  664-673 (`wayland`: the host compositor's socket), 686 and 699 (`xpra`, `nested`:
  the per-sandbox X socket directory), 714-720 (`host`: the host's X socket directory
  and, with a Wayland session, the compositor's socket), 774-779 (the sound socket).
  All are in the display section except 774-779.
- Inside the image or the container, not a host bind: 1410-1464 (the entrypoint's own
  runtime directory and the inner Docker's socket under `--with-docker`), 1582
  (the doctor), 1827, 2088, 2156-2158 (the Dockerfile), 2300 (the container's
  `XDG_RUNTIME_DIR`), 2493 and 2517 (the host's display launcher writing into the
  per-sandbox X socket directory).
- The other bind lines of the compose writer (its `volumes:` heredocs, 2326-2420) name
  the project, the tools, the per-sandbox state directories, the build caches, the
  shared knowledge and brain files and the Claude project directory: directories and
  files, no runtime directory and no socket.

So with audio off, the only host socket a default sandbox binds is its display's,
which is what the narrowed I3e states. The read is by hand over the hits of one
search; the executable part of O7 is the test case named in the plan.

## Re-run when the other branch lands on `main`

Phase 2's branch takes `main` in by a merge once phase 1 has landed there (or phase 1
takes phase 2's merge in, the other order; the plan, "Base and branches"). On the
branch that takes the merge, before its review or, if the review has already
accepted the tree, before the gate runs again:
1. Item 2 with `<p1 base>`=`dd0146a` and `<p1 tip>` the phase 1 commit merged:
   expected empty; a non-empty result is brought to the planner before the merge
   commit is reviewed.
2. Item 4 over the same range: a change to `fake_home`, `log` or `warn` is read
   against O1 to O7's cases.
3. R1 to R5 and S16 on the merged tree: R1 to R5 as the plan states; S16 29 lines
   plus whatever phase 1 added, each new host-side hit classified as above.
