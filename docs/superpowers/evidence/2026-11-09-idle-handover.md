# Evidence: idle handover timer (2026-11-09)

## Change A

global.md word count: before 5787, after 5823.

Reconciliation: the timer applies at every context size. The long-wait sub-bullet now says the lead's own end of block follows the timer; before any other long wait it applies unchanged. The Lead row of the table gains "at the end of a work block, when its 30-minute timer fires". The previous closed-question sub-bullet and its threshold split are removed, so the sub-bullet, the table and the long-wait definition give one action. Rationale in decisions.md.

```diff
commit e65f1c26254da6ea5170d5c17835155455dd9087
Author: jacek-lewandowski <lewandowski.jacek@gmail.com>
Date:   Mon Nov 9 10:32:15 2026 +0100

    feat(rules): the lead's end of block starts a 30-minute handover timer
    
    Co-Authored-By: Zuzia (Claude Sonnet 5.5) <noreply@anthropic.com>

diff --git a/decisions.md b/decisions.md
index f262c9a..fa4114a 100644
--- a/decisions.md
+++ b/decisions.md
@@ -14,6 +14,17 @@ Format:
 
 ## Entries
 
+- 2026-11-09 idle-handover-timer integrated
+  rules/global.md: replaces the end-of-block closed question ("a break of more
+  than an hour?") of the same day. The user said (translated): "better not to
+  ask it. Let the lead start a 30-minute countdown instead; if I do nothing
+  within 30 minutes, the handover is written and reviewed automatically, so the
+  session is ready to be cleared, with a notification in the status [line]."
+  The timer applies at every context size, the simplest rule: 30 minutes is
+  inside the one-hour cache lifetime, so the handover is written warm, and the
+  lead's end of block no longer counts as a long wait, so the table and the
+  long-wait sub-bullet give one action.
+
 - 2026-11-09 no-process-narration integrated
   rules/global.md: the user said, "Do not tell me what the reviewer found or
   who is fixing what now; that is your internal process, I have no influence on
diff --git a/rules/global.md b/rules/global.md
index 048ba67..152f975 100644
--- a/rules/global.md
+++ b/rules/global.md
@@ -202,19 +202,21 @@ Host rules apply everywhere, including inside an ai-sandbox container
   assume an hour. Inside a review-and-fix loop keep agents continued rather
   than replaced.
   - A long wait is a pause expected to outlast the cache lifetime: a question
-    to the user, the end of a work block, a task whose follow-up is not
-    ready. An agent past the prepare threshold that ends its turn before a
-    long wait acts now, on the warm cache, not after the return: the lead
-    writes its handover, a subagent is retired. A continued subagent whose
+    to the user, the end of a work block (the lead's own end of block follows
+    the timer below), a task whose follow-up is not ready. An agent past the
+    prepare threshold that ends its turn before a long wait acts now, on the
+    warm cache, not after the return: the lead writes its handover, a subagent
+    is retired. A continued subagent whose
     next use is a long wait away is retired at the end of its task, not kept.
-  - Where the environment can push a notification to the user, the lead ends
-    a work block with one carrying what finished. A lead past the prepare
-    threshold changes nothing: it writes its handover before the long wait as
-    above, and the notification says the handover is ready. A lead below the
-    threshold adds the closed question "a break of more than an hour?"; this
-    one question is not a long wait in the sense of the first sub-bullet. On
-    yes it writes its handover and retires its subagents as for a long wait;
-    on no it waits and the subagents stay.
+  - At the end of a work block the lead starts a 30-minute timer, at every
+    context size; 30 minutes is inside the cache lifetime, so what follows is
+    written on a warm cache. A message from the user before it fires cancels
+    it. When it fires with no user action, the lead writes its handover, has it
+    reviewed as below, retires its subagents, and marks the session ready to
+    clear where the environment can show such a mark; where it can push a
+    notification to the user, it sends one saying the handover is ready. The
+    timer replaces the lead's own end-of-block long wait above; before any
+    other long wait the first sub-bullet applies unchanged.
   - The lead's `/clear` makes every subagent unreachable, so before it the
     lead asks each live implementer with an open task for its note and lists
     the live agents, their open units and their note paths in the handover.
@@ -246,7 +248,7 @@ Host rules apply everywhere, including inside an ai-sandbox container
 
 | Agent | Past 250k | Past 350k | Who acts |
 |---|---|---|---|
-| Lead | Writes its handover file (open units of work, live agents by name with their note paths, the next step) at the path the project names, else beside the evidence files, at the phase boundary, has it reviewed, then `/clear`; before a long wait, at the current task boundary. | Handover, its review and `/clear` before any other work. | The lead, from its status line; the user may call for it. |
+| Lead | Writes its handover file (open units of work, live agents by name with their note paths, the next step) at the path the project names, else beside the evidence files, at the phase boundary, has it reviewed, then `/clear`; before a long wait, at the current task boundary; at the end of a work block, when its 30-minute timer fires. | Handover, its review and `/clear` before any other work. | The lead, from its status line; the user may call for it. |
 | Implementer | Finishes the current task; at the task boundary writes a short note beside its evidence file, reviews it itself, is retired and replaced in the same slot; the replacement starts from the brief, the plan and the note. | Retired at that stop, after its note and its review. | The lead, from the token count at each stop. |
 | Spec author, phase planner, brief writer, reviewer, runner, scout, writer | Retired at the next stop; a fresh agent in the same slot carries on from the files, under the same name. No note, no handover, no compaction. | Not reached: 250k is their ceiling. | The lead, from the token count at each stop. |
 | Second reviewer | Outside this rule: each round is one external run, continued by its conversation id; nothing to retire. | The same. | Nobody. |
```

