# Agent roles routed to other models and agents

Date: 2026-10-08
Status: draft, revision 2 after review round 1
([2026-10-08-agent-roles-design-review-1.md](2026-10-08-agent-roles-design-review-1.md)),
awaiting the user's approval
Input: [2026-10-08-agent-roles-brief.md](2026-10-08-agent-roles-brief.md)
(the user's decisions there are fixed and are not restated as open questions)
Related task: [2026-10-08-ai-sandbox-agy-delegation-brief.md](2026-10-08-ai-sandbox-agy-delegation-brief.md),
managed settings for `agy` in the image, committed as 6a6d25b and not yet
built on the host.
Scope:
- `~/knowledge`: `rules/global.md`, `roles/` and `decisions.md`, in the
  integrator clone, each change approved by the user.
- This repository:
  - `bin/ai/ai-knowledge`, for the render;
  - new: `bin/ai/ai-delegate`, `bin/ai/agent-routing` and
    `bin/ai/ai-text-check`;
  - `bin/ai/create-ai-sandbox.sh`, for the image, the managed settings and the
    tool notes;
  - `tests/ai-sandbox/` and `PROJECT_MAP.md`.

## Goal

The lead spends fewer tokens per piece of work because each layer reads more
than it passes up. Four new roles (scout, runner, writer, second reviewer)
return short reports in a fixed JSON shape, and the roles that suit another
vendor run there. A per-environment routing table, not the role files, decides
which tool and model run each role. When the preferred tool is unavailable or
not allowed, the role runs on Claude; the second reviewer is skipped instead.
Every report says which agent actually ran.

## Invariants

- **I1 Flat topology.** Only the lead spawns agents and calls `ai-delegate`.
  A delegated agent never spawns, delegates or continues another agent.
  - The runner and writer roles forbid calling `ai-delegate` or `agy`.
  - `ai-delegate` also refuses a caller it can identify as a subagent, if S1
    finds a marker that identifies one. Without such a marker, the rule is
    prose only for native agents with a shell.
- **I2 Role files are tool-neutral.**
  - No role file names a tool, CLI, vendor or model, and none carries a
    `model:` key.
  - Environment facts, such as CPU and memory limits or installed tools, come
    from the environment notes.
- **I3 Routing lives in the routing table.** Changing which tool or model runs
  a role edits the table, never a role file. `global.md` keeps the default
  tiers for environments without a table (D4).
- **I4 Project content reaches another vendor only by an opt-in the gated
  agent cannot grant itself.**
  - `ai-delegate` sends nothing to a non-Anthropic tool unless the allow file
    (C2) lists that tool.
  - The allow file counts only when root-owned and not writable by the
    invoking user.
  - The sandbox image ships it together with the Claude Code permission and
    auto-mode rules. On the host the user creates both (D3).
- **I5 External agents write nothing and see only what the brief may carry.**
  - An agent run through `ai-delegate` gets its inputs inline in the prompt,
    runs in an empty working directory, and returns one JSON document.
  - The wrapper alone writes the report and any writer output, under the C3
    path rules.
  - The wrapper never runs a command named in a brief.
- **I6 Confinement by mechanism.**
  - An external route is used only for a role with a confinement profile that
    phase 1 showed the tool enforces: web search and fetch for the scout, no
    tools for the writer and the second reviewer.
  - The wrapper resolves any other external route to its fallback, whatever
    table is in use.
  - Prose in a prompt does not count as confinement.
- **I7 Self-contained prompts.**
  - A prompt sent to a non-Claude model states every convention the task
    depends on. It relies neither on `global.md` nor on Claude defaults.
  - The delegable role files restate what they need from the global rules.
  - The writer's style reaches the model as an explicit style block (C3).
- **I8 Reports are schema-shaped and honest.**
  - Every report of a role in this spec conforms to C4 and names the tool and
    model that ran it, including a fallback and its reason.
  - Non-conforming output is stored as `failed` with the raw output beside it,
    and is never repaired by hand.
- **I9 Fallback is never silent.** If the preferred tool is unavailable, not
  allowed or not confined, the role runs on the route's fallback and the report
  says so. For a route whose fallback is `none`, the report has status
  `skipped` and the summary "second review skipped (no other vendor
  available)".
