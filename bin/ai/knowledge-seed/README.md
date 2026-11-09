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
| `proposals/` | Only this README on `main`. A proposal branch adds one `proposals/<date>-<slug>.md`. See `proposals/README.md`. |
| `reports/` | Never on `main`. A report ref holds one `reports/<project>/process-report-<P>-<F>_<T>.md`. |

## Branches

- `main` holds the knowledge. Only the integrator's clone commits to it, after the
  user approves each change; the one exception is the commit `ai-knowledge init
  --integrator` makes from the host to record the integrator in this README.
  Every clone has `main` checked out.
- `proposal/<date>-<slug>-<hex>` holds one proposal, created from `main` by the
  `propose-rule` skill in any sandbox. It may differ from `main` only under
  `proposals/`; the host refuses to push anything else, and refuses a branch whose
  name does not follow that pattern.
- `refs/reports/<date>-<project>-<hex>` is a ref, not a branch: one process report,
  one commit from `main` that adds only `reports/<project>/process-report-<P>-<F>_<T>.md`.
  The `process-report` skill files it in any sandbox; the host pushes it from every
  clone (refusing a bad name, a path outside `reports/` or an unrelated history) and
  the writer's clone drops it. Invariant: a report is never reachable from `main`
  and never lands in a clone other than the writer's and the integrator's, because
  clones fetch only `refs/heads/*`. The integrator lists it with
  `ai-knowledge reports`, shows it to the user and closes it with
  `git update-ref refs/reports-closed/<name> refs/reports/<name>`; the host then
  deletes it everywhere. A closed report cannot be recovered from git.

## Flow

1. An agent in a project sandbox learns something generic and runs the
   `propose-rule` skill, which commits one proposal file on its own branch.
2. On the next sync (a sandbox start, or `ai-knowledge sync --all` on the host) the
   host pushes the branch and fast-forwards the clone's `main`.
3. In the integrator sandbox the `knowledge-integrate` skill triages every open
   proposal, the user approves, the agent commits to `main` and closes each
   proposal with `git merge -s ours --no-ff` of its branch.
4. A process report follows the same sync as a ref, is read by the integrator only
   and closed after the user has seen it; a rule it suggests goes through the
   proposal flow above.
5. The host pushes `main`, deletes the closed branches on the remote and in every
   clone at their next sync; agents read the new `main` in their next session.

Nothing project-specific belongs here, with one deliberate exception the user
accepted: process reports live on this private remote, outside `main` and outside
`refs/heads/`. Project rules live in the project tree;
project memory travels with `ai-sync`.
