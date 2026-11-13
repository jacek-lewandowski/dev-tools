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
git credentials, the host never runs git in a directory a sandbox can write, every
change to `main` is approved by the user, and the host never force-pushes.

Project-specific knowledge stays out of the repository. Project rules live in the
project tree; Claude memory and conversations travel between computers with
`ai-sync` as before.

Design: [2026-09-18-shared-knowledge-v2-design.md](superpowers/specs/2026-09-18-shared-knowledge-v2-design.md),
which supersedes the flow and branch model of
[2026-09-14-shared-knowledge-design.md](superpowers/specs/2026-09-14-shared-knowledge-design.md).
Host helper: [bin/ai/ai-knowledge](../bin/ai/ai-knowledge).
Seed content: [bin/ai/knowledge-seed/](../bin/ai/knowledge-seed).

## Upgrading from an earlier setup

A host that already runs an earlier setup has old helpers in `~/.ai-sandbox/bin` and
sandboxes whose `SANDBOX_KNOWLEDGE` stamp is `1` (the clone made and updated by the
host) or missing. Upgrade in this order:

1. Refresh the helpers. Run the installed `ai-sandbox-migrate` once, or start any
   sandbox with `ai-sandbox`, which runs it. Either copies the new helpers and
   the knowledge seed from the dev-tools checkout into `~/.ai-sandbox/bin`.