- **I10 Role limits.**
  - The scout has no file access and no shell, and receives only its question.
  - The runner never edits tracked files, never narrows the selected tests and
    never ignores a failure.
  - The writer edits only the text files its brief names, never code, and
    never reviews its own translation.
  - The second reviewer comes from a vendor other than Anthropic and is never
    spawned as a Claude subagent. Its findings belong to the Claude reviewer's
    round, so the two-round limit is counted once. `ai-delegate` refuses an
    Anthropic model or a Claude fallback on a `second-reviewer` route, whatever
    the table says, and resolves such a route to `none`.
- **I11 Knowledge repository discipline.**
  - Changes reach `~/knowledge` `main` only with the user's approval per
    change, each with a `decisions.md` entry.
  - Nothing is pushed from here; the host's sync pushes.
  - Roles keep rendering for all four tools.
- **I12 No new host manipulation.**
  - Code this work adds writes nothing under the host's `~/.claude`, its
    settings or the seeded `$SANDBOX_DIR/.claude`.
  - The existing `ai-knowledge` render and `wire_host`, which link rendered
    roles into the host's `~/.claude/agents`, are unchanged and exempt.
  - Sandboxes get their permissions from the image.

## Non-goals

- A mechanical-editor role, and a summarizer or reporter role (declined in the
  brief).
- A locator role. The brief ranks it low priority; a later spec may add it.
- `codex` as a routed tool. It is not signed in here (verified: `codex login
  status` prints "Not logged in"). Phase 1 answers open point 3 for `codex`
  from documentation only, and a spec change can add it later.
- Sub-leads or any nested spawning (I1).
- Resource formats for `ai-text-check` beyond Markdown, JSON and Java
  properties (D14).
- The runner on another vendor. It needs the whole tree and a shell, which I6
  cannot confine.
- Measuring Gemini quality beyond the acceptance spot checks (open point 5).
- External agents on the host without the user's own opt-in (I4, D3).

## Decisions for the user

Each item is for the user to confirm or change. D3 and D14 were left open by
the review, and the safer option is chosen.

- **D1 One entry point for the four roles.** For scout, runner, writer and
  second reviewer, the lead always calls `ai-delegate run <brief>`. An
  external route runs there. A Claude route, or a fallback, yields a `pending`
  report naming the Claude model, and the lead spawns the native subagent
  (hand-over in C5). `ai-delegate route` serves the other roles' model choice.
  Reason: native subagents keep the harness's one-hour cache, continuation by
  name and the UI, and the lead branches on one status field.
- **D2 Name.** The wrapper is `bin/ai/ai-delegate`, matching the `ai-*`
  helpers, and the image installs it as `/usr/local/bin/ai-delegate`.
- **D3 Host opt-in (open in the review; safer option chosen).** The only
  allow file is `/etc/ai-sandbox/delegate-allow`, and it must be root-owned
  and not writable by the invoking user. No allow file under `$HOME` exists.
  - On the host, the user opts in by creating that file with `sudo` and by
    adding the `Bash(ai-delegate *)` permission and an auto-mode sentence to
    their own user settings. That is the brief's "permission rule + auto-mode
    entry", plus a gate an agent cannot write.
  - In a sandbox the user has passwordless `sudo`, so the gate there is the
    image's; the user has already consented to it.
  - Alternative: the wrapper reads the user settings for the rule. Rejected,
    because an agent can write those files.
- **D4 Tiers.** `global.md` §2 keeps its tier sentence as the default. The
  routing table overrides it where it exists, and the table's Claude rows equal
  the §2 defaults.
- **D5 Report placement.** The native runner and writer write their own report
  at the path the pending report names. A native scout has no write tool, so it
  returns the JSON as its final message, and the lead writes it to the same
  path.
- **D6 Runner output (global §4).**
  - The report quotes each failure's first real error verbatim.
  - The full, untrimmed output of every failure goes to a file the report
    names.
- **D7 Delegation files.**
  - Briefs, reports and logs live in `<git toplevel>/.ai-delegate/`.
  - `ai-delegate` adds that directory to `.git/info/exclude`.
- **D8 Second reviewer.**
  - It has its own role file, external-only, with no `tools:` key.
  - It runs in parallel with the Claude reviewer on the same plan and diff, and
    both reports form one round.
  - Round 2 uses `--continue`.
- **D9 Milestone suites (open point 2).** Global §2 changes: the lead runs the
  commits, hands milestone suites to the runner and reads its verdict.
- **D10 Render.** `ai-knowledge render` drops `tools:` from the Gemini CLI
  copy, because Gemini's tool names differ from Claude's.
- **D11 Polish style.** The writer role states the user's Polish rules for
  native runs. `ai-delegate` refuses a writer brief whose style block lacks a
  required key (C3).
