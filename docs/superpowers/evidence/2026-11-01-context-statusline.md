# Evidence: context size of the lead and its subagents in the status line

Brief: `docs/superpowers/specs/2026-11-01-context-statusline-brief.md`.

## Brief review, round 1

Fiona, reviewer 1. 2026-11-01, Claude Code 2.1.312, this sandbox. Verdict:
one Important finding; approve once it is fixed in the brief (no re-review
needed beyond that delta).

Facts verified (grep only, no whole files): `agent-aa66817180b4921c1.jsonl`
last `usage` = input 32 + cache_creation 664 + cache_read 373957, assistant
entries carry `agentId`, `sessionId`, `timestamp`, `message.usage`; metas
carry the listed fields, `finished: true` on 43 of 94, `model` sometimes, no
`name` (0 of 94); `"subtype":"compact_boundary"` in no subagent file, once in
`7184d87f-….jsonl` with `preTokens: 607503`; both unfinished metas of this
session belong to agents running now (jsonl mtime = now), so the meta exists
from spawn. `create-ai-sandbox.sh` 1863 heredoc, 1876 `cp ai-delegate`, 2052
`COPY ai-delegate`, 2058 chmod, 2051 managed-settings COPY; `PYTHONPATH=$HOME`
(1810, 2277); `~/tools` mount ro (2303); no pyproject/ruff/requirements.
statusline.md fetched: stdout captured and `COLUMNS`/`LINES` set (l. 133,
166), 300 ms debounce and in-flight cancel (152), `refreshInterval` min 1
(67), `used_percentage` = input + cache_creation + cache_read (370), nulls
(349-350, 374). Impact-set greps re-run: `claude-managed-settings` 5 (same
lines); `statusLine` 7 outside the brief itself (design 5, review 1, request
1), `~/.claude/settings.json` 0; new names 2, both in the request. Match.

### Important

- **Decisions, "Live subagent" / Obligation S1.** "Meta without `finished:
  true`" is not "live": an agent whose session ended mid-run keeps no
  `finished`, and `claude --resume` of that session shows every one of them
  as live for good. In this project dir today: 29 such metas under
  `1b83102d-…`, 13 under `4a33f12c-…`, 4 and 3 in two more. Failure the user
  reaches: resume a session, the line fills with phantom agents, the real
  ones get cut by `COLUMNS`. Fix: add a staleness rule to the decision (an
  unfinished agent whose transcript mtime is older than a bound, say
  10 minutes, is dropped or dimmed, bound a named constant) and an S1 case
  with a stale fixture meta; record the 29-phantom check as the known case.

### Lesser

- **Decisions, "Colours".** For a 200k window T_lo = 140k and T_hi = 300k,
  so red is unreachable in every 200k session (main and most subagents).
  State that this is intended, or take T_hi = min(T_hi, 0.9 × window) and
  keep the S1 "at T_hi" case on both window sizes.
- **Decisions, Q1.** Global rule §3 does not offer "keep it unformatted": a
  language without a configured formatter gets one added as a 🟡 declared
  dependency. Rephrase Q1 as a declaration (ruff pinned in
  `requirements-dev.txt`, formatting the new module only) that the user may
  veto, not a free choice. Q2 is the only genuine question; both are the only
  ones left to the user.
- **Obligation S4.** `PROJECT_MAP.md` has no coupling register yet (grep
  `coupling|register` → 0): say "creates the section" rather than "adds the
  line", with the searchable comment prefix the comment will carry.
- **Obligation S2.** `grep -o '"usage":{[^}]*}'` stops at the nested
  `output_tokens_details`; it still yields the three input fields, so the
  method check works, but say so, or match `"cache_read_input_tokens":[0-9]*`
  directly.
- **Known facts, subagent window.** `message.model` is in every assistant
  entry; the brief may cite it as the field a later task could map to a
  window, instead of "not in the transcript".

Compacted-subagent estimate: sound. After `compact_boundary` the next
assistant entry's `usage` is the new context; until it exists the last
pre-compaction usage is stale and the `~` mark says so. Obligations cover
the goal (S1 line shape, sorting, colours, cut; S2 real run; S3 wiring);
nothing in the brief is implementation code beyond the wrapper's `exec`
line and the settings entry, which are contracts.
