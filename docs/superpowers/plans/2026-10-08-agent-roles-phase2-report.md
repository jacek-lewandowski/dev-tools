# Phase 2 report: roles and rules in the knowledge repository

## T5. A12 check (lead, 2026-10-08)

**Result: pass.** A `tools:` list limits a native subagent: an inline subagent defined with
`tools: ["WebSearch","WebFetch"]` had only those two tools; Read and Bash were not available to it.

Command (claude 2.1.287, run from an empty scratch directory; the flag form is `--agents <json>`):

```
claude -p --model haiku --verbose --output-format stream-json \
  --agents '{"probe":{"description":"Probe agent for a tool-restriction test","prompt":"You are a probe. Try to read the file /etc/hostname with the Read tool, then try to run `echo hi` with the Bash tool. Report, for each attempt, either the exact result or that the tool is not available to you. Then list the names of all tools you have.","tools":["WebSearch","WebFetch"]}}' \
  "Call the Agent tool now, exactly once, with subagent_type \"probe\" and prompt \"Run your test and report.\" Then output the probe's report verbatim and nothing else."
```

Evidence from the stream (main session had 38 tools):

```
tool_use parent=None name=Agent input={"subagent_type": "probe", "description": "Probe test execution", "prompt": "Run your test and report."}
RESULT: ... Attempt 1: Read /etc/hostname — I do not have a "Read" tool. The tools available to me
are WebSearch and WebFetch ... Attempt 2: Run `echo hi` with Bash — I do not have a Bash tool
available ... Available Tools: 1. WebSearch 2. WebFetch
```

Runs: the first attempt (prompt "Delegate to the probe agent ...") was inconclusive because the
outer session did not delegate; the retry with an explicit Agent-tool instruction passed (plain
JSON output), and a third run with `stream-json` confirmed the Agent call was real rather than a
report written by the outer session. The probe made no tool calls: the tools were absent, not
refused at call time.

Scope: this proves the `tools` field of an inline definition; T8's scout smoke run re-checks it
with the rendered file in `~/.claude/agents`.

## T6. Approval gate and commits (lead, 2026-10-08)

The user approved all six changes and the spec's C4/C5 native-scout hand-over in one answer.
Commits on `~/knowledge` main, each with its decisions.md entry (not pushed):

- 72083e0 feat(roles): scout, runner, writer and second reviewer roles (agent-roles-roles)
- 4e23674 docs(roles): README drops model:, documents tools: for Claude Code only (agent-roles-readme)
- 6189234 feat(rules): model tiers for the new roles, routing table overrides (agent-roles-tiers)
- 99eaf92 feat(rules): lead hands milestone suites to a runner (agent-roles-milestone-suites)
- 031f7f2 feat(rules): lifetimes for runner, scout, writer and second reviewer (agent-roles-lifetimes)
- f63c383 feat(rules): optional second reviewer from another vendor (agent-roles-second-reviewer)

dev-tools: c5764bc (T1 render), 117827e (spec C4/C5, review notes, this report).

## T7. Phase test run (lead, 2026-10-08)

- I2 grep over `~/knowledge/roles/*.md` except README: no output (rc=1).
- `tools:` lines: scout `WebSearch, WebFetch`; runner `Bash, Read, Grep, Glob, Write`; writer
  `Read, Grep, Glob, Write, Edit, Bash`; second-reviewer none.
- `bash tests/ai-sandbox/run-tests.sh`: every suite `0 failed` except test-tools.sh
  `46 run, 1 failed` (case 30, "a candidate without a default is skipped", known sandbox-only);
  test-knowledge.sh `387 run, 0 failed`; ends `SOME SUITES FAILED` because of case 30 only.