- **D12 Lead role file.** The brief says the lead would not load a role file,
  but `claude --agent <agent>` and an `agent` setting exist (`claude --help`,
  2.1.287), so the brief should be corrected. Spike S1 decides whether a lead
  file is worth it, and phase 6 runs only if it is.
- **D13 Lifetimes of the new roles**, added to global §2 "Agent lifetimes" in
  phase 2:
  - runner: one per milestone, continued for every suite run and diagnosis in
    that milestone;
  - scout: one per question, retired after its report;
  - writer: one per text task, alive until accepted;
  - second reviewer: one per review, continued for round 2.
  A writer's translation is reviewed by a different agent.
- **D14 Writer scripts (open in the review; safer option chosen).**
  - A writer brief must name `check:`. The lead runs that check for external
    runs, and the native writer runs it itself. The wrapper never runs it.
  - Phase 4 ships `bin/ai/ai-text-check`, which compares source and
    translation:
    - Markdown: code spans, fenced blocks, link targets and heading count;
    - JSON and Java properties: key sets, placeholders, markup tags and ICU
      plural categories.
  - Inputs are whole resource files, or the output of an extraction script the
    brief names in `extract:`; never hand-copied strings. The lead or the
    native writer runs `extract:` as its own Bash call, writing under
    `.ai-delegate/`; the wrapper never runs it.
  - Plural categories: a small embedded table for the languages actually
    used, `pl` (one, few, many, other) and `en` (one, other), cited to CLDR.
    Other target languages are refused with a message. This avoids a
    dependency. Fetching or installing CLDR data instead would be a new
    external dependency that the phase 4 plan declares (🟡).
  - Alternative: per-project scripts only, with no shipped checker.
- **D15 Path rules and secret patterns** (C3).
- **D16 The scout receives the question only.** No inputs are inlined, because
  a prompt-injected page could have the scout fetch a URL carrying them.
- **D17 One-shot calls for now (user decision, 2026-10-08, after S2).**
  - Every external call is a one-shot `agy -p`.
  - `--continue` is a fresh call with the previous report inlined.
  - A persistent stream-json session mode is planned but deferred, not
    implemented (deferred list, entry 1).
- **D18 Open questions in every report (user decision, 2026-10-08).**
  - The C4 envelope carries `open_questions`, and each question is marked
    blocking or answered by a stated assumption.
  - The lead answers them through `--continue`, asking the user first when an
    answer is the user's decision.
  - A report with blocking open questions is not accepted (C5).

## Contracts

Names, fields and exit codes are binding. Bodies are the implementer's.

### C1 Routing table (`bin/ai/agent-routing`)

- Plain text, one route per line, fields separated by whitespace; `#` starts a
  comment.
- A route is `<role>` or `<role>.<variant>`, and the role part names the role
  file.
- `effort` is `-` for the tool's default.
- `fallback` is `claude:<haiku|sonnet|opus>`, `none`, or `-` when the route is
  already Claude.
- Gemini routes use the `-high` variants.

The defaults come from the brief:

```
# route              tool    model                  effort  fallback
planner.spec         claude  opus                   -       -
planner.phase        claude  sonnet                 -       -
implementer          claude  sonnet                 -       -
reviewer.diff        claude  opus                   -       -
reviewer.plan        claude  sonnet                 -       -
second-reviewer.diff agy     gemini-3.1-pro-high    -       none
second-reviewer.plan agy     gemini-3.8-flash-high  -       none
scout                agy     gemini-3.8-flash-high  -       claude:sonnet
writer               agy     gemini-3.8-flash-high  -       claude:sonnet
runner               claude  haiku                  -       -
```

Lookup order: `~/.config/ai-delegate/routing`, then
`/etc/ai-sandbox/agent-routing`, then the copy next to `ai-delegate`. The first
file found is used whole; files are not merged. A user-writable table can
choose models but cannot widen I4, I6 or I10: the gate, the confinement
profiles and the second-reviewer rule are checked after the lookup. On a
`second-reviewer` route, a `claude` tool, an Anthropic model or a `claude:`
fallback is treated as `none`, so the review is `skipped`, never run on
Claude.

### C2 Opt-in allow file

- Path: `/etc/ai-sandbox/delegate-allow`, one tool name per line.
- It is ignored unless it is owned by root, is not group- or world-writable,
  and is not writable by the invoking user. Absent or ignored means no tool is
  allowed.
