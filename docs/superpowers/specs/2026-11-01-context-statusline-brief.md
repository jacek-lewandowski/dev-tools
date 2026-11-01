# Brief: context size of the lead and its subagents in the status line

Date: 2026-11-01. Class: brief (request `2026-11-01-context-statusline-brief-request.md`);
one implementer, one diff review. Evidence: `docs/superpowers/evidence/2026-11-01-context-statusline.md`.

## Goal

In every sandbox and on the host the Claude Code status line shows one line:
model, main context as percentage and tokens, then one short token per live
subagent (label, estimated context), sorted by size, cut to `COLUMNS`, each
coloured green / yellow / red by threshold; one stdlib python module
`tools/context_statusline/` (`python3 -m tools.context_statusline`) with a
unit test on fixture JSON, a fixture transcript and fixture meta files.

## Known facts (checked 2026-11-01, Claude Code 2.1.312, this sandbox)

- Stdin JSON (code.claude.com/docs/en/statusline.md): `context_window.
  {context_window_size, used_percentage, remaining_percentage, current_usage}`,
  `current_usage.{input_tokens, output_tokens, cache_creation_input_tokens,
  cache_read_input_tokens}` (`used_percentage` = the three input fields over
  the window; both `null` before the first call and right after `/compact`),
  `session_id`, `transcript_path`, `model.display_name`, `cost`. 300 ms
  debounce, an in-flight run is cancelled; `refreshInterval` (s, min 1)
  re-runs it while the main session idles, which is when subagents work.
  Output is captured (stdout never a tty), `COLUMNS`/`LINES` are set, ANSI
  escapes render; no "no colour" signal is documented.
- Subagent files (this project's sessions `6d7fbdd3-…`, `8b89e0f1-…`):
  `agent-<id>.jsonl` entries carry `type` (`user`/`assistant`/`system`),
  `agentId`, `sessionId`, `timestamp`; an assistant entry has `message.usage.{input_tokens,
  cache_creation_input_tokens, cache_read_input_tokens, output_tokens}` and
  `message.model` (usable later to map a subagent to its window). Live
  estimate = last assistant entry's input + cache_creation + cache_read
  (seen: 373957 for a finished planner). `agent-<id>.meta.json`: `agentType`,
  `description`, `model` (sometimes), `toolUseId`, `spawnDepth`, `requestShape`,
  `requestNonInteractive`, `isBuiltIn`, `launchedWithDefaults`, `finished`
  (`true` once the agent ended, absent while it runs or when its session
  died); no `name` despite sub-agents.md, so the label is `description`.
  Compaction: `{"type":"system","subtype":"compact_boundary","compactMetadata":
  {"trigger","preTokens",…}}`, seen once in main transcript `7184d87f-…`
  (preTokens 607503), in no subagent file. Directory:
  `dirname(transcript_path)/<session_id>/subagents/`.
- Settings: `/etc/claude-code/managed-settings.json`, rendered by
  `create-ai-sandbox.sh` (heredoc `cat > "$BUILD_DIR/claude-managed-settings.json"`,
  copied by the Dockerfile), is the top precedence level; the per-sandbox
  `~/.claude/settings.json`, seeded once from the host, has no `statusLine`
  (0 matches). Supervisor design D10 reserves the managed slot for
  `ai-supervisor-statusline` (A9, A23). `PYTHONPATH=$HOME`; `~/tools` is the
  read-only mount of `tools/`; `ai-delegate` is the pattern for a script
  copied into `/usr/local/bin`. No python formatter or test exists in the repo.

## Decisions

- Wiring: one bash wrapper `bin/ai/context-statusline` that finds `tools` as
  `create-ai-sandbox.sh` does (own checkout, `~/dev/public/dev-tools`,
  `~/tools`), `cd`s to its parent and `exec python3 -m tools.context_statusline "$@"`.
  The image copies it beside `ai-delegate`; managed settings gain `"statusLine":
  {"type": "command", "command": "context-statusline", "refreshInterval": 10}`.
  Host note (reported, not performed): the same entry in host settings with
  `bin/ai` on PATH. The supervisor's writer later takes the slot and prints this line.
- Colours by absolute tokens, main session and every subagent alike: green
  below `PREPARE_TOKENS` (250000), yellow from it, red from `CEILING_TOKENS`
  (350000), the lifecycle rule's values as approved 2026-11-01; no
  window percentage. Both constants are defined once in the module under a
  consumer comment: they equal the knowledge rule's values (`rules/global.md`,
  context lifecycle bullet). Plain output on `--plain` or a non-empty
  `NO_COLOR` (no-color.org); no tty check, stdout is never a tty.
