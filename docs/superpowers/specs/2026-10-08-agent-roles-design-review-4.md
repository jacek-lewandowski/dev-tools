# Review of spec revision 4 (round 2 of review 3)

Date: 2026-10-08. Verdict: **blocked**. Findings 2-6 of review 3 resolved; #7 partly.
Both review rounds are used; finding A is the third with the same root cause, so per global §5
it is answered by a redesign (see the brief, "Decisions after review 4").

## A. Requests still let the lead read secrets (same root cause as review-3 #1)
Agent-supplied command strings, run through a shell, filtered by a deny list of options:
1. Shell expansion is not excluded: `git log -1 --format=$SOME_TOKEN` expands an env variable
   into the output (S1 recorded a messaging token in the environment); same for `~`, globs, braces.
2. Option values naming files are unchecked: `git blame --ignore-revs-file=<any file>`, `-S <file>`.
3. Secret patterns are not applied: `git show HEAD:id_ed25519`, `diff config/x.pem README.md`
   pass "tracked file inside the top level"; `git log -p` shows secrets committed and later deleted.

## B. Phase 2 contract contradicts native runs
It requires every delegable role text to say the agent "writes nothing and runs no command", but
role files are shared with native runs (I2): the native writer writes outputs and runs `check:` and
`extract:` (D5, D14); the runner runs commands by definition. Resolution: keep "no writes, no
commands, use `requests`" in the wrapper's standard prompt lines only; limit the phase 2 wording to
"lists needed output under `requests` when it cannot run commands", or restrict it to the scout and
the second reviewer.

## C. `--continue` has no channel for request output
`run <brief> [--continue <report>]` takes no extra inputs, and C3 refuses `inputs` for the scout, so
a scout's requests can never be answered. Resolution: a defined channel for request results (and
answers to `open_questions`) on `--continue`, allowed for every route.

## Lesser
- C6 step 2 should be `git diff --binary --no-ext-diff --no-textconv HEAD` (a user's
  `diff.external` or textconv would run a program, against I5, and corrupt the patch).
- `git ls-files -o`/`-i` and plain `git status` expose untracked and ignored file names.
- `--print-timeout` has no value when the brief has no `timeout`; the order of the sign-in check
  and the `/config` read is unstated.
