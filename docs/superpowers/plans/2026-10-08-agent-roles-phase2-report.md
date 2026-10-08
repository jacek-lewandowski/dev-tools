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
