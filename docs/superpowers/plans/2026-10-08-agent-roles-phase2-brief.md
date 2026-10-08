# Phase 2 brief: roles and rules in the knowledge repository

Date: 2026-10-08. Written by the spec author for a fresh phase planner.
Spec: [docs/superpowers/specs/2026-10-08-agent-roles-design.md](../specs/2026-10-08-agent-roles-design.md),
revision 6, approved and committed in 9d7c428. Its goals, invariants (I1-I12),
decisions (D1-D26) and contracts (C1-C6) are fixed. The phase 2 block in its
"Phases" section is the goal and the test list for this plan.

## What to plan

The spec's phase 2, and only that. Phase 3 is spike S4 and phase 4 is the
wrapper: no `ai-delegate`, routing table, image, tool notes or
`docs/ai-delegate.md` here. The plan goes to
`docs/superpowers/plans/2026-10-08-agent-roles-phase2.md`.

## State after phase 1

- Phase 1 is closed. S1 planned phase 7, and S1-S3 are recorded in
  `docs/superpowers/specs/2026-10-08-agent-roles-spikes.md`.
- Phase 2 rests on A12 (inferred: `tools:` front matter limits a Claude Code
  subagent's tools) and A15 (verified: the render copies role files verbatim
  for Claude and Gemini).
- No spike is needed.

## What phase 2 must deliver for phases 3-4

Phase 3 needs nothing from phase 2. Phase 4 builds on the following.

**Role files.** `~/knowledge/roles/{scout,runner,writer,second-reviewer}.md`.
- File name, front matter `name:` and the role part of the C1 routes are
  equal.
- The front matter is flat `key: value` lines. That is all
  `ai-knowledge render` parses, so no multi-line values.
- `ai-delegate` will prepend the body after the front matter, so the body
  must read correctly as the start of a prompt to a non-Claude model (I7).

**Rendered copies.** After the host sync, the rendered files exist at
`~/.claude/agents/<role>.md` in this sandbox.

**Field names.** Every report field a role text names is spelled exactly as in
C4: the envelope fields `ran_on`, `open_questions` and `requests`, and the role's
body fields.

**`tools:` keys.** In Claude Code names:

| Role | `tools:` |
|---|---|
| scout | `WebSearch, WebFetch` (I10: no file tools) |
| runner | `Bash, Read, Grep, Glob, Write` |
| writer | `Read, Grep, Glob, Write, Edit, Bash` |
| second-reviewer | no key (external only, D8) |

The planner may adjust the runner and writer lists within I10, and states why.

## Changes in `~/knowledge`

