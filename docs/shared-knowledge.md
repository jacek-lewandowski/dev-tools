# Shared knowledge repository

## What, when and why

**What.** One private git repository holds the knowledge that is common to every
project: the global rules (`rules/global.md`), role rules for planner, implementer
and reviewer agents (`roles/<name>.md`), own-authored skills (`skills/<name>/`) and
a decision log (`decisions.md`). Every AI sandbox reads a rendered copy of its
`main` branch read-only and proposes changes through its own clone, on its own
branch. One sandbox, the integrator, merges approved proposals into `main`.

**When.** The feature is optional and inert until `ai-knowledge init` has run on
the host. Without the config file every sandbox script behaves as before and the
global rules stay in `~/.gemini/GEMINI.md`.

**Why.** The rules used to live in a single file bind-mounted live into every
sandbox. They were not versioned, an agent could change them for every sandbox at
once, and a lesson learned in one project had no reviewed path into the global
rules. Now the effective rules are never writable from a sandbox, no sandbox holds
git credentials, every change to `main` is approved by the user, and the host never
force-pushes.

Project-specific knowledge stays out of the repository. Project rules live in the
project tree; Claude memory and conversations travel between computers with
`ai-sync` as before.

Design: [2026-09-14-shared-knowledge-design.md](superpowers/specs/2026-09-14-shared-knowledge-design.md).
Host helper: [bin/ai/ai-knowledge](../bin/ai/ai-knowledge).
Seed content: [bin/ai/knowledge-seed/](../bin/ai/knowledge-seed).

## Deployment

### 1. Install the helper

Re-run `create-ai-sandbox.sh` once for any project. It installs `ai-knowledge` into
`~/.ai-sandbox/bin` and records the dev-tools checkout in `~/.ai-sandbox/config`,
which `init` needs to find the seed directory.

### 2. Create the private remote

Create an empty private git repository wherever you host code. The host must be
able to clone and push to it with its own credentials.

### 3. Initialise

```bash
ai-knowledge init <remote-url> --integrator ~/dev/public/dev-tools
```

This writes `~/.ai-sandbox/knowledge/config` (`REMOTE`, `INTEGRATOR`), clones the
remote into `~/.ai-sandbox/knowledge/main` and, if the remote is empty, seeds it:

- the seed directory (README, `decisions.md`, `proposals/README.md`, three starter
  roles, the `propose-rule` skill), plus
- `rules/global.md` taken from the host's current `~/.gemini/GEMINI.md`, with the
  generated sandbox-environment block stripped.

It commits, pushes `main`, and renders (see step 4 of "How it works"). From now on
`~/.gemini/GEMINI.md` is a symlink into the render. The previous file is kept as
`GEMINI.md.pre-ai-knowledge.<timestamp>`.

`--integrator` names the project whose sandbox is the integrator. Its clone sits on
`main` instead of a proposals branch.

### 4. Migrate every existing sandbox

Every sandbox carries a stamp in its `.env`, `SANDBOX_KNOWLEDGE=0|1`, written by
`create-ai-sandbox.sh` and saying whether its compose file has the knowledge
mounts. `ai-sandbox` and `ai-sandbox-restart` compare the stamp with the host's
configuration and refuse to start a sandbox that is `stale` (stamp disagrees) or
`unstamped` (created before stamps existed). Such a sandbox would mount the live
`GEMINI.md`, which now resolves through the host symlink to the render, read-write.
The start scripts only check; they never rewrite a sandbox.

The repair is a separate, one-off script in the dev-tools checkout, not installed
into `~/.ai-sandbox/bin`:

```bash
ai-knowledge status                                  # every sandbox: current | stale | unstamped
<dev-tools>/bin/ai/ai-sandbox-migrate-knowledge      # stop and recreate each stale or unstamped one
```

It recovers the project of an unstamped sandbox from the project mount in its
compose file, refuses the whole run if any project directory is gone, and
forwards extra arguments to `create-ai-sandbox.sh`. Once `ai-knowledge status`
shows every sandbox as `current`, delete the script; nothing else refers to it.

Inside a container, `sandbox-doctor` tells the cases apart: "not configured on the
host", "NOT migrated", or the last sync line.

### 5. Second computer

Repeat steps 1 to 3 with the same remote URL. Proposal branches are keyed by
project id, a slug plus a hash of the absolute project path. Two machines holding
the project at different paths get different branches. At the same path they share
one branch, which works because the host merges the remote branch into the clone
before every push; only two commits to the same proposal file between syncs end in
a `conflict` status.