- The image installs it containing `agy`. Its managed settings, from 6a6d25b,
  gain `Bash(ai-delegate *)` in `permissions.allow` and an `autoMode.allow`
  sentence that names `ai-delegate` as an approved way to send project content
  to `agy`.

### C3 Brief file

Markdown with flat `key: value` front matter. Lists are space-separated paths
relative to the git top level.

```markdown
---
route: writer                        # required; a C1 route of scout, runner, writer or second-reviewer
report: .ai-delegate/<name>.report.json   # optional; default <brief>.report.json
inputs: docs/a.md docs/glossary-pl.md     # inlined into the prompt; forbidden for scout
outputs: docs/a.pl.md                # writer only, required: the only paths written
check: ai-text-check docs/a.md docs/a.pl.md   # writer only, required; never run by the wrapper
extract: <command>                   # writer: run by the lead or native writer into .ai-delegate/; never by the wrapper
round: 1                             # second reviewer only
timeout: 10m                         # optional
---
<the task: what, for whom, acceptance; for the scout, the question only>

## Style
language: pl
addressee: <who; grammatical gender; person, with one example verb form>
english-terms: <rule, with inflection examples: "do runnera", "w cache'u", "tego commita">
gender-neutral: never
glossary: <path; also listed in inputs>
```

**Style.**
- `## Style` is required for `writer`, with all five keys. For other routes it
  is optional, and `language: en` is assumed.
- Each key becomes a full sentence of the prompt. Unknown keys pass through
  verbatim; none is dropped.

**Path rules (D15).** A violation exits 2 before anything runs.
- The brief, `report` and any `--continue` report resolve, after `realpath`,
  under `<top>/.ai-delegate/`.
- `inputs`:
  - each is a regular file whose realpath is under the top level and not under
    `.git/`;
  - each is tracked by git or lies under `.ai-delegate/`.
- `outputs`:
  - each resolves under the top level, outside `.git/` and `.ai-delegate/`;
  - none is a symlink or an executable file;
  - the extension is one of `md txt rst adoc json properties po xliff xlf
    yaml yml arb strings`.
- Secret patterns: a path whose basename matches, case-insensitively, `.env`,
  `.env.*`, `.netrc`, `id_*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`,
  `*.keystore`, `*credential*` or `*secret*` is refused in any key.
- Per route:
  - a scout brief has no `inputs`, `outputs`, `check` or `extract`;
  - a writer brief without `outputs` or `check` is refused.

### C4 Reports (JSON, `agent-report/1`)

The envelope is the same for every role:

```json
{ "schema": "agent-report/1",
  "route": "scout",
  "ran_on": {"tool": "agy|claude", "model": "...", "fallback_reason": null},
  "session": null,
  "usage": {"input_uncached": 0, "cache_read": 0, "output": 0, "thinking": 0},
  "status": "done|partial|failed|pending|skipped",
  "summary": "<= 60 words",
  "open_questions": [{"question": "...", "reason": "why it blocks, or what was assumed instead",
                      "blocking": true}],
  "body": {} }
```

- `fallback_reason` is one of `null`, `not-signed-in`, `not-allowed`,
  `not-confined`, `tool-error`.
- `session` holds the external tool's `conversation_id`, and is `null` for a
  native run.
- `usage` holds the per-call token counts of an external run, and is `null`
  for a native run:
  - `agy` reports `input_tokens` as the uncached part only, with
    `cache_read_tokens` beside it, not inside it.
  - All of its counters are cumulative over a conversation.
  - The wrapper therefore records the per-call delta of each counter, which
    for a one-shot call equals the reported value. The recorded `session`
    and `cache_read` keep A7 measurable later (S2).
- `body` is `null` when the status is `pending` or `skipped`.
- `open_questions` lists the questions the delegated agent could not answer
  from its prompt. The list is `[]` when there are none.
  - Each entry carries the question and a reason. The reason says why the
    work is blocked or, when it is not, what was assumed instead.
  - `blocking` is `true` when the work is blocked, and `false` when it was done
    under the stated assumption.

The body depends on the role:

