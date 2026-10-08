# Task brief: allow Claude Code to delegate to `agy` inside every sandbox

Date: 2026-10-08. Small task, no spec. Part of the agent-roles work (scout,
runner, writer roles routed to Gemini through `agy`); the spec for that comes
later.

## Problem (confirmed)

Inside a sandbox, Claude Code in auto mode blocks `agy -p "<prompt>"` as data
exfiltration, because it sends project text to Google. The user authorised it
for sandboxes (2026-10-08): "I'm ok with whatever is needed to do in the
sandbox to make it work as long as we do not manipulate the host system".
Verified in this sandbox: a project-local allow rule `Bash(agy -p *)` lets a
single bare `agy -p ...` command through; any command chained around it is
judged by the classifier and blocked. An `autoMode.allow` entry is the
documented way to tell the classifier the destination is approved. Claude Code
refuses to write that entry into its own settings from inside a session, so it
has to come from the image.

Note: `agy -p` takes the prompt as its own value; the prompt must directly
follow `-p`, before `--model` and other flags.

## Goal

Every sandbox built from the image lets Claude Code call `agy -p ...` and
`agy models` without a prompt or a classifier refusal, and the agents are told
how to call it. Nothing on the host changes: no file under the host's `~/.claude`
or the seeded `$SANDBOX_DIR/.claude` is written.

## Approach

- The generated Dockerfile in `bin/ai/create-ai-sandbox.sh` installs
  `/etc/claude-code/managed-settings.json` (root-owned, read-only to the
  sandbox user) with:
  ```json
  {
    "permissions": { "allow": ["Bash(agy -p *)", "Bash(agy models)"] },
    "autoMode": {
      "allow": [
        "$defaults",
        "agy (Antigravity CLI, Gemini) is a user-approved model provider in this sandbox; sending prompts and project content to it with `agy -p` is authorized"
      ]
    }
  }
  ```
- `TOOL_NOTES` in the same script gets one line: `agy -p "<prompt>" --model
  <id>` may receive project content; call it as one bare command, prompt right
  after `-p`; if `agy models` says it is not signed in, use Claude instead.
- Assumption, not verified: Claude Code reads `autoMode` from managed settings
  on Linux at `/etc/claude-code/managed-settings.json`. Check it against the
  Claude Code documentation or the installed binary before relying on it;
  if it is wrong, stop and report instead of choosing another location.

## Tests

Regression test first, in `tests/ai-sandbox/` (most likely `test-image.sh`,
which asserts on the generated Dockerfile text): the Dockerfile writes the
managed settings file with both permission rules and the `autoMode` entry,
and the generated notes mention `agy -p`. Run the targeted test file, then the
whole suite once (`bash tests/ai-sandbox/run-tests.sh`).

## Acceptance

- The test fails before the change and passes after it; the full suite passes.
- The managed settings JSON in the generated Dockerfile parses
  (`python3 -m json.tool`).
- No other behaviour changes. The image hash changes, so the shared image is
  rebuilt once on the next `create-ai-sandbox.sh`; that is expected.
- The end-to-end check (a fresh sandbox runs `agy -p` from Claude Code
  unprompted) needs a host rebuild; the lead asks the user to run it.
- Do not commit; the lead commits after review.