## Change B: handover-ready mark in the status line (Wojtek)

Commits: see `git log --grep "handover-ready"` (two: `feat:` for the segment and
helper, `docs:` for PROJECT_MAP.md).

Choice: marker `dirname(transcript_path)/<session_id>/handover-ready` holding the
handover path (session-scoped, outside the project tree); registered in
PROJECT_MAP.md coupling register. Helper `bin/ai/handover-ready <path>|--clear`
(`tools/context_statusline/mark.py`) finds the session from
`CLAUDE_CODE_SESSION_ID` (set in every Claude Code shell here), falling back to
the newest `*.jsonl` in `~/.claude/projects/<cwd with non-alphanumerics as "-">`
(`CLAUDE_CONFIG_DIR` honoured).

- Red (tests written first, before `statusline.py`/`mark.py` changed):
  `python3 -m unittest tools.context_statusline.test_statusline` -> `Ran 1 test in 0.000s / FAILED (errors=1)` (ImportError of `HANDOVER_MARKER`, `mark`).
- Green: `Ran 21 tests in 0.023s / OK` (after the last edit, which was ruff's import sort).
- ruff 0.17.3 (pinned; installed in a scratch venv, not on PATH): in `tools/context_statusline`, `ruff check --no-cache .` fixed one I001 in the test imports, then `ruff format --no-cache --check .` -> `5 files already formatted`.
- Real run, this sandbox, session 34adc6b8-..., `context-statusline --plain` with real stdin JSON:
  - before: `Sonnet 5.5 -- | Statusline h:72k`
  - `bin/ai/handover-ready docs/superpowers/evidence/2026-11-09-idle-handover.md` -> `marked .../34adc6b8-.../handover-ready`, rc=0
  - after: `Sonnet 5.5 -- | Statusline h:72k | handover ready`
  - `bin/ai/handover-ready --clear` -> marker removed; line back to `Sonnet 5.5 -- | Statusline h:73k`. No marker left.

## Change A fix round

Fixes M1-M4 and the I2 clause of the review. global.md word count: before 5823, after 5871.
M1 cache-lifetime clause dropped; M2 table says "at any context size"; M3 the timer governs a block ending with a question and replaces the first sub-bullet for the lead's end of block; M4 decisions.md records the dropped 8713b48 notification; I2 "one after the mark is set withdraws the mark".

```diff
commit e76335c029afff42ecc7d27b8f6f80d3faa21211
Author: jacek-lewandowski <lewandowski.jacek@gmail.com>
Date:   Mon Nov 9 10:37:00 2026 +0100

    fix(rules): one trigger for the lead's end of block, timer shown at every context size
    
    Co-Authored-By: Zuzia (Claude Sonnet 5.5) <noreply@anthropic.com>

diff --git a/decisions.md b/decisions.md
index 894348a..3bdd647 100644
--- a/decisions.md
+++ b/decisions.md
@@ -46,6 +46,9 @@ Format:
   inside the one-hour cache lifetime, so the handover is written warm, and the
   lead's end of block no longer counts as a long wait, so the table and the
   long-wait sub-bullet give one action.
+  The end-of-block notification "carrying what finished" of 8713b48 is dropped
+  with the question: the lead now notifies only when the handover is ready. A
+  block ending with a question to the user is still governed by the timer.
 
 - 2026-11-09 no-process-narration integrated
   rules/global.md: the user said, "Do not tell me what the reviewer found or
diff --git a/rules/global.md b/rules/global.md
index c95bef7..4bf0632 100644
--- a/rules/global.md
+++ b/rules/global.md
@@ -202,21 +202,21 @@ Host rules apply everywhere, including inside an ai-sandbox container
   assume an hour. Inside a review-and-fix loop keep agents continued rather
   than replaced.
   - A long wait is a pause expected to outlast the cache lifetime: a question
-    to the user, the end of a work block (the lead's own end of block follows
-    the timer below), a task whose follow-up is not ready. An agent past the
-    prepare threshold that ends its turn before a long wait acts now, on the
-    warm cache, not after the return: the lead writes its handover, a subagent
-    is retired. A continued subagent whose
+    to the user, the end of a work block, a task whose follow-up is not
+    ready. An agent past the prepare threshold that ends its turn before a
+    long wait acts now, on the warm cache, not after the return: the lead
+    writes its handover, a subagent is retired. A continued subagent whose
     next use is a long wait away is retired at the end of its task, not kept.
   - At the end of a work block the lead starts a 30-minute timer, at every
-    context size; 30 minutes is inside the cache lifetime, so what follows is
-    written on a warm cache. A message from the user before it fires cancels
-    it. When it fires with no user action, the lead writes its handover, has it
-    reviewed as below, retires its subagents, and marks the session ready to
-    clear where the environment can show such a mark; where it can push a
-    notification to the user, it sends one saying the handover is ready. The
-    timer replaces the lead's own end-of-block long wait above; before any
-    other long wait the first sub-bullet applies unchanged.
+    context size, also when the block ends with a question to the user. A
+    message from the user before it fires cancels it; one after the mark is
+    set withdraws the mark. When it fires with no user action, the lead writes
+    its handover, has it reviewed as below, retires its subagents, and marks
+    the session ready to clear where the environment can show such a mark;
+    where it can push a notification to the user, it sends one saying the
+    handover is ready. The timer replaces the first sub-bullet for the lead's
+    end of a work block; before any other long wait the first sub-bullet
+    applies unchanged.
   - The lead's `/clear` makes every subagent unreachable, so before it the
     lead asks each live implementer with an open task for its note and lists
     the live agents, their open units and their note paths in the handover.
@@ -248,7 +248,7 @@ Host rules apply everywhere, including inside an ai-sandbox container
 
 | Agent | Past 250k | Past 350k | Who acts |
 |---|---|---|---|
-| Lead | Writes its handover file (open units of work, live agents by name with their note paths, the next step) at the path the project names, else beside the evidence files, at the phase boundary, has it reviewed, then `/clear`; before a long wait, at the current task boundary; at the end of a work block, when its 30-minute timer fires. | Handover, its review and `/clear` before any other work. | The lead, from its status line; the user may call for it. |
+| Lead | Writes its handover file (open units of work, live agents by name with their note paths, the next step) at the path the project names, else beside the evidence files, at the phase boundary, has it reviewed, then `/clear`; before a long wait, at the current task boundary; at the end of a work block, at any context size, when its 30-minute timer fires. | Handover, its review and `/clear` before any other work. | The lead, from its status line; the user may call for it. |
 | Implementer | Finishes the current task; at the task boundary writes a short note beside its evidence file, reviews it itself, is retired and replaced in the same slot; the replacement starts from the brief, the plan and the note. | Retired at that stop, after its note and its review. | The lead, from the token count at each stop. |
 | Spec author, phase planner, brief writer, reviewer, runner, scout, writer | Retired at the next stop; a fresh agent in the same slot carries on from the files, under the same name. No note, no handover, no compaction. | Not reached: 250k is their ceiling. | The lead, from the token count at each stop. |
 | Second reviewer | Outside this rule: each round is one external run, continued by its conversation id; nothing to retire. | The same. | Nobody. |
```

## Change B fix round (Wojtek)

Findings: I1, I2, M5, M6/M7 of `2026-11-09-idle-handover-review.md`. Commit: the
`fix:` commit "withdraw the handover mark ..." (`git log --grep handover-ready`).

- I1/M6/M7: `mark.py` takes the session only from `CLAUDE_CODE_SESSION_ID` (exit 2 if unset), finds `<projects>/*/<id>.jsonl` (exit 2 and nothing created if absent), never uses the cwd; the newest-transcript fallback is gone; a newer transcript beside it prints a stderr warning, exit 0.
- I2: `handover_ready` hides the mark when the transcript's last user message (not tool result, `isMeta`, `isSidechain`; tail read growing like `last_reply`) is newer than the marker's mtime.
- M5: PROJECT_MAP row and module line reworded.
- Red (tests first): `Ran 27 tests ... FAILED (failures=6, errors=1)`.
- Green: `Ran 27 tests in 0.028s / OK`. ruff 0.17.3: `All checks passed!`, `5 files already formatted`.
- Real run from `tools/` (a subdirectory): `../bin/ai/handover-ready /x.md` -> marked under the session's real directory; status line `Sonnet 5.5 -- | Statusline h:84k | handover ready`; `--clear` removed it. Unset var -> `CLAUDE_CODE_SESSION_ID is not set`, rc=2; `CLAUDE_CODE_SESSION_ID=nope` -> `no transcript for session nope`, rc=2; no new directory in `~/.claude/projects`. No marker left.