```json
// scout
{"question": "...", "answer": "<= 150 words, each sentence backed by claims",
 "claims": [{"id": 1, "claim": "...", "url": "...", "fetched": "YYYY-MM-DD",
             "quote": "verbatim, <= 40 words"}],
 "unresolved": ["..."]}
// runner
{"command": {"original": "...", "final": "...", "why_changed": "... | null"},
 "exit_code": 0, "verdict": "pass|fail|build-broken|env-limit",
 "tests": {"run": 0, "failed": 0, "skipped": 0},
 "failures": [{"test": "...", "first_error": "verbatim", "output_file": "..."}],
 "log_file": "..."}
// writer (an external agent also returns "content" per output; the wrapper
// writes it and stores the report without it)
{"outputs": [{"path": "...", "source": "...", "language": "pl", "words": 0}],
 "check": {"command": "...", "exit_code": null, "output": "first 40 lines | null"},
 "glossary_proposals": [{"term": "...", "proposed": "...", "why": "..."}]}
// second-reviewer
{"object": "diff|plan", "round": 1, "verdict": "block|pass",
 "findings": [{"severity": "critical|important|minor", "file": "...",
               "symbol": "...", "scenario": "...", "resolution": "..."}]}
```

The scout's `unresolved` lists research questions the web did not answer, which are findings; the envelope's `open_questions` lists what blocks the work or what was assumed instead.

`check.exit_code` stays `null` after an external run. The lead runs the
check as its own Bash call.

### C5 `ai-delegate` and the fallback hand-over

```
ai-delegate route <route>
  stdout: <tool>\t<model>\t<effort>\t<reason>   # resolved; reason "-" or a fallback_reason
  exit 0 resolved | 3 resolves to none | 2 unknown route or bad table
ai-delegate run <brief> [--continue <previous report>]
  stdout: "<status> <report path>"
  exit 0 an external agent ran (any status in the report)
  exit 3 nothing ran here; the report is pending (spawn the native role) or skipped
  exit 2 invalid brief or path rule violated; nothing run, no report
```

**Hand-over after exit 3 with `pending`.** The pending report carries the
final `ran_on`: `tool: claude`, the model, and the `fallback_reason`
(`null` when the route itself is Claude).
1. The lead spawns the native role with that model and gives it two paths:
   the same brief and the report.
2. The native agent copies `ran_on` from the pending report and overwrites
   the report at that path with its final report. For a scout, the lead writes
   the returned JSON there.
3. A report still `pending` afterwards means the native run did not happen.

**Open questions.** The lead answers a report's `open_questions` with
`--continue`, a fresh call with the answers inlined. When an answer is the
user's decision, the lead asks the user first. A report with any blocking open
question is not accepted until a continued run resolves it (D18).

**`--continue`.** It makes a fresh one-shot call with the brief and the
previous report inlined, and never resumes `session`. S2 failed its rule on
call 2 in one of two runs (D17).

## Assumptions

Status is one of **verified** (seen here), **inferred** (from documentation or
a neighbouring fact) or **guessed**.

