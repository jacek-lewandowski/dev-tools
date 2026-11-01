# Handover 2026-11-01T14:40Z lead session (Stefan, dev-tools sandbox)

## Task
Supervising the leads from the phone: a design for "Krzysiu" (supervisor agent)
was written, reviewed and shelved; what replaced it landed today as two briefs
plus one user-run spike. No phase is open; every task below is closed.

## Done (committed)
- ~/knowledge main: a4a7343 asker self-check rule; dd91d76 context lifecycle
  per role (prepare 250k, ceiling 350k, act before a long wait). Host synced
  and re-rendered (the rendered ~/.claude/CLAUDE.md carries the rule).
- dev-tools: ce5c536, e177c27 (briefs); 2052b5f, 62ce6cb, 7cbdc66, 4bc7f77
  (context status line: tools/context_statusline, bin/ai/context-statusline,
  managed statusLine entry, coupling register in PROJECT_MAP.md); 39f1dcc,
  db750d5 (evidence + diff reviews); 3a59fd3 (Google Chat channel spike doc).
- Sandbox rebuilt by the user on 2026-11-01; status line verified in it.

## In progress (uncommitted)
- docs/superpowers/specs/2026-10-30-sandbox-supervisor-{design,brief}.md and
  docs/superpowers/evidence/2026-10-30-sandbox-supervisor-{spec-review,
  reverse-review}.md: the shelved supervisor design (revision 5) with its
  reviews; the user decides: commit as a record (status line "shelved") or
  delete.
- No live agents with open units; every agent of today is retired.

## Next
1. The user runs the spike docs/superpowers/specs/2026-11-01-google-chat-channel-spike.md
   on the host (Google Cloud console + one sandbox) and pastes the blocks; the
   lead records them in ...-google-chat-channel-spike-results.md and reports
   Q1-Q6.
2. If the spike passes: a brief for the per-host handover cron (lead writes
   handover with a ready marker; cron replaces the `--bg` session when idle)
   and for wiring the channel into create-ai-sandbox.sh; Krzysiu as an agent
   stays shelved.
3. Host step still owed from 2026-10-31 (memory): config budget line and B12
   docker inspect in the memory-budget evidence.

## Open
- Commit or delete the shelved supervisor files (user).
- Host: statusLine entry in the host's own ~/.claude/settings.json with bin/ai
  on PATH, if the user wants the line outside sandboxes.

## Read first
1. ~/.claude/projects/-home-jlewandowski-dev-public-dev-tools/memory/context-lifecycle-2026-11-01.md
2. docs/superpowers/specs/2026-11-01-google-chat-channel-spike.md
3. docs/superpowers/evidence/2026-10-30-sandbox-supervisor-reverse-review.md (why Krzysiu was shelved)
4. docs/superpowers/specs/2026-11-01-context-lifecycle-rules-brief.md (the rule text as landed)
