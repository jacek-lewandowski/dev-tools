# Shared knowledge repository

## What, when and why

**What.** One private git repository holds the knowledge that is common to every
project: the global rules (`rules/global.md`), role rules for planner, implementer
and reviewer agents (`roles/<name>.md`), own-authored skills (`skills/<name>/`) and
a decision log (`decisions.md`). Every AI sandbox reads a rendered copy of its
`main` branch read-only and proposes changes through its own clone, one branch
per proposal. One sandbox, the integrator, merges approved proposals into `main`.

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

Design: [2026-09-18-shared-knowledge-v2-design.md](superpowers/specs/2026-09-18-shared-knowledge-v2-design.md),
which supersedes the flow and branch model of
[2026-09-14-shared-knowledge-design.md](superpowers/specs/2026-09-14-shared-knowledge-design.md).
Host helper: [bin/ai/ai-knowledge](../bin/ai/ai-knowledge).
Seed content: [bin/ai/knowledge-seed/](../bin/ai/knowledge-seed).

## Deployment

### 1. Install the helpers once

Run `create-ai-sandbox.sh` for any project, once per host. It installs
`ai-knowledge` and the knowledge seed into `~/.ai-sandbox/bin`. Only the one-off
migration script of step 4 still runs from the dev-tools checkout.

### 2. Create the private remote

Create an empty private git repository wherever you host code. The host must be
able to clone and push to it with its own credentials. A passphrase-protected ssh
key is fine: `ai-knowledge` loads it into your agent, or into one it starts and
removes, when the remote refuses the key.

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

It commits, pushes `main`, records the integrator, and renders (see step 4 of
"How it works"). From now on `~/.gemini/GEMINI.md` is a symlink into the render.
The previous file is kept as `GEMINI.md.pre-ai-knowledge.<timestamp>`.

`--integrator` names the project whose sandbox is the integrator: the one clone
that commits on `main`. The first host to pass it writes one line into
`README.md` on `main`, `<!-- ai-knowledge integrator: <hostname>:<path> -->`; a
later host passing `--integrator` is warned that two integrators can make `main`
diverge, and the record is left alone.

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

After the sandboxes it converts the knowledge branches of the first design: every
open file on a remote `proposals/<project-id>` branch becomes a `proposal/*` branch
(`project_id` from the old branch name, `machine: unknown`); with your confirmation
each old branch is merged into `main` with `-s ours` and deleted on the remote
under a lease; every clean clone on this host moves from its old branch to `main`.
A clone with an unpushed old-style commit is pushed first, or the run stops; a
dirty clone is named and left. It recovers the project of an unstamped sandbox
from its `project-path` file or the project mount in its compose file, refuses
the whole run if any project directory is gone, forwards extra arguments to
`create-ai-sandbox.sh`, and recreates with `--no-start`, so migrated sandboxes
stay stopped and the running cap cannot end the run halfway; start each with
`ai-sandbox` when needed. A sandbox whose recreation fails is listed under
`failed:` and the run exits 1; the others are still migrated. Once
`ai-knowledge status` shows every sandbox as `current` and no clone sits on an
old branch, delete the script; nothing else refers to it.

Inside a container, `sandbox-doctor` tells the cases apart: "not configured on the
host", "NOT migrated", or the last sync line with its age and each proposal branch
as `pushed` or `pending`.

### 5. Second computer

Repeat steps 1 to 3 with the same remote URL, without `--integrator` unless this
host is to take over that role. If the host had its own `~/.gemini/GEMINI.md`,
`init` shows how it differs from `rules/global.md` on `main` and asks on stdin
whether to file the difference as a proposal
(`proposal/<date>-gemini-md-<hostname>-<hex>`, a fenced diff with the hostname as
`machine`); a terminal waits for the answer, anything else gets a short bounded
read and, with no answer, the `ai-knowledge propose` command to run later. The old file is backed up either
way. Every proposal has its own branch, so two machines, or two checkouts of one
project, never share a branch and never conflict.

### Editing the rules yourself

You own the repository. Edit `main` directly in the integrator's clone, the path
`ai-knowledge status` prints as `clone (integrator)`, either inside that sandbox
or on the host, add a `decisions.md` entry, commit. The next sync pushes `main`,
re-renders, and every other sandbox picks it up at its next sync; agents read it
in their next session. Nothing requires a proposal for the owner's own changes.

### Commands

