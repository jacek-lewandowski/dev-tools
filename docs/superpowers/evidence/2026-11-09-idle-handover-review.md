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

# Round 2

Delta: `~/knowledge` e76335c (Change A fixes); dev-tools 72681ef (Change B
fixes) and the two fix-round sections of the evidence file. Also, as part of
this one review of today's small changes on `~/knowledge` main: the integration
of four proposals, d22aa1f, a6568d1, 52aa7a6 and the merges 9877d07, 5d38f5b,
37c1b55, 3ef55e4, against `2026-11-09-proposals-triage.md` and the user's
"the linter must not stop at the first error, it must produce a full report"
(transcript 2026-11-09T09:34:36Z).

Verdict: **not accepted**: one Important finding on each side.

## Run

- `python3 -m unittest tools.context_statusline.test_statusline`: `Ran 27 tests
  in 0.033s / OK`.
- I1 reproducer through the real `bin/ai/handover-ready`, run from a
  subdirectory of the scratchpad with `CLAUDE_CONFIG_DIR` set to a scratch
  config dir and `CLAUDE_CODE_SESSION_ID=sess1`: it marked
  `cfg/projects/-work-proj/sess1/handover-ready`, the line showed
  `? -- | handover ready`, and no other directory was created. With
  `CLAUDE_CODE_SESSION_ID=nope`: `no transcript for session nope`, rc 2.
  **I1 is closed.**
- `_is_user_message` applied to this session's real transcript (34adc6b8),
  grouped by `origin.kind`: 16 human entries (`origin.kind` `human`). It also
  accepts 3 non-meta `<task-notification>` entries (`origin.kind`
  `task-notification`, e.g. 09:32:28Z and 09:37:08Z). Peer hand-backs carry
  `isMeta` and are excluded.
- Ours-merges: in each of the four, the tree equals the first parent and the
  second parent is the proposal branch tip; `git diff <tip> <merge> --
  proposals` deletes the proposal file; `git ls-tree -r HEAD proposals` lists
  only `proposals/README.md`.
- The two sentences in `rules/global.md` and the four decisions.md entries
  match the triage drafts word for word.

## Important

**R2-I1. `tools/context_statusline/statusline.py` `_is_user_message`: a task
notification counts as the user coming back, so the mark can disappear before
the user has seen it.** Claude Code writes a non-meta `type: "user"` entry
with string content `<task-notification>...` (`origin.kind`
`"task-notification"`) whenever a background agent or command stops,
"each time this agent stops", killed ones included. Above, a reviewer's
hand-back at 09:32:26Z was followed by its task notification at 09:32:28Z. In
the intended flow, the lead gets the handover reviewer's hand-back, retires
the subagents and runs `handover-ready` in the same turn. Any notification
written after that (the reviewer's own, a killed subagent's, a late
background job's) has a timestamp later than the mark's mtime, and
`handover_ready` hides the segment though no user acted. That defeats the
mark the user asked for. Resolve: count only human entries (`origin.kind ==
"human"`, the field the coupling register already lists for queued commands),
or at least exclude the prefixes `~/knowledge` `transcript_stats.py`
`NOT_A_ROUND` lists. Add a test with a task-notification entry after the
mark, built from a real transcript line, and add `origin.kind` to the
`reads-outside` comment.

**R2-I2. `~/knowledge` `rules/global.md`, gate sentence (d22aa1f): the landed
clause does not state the user's requirement.** "a lint runner that stops at
its first failure is run past it, so that every task reports" was drafted
before the user said the linter must not stop at the first error and must
produce a full report, and it landed unchanged. In this file "task" is the
defined unit of work (small, brief, phase task), so "every task reports"
reads as agent tasks reporting. A linter that stops at its first error within
one check is not clearly covered either. Resolve: reword to the user's
statement, tool-neutral, e.g. "and a linter or lint runner that stops at its
first error is run so that it reports every error", with the matching words
in the d22aa1f decisions entry.

## Minor (non-blocking)

- R2-M1. `statusline.py` `last_user_time`: a malformed `type: "user"` line
  whose `message` is not an object raises `AttributeError` (reproduced:
  `'str' object has no attribute 'get'`). `main` does not catch it, so while a
  mark exists the line fails, against the module's "a malformed file ... still
  prints the main part". Claude Code does not write such lines. Adding
  `AttributeError`/`TypeError` to the caught exceptions, or an `isinstance`
  check, closes it.
- R2-M2. decisions.md: the five 2026-11-09 entries above
  `no-process-narration` have no blank line between them, unlike the rest of
  the log.
- R2-M3. `mark.py`'s newer-transcript warning also fires whenever another
  session of the same project wrote last. This is harmless (stderr, rc 0), but
  it will often be a false alarm.

## Closed from round 1

I1 (reproducer above), I2 rule side (Change A clause "one after the mark is
set withdraws the mark"; Change B hides the mark after a later user entry,
subject to R2-I1), M1 to M5 and M7. M6 is reduced to a stderr warning; whether
the variable stays stale after `/clear` remains unverified, as before.
Change A's delta is otherwise consistent: one trigger for the lead's end of
block, the long-wait rule for every other wait, and the table says "at any
context size".
