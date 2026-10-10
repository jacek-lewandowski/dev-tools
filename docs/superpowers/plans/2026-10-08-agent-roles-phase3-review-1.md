# Review of the phase 3 plan (spike S4), round 1

Date: 2026-10-08. Verdict: **not ready to run** (2 important, 2 important-adjacent). Decision
rules for A21, A22, A23 and scratch/ are copied unchanged; T6 correctly flags the container limit.

## Important

1. **T1/T8: no guaranteed restore and cleanup when a task fails midway.** If T4 or T5 aborts or the
   implementer is cut off, an agy run, the worktree, canaries or a tmpfs namespace stay behind and
   the settings file stays as agy last rewrote it. Resolution: T8 is mandatory on every exit path,
   including a stop-and-ask in T5; `pgrep -a agy` must be empty before the restore; record `ls -l`
   of the settings file before and after, plus hash and `diff`.
2. **T1: the host-backed check covers only ~/.gemini.** `~/.config/s4-canary/` and `~/s4-empty/`
   are created without checking whether `$HOME` or `~/.config` is a host bind mount. Resolution:
   `findmnt -T` on every canary and directory path and on `~/.gemini/antigravity-cli` before
   creating anything; abort if any is host-backed. State in T7 that the main-tree canaries under
   `<top>/.ai-delegate/` are real host-tree writes (the brief prescribes them).

## Important-adjacent (same pass)

3. **T4: the control may not control anything.** The harness may already export TMPDIR. Record
   `echo $TMPDIR` first and run the control with `env -u TMPDIR`. File existence on disk, not the
   model's answer, decides a write test. A partial result (reads follow TMPDIR, writes do not)
   counts as "does not work" for D24.
4. **T5: the fake home layout is unspecified.** Mirror the real relative path
   (`.gemini/antigravity-cli/settings.json`) under the fake HOME; define the layout for the
   XDG_CONFIG_HOME and ANTIGRAVITY_EXECUTABLE_DATA_DIR variants; add a positive control (a rule
   that `/config` shows only if the file was read). If sign-in needs credentials, record "blocked
   on the user's decision, default no change" (not "cannot"), and still run T6-T8.

## Lesser

- T2: the A23 and TMPDIR canaries share the name `c.txt` under `.ai-delegate/`; use unique names.
- T2-T4: add a "not attempted" outcome; a run where the model never called the tool is not a
  denial; require the tool name on stderr or in the JSON for any "denied".
- T2 acceptance says six outside runs; four prompts repeated once is eight.
- T7: state how T3 and T4 combine (if scratch/ is readable and only TMPDIR works, D24 closes for
  /tmp but scratch/ stays residual, since TMPDIR does not cover ~/.gemini).
- T7: the created/removed table should also list what stays: agy's conversation records under the
  host-backed `~/.gemini/antigravity*/{brain,conversations}` (left untouched, but they conflict with
  the brief's "no file outside the scratchpad changed").
- T6: compare the tmpfs mount count before and after instead of a noisy `grep -c`.
- T1: the settings backup sits in the scratchpad under /tmp, which T4's control can write; record
  the hash in the notes too.
