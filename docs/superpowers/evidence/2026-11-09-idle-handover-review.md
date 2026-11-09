# Review: idle handover timer (2026-11-09), round 1

Reviewer: Fiona, reviewer 1. Class: small, two changes on one review.
Object: `~/knowledge` e65f1c2 (Change A); dev-tools 9b92435, 28f417a (Change B).

Verdict: **not accepted**: two Important findings, both in Change B (one also
needs a sentence in Change A).

## Run

- `python3 -m unittest tools.context_statusline.test_statusline` (dev-tools,
  clean tree at 0b22685): `Ran 21 tests in 0.023s / OK`.
- Word count `rules/global.md`: 5787 before, 5823 after, as recorded.
- Scratch reproduction of I1 (fake projects dir in the scratchpad, real
  `mark.main` and `render`): from `cwd=/work/proj` the line shows
  `? -- | handover ready`; from `cwd=/work/proj/sub` with the same
  `CLAUDE_CODE_SESSION_ID`, rc 0, "marked .../-work-proj-sub/sess1/handover-ready",
  line `? --`, and a new directory `-work-proj-sub` created under `projects/`.

## Important

**I1. `tools/context_statusline/mark.py` `find_session`: the mark lands in the
wrong project directory when the caller's cwd is not the session's start
directory.** The directory is the slug of the caller's `$PWD`
(`bin/ai/handover-ready` passes `caller=$PWD`), while the status line reads
`dirname(transcript_path)`, the slug of the directory the session started in.
The main session's shell keeps a `cd` that ends inside its working
directories, so a lead whose shell sits in a subdirectory or in another working
directory gets rc 0 and "marked ...", the line never shows the segment, and a
bogus `~/.claude/projects/<slug>/` directory is created. The user's requested
notice silently fails. Resolve: with the session id known, locate
`<projects>/*/<session_id>.jsonl` (the id is unique) and use its directory;
fall back to the cwd slug only for the newest-transcript path; exit 2 when the
id's transcript is not found instead of creating a directory. Add a test with
`cwd` set to a subdirectory.

**I2. The mark outlives the handover it announces (`rules/global.md` timer
sub-bullet; `statusline.py` `handover_ready`; `mark.py`).** Nothing withdraws
the mark when the user, after the timer fired, keeps working in the same
session instead of clearing it. The line keeps saying `handover ready` while
the handover no longer describes the work done since; a user who `/clear`s on
that cue later hands the next lead a stale next step. Session scoping covers
`/clear`, not continued use. Resolve: one operative clause in Change A (a user
message after the mark withdraws it, and the lead withdraws it before other
work), and the lead's use of `handover-ready --clear` named in the PROJECT_MAP
row; or an automatic withdrawal in Change B (e.g. the line ignores a mark older
than the transcript's last user entry), with its test.

## Minor (non-blocking)

- M1. `rules/global.md` timer sub-bullet: "30 minutes is inside the cache
  lifetime, so what follows is written on a warm cache" is rationale and
  repeats decisions.md; the check "rationale only in decisions.md" is not met
  by that clause. Drop it, or keep only the operative constraint if wanted.
- M2. `rules/global.md` table, Lead row: the timer sits in the "Past 250k"
  column although the bullet applies it at every context size; a reader of the
  table alone may take it as threshold-bound. "(at every context size)" or a
  pointer to the bullet would settle it.
- M3. `rules/global.md` long-wait sub-bullet: a turn that both ends a work
  block and asks the user a question is both "the lead's own end of block" and
  "any other long wait"; past 250k the text gives two triggers (handover now,
  and again when the timer fires). Stating which wins would close it.
- M4. decisions.md entry does not say that the end-of-block push notification
  "carrying what finished" (8713b48) is dropped with the question; the new text
  notifies only when the handover is ready. Intended per the task statement,
  but unrecorded.
- M5. PROJECT_MAP.md coupling row: "after the idle timer fires" omits "after
  the handover's review closes" (the handover rule: reviewed before declared
  ready through any marker), and "`/clear` drops it" means the line stops
  showing it; the file stays.
- M6. Unverified: that `CLAUDE_CODE_SESSION_ID` in the lead's shell changes on
  `/clear`. The evidence's real run was in session 34adc6b8, whose CLI process
  (pid 95, started 05:32:52Z) began with that session (first entry
  05:32:54Z), so no `/clear` has been observed. If the variable stays stale,
  every lead after the first `/clear` marks the previous session and I1's
  silent failure recurs. Settle after the next `/clear`: `echo
  $CLAUDE_CODE_SESSION_ID` against the newest transcript name.
- M7. `find_session` fallback (no env var) takes the newest transcript of the
  project, which is another session's when two sessions share a project.
  Reachable only without `CLAUDE_CODE_SESSION_ID`.

## Change A otherwise

The bullet, its sub-bullets and the table give one action per case: the lead's
own end of block follows the timer at every size; other long waits keep the
past-threshold rule; the order write, review, retire, mark agrees with the
handover-review rule (reviewed before declared ready; implementers listed in
the handover stay live until the review closes). Wording is tool-neutral.
