# Task statement: idle timer instead of the end-of-block question

Stated by Skippy Wspaniały (lead), 2026-11-09. Two small changes, one per
repository, done in parallel by two implementers.

## What the user asked (2026-11-09, translated)

"About the closed question at the end of the lead's work: better not to ask it.
Let the lead start a 30-minute countdown instead; if I do nothing within 30
minutes, the handover is written and reviewed automatically, so the session is
ready to be cleared, with a notification in the status [line]."

This replaces the end-of-block notification with the closed question "a break of
more than an hour?" that landed today in `~/knowledge` (8713b48, 6538cce,
`rules/global.md`, context lifecycle bullet).

## Change A: the rule (`~/knowledge`, rules/global.md + decisions.md)

- Replace the closed-question sub-bullet: at the end of a work block the lead
  starts a 30-minute timer. A message from the user before it fires cancels it.
  When it fires with no user action, the lead writes its handover, has it
  reviewed (as the handover rule already says), retires its subagents, and marks
  the session ready to clear where the environment can show such a mark (the
  status line here); where it can push a notification, it sends one saying the
  handover is ready.
- 30 minutes is inside the one-hour cache lifetime, so the handover is written on
  a warm cache. Reconcile with the existing "past the prepare threshold, act
  before a long wait" sub-bullet and the table: decide whether the timer applies
  at every context size (simplest) or only below the threshold, and make the
  bullet and the table say one thing. Rationale goes to decisions.md.
- Tool-neutral wording; no tool names in global.md.

## Change B: the mark in the status line (dev-tools, tools/context_statusline)

- The status line receives `session_id` and `transcript_path` on stdin. A marker
  file per session, e.g. `dirname(transcript_path)/<session_id>/handover-ready`
  holding the handover's path, is session-scoped by construction: after
  `/clear` the new session has another id and the mark disappears. The
  implementer may choose another location if it is equally session-scoped and
  outside the project tree; record the choice in the coupling register.
- When the marker exists the status line shows a short, distinct segment (for
  example `handover ready`), never failing the line.
- A small helper the lead runs to write the marker for its own session (find the
  session from the newest transcript in the project's Claude directory, or a
  better source if one exists; state which), under `bin/ai/`.
- Tests first; fixtures as the module already uses.
