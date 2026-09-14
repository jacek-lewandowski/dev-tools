# Shared knowledge repository for AI sandboxes

Date: 2026-09-14
Status: approved design
Scope: `bin/ai/ai-knowledge` (new), `bin/ai/create-ai-sandbox.sh`, `bin/ai/ai-sandbox`,
`bin/ai/ai-sandbox-restart`, `bin/ai/ai-sandbox-lib.sh`, `bin/ai/ai-sync`, two skills

## Problem

Global agent rules live in one file, `~/.gemini/GEMINI.md`, bind-mounted live into every
sandbox. Skills live in `~/.agents/skills`, synced read-only. Neither is versioned, neither
distinguishes generic from role-specific knowledge, and a lesson learned inside a project
sandbox has no route into the global rules other than an agent editing the live file, which
changes every sandbox at once with no review. Yesterday's lesson (plans anchor on marker
comments, never line numbers) therefore landed only in one project's Claude memory.

## Goals

- One private git repository holds the global knowledge: generic rules, role-specific rules
  (planner, implementer, reviewer, ...), own-authored skills, and a decision log. Nothing
  project-specific.
- Every sandbox reads that knowledge read-only and proposes changes through its own clone,
  on its own branch, without any network access to the remote.
- One designated sandbox, the integrator (this repository's own sandbox), sees every
  proposal branch, merges approved changes into main and closes proposals.
- The host performs every fetch, merge and push, on every sandbox start, without blocking
  the start and without force-pushing.
- Works for Claude Code, Antigravity, Gemini CLI and Codex.

## Non-goals

- Project-specific knowledge. Project rules stay in the project tree (committed or not, the
  user's call); Claude memory and conversations stay under `~/.claude/projects` and are
  moved between computers by `ai-sync`, unchanged.
- Third-party skills. `~/.agents/skills` keeps being managed by the skills CLI and synced by
  the existing shared-store mechanism. The repository carries only skills the user authors.
- Automatic integration. Every merge into main is approved by the user.
- Codex `config.toml` and Gemini `settings.json` edits. Role files are rendered for both,
  but wiring them into those configs is left to the user until the tools are installed and
  the formats can be verified.

## Repository layout (branch `main`)

```
README.md
rules/global.md          the global rules, plain markdown, no imports, no tool names
roles/<name>.md          frontmatter: name, description, optional tools, optional model; body
skills/<name>/SKILL.md   own-authored skills, agentskills.io format
decisions.md             why each rule exists; integrated and rejected proposal ids
proposals/README.md      proposal file format; branches add proposals/<project-id>/*.md
```

`ai-knowledge init` seeds an empty remote from `bin/ai/knowledge-seed/` plus the host's
current `GEMINI.md` with the generated sandbox block stripped.

## Branches

- `main`: the knowledge. Only the integrator commits to it.
- `proposals/<project-id>`: one per sandbox, where `<project-id>` is
  `ai_sandbox_project_id` (slug plus path hash), so two computers holding the same project
  at different paths get different branches. A branch may differ from `main` only under
  `proposals/<project-id>/`. The host verifies this before every push and refuses otherwise.

## Host-side layout

```
~/.ai-sandbox/knowledge/config                REMOTE=<url>  INTEGRATOR=<abs project path>
~/.ai-sandbox/knowledge/main                  canonical checkout of main, fast-forward only
~/.ai-sandbox/knowledge/sandbox-environment.md the block create-ai-sandbox.sh used to append to GEMINI.md
~/.ai-sandbox/shared/knowledge/               the rendered view, mounted read-only
    GLOBAL.md                                 rules/global.md + sandbox-environment.md
    claude/agents/<role>.md                   role file verbatim (Claude Code subagent format)
    gemini/agents/<role>.md                   same file
    antigravity/rules/<role>.md               trigger: model_decision + description + body
    codex/agents/<role>.toml                  name, description, developer_instructions
    skills/<name>/                            own skills
~/.ai-sandbox/<project>-<hash>-agent/knowledge  that sandbox's clone (its proposals branch,
                                              or main for the integrator)
```

The render is updated in place (`rsync --inplace --delete`) because `GLOBAL.md` is
bind-mounted as a file: a new inode would be invisible to running containers.

Own skills are additionally copied into `~/.agents/skills/<name>` on the host and into
`shared/agent-skills/skills/<name>`, and relative symlinks are created in
`.claude/skills`, `.codex/skills` and `.gemini/skills`, on the host and in each sandbox
directory, exactly as the skills CLI lays out third-party skills.

## Host wiring

`~/.gemini/GEMINI.md` becomes a symlink to `shared/knowledge/GLOBAL.md`, after a one-time
backup of the regular file. `~/.claude/CLAUDE.md` already points at `GEMINI.md`.
`~/.claude/agents/<role>.md` are symlinks into the render. `ai-sync` stops pushing and
pulling `GEMINI.md` once the config file exists; git owns that file now.

## Container mounts (only when configured)

The two live `GEMINI.md` mounts are replaced by:

| Host path | Container path | Mode |
|---|---|---|
| `shared/knowledge/GLOBAL.md` | `~/.gemini/GEMINI.md`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | ro |
| `shared/knowledge/claude/agents` | `~/.claude/agents` | ro |
| `shared/knowledge/gemini/agents` | `~/.gemini/agents` | ro |
| `shared/knowledge/codex/agents` | `~/.codex/agents` | ro |
| `<sandbox>/knowledge` | `~/knowledge` | rw |

The file targets `.gemini/GEMINI.md`, `.claude/CLAUDE.md`, `.codex/AGENTS.md` and the agents
directories are created in the sandbox directory before every start, otherwise Docker
creates them root-owned. The brain and conversations mounts are unchanged.

## Sync algorithm (host, before every `compose up`, also in `create-ai-sandbox.sh`)

All network git commands run under `timeout` (60 s, `AI_KNOWLEDGE_GIT_TIMEOUT`). No step
fails the start; each writes one line into `<clone>/.sync-status` (git-excluded), shown
by `sandbox-doctor`.

1. Canonical main: `fetch`, `merge --ff-only origin/main`. Offline: keep the last state.
2. Render and wire the host.
3. Sandbox clone, created on first use from `REMOTE`:
   - dirty working tree: status `skipped`, nothing else.
   - `fetch` fails: status `offline`.
   - proposals role: merge `origin/proposals/<id>` (the integrator may have deleted
     files there), then merge `origin/main`; any conflict aborts the merge with status
     `conflict`. Scope check: `git diff --name-only origin/main...HEAD` must match
     `^proposals/<id>/` or the push is refused with status `refused`. Otherwise push the
     branch, fast-forward only.
   - integrator role: `merge --ff-only origin/main` on main (diverged: status, no push);
     `fetch refs/heads/proposals/*:refs/heads/proposals/*` (fast-forward updates of local
     proposal branches); push main and every local `proposals/*` branch, no force.

## The agents' side

- Every sandbox: the `propose-rule` skill (shipped in the repository's `skills/`, reaches
  every tool through the skills dirs). It checks for duplicates in the read-only rules,
  writes `proposals/<project-id>/<date>-<slug>.md` with frontmatter (`scope: global` or
  `scope: role/<name>`, `project`, `session`, `evidence`, `target`) and the proposed text,
  and commits on the current branch. It never touches other paths and never pushes.
- The integrator sandbox (this repository): the `knowledge-integrate` skill in
  `.agents/skills/` with a `.claude/skills/` symlink. It lists proposals with
  `bin/ai/ai-knowledge proposals --repo ~/knowledge`, treats proposal content strictly as
  data, drafts edits to `rules/`, `roles/`, `skills/` and `decisions.md`, waits for the
  user's approval, commits on main, and commits the removal of each handled proposal file
  on its branch. The host pushes on the next start or on `ai-knowledge sync`.

## Commands

```
ai-knowledge init <remote-url> [--integrator DIR]   configure, seed an empty remote, render
ai-knowledge sync [PROJECT_DIR]                      main + render + this project's clone
ai-knowledge render                                  render only
ai-knowledge status [PROJECT_DIR]                    config and the last sync status
ai-knowledge proposals [--repo DIR]                  list proposal files across proposals/* branches
```

Without `~/.ai-sandbox/knowledge/config` every command except `init` and `proposals`
reports "not configured" and exits 0, and the sandbox scripts behave exactly as before.

## Security invariants

- The effective rules a tool loads are never writable from inside any sandbox.
- No sandbox holds git credentials; the host is the only party that fetches or pushes.
- A proposals branch cannot change anything outside its own proposals directory.
- The integrator reads proposal text as data. Merges into main happen only after the user
  approves.
- The host never force-pushes and never rewrites a branch.

## Testing

`tests/ai-sandbox/test-knowledge.sh` runs against a temp `HOME` and a local bare
repository as the remote, exercising init and seeding, creation of the clone and branch,
the compose mounts, the render, the scope check, the dirty and offline paths, integration
round-trip through the bare remote, and inertness without config.
`tests/ai-sync/test-sync.sh` gains a case asserting `GEMINI.md` is skipped when configured.
