Task: 2026-11-11-sandbox-hardening
Class: phase

# Phase 1 plan, round 2: answers to the review

Bartek (planner 2), 2026-11-12, a fresh agent in the phase planner's slot. Answers the
"Round 2" section of `plan-review.md` in this directory, for the third and last round
the user allowed (2026-11-12). Changed:
`docs/superpowers/plans/2026-11-11-sandbox-hardening-p1-plan.md` and its evidence file
`2026-11-11-sandbox-hardening-p1-plan.md` here. The versions before this round are kept
untracked for the re-review's diff:
`.tmp/security/2026-11-11-sandbox-hardening-p1-plan.pre-r3.md` and
`.tmp/security/2026-11-11-sandbox-hardening-p1-plan-evidence.pre-r3.md` (byte-equal to
the `.r2.md` copies). The tree is unchanged since round 2 (`4d6f677`). The fixture file
is unchanged; its SHA-256 is still the one B1a checks. Properties and keys only; inputs
are named by their class.

## N1 (Important): a pending close of a report could be dropped unpublished

**Variant: the removal is driven by the host**, like the other two removals inside.
Reason: only the host reaches the remote, and the base drops a report and its
tombstone only after the remote answered; a key the host writes from its own completed
fetch of the remote keeps that condition and keeps the classification on the host
(O17), while a "fetch completed" marker would still leave the decision to the origin's
content, read inside the sandbox.

Changed:
- Data block: new key `closed-report=<name>` in `status/knowledge`, integrator only,
  one per tombstone in the integrator's namespace whose report this sync's completed
  fetch of the remote's reports no longer finds; it names the report alone (PA12, as
  `pushed-report=`). A sentence states that every removal inside follows a key the
  host wrote, never the origin's content alone. The key is plan detail by the author's
  answer to Q1 (C-STATUS fixes the named keys; others of the same shape are the plan's);
  listed in "Read this first", item 6.
- O11: the integrator's command deletes a report and its tombstone only while the
  status file lists it `closed-report=`; an origin without the report is no signal.
- O18: the case the review asks for, with two triggers (first sync offline; lock
  busy): both refs survive the container's start, the report stays on the remote, the
  next sync that reaches the remote deletes it there and lists it, and the command then
  removes both refs.
- T06: removes refs inside only as the status file lists them; now cites O18 with T09
  and T10. T09: O18 moves to "with T10". T10: writes `closed-report=` and completes O18.
- "Who uses it": the state (trigger: the create's sync offline or the lock busy, the
  origin then holding none of the remote's reports, O10; B2) and the retry line.
- B2 step 2: a re-creation whose sync is offline or finds the lock busy loses nothing;
  run `sync --all` once the remote is reachable.
- O10: unchanged. Its property (the origin's refs after a sync, an empty origin before)
  still holds; the fix removes the reading of the origin as the remote's answer, which
  was O11's.
- Impact set: `closed-report` joins the new names (S20c, 0 on the base).

## Lesser findings

| Item | Outcome | Where |
|---|---|---|
| N2 B2's ref line fails on the host's own `proposal/*` branches | fixed | B2 step 3 and H: the refs outside the host's namespaces, with their commits, are listed before the sync and compared after it (expected `same`); the before-list is explained (branches left by the migration's `ai-knowledge propose` calls, the host's own); a diff line means H is not passed and goes to the planner and the spec's author. The command was checked on a scratch repository: unchanged refs give `same`, two added refs outside the namespaces give two diff lines. |
| N3 B2 step 3 has no control | fixed | B2 step 3: markers left inside by an earlier attempt are removed first; the plant step prints `planted` (a refusal: undo and start again); before the undo, the markers inside are listed for the record and the fixture's `control` must print `live`, otherwise step 3 is repeated, not passed. H names the control. |
| N4 O3's "quoted or not" not pinned | fixed (claim kept, cases added) | O3: the known case adds a quoted command name in double quotes, in single quotes and quoted with a path, and a quoted argument of a wrapper: 10 reports. Evidence, "Structural search": the rule's `command_name` line now admits quotes; on the scratch file round 2's rule gave 7, the revised one 10; on the base the counts stay 106 and 123. R1b's pattern also matches a quoted or path-qualified command name; on the base it gives the same 177 lines (`diff` empty), so the 57-line classification stands. |
| N5 O14's stamp-1 case starts from a later layout | fixed | O14: the stamp-`1` cases start from a sandbox directory as the base left it (no `status/`, no `knowledge-origin.git`). |
| N6 B1b's stop question and order key | fixed | B1b prints the integrator named in the host's knowledge configuration (the value the migration reads), or `none`, in place of the README line; the order rule names that line; step 2 says the stop question is asked once for all running stale sandboxes and what to answer. The changed block passes `bash -n`, and prints the configured value and `none` on a scratch home. |
| N7 O15's host clause | fixed | O15 keeps the tree check only; RP1 names `a3.md` as its condition (T08 already did). |
| N8 a second sandbox's namespace | fixed | O19: the namespace of a second sandbox is the same after `sync <project>` of the first as before; the direct case of the lib function (below) keeps a second prefix unchanged too. |

## R10: `FETCH_HEAD`

Added. R10 gains `command grep -rnaF 'FETCH_HEAD' bin/ai`, expected empty. Base: empty
(evidence S26, with a known case). The impact-set row for short names now covers it.

## The spec author's suggestion: the confined fetch in `ai-sandbox-lib.sh`

**Taken.** The fetch is the property S-3 proposes to bind phases 4 and 6 to; one
function in the lib keeps that rule in one place and tested once, and costs phase 1
only its location and one contract line, while leaving it in `ai-knowledge` would make
phase 4 move code out of a host-executed file. Changed: contract block,
`ai_sandbox_confined_fetch <repository> <prefix> <root> <subdirectory> <ref pattern>...`
(each `refs/<name>/*` of the served tree lands as `<prefix>/<name>/*`, pruned below the
prefix, no ref outside it changes; the prefix's conditions follow S-3's final text and
hold for phase 1 whether or not S-3 is approved); T09 adds it to the lib; O19 adds a
direct case in `test-confined-git.sh` with its own negative case; the data block's
sentence and "What the plan becomes" name it; "Read this first", item 6; new names
(S20c, 0 on the base).

## Findings that need a decision

None. N1's variant follows from the plan's and the spec's own terms (above); N2 to N8
had one fix each; the new status key is plan detail by the author's answer to Q1.
