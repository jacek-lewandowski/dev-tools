# AI knowledge

The global, project-independent knowledge every AI agent in every sandbox reads:
generic rules, role-specific rules, own-authored skills and the decision log behind
them. Managed by `dev-tools/bin/ai/ai-knowledge`; do not edit the rendered copies,
edit this repository.

## Layout

| Path | Content |
|---|---|
| `rules/global.md` | Rules for every agent and every tool. Plain markdown, no imports, no tool-specific syntax. Rendered to `~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md` and `~/.codex/AGENTS.md`. |
| `roles/<name>.md` | Rules for one kind of agent (planner, implementer, reviewer, ...). See `roles/README.md`. |
| `skills/<name>/SKILL.md` | Skills authored here. Copied into `~/.agents/skills` and linked from every tool's skills directory. |
| `decisions.md` | Why each rule exists, and which proposals were integrated or rejected. |
| `proposals/` | Empty on `main`. A sandbox's branch adds `proposals/<project-id>/*.md`. See `proposals/README.md`. |

## Branches

- `main` holds the knowledge. Only the integrator sandbox commits to it, after the
  user approves each change.
- `proposals/<project-id>` belongs to one sandbox. It may differ from `main` only
  under `proposals/<project-id>/`; the host refuses to push anything else.

## Flow

1. An agent in a project sandbox learns something generic and runs the
   `propose-rule` skill, which commits one proposal file on the sandbox's branch.
2. On the next sync (a sandbox start, or `ai-knowledge sync --all` on the host) the
   host merges `main` into the branch and pushes it.
3. In the integrator sandbox the `knowledge-integrate` skill triages every open
   proposal, the user approves, the agent commits to `main` and removes the
   proposal file on its branch.
4. The host pushes; every sandbox picks up the new `main` on its next sync, and
   agents read it in their next session.

Nothing project-specific belongs here. Project rules live in the project tree;
project memory travels with `ai-sync`.