2. Expect refusals. A stopped sandbox whose stamp is not current is refused by
   `ai-sandbox` and `ai-sandbox-restart` with one repair named,
   `create-ai-sandbox.sh <project>`. A running one is entered, its host side is
   synced, nothing is executed in it, and the host says it must be re-created.
   `ai-knowledge sync --all` lists it as stale with the same command and does not
   sync it (`tests/ai-sandbox/test-knowledge.sh`, sections "the start scripts
   refuse a sandbox whose stamp does not match the host" and "sync --all").
3. Re-create each sandbox with a plain `create-ai-sandbox.sh <project>`. That
   rebuilds the image when needed, so the `sandbox-doctor` and
   `sandbox-knowledge-sync` inside it are the current ones, writes stamp `2`, and
   makes the sandbox's `knowledge/` directory and its read-only origin.
4. Old `proposals/<project-id>` branches (the first design) are no longer
   converted, and the one-off script that converted them is removed from the tree.
   The sync ignores such a branch: only `proposal/<date>-<slug>-<hex>` branches are
   looked at. A host that still has them converts them first with the last version
   of that script, which the history keeps (`git log --diff-filter=D --oneline --
   'bin/ai/ai-sandbox-migrate-k*'`, then `git show <parent of that commit>:<path>`),
   before the sandboxes are re-created.
5. Run `ai-knowledge init <url> --integrator <dev-tools dir>` once more. The
   first design kept the integrator in the host's config only; this run records
   it in `README.md` on `main`. A re-run is safe. While the integrator clone has
   commits on `main` that are not pushed yet, the record is skipped and the
   message says so: run `ai-knowledge sync --all` first, then `init` again.

## Deployment

### 1. Install the helpers once

Run `create-ai-sandbox.sh` for any project, once per host. It installs
`ai-knowledge` and the knowledge seed into `~/.ai-sandbox/bin`. The in-sandbox
command `sandbox-knowledge-sync` is not installed on the host: it exists only in
the image.

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

### 4. Stamps and re-creating a sandbox

Every sandbox carries a stamp in its `.env`, `SANDBOX_KNOWLEDGE`, written by
`create-ai-sandbox.sh`: `2` when knowledge is configured on the host (the sandbox
mounts the render, its own clone and its read-only origin, and runs the in-sandbox
command), `0` when it is not (the sandbox has the live `GEMINI.md` mount). A stamp
of `1` is the earlier setup, in which the host made and updated the clone, and is no
longer current (`ai_sandbox_knowledge_state` in `bin/ai/ai-sandbox-lib.sh`,
`tests/ai-sandbox/test-knowledge.sh` "knowledge stamps classify a sandbox from its
.env"). `ai-sandbox` and `ai-sandbox-restart` compare the stamp with the host's
configuration and refuse to start a sandbox that is `stale` (stamp disagrees) or
`unstamped` (created before stamps existed). Such a sandbox would mount the live
`GEMINI.md`, which resolves through the host symlink to the render, read-write, or
predate the in-sandbox sync. The start scripts only check; they never rewrite a
sandbox. `ai-sandbox` checks only when it would start the container; entering a
running sandbox always works, and the host then runs nothing in it and says it must
be re-created.

The repair for one sandbox is a plain `create-ai-sandbox.sh <project>` run, and
every message about a stale or unstamped sandbox (the refusal, `ai-knowledge
status`, `sync --all`, the doctor) names it. There is no script that repairs them
all; `ai-knowledge status` lists every sandbox as `current`, `stale` or
`unstamped`, and you re-create the ones that are not.

Inside a container, `sandbox-doctor` tells the cases apart: "not configured on the
host", "stale" (stamp `1`), "NOT migrated" (no stamp), or, for stamp `2`, each
proposal branch as `pushed` or `pending` and, among the lines it prints for the
host's status directory, line 1 of `status/knowledge` with its age
(`tests/ai-sandbox/test-knowledge.sh`, "O9"). The doctor is part of the image: a
plain `create-ai-sandbox.sh <project>` run rebuilds it.

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

Step 4 applies here too: a sandbox created before `init` ran on this host is
stamped `0` while knowledge is now configured, so it is `stale` and needs the same
re-creation.

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
| `ai-knowledge sync [PROJECT_DIR]` | Update `main`, render, then refresh the project's origin and publish what its clone holds |
| `ai-knowledge sync --all` | Update `main`, render, sync every current sandbox in parallel, render again if `main` moved |
| `ai-knowledge render` | Render only |
| `ai-knowledge status` | Config, `main` revision, then every sandbox with its knowledge state and line 1 of its status file |
| `ai-knowledge status PROJECT_DIR` | The same header, then that project's clone and status line |
| `ai-knowledge proposals [--repo DIR]` | List open proposal files across `proposal/*` branches |
| `ai-knowledge reports [--repo DIR]` | List open report files across `refs/reports/*` of a clone (tombstoned ones hidden); the integrator's `~/knowledge` is the one that holds them |
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

A process report is not a branch: it is the ref `refs/reports/<YYYY-MM-DD>-<project>-<hex>`
(`<project>` the slugged project directory, `<hex>` four characters of the commit),
one commit from `main` that adds only `reports/<project>/process-report-<P>-<F>_<T>.md`.
Deliberate exception to "nothing project-specific belongs here", accepted by the
user: reports live on the private remote outside `main` and outside `refs/heads/`.
Invariant: a report object is never reachable from `main` and never lands in a
clone other than the one that wrote it and the integrator's. Default `git clone`
and `fetch --prune origin` take only `refs/heads/*`, so no clone needs a change;
only the integrator's origin carries `refs/reports/*` (the host fetches the remote's
reports into its own `refs/origin-reports/*` and publishes them there, and only
there: `test-knowledge.sh`, "O10 (the origin)"). The host refuses to push a ref
whose name is off the pattern, that changes any path outside `reports/`, or that has
no common history with its own `refs/remotes/origin/main`. `main` never carries
`reports/`.

### 2. Host-side layout

```
~/.ai-sandbox/knowledge/config                  REMOTE, INTEGRATOR
~/.ai-sandbox/knowledge/main                    the host-owned repository: canonical checkout of main,
                                                fast-forward only, and the refs below
    refs/remotes/origin/*                       the remote's heads, fetched by the host
    refs/origin-reports/*                       the remote's refs/reports/*, fetched by the host
    refs/sandbox/<id>/heads/*                   a sandbox's branches, fetched through the confined container
    refs/sandbox/<id>/reports/*                 its refs/reports/*
    refs/sandbox/<id>/reports-closed/*          its refs/reports-closed/*
    refs/pushed-reports/<id>/<name>             the commit the host pushed for that report
~/.ai-sandbox/knowledge/sandbox-environment.md  the generated sandbox block, appended at render
~/.ai-sandbox/shared/knowledge/                 the render, mounted read-only
    GLOBAL.md                                   rules/global.md + sandbox-environment.md
    claude/agents/<role>.md                     role file verbatim
    gemini/agents/<role>.md                     role file verbatim
    antigravity/rules/<role>.md                 model_decision rule with the role's description
    codex/agents/<role>.toml                    name, description, developer_instructions
    skills/<name>/                              own skills
~/.ai-sandbox/<project>-<hash>-agent/knowledge  that sandbox's clone (written by the sandbox only)
~/.ai-sandbox/<project>-<hash>-agent/knowledge-origin.git
                                                bare, host-written, read-only in the sandbox: the
                                                remote's heads; the remote's reports in the integrator's only
~/.ai-sandbox/<project>-<hash>-agent/status/knowledge
                                                host-written, read-only in the sandbox: line 1, then keys
```

`<id>` is the project id (the sandbox directory's name without `-agent`). The
mirror below `refs/sandbox/<id>/` is the clone's refs at the last successful read,
pruned on every read, and is data only: nothing in it is ever checked out, and the
host decides from it against its own `refs/remotes/origin/main`. A removed
sandbox's namespace and records stay until a sandbox of the same id is synced again.
Refs of `refs/pushed-reports/<id>/` are dropped once the mirror no longer holds the
report. The layout is checked by `test-knowledge.sh`, sections "O10 (the origin)"
and "O7, O8, O19 (the gateway)".

The status file's line 1 is `<time> <ok|warn|refused|offline> <message>`; then
`role=<proposals|integrator>`, `project-id=<id>`, and the keys the in-sandbox command
acts on: `closed-proposal=<branch> <commit>`, `pushed-report=<name>` (a writer's
reports the host has pushed and the clone may drop) and `closed-report=<name>` (the
integrator's reports closed on the remote, whose refs and tombstones the clone may
remove). Every sync writes the file whole, so a key not repeated is withdrawn.

### 3. Sync on every sandbox start

`create-ai-sandbox.sh`, `ai-sandbox` and `ai-sandbox-restart` run
`ai-knowledge sync <project>` before `compose up`; a start syncs only its own
sandbox. Network git runs non-interactively (`GIT_TERMINAL_PROMPT=0`, ssh
`BatchMode=yes`) and under a timeout (60 s, `AI_KNOWLEDGE_GIT_TIMEOUT`, which also
bounds the confined read of the clone and the `docker exec` below). No step fails
the start. The outcome is `status/knowledge` in the sandbox directory, shown by
`sandbox-doctor` (line 1 with its age) and `ai-knowledge status`.

When a fetch or push fails, for example because the ssh key needs a passphrase
and no agent holds it, the sync carries on with the last fetched refs and ends
with the commands to run by hand on the host, in order: the fetches, then
`ai-knowledge sync <project>`, then the pushes. The status line says `offline`
and whether a push is pending. The pushes are commands in the host-owned
repository, such as
`git -C ~/.ai-sandbox/knowledge/main push origin refs/sandbox/<id>/heads/<branch>:refs/heads/<branch>`
(`test-knowledge.sh`, "offline is a status, not a failure" and the report cases of
"reports").

1. Fetch the canonical `main` (and the remote's reports) and fast-forward it.
   Offline: keep the last state.
2. Render and wire the host (step 4).
3. Refresh the sandbox's origin, read the clone, publish (step 5 or 6), write the
   status, then run the sandbox's command.

The sandbox's command, `sandbox-knowledge-sync` (in the image only), runs in the
container at its start when the stamp is `2`, and the host runs it with
`docker exec` after each of its syncs, only in a running container whose stamp is
current; it runs as the sandbox's own user, without a terminal, with standard input
closed and under the time limit, and its failure is a warning in the status line,
never the end of the sync (`test-knowledge.sh`, "O12 (who runs it)").

### Sync on demand: `ai-knowledge sync --all`

Nothing runs on a timer. Between sandbox starts the user runs `ai-knowledge sync
--all` on the host. It fetches and renders `main` once, then syncs every current
sandbox's clone, running or stopped, in parallel (`AI_KNOWLEDGE_JOBS`, default 4),
then fetches `main` once more and renders again only if an integrator clone
advanced it. Children never render, so the render is rebuilt by one process at a
time. Each clone's output is printed as a block under its sandbox name, followed
by one table: sandbox, state, last sync line. A stale or unstamped sandbox is
listed and not synced; a sandbox whose project directory is gone is listed as
`missing project`; a failing child is a row, never the end of the run. Running
containers see the new render at once, and the host runs the sandbox's command in
each running current one (step 3); agents read the new rules in their next session.

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

The host never runs git in the clone, and neither makes nor edits anything below
it (`create-ai-sandbox.sh` only makes the empty `knowledge/` directory): the sandbox can write the clone, including its configuration, hooks and refs,
and a host git run there would execute what it planted (`test-knowledge.sh`, "O7,
O8, O19 (the gateway)": no marker, no host git process with the clone as
repository, nothing below the clone changed). The clone is made by
`sandbox-knowledge-sync` from the read-only origin when the sandbox starts, with
`main` checked out. The same command writes `.git/ai-knowledge-role`
(`proposals <project-id>`) and a pre-commit hook on every run. The hook refuses a
commit on `main` and any staged path outside `proposals/` on a `proposal/*` branch
(or outside `reports/` on a `report/*` branch, the temporary branch the
`process-report` skill builds a report on), so a mistake fails inside the sandbox at
commit time; the host's scope check below remains the enforcement.

On the host, every sync reads the clone with `ai_sandbox_confined_fetch`: a
throwaway container of the sandbox image, no network, no environment, the sandbox
directory mounted read-only, runs `git upload-pack`, and the host fetches into
`refs/sandbox/<id>/` of its own repository, creating or moving no other ref
(`test-confined-git.sh`). Then, against the host's own `refs/remotes/origin/main`:

1. If there is no clone yet, the status says so (`ok: no clone yet`); if
   `~/knowledge` is not a clone, the status names the problem and nothing is moved
   aside. Either way the command runs afterwards.
2. A read that fails is a `warn` status that names the cause and says nothing was
   pushed: no sandbox image yet (`create-ai-sandbox.sh` syncs before it builds
   one), the container could not run, or the time limit passed. A busy clone lock
   gives a `skipped: lock busy` status. The start proceeds in each case and the
   next sync retries (`test-knowledge.sh`, "O12" and the lock-busy case).
3. Every mirrored `proposal/*` branch is classified: a malformed name or a change
   outside `proposals/` (no merge base counts as one) is `refused` and never
   pushed; a tip that is an ancestor of the host's `origin/main` and not on its
   first-parent chain is closed, and written to the status as
   `closed-proposal=<branch> <tip>`; a tip on the first-parent chain is `empty`,
   reported and kept; the rest are open and pushed fast-forward only, a remote with
   commits the branch lacks being a `conflict`. A clone with uncommitted changes is
   not skipped: the host sees refs only, so committed branches are pushed, and the
   sandbox's command leaves `main` where it is and says so.
4. Every mirrored report is checked for name and scope the same way (`refused`
   with its name when not). A writer's report is pushed once per commit: the host
   records it in `refs/pushed-reports/<id>/<name>`, writes `pushed-report=<name>`
   and, from then on, does not push it again while the clone still holds that commit,
   whether or not the container ever ran its command (stopped, or stamp `1`) and
   even after the integrator closed it on the remote. The record is dropped once the
   mirror no longer holds the report (`test-knowledge.sh`, "reports", O20 cases).
5. The status line: `ok: main current; pushed N; closed M` (plus `; reports pushed
   N` when a report went), or the first problem found, or `offline` with the
   per-branch push commands to run by hand.

The sandbox's command then brings the clone up to date: it fetches `origin` with
`--prune`, makes `main` fast-forward to `origin/main` whether or not it is checked
out (a `main` with local commits, or a dirty tree, is left as it is and the command
says so; the host's status says `diverged`), deletes a local `proposal/*` branch
only when the status lists it `closed-proposal=` at the commit listed, and deletes a
local `refs/reports/<name>` only when the status lists it `pushed-report=`
(`test-knowledge.sh`, "O11 (the in-sandbox command)").

### 6. Integrator clone

The integrator's clone is on `main` and carries a local branch for every open
`proposal/*` branch of its origin. Which sandbox is the integrator is decided by the
host's configuration and the sandbox's stamp, never by anything the clone says
(`test-knowledge.sh`, "O6"). Every host sync does for it what step 5 describes, and
in addition: pushes `main` when the clone's `main` is ahead of the host's own
(`diverged` and no push when it has commits the host's `main` lacks and the host's
has moved on); then, only after `main` is on the remote,
deletes closed branches on the remote, only for a tip that is an ancestor of the
host's `origin/main`, and only under a lease on the fetched tip: an amendment the
proposer pushed meanwhile rejects the lease, and the proposal is simply open
again. If `main` advanced, the host re-renders at once. The sandbox's command fetches
`refs/heads/proposal/*` and `refs/reports/*` from the origin into local refs
(non-forced; a branch that does not fast-forward is left alone).

Closing a proposal is `git merge -s ours --no-ff` of its branch into `main`:
`main`'s tree is unchanged, the branch tip becomes an ancestor of `main`, and no
checkout or file removal is needed. The proposal text stays reachable with
`git log --full-history -- proposals/` or `git show <merge>^2:proposals/<file>`.

Closing a report is deletion. After the user has seen it, the integrator runs
`git -C ~/knowledge update-ref refs/reports-closed/<name> refs/reports/<name>`
(never under `refs/reports/`). At its next sync the host deletes the report on the
remote with `--force-with-lease=refs/reports/<name>:<tombstone value>`, then fetches
the remote's reports again, and only a sync that did so and no longer finds the
report writes `closed-report=<name>`; the sandbox's command then removes the report
ref and the tombstone. git answers a leased delete of a ref the remote no longer has
with "stale info" too, so the fetch decides: a report that is gone counts as closed,
one still there under another tip (a moved remote ref) keeps everything and is
reported. A sync that did not reach the remote, a failed deletion or a failed fetch
lists nothing, so both refs stay in the clone and the report on the remote until a
sync does (`test-knowledge.sh`, "reports" and the pending-close cases: offline, the
origin holding none of the remote's reports, the clone's lock busy). The integrator
pushes a report of its own only when the host's copy of the remote's reports lacks
it or holds another tip, so a sync with nothing new reports no `reports pushed`; it
keeps its own report refs until they are closed. A tombstone counts only for the
integrator and only for a name matching the report pattern. There is no
`decisions.md` entry, a closed report is not recoverable from git and, unlike a
proposal, is not re-opened; a rule it suggests follows the proposal flow.

### Re-opening a closed proposal

A closed proposal's branch is gone, but its file is still in `main`'s history,
on the second parent of the merge that closed it. Only the host can file a new
proposal, and the host has no `~/knowledge`; its checkout of `main` is
`~/.ai-sandbox/knowledge/main`. Sync first so that checkout carries the merge,
then take the file from there and file it again:

```bash
ai-knowledge sync --all
git -C ~/.ai-sandbox/knowledge/main show <merge commit>^2:proposals/<file> > ~/.ai-sandbox/knowledge/reopen-<slug>.md
ai-knowledge propose ~/.ai-sandbox/knowledge/reopen-<slug>.md --push
```

Inside the integrator sandbox an agent can only extract the text, with
`git -C ~/knowledge show <merge commit>^2:proposals/<file>`, and hand it to the
user. The sandbox's `/tmp` is not the host's, so a file written there is not
visible to `ai-knowledge propose`.

Close proposals with `-s ours` only. A plain `git merge <branch>` puts the
proposal file on `main` for good: every clone and the render carry it, and the
integrator's next sync warns that `main carries proposal files` because `a
proposal branch was merged for real`. When `main` had not moved, that merge is
a fast-forward: the branch tip lands on `main`'s first-parent chain, every sync
reports the branch as `empty`, keeps it on the remote and in every clone, and
`ai-knowledge proposals` hides it. To fix it, remove the file from `main` with a
normal commit in the integrator's clone (`git rm proposals/<file>`), add a
`decisions.md` entry saying what happened, and let the next sync push. Then
delete the branch by hand; the sync never does it for a tip on the first-parent
chain. In the integrator clone: `git -C ~/knowledge branch -D <branch>`. On the
host: `git -C ~/.ai-sandbox/knowledge/main push origin :refs/heads/<branch>`.
Never rewrite `main` to undo the merge.

### 7. Container mounts

When configured, the two live `GEMINI.md` mounts are replaced by:

| Host path | Container path | Mode |
|---|---|---|
| `shared/knowledge/GLOBAL.md` | `~/.gemini/GEMINI.md`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | ro |
| `shared/knowledge/claude/agents` | `~/.claude/agents` | ro |
| `shared/knowledge/gemini/agents` | `~/.gemini/agents` | ro |
| `shared/knowledge/codex/agents` | `~/.codex/agents` | ro |
| `<sandbox>/knowledge` | `~/knowledge` | rw |
| `<sandbox>/knowledge-origin.git` | `/run/ai-sandbox/knowledge-origin.git` | ro |
| `<sandbox>/status` | `/run/ai-sandbox/status` | ro (also when knowledge is not configured) |

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
`ai-knowledge sync --all` on the host, reading the clone through the confined
container. Inside the sandbox, `sandbox-doctor` shows each local proposal branch as
`pushed` or `pending`, and the age of the host's last status.

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

Reports are listed with `bin/ai/ai-knowledge reports --repo ~/knowledge` and read
with `git show refs/reports/<name>:<path>`; they are shown to the user and closed
with the tombstone command above, never merged into `main`. The skill reads the
host's last status from `/run/ai-sandbox/status/knowledge`. Their figures are not
re-checkable (the stats JSON is not shipped).

The host pushes `main` and deletes the closed branches on the remote on the next
sync. Every other sandbox receives the new rules on its next sync, and its command
drops its own copies of the closed branches the status lists; agents read the new
rules in their next session.

The owner may also edit `main` directly in the integrator's clone, with a
`decisions.md` entry; that clone is the one `ai-knowledge status <dev-tools dir>`
prints.

### Who can do what

| Party | Effective rules | Clone | Network git |
|---|---|---|---|
| Project sandbox | read-only | commit on `proposal/*` branches and `refs/reports/*` refs it creates; fetch from its read-only origin through its own command | none |
| Integrator sandbox | read-only | commit on `main`; close proposals with an ours-merge, reports with a tombstone | none |
| Host | writes the render, the origin and the status file | fetch, fast-forward, read the clone through a confined container, scope check, push, leased deletion of closed branches and reports; never git in the clone | all |

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
local bare repository as the remote and a stub `docker`; `test-confined-git.sh` covers
the confined fetch and the host's git function, and `test-host-git.sh` checks with
`ast-grep` that no git is started in `bin/ai` outside those two functions and a
short list of named exceptions. `bash tests/ai-sync/test-sync.sh` asserts that
`GEMINI.md` is skipped once configured.
