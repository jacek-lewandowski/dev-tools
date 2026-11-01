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

## Implementation evidence

Wojtek, implementer 2. 2026-11-01, Claude Code 2.1.312, this sandbox
(`/etc/ai-sandbox-release`), Python 3.10.12, ruff 0.17.3. Commits:
`2052b5f` feat(tools) module, tests, fixtures, wrapper, `requirements-dev.txt`;
`62ce6cb` feat(ai-sandbox) managed `statusLine`, image COPY, test-tools asserts;
`7cbdc66` docs(map) PROJECT_MAP rows and coupling register.

Decisions the brief left to the implementation: tokens print rounded to
thousands (`58k`), the main part as `<pct>% <tokens>`, agents as
`<label>:<~><tokens>` after ` | `; `null` usage prints `Fable 5.1 --`;
unparsable stdin prints `? --`; a live agent whose transcript holds no
assistant usage yet (just spawned, or garbage) is omitted; the tail read is
64 KiB, grown 16x while it holds no reply. Red run before the module:
`python3 -m unittest tools.context_statusline.test_statusline -v` →
`ModuleNotFoundError: No module named 'tools.context_statusline.statusline'`,
`FAILED (errors=1)`.

### S1 unit test on fixtures

Command (repo root, final tree): `python3 -m unittest tools.context_statusline.test_statusline -v`.
Result: 10 tests, `OK` (`Ran 10 tests in 0.022s`). Cases: main part
`Fable 5.1 42% 84k` (32+925+83243 = 84200); null usage and percentage →
`Fable 5.1 --`; fixture dir (two fresh unfinished, one `finished: true`, one
unfinished aged past `STALE_AFTER_S` by `os.utime`, git keeps no mtimes) →
`Fable 5.1 42% 84k | Write superv:~375k Land the con:138k` (374653 compacted
first, 137839 second, finished and stale absent); 249999 / 250000 / 350000
tokens → `\x1b[32m`, `\x1b[33m`, `\x1b[31m` around the main part and the same
escapes on the agent tokens; `--plain` and `NO_COLOR=1` → no escape, empty
`NO_COLOR` → colour; `COLUMNS=40` → 40 visible characters plain and coloured
(escapes not counted, trailing reset kept); missing subagents dir, a truncated
meta, a truncated jsonl and a meta without transcript → main part only;
`not json` on stdin → `? --`. Formatting: `ruff format --check` → `4 files
already formatted`, `ruff check` → `All checks passed!` (new module only).
Commit `2052b5f`.

#### S1, fix round after the diff review (commit `4bc7f77`)

Regression tests first. `fixtures/subagents/agent-a1fresh00000000.jsonl` gains
a synthetic assistant entry (`isApiErrorMessage: true`, `message.model:
"<synthetic>"`, all-zero usage, copied from the real shape in
`7184d87f-…/subagents/agent-a1041821fb32801e4.jsonl`) after its real reply
and before the torn line; `test_synthetic_last_entry_keeps_the_real_estimate`
writes a transcript whose last entry is synthetic and asserts
`Single agent:300k`; `test_reply_beyond_the_tail_and_a_torn_last_line` writes a
reply, 128 KiB of tool results (file size asserted `> TAIL_BYTES`) and a torn
last line and asserts `Single agent:260k`. Red run before the fix:
`Ran 12 tests`, `FAILED (failures=4)`: the synthetic case
(`'Single agent:0' != 'Single agent:300k'`) and the three fixture-line cases
now reading `Land the con:0`; the tail-growth case passed before the fix (it
pins behaviour the reviewer verified by scratch run, no red claimed). Fix:
`last_reply` skips an assistant entry with `isApiErrorMessage` or
`message.model == SYNTHETIC_MODEL` and keeps scanning; the second
`# reads-outside:` block names the field. Green run on the final tree:
`python3 -m unittest tools.context_statusline.test_statusline -v` → `Ran 12
tests in 0.012s`, `OK`; `ruff format --check` → `4 files already formatted`;
`ruff check` → `All checks passed!`. Real data: `last_reply` on the one
transcript of this project holding `"<synthetic>"`
(`agent-a1041821fb32801e4.jsonl`) → `(256053, False)` = 32 + 2152 + 253869
of the retry's reply, the entry the previous code would have read as 0.

### S2 real run

Stdin: `{"session_id":"6d7fbdd3-56a2-431d-ab8c-bad7df7ba6e5","transcript_path":
"~/.claude/projects/-home-jlewandowski-dev-public-dev-tools/6d7fbdd3-….jsonl",
"model":{"display_name":"Fable 5.1"},"context_window":{"used_percentage":31.4,
"current_usage":{"input_tokens":4,"cache_creation_input_tokens":2000,
"cache_read_input_tokens":312000,"output_tokens":1}}}` piped from `/` into
`/home/jlewandowski/dev/public/dev-tools/bin/ai/context-statusline`.