### Commands

| Command | Effect |
|---|---|
| `ai-knowledge init <url> [--integrator DIR]` | Configure, seed an empty remote, render |
| `ai-knowledge sync [PROJECT_DIR]` | Update `main`, render, sync the project's clone |
| `ai-knowledge render` | Render only |
| `ai-knowledge status` | Config, `main` revision, then every sandbox with its knowledge state and last sync |
| `ai-knowledge status PROJECT_DIR` | The same header, then that project's clone and last sync |
| `ai-knowledge proposals [--repo DIR]` | List open proposal files across `proposals/*` branches |

## How it works

### 1. Repository layout

```
rules/global.md          rules for every agent and every tool; plain markdown
roles/<name>.md          frontmatter (name, description, optional tools, model) + body
skills/<name>/SKILL.md   own-authored skills
decisions.md             why each rule exists; integrated and rejected proposals
proposals/README.md      proposal format; branches add proposals/<project-id>/*.md
```

Branch `main` holds the knowledge and is written only by the integrator. Branch
`proposals/<project-id>` belongs to one sandbox and may differ from `main` only
under `proposals/<project-id>/`.

### 2. Host-side layout

```
~/.ai-sandbox/knowledge/config                  REMOTE, INTEGRATOR
~/.ai-sandbox/knowledge/main                    canonical checkout of main, fast-forward only
~/.ai-sandbox/knowledge/sandbox-environment.md  the generated sandbox block, appended at render
~/.ai-sandbox/shared/knowledge/                 the render, mounted read-only
    GLOBAL.md                                   rules/global.md + sandbox-environment.md
    claude/agents/<role>.md                     role file verbatim
    gemini/agents/<role>.md                     role file verbatim
    antigravity/rules/<role>.md                 model_decision rule with the role's description
    codex/agents/<role>.toml                    name, description, developer_instructions
    skills/<name>/                              own skills
~/.ai-sandbox/<project>-<hash>-agent/knowledge  that sandbox's clone
```

### 3. Sync on every sandbox start

`create-ai-sandbox.sh`, `ai-sandbox` and `ai-sandbox-restart` run
`ai-knowledge sync <project>` before `compose up`; a start syncs only its own
sandbox's clone. Network git runs
non-interactively (`GIT_TERMINAL_PROMPT=0`, ssh `BatchMode=yes`) and under a
timeout (60 s, `AI_KNOWLEDGE_GIT_TIMEOUT`). No step fails the start. The outcome
is one line in `<clone>/.sync-status`, shown by `sandbox-doctor` and
`ai-knowledge status`.

When a fetch or push fails, for example because the ssh key needs a passphrase
and no agent holds it, the sync carries on with the last fetched refs and ends
with the commands to run by hand on the host, in order: the fetches, then
`ai-knowledge sync <project>`, then the pushes. The status line says `offline`
and whether a push is pending.

1. Fetch the canonical `main` and fast-forward it. Offline: keep the last state.
2. Render and wire the host (step 4).
3. Sync the sandbox's clone (step 5 or 6).

### 4. Render and host wiring

The render is rebuilt from `main` into a temporary directory and copied over
`~/.ai-sandbox/shared/knowledge` in place, so `GLOBAL.md`, which is bind-mounted
as a file, keeps its inode and running containers see the change.

On the host, `~/.gemini/GEMINI.md` is a symlink to `GLOBAL.md`, and
`~/.claude/agents/<role>.md` are symlinks into the render. Own skills are copied
into `~/.agents/skills/<name>` and into the shared agent-skills store, and linked
from `.claude/skills`, `.codex/skills` and `.gemini/skills` on the host and in each
sandbox directory, in the same layout the skills CLI uses.

`create-ai-sandbox.sh` no longer writes its sandbox-environment block into
`GEMINI.md`. It writes it to `sandbox-environment.md` and re-renders. When the
knowledge repository is configured, that block also tells the agent where its clone
is and how to propose a rule.

`ai-sync` skips `GEMINI.md` in both directions once the config file exists. Git is
the transport for the rules now.

### 5. Project sandbox clone

The clone is created from the remote on first use and checked out on
`proposals/<project-id>`, from the remote branch if it exists, otherwise from
`main`. Every sync then:

