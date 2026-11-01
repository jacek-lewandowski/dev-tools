# Task statement: context size of the lead and its subagents in the status line

Stated by Stefan (lead), 2026-11-01. Class: **brief** (a new script in this
repository, a managed-settings change in the sandbox image, no contract
change). The planner writes the brief; a reviewer checks it; the user approves;
one implementer closes it.

## What the user asked

"Add to the status line the context size of the main session and of the
subagents, best with colours."

## Facts the planner starts from (checked 2026-10-29 to 2026-11-01)

- The status line script receives JSON on stdin with
  `context_window.used_percentage`, `remaining_percentage`,
  `context_window_size`, `current_usage`, `session_id`, `transcript_path`,
  `cost`; `used_percentage` may be null early and right after /compact;
  updates are debounced 300 ms (code.claude.com/docs/en/statusline.md).
- No documented way exists for the parent to read a subagent's percentage.
  Subagent transcripts live at
  `~/.claude/projects/<project>/<session-id>/subagents/agent-<id>.jsonl` with
  a sibling `agent-<id>.meta.json`; compaction events are logged there as
  `compact_boundary` with `trigger` and `preTokens`
  (code.claude.com/docs/en/sub-agents.md). Whether assistant entries carry a
  `usage` object with input/cache token counts is undocumented: the planner
  reads one real transcript in this sandbox
  (`~/.claude/projects/-home-jlewandowski-dev-public-dev-tools/<session>/subagents/`)
  and the meta file, and states the field names it found, as the source of
  the per-agent estimate. The estimate of a subagent's live context is the
  last assistant entry's input + cache_read + cache_creation tokens, if those
  fields exist.
- Sandboxes get Claude Code settings from the image's managed settings
  (`/etc/claude-code/managed-settings.json`, written by
  bin/ai/create-ai-sandbox.sh around line 1863) and from the per-sandbox
  copy of `~/.claude/settings.json`. The user's host settings also seed the
  sandbox. Decide where the statusLine entry goes so every sandbox and the
  host can share one script; dev-tools is mounted read-only at `~/tools` in
  every sandbox and the project's python helpers live under `tools/`.
- The global rules (CLAUDE.md) set a 300k-token ceiling per agent, so the
  colours should mark that threshold and the compaction/handover threshold
  (the user's default from the supervisor discussion: 70 % of the window).

## Scope

- One script (python, under `tools/`, with a unit test on fixture JSON and a
  fixture transcript) that prints one line: model, main context as a
  percentage and tokens, then one short token per live subagent (name or id
  prefix, its estimated context, coloured), sorted by size, limited to what
  fits; colours by threshold (green / yellow / red), ANSI, and a plain fallback
  when not a tty or when the harness says no colour.
- The settings change that wires it in the sandbox image and a note for the
  host.
- Out of scope: any change to the rules, any supervisor feature, anything
  that writes files from the status line.

## Deliverable

`docs/superpowers/specs/2026-11-01-context-statusline-brief.md` in the house
brief shape (goal, the two or three obligations with their checks, the
evidence file path `docs/superpowers/evidence/2026-11-01-context-statusline.md`,
the impact set with its sources), under 120 lines.