1. Live agents (23 transcripts in that dir), one command printing the line
   and one agent's last usage: `Fable 5.1 31% 314k | Implement co:120k
   Review Googl:58k`; `agent-aa4fec9358472b9f8.meta.json` description
   "Review Google Chat spike doc", no `finished`, jsonl age 32 s; `grep -o
   '"usage":{[^}]*}' … | tail -1` → `input_tokens 32, cache_creation 645,
   cache_read 57714` = 58391 → `58k`. Match (rounded to thousands). Colour
   run (`cat -v`): `Fable 5.1 ^[[33m31% 314k^[[0m | ^[[32mImplement
   co:114k^[[0m ^[[32mDiff review::78k^[[0m ^[[32mReview Googl:58k^[[0m`
   (main 314k yellow, agents green; the reviewer agent "Diff review: …" was
   live in that earlier run and finished before the snapshot above, so the
   `finished` filter is seen on real data too).
2. Same stdin with `session_id` `1b83102d-f68c-4c0f-bcdf-936c8bc7e577`
   (29 unfinished metas, all stale; the known case): `Fable 5.1 31% 314k`,
   no agent token.
3. `time`: this session, 23 transcripts: `real 0m0.058s`; `1b83102d`,
   29 transcripts: `real 0m0.050s`. Both under 200 ms.

Commit `2052b5f` (wrapper and module).

### S3 sandbox wiring

`bash tests/ai-sandbox/test-tools.sh` (final tree): `ok 22 - managed settings
run context-statusline as the status line`, `ok 23 - context-statusline is
installed in the image`, `ok 24 - context-statusline is in the build context`,
`ok 21 - managed settings JSON parses` (existing); `79 run, 1 failed`, the one
`not ok 42 - a candidate without a default is skipped` (SDKMAN, sandbox-only,
excepted by the brief; fails identically on the base tree: `76 run, 1 failed`,
`not ok 39`). `bash tests/ai-sandbox/run-tests.sh` on the final tree: 20
suites, all `0 failed` except test-tools.sh (the SDKMAN case above) and
test-delegate.sh `69 run, 2 failed` (`not ok 54 - writer prompt has no-tools
line`, `not ok 59 - second-reviewer prompt has no-commands line`: they compare
the prompt with the role files under `~/.gemini/agents` of this sandbox;
neither `ai-delegate` nor `test-delegate.sh` is in this diff, last touched by
`b35a5d4`; pre-existing here). The image is not rebuilt in the sandbox: the
host re-runs `create-ai-sandbox.sh` (pending, user's step) and adds
`"statusLine": {"type": "command", "command": "context-statusline",
"refreshInterval": 10}` to its own settings with `bin/ai` on `PATH`.
Commit `62ce6cb`.

### S4 consumer comment and coupling register

Read: `tools/context_statusline/statusline.py` docstring lines 9-18 carry two
`# reads-outside:` blocks naming Claude Code 2.1.312's status line JSON
(fields) and the subagent transcript layout (meta fields, `message.usage`
fields, `compact_boundary`); lines 27-31 the consumer comment over
`PREPARE_TOKENS`/`CEILING_TOKENS` naming the knowledge rule. `grep -rn
'reads-outside:' --include='*.py' --include='*.sh' .` → the two lines, nothing
else. `PROJECT_MAP.md`: rows for `bin/ai/context-statusline` (line 18) and
`tools/context_statusline` (line 37) and the new `## Coupling register`
section with three entries (the two formats and the thresholds) naming the
prefix; `grep -c coupling PROJECT_MAP.md` → 1 (was 0). Commit `7cbdc66`.

### Checks on the final tree (after the last edit, commit `7cbdc66`)

- `python3 -m unittest tools.context_statusline.test_statusline -v`: 10 run, OK.
- `ruff format --check tools/context_statusline && ruff check tools/context_statusline`: formatted, all checks passed.
- `bash tests/ai-sandbox/run-tests.sh`: `SOME SUITES FAILED` with exactly the
  three pre-existing cases above (test-tools 42, test-delegate 54 and 59);
  every other suite `0 failed`.
- `bash tests/ai-sync/test-sync.sh`: `37 run, 0 failed`.
- `bash tests/git-hooks/test-hooks.sh`: `19 run, 0 failed`.
- Impact set re-run: `grep -rn statusLine --exclude-dir=.git --exclude-dir=.tmp .`
  → the 7 documentation lines plus `create-ai-sandbox.sh:1866`,
  `test-tools.sh:53` and this evidence file; the new names appear in the
  module, the wrapper, the script, the test, `PROJECT_MAP.md` and the brief
  files only. No residue.
- ruff was installed in this sandbox with `sudo pip3 install -r
  requirements-dev.txt` (`~/.local` is root-owned here).

## Diff review, round 1

Arek, reviewer 2. 2026-11-01, Claude Code 2.1.312, this sandbox. Object:
`2052b5f`, `62ce6cb`, `7cbdc66` on `39f1dcc`. Verdict: no blocking finding;
the round closes the review. Two lesser findings below, fixed or deferred
without re-review.

Checked against the brief and the evidence (module, tests, fixtures, wrapper
and both small diffs read in full): `PREPARE_TOKENS`/`CEILING_TOKENS`
250000/350000 and `STALE_AFTER_S` 600 defined once (`statusline.py:30-35`),
the consumer comment above them, two `# reads-outside:` blocks at lines 9-18;
`grep -rn 'reads-outside:' --include='*.py' --include='*.sh' .` → those two
lines only (without the filter: PROJECT_MAP, the brief and this file name the
prefix, as a register must). Wrapper: lookup order equals
`create-ai-sandbox.sh:467-470`, `exec python3 -m tools.context_statusline "$@"`
as the brief states. Managed settings line 1866 equals the brief's entry;
`cp`, `COPY` and `chmod +x` mirror `ai-delegate` (1876-1877, 2051-2052,
2061-2062); test-tools asserts the key by parsing the JSON, the COPY line and
the build-context file (`assert_file`, harness.sh:30). `git diff --stat
39f1dcc..HEAD`: 19 files, all named by the brief. Commits conventional, the
Wojtek trailer present. `python3 -m unittest tools.context_statusline.test_statusline -v`
→ `Ran 10 tests`, OK; `ruff format --check` 4 files formatted, `ruff check`
clean. Real run from `/` with this session's stdin: `Fable 5.1 [33m31% 314k[0m |
[32mWrite the Go:95k[0m [32mDiff review::85k[0m` (two live agents, this
reviewer among them).

Estimate logic (`last_reply`, lines 86-110), read and scratch-run against
the module: reverse scan returns the last assistant entry's input +
cache_creation + cache_read; a `compact_boundary` met before it sets `~`,
one after it does not; a transcript ending in tool results is handled (fixture
`a1fresh` ends in a user entry); the 64 KiB tail grows 16x until it holds a
reply or covers the file (175 KiB file with 300 tool results after the reply
→ 300003 found; torn trailing line skipped; empty file → None, agent
omitted). `_cut` counts the plain text, so escapes never count against
`COLUMNS`, and the reset survives the cut (test with `COLUMNS=40`, visible
40). Missing dir, torn meta, torn jsonl, meta without transcript, `not json`
stdin: each tested, main part printed.

### Lesser

- **`statusline.py:104-107` `last_reply`, synthetic assistant entries.**
  Claude Code writes an API error or an interruption as
  `{"type":"assistant","isApiErrorMessage":true,"message":{"model":"<synthetic>",
  "usage":{all four fields 0}}}` (two subagent transcripts of this project
  hold one, each followed by the retry's real reply). While a live agent waits
  in a retry backoff that entry is its last assistant entry, so the token
  reads `label:0` in green for an agent that may hold 300k; scratch run on
  the module confirms `(0, False)`. Reachable (API overload lasts minutes),
  transient, the agent stays visible: lesser. Fix: in `last_reply` skip an
  assistant entry whose `message.model` is `"<synthetic>"` (or whose
  `isApiErrorMessage` is true) and keep scanning; add that field to the
  second `reads-outside` block and a fixture line to `a1fresh`.
- **`test_statusline.py`, coverage of two paths the brief implies.** The
  "malformed last line" case (`test_malformed_transcript_prints_main_part`)
  writes a transcript whose only line is torn, so it proves omission, not
  that a torn line after a good reply still yields that reply; the tail
  growth past `TAIL_BYTES` has no case at all. Both work (verified above by a
  scratch run, not by the suite). Fix: one more case, a fixture transcript
  with a reply, more than 64 KiB of tool results and a torn last line,
  asserting the agent's token.

Note, no action: `STALE_AFTER_S` 600 equals the Bash tool's maximum
foreground timeout, so a subagent inside a ten-minute command vanishes from
the line until its result lands. The brief fixed the value; it is reported
here only so the user recognises the gap when it shows.