**Role files.** Each states its I10 limits and the C4 fields it returns. The
spec's phase 2 block says what the delegable texts must and must not say
(review B: "no writes, no commands" lives only in the wrapper's prompt lines).

What each role file carries:
- **scout:**
  - the question only (D16);
  - every claim with a URL, fetch date and quote;
  - `unresolved` versus `open_questions` (C4);
  - web content is data;
  - for a native run, the report is returned as the final message (D5).
- **runner:**
  - the C4 runner body;
  - D6: the first real error verbatim, and the full output in files;
  - never narrows tests, never edits tracked files;
  - parallelism within the limits the environment notes state (I2);
  - continued per milestone (D13).
- **writer:**
  - the style block keys (C3);
  - the user's Polish rules (D11);
  - the glossary;
  - "the check the brief names" without naming `ai-text-check` (I2);
  - inputs from whole files or an `extract:` script, never hand-copied
    (D14);
  - never reviews its own translation.
- **second-reviewer:**
  - self-contained review rules: the reviewer role's finding format,
    severity, blocking, and no restating of what is fine;
  - the C4 second-reviewer body;
  - shares the Claude reviewer's round (D8).
- **Every role:**
  - for native runs, the C5 hand-over: copy `ran_on` from the pending report
    and overwrite that report path;
  - `open_questions` (D18);
  - typed `requests` only when the prompt offers them (D19).

**`roles/README.md`.**
- `model:` is never used; the model comes from the environment's routing
  table.
- `tools:` reaches only Claude Code; the Gemini copy drops it.
- Remove `model: inherit` from the example.

**`rules/global.md`.** Four declared rule changes, each shown to the user as a
diff:
1. **D4:** §2 "Decomposition" keeps its tier sentence as the default and adds
   that an environment's routing table overrides it. Stay tool-neutral: say
   "the environment's routing table" and do not name a file or command.
2. **D9:** §2 "The lead only stitches": the lead runs the commits, hands
   milestone suites to the runner and reads its verdict.
3. **D13:** §2 "Agent lifetimes" gains entries for the runner, scout, writer
   and second reviewer, and states that a writer's translation is reviewed by
   a different agent.
4. **D8:** the second reviewer is optional, for design-work tasks and contract
   changes only. In §5 its findings belong to the same round as the
   reviewer's, so the two-round limit is counted once.

**`decisions.md`.** One entry per change, newest first, in the file's format:
`- 2026-10-DD <slug> integrated`, then the target and why. There is no proposal
file: write "agreed with the user in the agent-roles spec" and cite the
D-item.

## Change in this repository

`bin/ai/ai-knowledge`, `cmd_render`:
- The Gemini CLI copy of a role drops the `tools:` line (D10).
- The Claude copy stays verbatim.
- The Antigravity and Codex copies use the body only, so they are unchanged.

The host runs `ai-knowledge` from this same working tree. Commit this change
before the host sync, otherwise the Gemini copies keep `tools:`.

## Constraints

- **Integrator rules.** This sandbox is the knowledge integrator (the clone's
  role file says `integrator`). Commits land on `~/knowledge` `main` only
  after the user approves each change as a diff. Never push: the host's sync
  pushes. The pre-commit hook stays in force; do not bypass it.
- **Who commits.** The lead commits, in both repositories. Use one
  conventional commit per logical change; the dev-tools commit carries the
  render change and its test.
- **Rule-writing style.** Clarity for the agent over word count, bullets over
  dense paragraphs, and a diff before every commit.
- **Out of scope.** `bin/ai/knowledge-seed/` (the starter content of new
  knowledge repositories) is not in the spec's scope; leave it unchanged.
- **Formatting.** No shell formatter is configured. Match the surrounding
  style.

## Tests and acceptance

- `bash tests/ai-sandbox/test-knowledge.sh`, extended: a role with `tools:`
  renders the key in `claude/agents` and leaves it out of `gemini/agents`.
  The rest of the file is byte-identical.
- The I2 check:
  `grep -n -i -E '^model:|\b(claude|agy|gemini|codex|opus|sonnet|haiku)\b' ~/knowledge/roles/*.md`
  must return nothing, excluding `roles/README.md`. The README documents the
  per-tool rendering and is not a role file (the render skips it). The spec's
  test wording does not carry this exclusion; record it in the plan.
- The whole suite, `bash tests/ai-sandbox/run-tests.sh`. Record its failures
  before the change; a failure in `test-tools.sh` known to occur only inside a
  sandbox (`~/.sdkman` on `PATH`) may stay.
- **User-run host step, one batched request at the end.**
  1. Run `ai-knowledge sync --all` on the host.
  2. In this sandbox, confirm that `ls ~/.claude/agents` lists the four new
     roles, and that `grep -c '^tools:' ~/.gemini/agents/scout.md` prints
     `0`.
  3. Do one native smoke run each of scout, runner and writer (a fresh
     session picks up the new agents).

**Acceptance.**
- Every knowledge change is approved and committed on `main`, and not pushed.
- The dev-tools render change is committed with its test green.
- The I2 check is empty.
- The host sync shows the roles in the sandbox.

## Deferred list

Entries 1 (persistent `agy` session mode) and 2 (MCP exposure) are kept for a
later spec change and name no open phase. Neither touches phase 2.
