# Roles

One file per kind of agent. The body is that agent's rule set, on top of
`rules/global.md`, which every agent already has. Keep the body pure prose so it
renders for every tool.

```markdown
---
name: planner
description: Writes implementation plans and specs; never edits source files except to place plan anchors.
tools: Read, Grep, Glob, Bash        # optional, Claude Code and Gemini CLI only
model: inherit                        # optional
---

<rules for this role>
```

Rendered by `ai-knowledge render` to:

| Tool | Rendered as |
|---|---|
| Claude Code | `~/.claude/agents/<name>.md`, the file verbatim (subagent definition) |
| Gemini CLI | `~/.gemini/agents/<name>.md`, the file verbatim |
| Antigravity | `antigravity/rules/<name>.md` with `trigger: model_decision` and the description; symlink it into a project's `.agents/rules/` when wanted |
| Codex | `~/.codex/agents/<name>.toml` with `name`, `description`, `developer_instructions`; register it in `config.toml` when wanted |