| Command | Effect |
|---|---|
| `ai-knowledge init <url> [--integrator DIR]` | Configure, seed an empty remote, render |
| `ai-knowledge sync [PROJECT_DIR]` | Update `main`, render, sync the project's clone |
| `ai-knowledge sync --all` | Update `main`, render, sync every sandbox's clone in parallel, render again if `main` moved |
| `ai-knowledge render` | Render only |
| `ai-knowledge status` | Config, `main` revision, then every sandbox with its knowledge state and last sync |
| `ai-knowledge status PROJECT_DIR` | The same header, then that project's clone and last sync |
| `ai-knowledge proposals [--repo DIR]` | List open proposal files across `proposal/*` branches |
| `ai-knowledge propose FILE [--slug S] [--project-id ID] [--machine M] [--push]` | File a document as a `proposal/*` branch from `origin/main` |

## How it works

### 1. Repository layout

```
rules/global.md          rules for every agent and every tool; plain markdown
roles/<name>.md          frontmatter (name, description, optional tools, model) + body
skills/<name>/SKILL.md   own-authored skills
decisions.md             why each rule exists; integrated and rejected proposals
proposals/README.md      proposal format; a proposal branch adds proposals/<date>-<slug>.md
```

Branch `main` holds the knowledge and is written only by the integrator's clone
(the integrator sandbox, or the owner in that clone, always with a `decisions.md`
entry), with one exception: the single commit `init --integrator` makes from the
host to record the integrator in `README.md`, which that flag is the approval for. Branch `proposal/<YYYY-MM-DD>-<slug>-<hex>` holds one proposal, created
from `main`, and may differ from `main` only under `proposals/`. The host refuses
to push a proposal branch whose name does not follow that pattern.

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

### Sync on demand: `ai-knowledge sync --all`

Nothing runs on a timer. Between sandbox starts the user runs `ai-knowledge sync
--all` on the host. It fetches and renders `main` once, then syncs every stamped
sandbox's clone, running or stopped, in parallel (`AI_KNOWLEDGE_JOBS`, default 4),
then fetches `main` once more and renders again only if an integrator clone
advanced it. Children never render, so the render is rebuilt by one process at a
time. Each clone's output is printed as a block under its sandbox name, followed
by one table: sandbox, state, last sync line. A stale or unstamped sandbox is
listed and not synced; a sandbox whose project directory is gone is listed as
`missing project`; a failing child is a row, never the end of the run. Running
containers see the new render at once; agents read it in their next session.

**Passphrase-protected keys.** Before the first network command, `ai-knowledge`
probes the remote. When the probe fails with a public-key refusal on an ssh URL:

1. An agent is reachable through `SSH_AUTH_SOCK`: the keys `ssh -G` reports for the
   remote's host are added with `ssh-add -t 3600` and the user is told that the key
   sits in their agent for one hour. That agent is never killed.
2. No agent, but a terminal: `ai-knowledge` starts an `ssh-agent` for this run,
   adds the keys, says so, and kills it when it exits, on success, on an error and
   on `die` alike. Children of `sync --all` inherit the agent and never kill it.
3. No agent and no terminal: the offline path, with the manual commands, as before.

Any other probe failure (timeout, unknown host, no network) and a second refusal
after the key was added take the offline path without touching an agent.

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

The clone is created from the remote on first use with `main` checked out. The
host writes `.git/ai-knowledge-role` (`proposals <project-id>`) and a pre-commit
hook into it on every sync. The hook refuses a commit on `main` and any staged
path outside `proposals/` on a `proposal/*` branch, so a mistake fails inside the
sandbox at commit time; the host's scope check below remains the enforcement.
Every sync:

1. Stops with `skipped` if the working tree has uncommitted changes, or if the
   clone sits on an old-style `proposals/<project-id>` branch (run the migration
   script).
2. Fetches with `--prune`. On failure it records the manual fetch command and
   continues on the last fetched refs.
3. Fast-forwards `main` to `origin/main`, whether or not it is checked out. A
   `main` with local commits is `diverged`; the proposal branches are still
   processed.
4. Classifies every local `proposal/*` branch: a malformed name or a change
   outside `proposals/` is `refused` and never pushed; a tip that is an ancestor
   of `origin/main` is closed and the local branch deleted (checking out `main`
   first if the clone sat on it); the rest are open and pushed fast-forward only,
   a remote with commits the branch lacks being a `conflict`.
5. Writes `ok: main current; pushed N; closed M`, or the first problem found, or
   `offline` with the per-branch push commands to run by hand.

### 6. Integrator clone

