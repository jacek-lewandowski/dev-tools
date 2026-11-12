Task: 2026-11-11-sandbox-hardening

# Phase 2 plan review (round 1)

Fiona, reviewer 1, 2026-11-12. Object: `docs/superpowers/plans/2026-11-11-sandbox-hardening-p2-plan.md`,
its evidence file, `author-answers.md` and the proposed change S-4 (`spec-change-I3e.md`),
against the spec at `dd0146a` and the tree (main checkout, code identical to `dd0146a`;
phase 1 at `7156737`, read-only).

**Verdict: not accepted.** 3 Important, 6 Minor. The Important findings return to the
planner (I1, I2) and to the spec's author (I3); a delta re-review follows.

Re-run, exactly as recorded, with matching results: S1 (12), S2 (5), S3 (15), S4 (25),
S5 (144, 771), S6 (3 files, 11 lines), S7 (no file; known case 7), S8 (empty; known
case 7), S9, S10 (empty; known case 8), S14, S16 (29 on both trees), R1 to R5 on the
base, item 2 (empty; known case 25), item 4 and the hunk list on `7156737`. My own
search for sockets S16's pattern cannot match (agent, D-Bus, keyring and Docker
sockets, `/var/run`, every `add_vol`, `- "` and `printf` bind line of the compose
writer) found no other host socket, and no composed `SANDBOX_*` key name. No detail
of the untracked review (commands, modules, reproduction steps) appears in the four
files.

## Important

- **I1 Batch B covers one host only.** Place: plan, "Batch B", steps 1 and 2. The
  user has more than one host (phase 1's B1 runs "on every host"; its B2 step 1 brings
  each host's checkout to the merged `main` first). Batch B lists only
  `~/.ai-sandbox` of the host it runs on and never updates another host's checkout.
  Failure: on a second host every re-creation runs the code from before this phase,
  writes `1` again and keeps the sound socket, so C2 stays open there and I3e does not
  hold. Correction: a first step "on every host with sandboxes, bring the checkout to
  the merged `main`" (as phase 1's B2 step 1), steps 1 and 2 run on each host, and the
  verdict recorded per host; the order cases apply per host.
- **I2 Host output goes into a committed file.** Place: plan, "Batch B", step 2:
  "Paste back the output; the lead records it in `host.md`". The spec ("Files of this
  work") keeps logs of host runs untracked under `.tmp/security/` and records only
  their verdict; step 2's output names the user's sandboxes and projects. Correction:
  the lead keeps the output under `.tmp/security/` and records only the verdict
  (`none`, or the count of opted-in sandboxes) in `host.md`, as phase 1 does.
- **I3 S-4 narrows I3e a second way that no spec text records.** Place:
  `spec-change-I3e.md`, change 1, paragraph "Also narrowed"; plan, "Decision for the
  user". Today every sandbox gets `host.docker.internal:host-gateway`
  (`create-ai-sandbox.sh` 2281), so host services listening on that address are within
  reach; the old I3e covered them, the new one does not. The paragraph saying so is
  not part of the text inserted into the spec, and the plan's decision summary names
  only the display server. Failure: once applied, neither invariant nor residual risk
  says a sandbox reaches host network services, so phase 10 and its independent review
  plan against a spec that silently dropped them, and the user approves (a) without
  that loss in front of them. Correction: add a residual-risk line (host services
  listening on the address a sandbox reaches the host by) to change 1, and name it in
  the plan's decision for the user.

## Minor

- **M1 Read point RP.** Place: plan, "Read point RP" and "When phase 1 adds commits".
  It does not say that RP is read again when the other phase lands after RP and G runs
  on a new tip, though that merge commit can change `bin/ai`; it reads only `bin/ai`,
  without phase 1's `--stat` over every path, so a change elsewhere the host runs (for
  example `.githooks/`) is not shown; and the reading is missing from the host
  commands line. Correction: RP repeats on every tip G runs on, starts with
  `--stat` over the same range, and is listed as set-up at the host.
- **M2 Change 2 left optional.** O4 (a bare run after `--audio` keeps audio on) rests
  on the reading change 2 writes down; without it the phase review checks O4 against
  "a re-creation without an explicit `--audio` turns audio off". Correction: make
  change 2 part of option (a).
- **M3 "Run B2 instead" loses a wanted `--audio`.** Place: Batch B, third order case.
  B2's commands are bare, so a sandbox the user wants sound in loses it (O2's notice
  says so afterwards). Correction: tell the user to add `--audio` to B2's command for
  such a sandbox, as step 1 does.
- **M4 R1 forbids the natural wording of O2's notice.** "Audio used to be on by
  default" matches R1 and fails the residue check. Correction: say so in O2 or T01.
- **M5 Merge procedure for phase 1 landing second.** Place: "When phase 1 adds
  commits". The merge commit, suites, delta review and gate re-run then bind phase 1's
  branch, but only the RP1 range is carried to phase 1's plan. Correction: carry the
  whole procedure, and the re-run of this plan's last evidence section, with it.
- **M6 A claim rests on the untracked review.** Place: `author-answers.md`, Q2, "What
  the new wording claims": the host sockets a container gets are cited from the
  review's table. Correction: cite S16 (the tree) instead and drop the review's
  contents from the committed file.

Context: about 95k tokens.

## Round 2

Fiona, reviewer 1, 2026-11-12. Delta read: the plan's "Read this first", "Base and
branches", O2, "Batch B", host commands line, Q1 and "Decision for the user";
`spec-change-I3e.md`; `author-answers.md` (header, Q1, Q2). The `extra_hosts` claim
was checked in `create-ai-sandbox.sh` (2277-2281; its comment says the host is
reachable "by name when deliberately needed").

**Verdict: accepted.** 0 Critical, 0 Important, 1 Minor (new).

Round 1 findings, each closed:
- I1: Batch B now runs steps 0 to 2 on every host, step 0 updates each host's
  checkout to the merged `main`, and the order cases apply per host.
- I2: the output stays under `.tmp/security/`; `host.md` holds only the verdict per
  host.
- I3: change 1 adds the second residual-risk line (host network services at
  `host.docker.internal`); the plan's decision names both lines.
- M1: RP starts with `--stat` over every path, is taken again on every tip G runs on,
  and is listed among the host commands.
- M2: change 2 is part of option (a) in S-4, in the plan's Q1 and in its decision.
- M3: the "run B2 instead" case tells the user to add `--audio`.
- M4: O2 tells the implementer to avoid the phrase R1 searches for.
- M5: the five-step second-landing procedure and the re-run of the evidence section
  are carried to phase 1, with RP1's `merge-base` form.
- M6: the claim about host sockets rests on S16; the review's contents are gone.
  `author-answers.md` names findings by key only.

The decision matches S-4: (a) covers both changes and both residual-risk lines;
(b) removes the display servers from the default and the sandbox's access to host
services.

New Minor:
- **M7 Option (b) of S-4 overstates what dropping the name does.** Place:
  `spec-change-I3e.md`, "Options for the user", (b): "stop giving a sandbox the address
  `host.docker.internal`, so the host's services are no longer reachable from it".
  The `extra_hosts` entry only names the bridge gateway. Without it, a sandbox on the
  bridge network still reaches host services listening there by IP. The plan's
  decision is more accurate ("the sandbox's route to services on the host"). Failure:
  none under (a). Under (b), a re-plan that removed only the name would still leave
  the services reachable. Correction: make S-4's (b) say "the sandbox's route to
  services on the host", as the plan does.

Context: about 105k tokens.