| # | Assumption | Status | Checked by |
|---|---|---|---|
| A1 | `agy` print mode: `-p` with the prompt right after it, `--model`, `--effort`, `--output-format text\|json\|stream-json`, `--json-schema`, `--print-timeout`, `--conversation`, `--mode`, `--sandbox`, `--dangerously-skip-permissions` | verified (`agy --help`, agy 1.1.22) | - |
| A2 | `agy models` lists `gemini-3.1-pro-high` and `gemini-3.8-flash-high` | verified (run 2026-10-08) | - |
| A3 | When `agy` is not signed in, `agy models` prints "Please sign in" | inferred (the brief; agy is signed in here) | S3 |
| A4 | `--output-format json` exposes the final text, a conversation id and token usage including cached tokens | verified (S2: `response`, `conversation_id`, `usage.cache_read_tokens`; `input_tokens` is the uncached part, and all counters are cumulative over a conversation) | S2 |
| A5 | `--json-schema` makes the final output conform to the schema | guessed | S3 |
| A6 | `agy` can be confined to web search and fetch only, or to no tools, with no read of the repository, `~/.claude` or `~/.config`, no write and no shell | guessed; decides I6 | S3 |
| A7 | `agy --conversation` reuses a provider-side cache between calls | not reliably shown (S2: call 2 cached 0 % in run A and 77.5 % in run B, corrected shares; later calls 88-90 %); not relied on (D17) | S2 |
| A8 | `codex exec resume` reuses a provider-side cache | not shown (S2: `codex` help is silent on caching; nothing run, codex not logged in) | S2 |
| A9 | Claude Code subagents receive the user-level `CLAUDE.md` | verified (it is in this spec author's subagent context, and in the reviewer's) | - |
| A10 | Some session mechanism (`claude --agent`, the `agent` setting, or `--append-system-prompt-file`) adds a lead body while keeping the default system prompt and `CLAUDE.md` | guessed (the flags exist: `claude --help`) | S1 |
| A11 | The Agent tool takes a model alias (`haiku`, `sonnet`, `opus`) per spawn | verified (Agent tool schema) | - |
| A12 | A subagent's `tools:` front matter limits its tools | inferred (Claude Code documentation) | phase 2 test |
| A13 | Claude Code reads `/etc/claude-code/managed-settings.json` on Linux, `autoMode` included | inferred (binary inspected, per the brief; not built on the host; absent from this older sandbox's image) | phase 5 |
| A14 | A `Bash(ai-delegate *)` rule plus an auto-mode sentence let a bare `ai-delegate` call through | inferred (the same mechanism verified for `agy -p`) | phase 5 |
| A15 | `ai-knowledge render` copies role files verbatim to `claude/agents` and `gemini/agents`. A sandbox mounts the host render read-only at `~/.claude/agents` | verified (`cmd_render`; the compose block in `create-ai-sandbox.sh`) | - |
| A16 | python3 is available to `ai-delegate` in the sandbox and on the host | verified in the sandbox (3.10.12); inferred on the host | - |
| A17 | gemini-3.8-flash-high is good enough for scout, writer and plan reviews | guessed (open point 5) | phase 5 spot check |
| A18 | An explicit style block fixes the uninflected terms and the mixed translations seen in the brief's test | guessed | phase 5 |
| A19 | A subagent's shell can be told apart from the main session's, for example by an environment variable | guessed | S1 |

## Phases

### Phase 1 -- spikes: what the tools actually do (no code, no rule change)

**Goal.** Open points 1 and 3, and every guessed assumption that decides
feasibility (A4-A8, A10, A19), are answered by measurement or documentation
before any role or wrapper depends on them.
- The answers go to `docs/superpowers/specs/2026-10-08-agent-roles-spikes.md`,
  each with the command and the output line that shows it, or a documentation
  URL with its fetch date and a quote.
- The assumption table is updated. Any spec change goes to the user before
  phase 2 is planned.

**Spikes and their decision rules, fixed before measuring.**

- **S1 (open point 1: A10, A19).** A9 is already verified. In a scratch
  directory with its own `CLAUDE.md` carrying a canary, run headless `claude -p`
  three ways: with `--agent <scratch agent>`, with `--append-system-prompt-file`,
  and with the `agent` setting. For each, record:
  - whether the session keeps the default system prompt and `CLAUDE.md`
    (canary and user rules visible, tool use intact);
  - the first request's input tokens;
  - whether a spawned subagent's shell sees a variable the main session's
    shell lacks.

  Decision rules:
  - If one mechanism keeps both, phase 6 is planned on it.
  - If none does, phase 6 moves to the non-goals.
  - If a marker exists, `ai-delegate` refuses subagent callers (I1).
- **S2 (open point 3: A4, A7, A8).** Make two `agy -p` calls on one
  `--conversation` with a prefix of more than 4,000 tokens, then two fresh
  calls, and compare the reported cached input. Reuse counts as shown when the
  second call on the conversation reports at least 50 % of its input as cached.
  - If `agy` reports no usage, the documentation decides. If that is silent
    too, there is no reuse.
  - `codex exec resume` is checked by documentation only.
  - With reuse, `--continue` resumes `session`. Without it, `--continue` sends
    a fresh call with the previous report inlined.
  - **Done (2026-10-08, [2026-10-08-agent-roles-spikes.md](2026-10-08-agent-roles-spikes.md)).** The rule failed:
    - run A's call 2 had 0 % cached, a complete resend;
    - run B's call 2 had 77.5 %, a corrected share;
    - later calls had 88-90 %.
    `codex` documentation is silent. Outcome: no reliance on reuse, and
    `--continue` is a fresh call (C5, D17). S2b measured a persistent
    stream-json session, now deferred (deferred list, entry 1).
- **S3 (A3, A5, A6).** Measure:
  - the JSON output shape and the exit codes;
  - whether `--json-schema` is enforced;
  - which tools print mode offers with and without
    `--dangerously-skip-permissions`, `--mode plan` and `--sandbox`;
  - from an empty directory, whether a run can read the repository by absolute
    path, `~/.claude` or `~/.config/gcloud`, write a file, or run a shell;
  - the not-signed-in message, under a `HOME` without credentials.

  The confinement profiles of I6 are set from these results. A role whose
  profile is not shown stays on its fallback, `not-confined`.

**Contract needed.** None.

**Tests.** The spikes file, read against the decision rules. Spike scripts stay
in the scratchpad.

**Assumptions.** `agy` stays signed in here (verified today).

### Phase 2 -- roles and rules in the knowledge repository

**Goal.**
- `~/knowledge` `main` has four new role files:
  - `roles/scout.md`, `roles/runner.md` and `roles/writer.md`, each stating
    its I10 limits and the C4 body it returns;
  - `roles/second-reviewer.md`, external-only, with no `tools:` key and a
    description saying it is never spawned natively.
- The delegable role files are self-contained (I7), and no role file names a
  tool or model (I2).
- `roles/README.md` says that `model:` is never used and that `tools:` reaches
  only Claude Code.
- `global.md`:
  - §2 Decomposition keeps the tiers as defaults that a routing table
    overrides (D4);
  - the lead hands milestone suites to the runner (D9);
  - Agent lifetimes gains the D13 entries;
  - §2 and §5 say the second reviewer is optional, for design work and
    contract changes only, and shares the reviewer's round (D8).
- `decisions.md` gets one entry per change.
- `ai-knowledge render` drops `tools:` from the Gemini copy (D10).

**Contract from phase 1.** S1's answer and S3's profiles. These decide routes
and phase 6, not the role text.

**Tests.**
- `bash tests/ai-sandbox/test-knowledge.sh` is extended: `tools:` is rendered
  for Claude and left out for Gemini.
- A search of `~/knowledge/roles/` finds no `model:` key and none of the
  names `claude`, `agy`, `gemini`, `codex`, `opus`, `sonnet` and `haiku`.
- Then the whole suite runs.

**User-run host step (batched, ends the phase).** The rendered agents in a
sandbox are a read-only mount of the host render, and `main` is unpushed until
a host sync. So the user runs `ai-knowledge sync --all` on the host, then
confirms that `ls ~/.claude/agents` in this sandbox lists the four roles. The
same request asks for one native smoke run of each Claude-capable role.

**Done when.** The changes are approved and committed on `main`, and the host
sync shows the roles in the sandbox.

**Assumptions.** A12, A15.

### Phase 3 -- `ai-delegate`, routing table and sandbox wiring

**Goal.**
- `ai-delegate route` and `run` behave as C5 says, on C1, C2, C3 and C4.
- The prompt is the role body from `~/.claude/agents`, the rendered style
  block, the brief, and then the inlined inputs.
- `agy` runs in an empty directory under the profile S3 found.
- A non-conforming output is stored as `failed` with a `.raw` file beside it.
  Writer outputs are written only to the `outputs:` paths.
- A route that is not signed in, not allowed or not confined yields a
  `pending` report; a `none` route yields `skipped`.
- `.ai-delegate/` is excluded locally.
- The image installs `ai-delegate`, `/etc/ai-sandbox/agent-routing`, and a
  root-owned `/etc/ai-sandbox/delegate-allow`. The managed settings from
  6a6d25b gain the C2 rule and sentence.
- The tool notes tell the lead to call `ai-delegate run` for the four roles
  and how to follow exit 3.
- `docs/ai-delegate.md` holds a short host opt-in how-to for D3: create the
  root-owned allow file with `sudo`, add the `Bash(ai-delegate *)` permission
  rule to the user settings, and add the auto-mode sentence. The tool notes
  point to it.
- `PROJECT_MAP.md` is updated.

**Contract from phases 1-2.** S2 (the `--continue` mechanism); S3 (flags,
output shape, profiles); S1 (subagent marker); and the rendered role bodies.

**Tests.** A new `bash tests/ai-sandbox/test-delegate.sh`, with a stub `agy`
(signed in, signed out, malformed output, timeout) and a fake `HOME`, covers:
- every lookup level, with exit codes 0, 2 and 3;
- the allow file ignored when it is user-writable;
- an external runner route resolving to `not-confined`;
- a Claude route yielding `pending` with the right `ran_on`;
- refusals for `.env`, `../`, `.git/hooks`, a report outside `.ai-delegate/`,
  scout `inputs`, and a writer without `check`;
- a `check:` never executed;
- style keys present as sentences;
- a skipped second review;
- a report with `open_questions` accepted, and the schema check rejecting a
  malformed entry (missing `question`, or a non-boolean `blocking`), which is
  stored as `failed` with its `.raw` file;
- a table that routes `second-reviewer` to `claude` or gives it a `claude:`
  fallback, which still yields `skipped`.

`test-tools.sh` is extended for the image files, the ownership and the
settings. Then the whole suite runs.

**Assumptions.** A13, A14 and A16, plus A1-A6 as phase 1 leaves them.

### Phase 4 -- `ai-text-check`

**Goal.** `ai-text-check <source> <translation>` exits non-zero and names each
difference:
- Markdown: code spans, fenced blocks, link targets and heading count;
- JSON and Java properties: key sets, placeholders (`{x}`, `{{x}}`, `%s`,
  `%1$s`), markup tags, and ICU plural categories required for the target
  language.

It runs locally and sends nothing anywhere. The image installs
`/usr/local/bin/ai-text-check`. The tool notes name it as the default
`check:`, while the writer role says only "the check the brief names" (I2).
Phase 4 does not touch `~/knowledge`, so it needs no knowledge approval, no
`decisions.md` entry and no host sync.

**Contract from phase 3.** C3's `check:` key, which this checker fills.

**Tests.** `bash tests/ai-sandbox/test-text-check.sh` uses fixtures for each
format, each with one passing pair and one pair per kind of difference. Then
the whole suite runs.

**Assumptions.** Plural categories come from an embedded table for `pl` and
`en`, its values taken from CLDR with the source cited (global §2), not from
memory. No CLDR package is added. If one were needed, it would be a 🟡
dependency declared in the phase 4 plan.

### Phase 5 -- acceptance in a rebuilt sandbox (user-run rebuild)

**Goal.** In a sandbox the host recreated with the new image:
- the lead runs `ai-delegate` unprompted;
- a scout answers a factual question, every claim carrying a URL, a date and
  a quote;
- a writer translates a ~600-word note into Polish with a glossary and a full
  style block, and `ai-text-check` passes. The user judges the inflection and
  the one-translation-per-term rule (A18).
- a second reviewer reviews a small real diff;
- the native runner runs `bash tests/ai-sandbox/run-tests.sh` as a milestone
  suite through the hand-over. The lead's context grows only by the report.
- with `agy` signed out, the scout and the writer go `pending`, the native
  agents overwrite the same report paths with `not-signed-in`, and the second
  review is `skipped`.

The phase 5 plan writes the commands as one batched request.

**Contract from phases 3-4.** The finished wrapper, checker and image.

**Assumptions.** A13, A14, A17 and A18. If a check fails, the route changes in
the table, not in a role.

### Phase 6 -- lead role file (only if S1 says so)

**Goal.**
- The lead-only rules move from `global.md` into `roles/lead.md`:
  - the lead only stitches;
  - agent lifetimes;
  - forks;
  - the cache rule;
  - the user sees only reviewed versions;
  - the round loop.
- Sessions start with that file through the mechanism S1 verified.
- Every other agent's prefix shrinks by the moved words, measured with S1's
  method. `global.md` keeps one pointer sentence.

**Contract from phase 1.** S1 names a mechanism that keeps the default prompt
and `CLAUDE.md`. Without one, this phase moves to the non-goals.

**Tests.** S1's measurement repeated before and after. The user approves each
knowledge change, and a host sync follows as in phase 2.

**Assumptions.** A10 as phase 1 leaves it. Selecting the agent in a sandbox
(launcher flag or managed setting) is for the phase plan, within I12.

## Deferred list

Cap: ten open entries; see the planner rules for folding, keeping and
dropping.

1. **Persistent `agy` stream-json session mode** (planned by the user, deferred
   2026-10-08; D17). Kept for a later spec change, not addressed to an open
   phase.
   - **Measured** ([2026-10-08-agent-roles-spikes.md](2026-10-08-agent-roles-spikes.md), S2b and repeats):
     - turn 2 had 86-90 % cached in 3 of 3 sessions, and later turns 69-93 %;
     - the cached part is agy's fixed prefix of about 24.5k tokens;
     - there is no latency gain to separate beyond about 2-3 s of start-up per
       call, since thinking tokens dominate turn time.
   - **Working command:**
     `agy --input-format stream-json --output-format stream-json --model <id>`,
     run with stdin held open and no `-p`. Each turn is one NDJSON line:
     `{"event":"user","message":{"role":"user","content":"<text>"}}`.
     - Output is NDJSON events (`init`, `step_update`), plus one `result` per
       turn.
     - An unsupported `event` value is dropped with only a stderr warning.
   - **Plumbing it needs:**
     - a per-turn timeout of the wrapper's own;
     - subtraction of the cumulative counters, or use of the step usage;
     - a parent process that holds stdin (closing stdin ends agy with exit 0);
     - stderr capture;
     - a fallback that re-inlines the previous report when the process is
       gone.
   - **Pick it up when:** a role with three or more dependent turns per
     milestone becomes common.