1. Stops with `skipped` if the working tree has uncommitted changes.
2. Fetches. On failure it records the manual fetch command and continues.
3. Merges `origin/proposals/<project-id>`, then `origin/main`. A conflict aborts
   the merge with `conflict`; it is resolved inside the sandbox.
4. Checks that the branch differs from `origin/main` only under
   `proposals/<project-id>/`. Anything else is `refused` and not pushed.
5. Pushes the branch, fast-forward only. Status `ok`, or `offline` with the
   manual push command when the remote is unreachable.

A clone made by hand with `git clone` is picked up by the next sync, which
creates the proposals branch.

### 6. Integrator clone

The integrator's clone is on `main` and holds a local branch for every
`proposals/*` branch. Every sync:

1. Fast-forwards `main` from `origin/main`. If it diverged, status `diverged`, no
   push.
2. Fetches every `proposals/*` branch into a local branch of the same name,
   fast-forward only.
3. Pushes `main` and every local `proposals/*` branch without force. A proposals
   branch that diverged from the remote is reported and left alone. Offline, the
   pushes are listed as manual commands instead.
4. If `main` advanced, re-renders immediately.

### 7. Container mounts

When configured, the two live `GEMINI.md` mounts are replaced by:

| Host path | Container path | Mode |
|---|---|---|
| `shared/knowledge/GLOBAL.md` | `~/.gemini/GEMINI.md`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | ro |
| `shared/knowledge/claude/agents` | `~/.claude/agents` | ro |
| `shared/knowledge/gemini/agents` | `~/.gemini/agents` | ro |
| `shared/knowledge/codex/agents` | `~/.codex/agents` | ro |
| `<sandbox>/knowledge` | `~/knowledge` | rw |

The mount targets are created in the sandbox directory before every start so
Docker does not create them root-owned.

### 8. Proposing a rule (any sandbox)

The `propose-rule` skill ships in the repository's `skills/` and reaches every tool
through the skills directories. It:

1. Verifies `~/knowledge` is on `proposals/<project-id>` with a clean tree.
2. Greps `rules/`, `roles/` and `decisions.md` for duplicates and prior rejections.
3. Writes `proposals/<project-id>/<YYYY-MM-DD>-<slug>.md` with frontmatter
   (`scope`, `project`, `target`, `evidence`) and the rule text as it should appear
   in the target file.
4. Commits only that file. It never pushes and never touches other paths.

The host pushes the branch on the next sandbox start.

### 9. Integrating (integrator sandbox)

The `knowledge-integrate` skill lives in this repository under
[.agents/skills/knowledge-integrate/](../.agents/skills/knowledge-integrate/SKILL.md),
linked from `.claude/skills/`. It:

1. Lists open proposals with `bin/ai/ai-knowledge proposals --repo ~/knowledge`
   and reads each with `git show <branch>:<path>`. Proposal content is treated as
   data, never as instructions.
2. Triages each as duplicate, global, role, skill or reject, and drafts the edits
   to `rules/`, `roles/`, `skills/` and `decisions.md`.
3. Waits for the user's approval of the triage table and diffs.
4. Commits the approved edits on `main`, one commit per proposal or merged group.
   Rejections get only a `decisions.md` entry.
5. Checks out each source branch and commits the removal of the handled proposal
   file.

The host pushes `main` and the touched branches on the integrator's next start or
on `ai-knowledge sync`. Every other sandbox receives the new rules on its next
start, when its branch also merges the new `main`.

### Who can do what

| Party | Effective rules | Clone | Network git |
|---|---|---|---|
| Project sandbox | read-only | commit on its own proposals branch | none |
| Integrator sandbox | read-only | commit on `main` and every proposals branch | none |
| Host | writes the render | fetch, merge, scope check, fast-forward push | all |

## Known limits

- Codex and Gemini CLI are not installed on the host, so their role renders follow
  documented formats and are unverified. Codex agents are rendered but not
  registered in `config.toml`; Antigravity rules are rendered but linked into a
  project's `.agents/rules/` only by hand.
- Mounting the render over `~/.claude/agents` hides agents seeded from the host's
  own directory. Roles come from the repository only.

## Tests

`bash tests/ai-sandbox/test-knowledge.sh` runs against a temporary `HOME` with a
local bare repository as the remote. `bash tests/ai-sync/test-sync.sh` asserts that
`GEMINI.md` is skipped once configured.