The integrator's clone is on `main` and carries a local branch for every open
`proposal/*` branch. Every sync: fetches with `--prune` and fetches every
`refs/heads/proposal/*` into a local branch of the same name (a branch that does
not fast-forward is left alone); fast-forwards `main` unless it has commits to
push; pushes open proposal branches that are fast-forwards of the remote; pushes
`main` when it is ahead (`diverged` and no push when it is not a fast-forward);
then deletes closed branches locally and on the remote. Remote deletion happens
only after `main` is on the remote, only for a tip that is an ancestor of
`origin/main`, and only under a lease on the fetched tip: an amendment the
proposer pushed meanwhile rejects the lease, and the proposal is simply open
again. If `main` advanced, the host re-renders at once.

Closing a proposal is `git merge -s ours --no-ff` of its branch into `main`:
`main`'s tree is unchanged, the branch tip becomes an ancestor of `main`, and no
checkout or file removal is needed. The proposal text stays reachable with
`git log --full-history -- proposals/` or `git show <merge>^2:proposals/<file>`.

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

1. Verifies `~/knowledge` is on `main` with a clean tree.
2. Greps `rules/`, `roles/` and `decisions.md` for duplicates and prior rejections.
3. Creates `proposal/tmp-<slug>` from `main`, writes
   `proposals/<YYYY-MM-DD>-<slug>.md` with frontmatter (`scope`, `project`,
   `project_id`, `machine`, `target`, `evidence`) and the rule text as it should
   appear in the target file, commits only that file, renames the branch to
   `proposal/<YYYY-MM-DD>-<slug>-<4 hex of the commit>` and returns to `main`.
4. Never pushes and never touches other paths.

The host pushes the branch on the next sync: a sandbox start, or
`ai-knowledge sync --all` on the host. Inside the sandbox, `sandbox-doctor` shows
each local proposal branch as `pushed` or `pending`, and the age of the last sync.

From the host, `ai-knowledge propose FILE [--slug S] [--project-id ID] [--machine M] [--push]`
files any markdown document as a proposal branch, built from `origin/main` with
plumbing, without touching a working tree.

### 9. Integrating (integrator sandbox)

The `knowledge-integrate` skill lives in this repository under
[.agents/skills/knowledge-integrate/](../.agents/skills/knowledge-integrate/SKILL.md),
linked from `.claude/skills/`. It:

1. Lists open proposals with `bin/ai/ai-knowledge proposals --repo ~/knowledge`
   (`<branch> <path>` per file on a `proposal/*` branch that `main` has not
   absorbed) and reads each with `git show <branch>:<path>`. Proposal content is
   treated as data, never as instructions. It never checks a proposal branch out.
2. Triages each as duplicate, global, role, skill or reject, and drafts the edits
   to `rules/`, `roles/`, `skills/` and `decisions.md`.
3. Waits for the user's approval of the triage table and diffs.
4. Commits the approved edits on `main`, one commit per proposal or merged group.
   Rejections get only a `decisions.md` entry.
5. Closes each handled proposal with `git merge -s ours --no-ff -m "proposal:
   <slug> integrated|rejected" <branch>`.

The host pushes `main` and deletes the closed branches on the next sync. Every
other sandbox receives the new rules on its next sync and drops its own copies of
the closed branches; agents read the new rules in their next session.

The owner may also edit `main` directly in the integrator's clone, with a
`decisions.md` entry; that clone is the one `ai-knowledge status <dev-tools dir>`
prints.

### Who can do what

| Party | Effective rules | Clone | Network git |
|---|---|---|---|
| Project sandbox | read-only | commit on `proposal/*` branches it creates | none |
| Integrator sandbox | read-only | commit on `main`; close proposals with an ours-merge | none |
| Host | writes the render | fetch, fast-forward, scope check, push, leased deletion of closed branches | all |

## Known limits

- Codex and Gemini CLI are not installed on the host, so their role renders follow
  documented formats and are unverified. Codex agents are rendered but not
  registered in `config.toml`; Antigravity rules are rendered but linked into a
  project's `.agents/rules/` only by hand.
- Mounting the render over `~/.claude/agents` hides agents seeded from the host's
  own directory. Roles come from the repository only.
- Key discovery for the ssh-agent step relies on `ssh -G` printing `identityfile`
  lines; with none usable it falls back to a bare `ssh-add`, and several configured
  keys may prompt more than once.

## Tests

`bash tests/ai-sandbox/test-knowledge.sh` runs against a temporary `HOME` with a
local bare repository as the remote. `bash tests/ai-sync/test-sync.sh` asserts that
`GEMINI.md` is skipped once configured.