- Live subagent: meta without `finished: true` whose transcript mtime is
  younger than `STALE_AFTER_S` (600; a session that ended mid-run leaves
  unfinished metas for good, 29 under `1b83102d-…`); older ones are dropped.
  Label `description` cut to 12 characters; a `compact_boundary` after the
  last assistant entry marks the token `~`; `null` main usage prints `--`;
  a missing directory or a malformed line never fails the line. Only each
  transcript's tail is read (files reach 1 MB), far below the 300 ms debounce.
- 🟡 Declared dependency (global rule §3), approved 2026-11-01: `ruff`, pinned,
  in a new `requirements-dev.txt`, formatting the new module only.
- Decided 2026-11-01: `refreshInterval` 10 s (was Q2). No question is open.

## Obligations

- S1 `python3 -m unittest tools.context_statusline.test_statusline -v` passes.
  Cases: stdin fixture with usage prints model, percentage, tokens; null
  `current_usage` and `used_percentage` print `--`; a fixture subagents dir
  with two fresh unfinished metas, one finished and one unfinished but older
  than `STALE_AFTER_S` prints two tokens sorted by size, the finished and
  the stale absent, the compacted one marked `~`; values below `PREPARE_TOKENS`,
  at it, and at `CEILING_TOKENS` yield the green, yellow and red escapes,
  and with `--plain` or `NO_COLOR=1` none; `COLUMNS=40` cuts to 40 visible
  characters; a missing directory or a malformed last line still prints the
  main part. Expected: all pass.
- S2 real run: this session's `session_id` and `transcript_path` in a stdin
  JSON piped to `bin/ai/context-statusline` from `/` prints one line naming
  the live agents; one agent's number equals the sum of the three input
  fields in `grep -o '"usage":{[^}]*}' <its jsonl> | tail -1` (the match
  stops at the nested `output_tokens_details` but holds those three); the
  same stdin with session `1b83102d-…` (29 unfinished, all stale) prints no
  agent token; `time` under 200 ms with 16 transcripts. Record all three.
- S3 `tests/ai-sandbox/test-tools.sh` asserts on the generated build dir that
  `claude-managed-settings.json` parses (existing case), has
  `statusLine.command == "context-statusline"` and the Dockerfile copies the
  wrapper; `bash tests/ai-sandbox/run-tests.sh` green (SDKMAN case excepted).
- S4 read: the module's top comment, under the prefix `# reads-outside:`,
  names the contract it reads (Claude Code 2.1.312 status line JSON and
  transcript JSONL, fields above); `PROJECT_MAP.md` lists the module and the
  wrapper and creates the coupling-register section (none exists:
  `grep -c coupling PROJECT_MAP.md` → 0) naming that prefix and this format.

## Impact set

- `claude-managed-settings.json` (key added): `grep -n claude-managed-settings
  bin/ai/create-ai-sandbox.sh tests/ai-sandbox/*.sh` → 5 (script 1863, 2051;
  test-tools.sh 41, 42, 50). Addition only, no residue.
- `statusLine`: `grep -rn statusLine --exclude-dir=.git --exclude-dir=.tmp .`
  → 7 (supervisor design, its review, the request); `grep -c statusLine
  ~/.claude/settings.json` → 0. New names `context-statusline` /
  `context_statusline`: same grep → 2, both in the request. No residue.
- Outside the repository: Claude Code's JSON and transcript layout (S4); the
  knowledge rule's thresholds (consumer comment); host settings (user step).

Acceptance: S1 to S4 evidenced with output and commits; the host re-runs `create-ai-sandbox.sh` (user's step).
