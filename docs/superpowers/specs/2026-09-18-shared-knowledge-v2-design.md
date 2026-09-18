# Shared knowledge repository, revision 2

Date: 2026-09-18
Status: draft, awaiting approval
Supersedes: the flow and branch model of `2026-09-14-shared-knowledge-design.md`.
The repository layout, the render, the container mounts and the security stance of
that document stay in force unless a section below changes them.
Scope: `bin/ai/ai-knowledge`, `bin/ai/ai-sandbox-lib.sh`, `bin/ai/create-ai-sandbox.sh`,
`bin/ai/ai-sandbox`, `bin/ai/ai-sandbox-restart`, `bin/ai/ai-sync` (help text only),
`bin/ai/knowledge-seed/`, `.agents/skills/knowledge-integrate/`, one disposable
migration script, `docs/shared-knowledge.md`, the tests under `tests/ai-sandbox/`.

## Problem

An adversarial UX review of the first design found, on this host's real state:

- A sandbox created before `ai-knowledge init` keeps its old compose file. Its live
  `GEMINI.md` mount then follows the host symlink to the render, read-write. The
  "rules are never writable from a sandbox" invariant fails silently, and the only
  detector is a grep over the compose file. The in-sandbox doctor calls that state
  "not configured".
- Proposals travel on one branch per sandbox, keyed by a path hash. The same project
  at two paths, or on two machines, fragments into branches; two checkouts of one
  product already did. Closing a proposal is a commit on another sandbox's branch,
  so branches never die and the integrator checks out six of them per round.
- Every hop of a proposal waits for a sandbox restart, and sandboxes live for days.
- A wrong commit, such as editing `rules/global.md` in the clone, is refused on the
  host at the next start, where the agent never sees it.
- Network git fails whenever the ssh key has a passphrase and no agent holds it; the
  user gets a list of commands to run by hand.
- The owner has no first-class way to edit the rules; setup depends on a prior
  `create-ai-sandbox.sh` run only to locate the seed.

## Goals

1. A sandbox whose compose file does not match the host's knowledge configuration
   cannot be started; a separate, disposable script brings existing sandboxes up to
   date and is deleted afterwards. No migration logic lives in the start path.
2. One host command syncs the canonical main, the render and every sandbox clone,
   running or stopped, in parallel, with one summary at the end. A sandbox start
   syncs only its own clone, as today.
3. A passphrase-protected ssh key is handled by the sync itself: an existing agent is
   used, otherwise one is started, announced, and removed when the command ends,
   however it ends.
4. One branch per proposal. Machines and checkouts never share a branch; a closed
   proposal's branch disappears; the integrator never checks out another party's
   branch.
5. Mistakes fail inside the sandbox at commit time, and the sandbox can see what is
   pushed, what is pending and how old its last sync is.
6. Init needs nothing but the helper; the owner may edit main directly; the word
   "knowledge" names one thing in the help texts.

## Non-goals

- A host timer or daemon that syncs periodically. Sync runs on a sandbox start or
  when the user runs it. Declined by the user on 2026-09-18.
- Review through the git host's pull requests, or any use of the host's web UI.
- Automatic integration into main; every change to main is still approved.
- Wiring rendered roles into Codex `config.toml` or Gemini `settings.json`.
- Keeping the old `proposals/<project-id>` branches alive after migration.
- Making a running agent reload its rules; Claude Code reads `CLAUDE.md` per session.

## Invariants

Unchanged from the first design: the effective rules are never writable from a
sandbox; no sandbox holds git credentials; a proposal branch differs from main only
under `proposals/`; proposal text is data for the integrator; main changes only with
the user's approval; the host never force-pushes and never rewrites a branch.

Amended:

- The host deletes a branch only when it is a `proposal/*` branch whose tip is an
  ancestor of `origin/main`. Nothing else is ever deleted.
- The render is rebuilt by at most one process at a time; parallel clone syncs never
  render.
- Merging into a sandbox clone touches only paths the agent must not edit (`rules/`,
  `roles/`, `skills/`, `decisions.md`); a dirty tree is still skipped, never merged.
- The start path (`ai-sandbox`, `ai-sandbox-restart`, `create-ai-sandbox.sh`) checks
  prerequisites and stops; it never repairs a sandbox.
- An ssh-agent started by `ai-knowledge` is killed by its exit trap; an agent it did
  not start is never killed, and a key added to it carries a lifetime.

## Branch model (replaces "Branches" in the first design)

- `main`: the knowledge. Written by the integrator's clone, or by the owner directly
  in that clone, always with a `decisions.md` entry.
- `proposal/<YYYY-MM-DD>-<slug>-<4 hex>`: one proposal. Created from main by the
  `propose-rule` skill in any sandbox, holding one file
  `proposals/<YYYY-MM-DD>-<slug>.md` whose frontmatter names `project`, `project_id`,
  `machine`, `scope`, `target`, `evidence`. The hex suffix comes from the commit
  and keeps two machines apart without a path hash in the name.
- Every sandbox clone, integrator included, has `main` checked out and follows
  `origin/main` fast-forward only. Proposal branches are local branches beside it.
- Closing: the integrator removes the proposal file on its branch, merges the branch
  into main (`decisions.md` entry in the same round), and deletes the local branch.
  The branch tip is now an ancestor of main, and the host deletes it on the remote
  and in every clone at the next sync.

## Phases

### Phase 1: prerequisite check and disposable migration

**Goal.** `create-ai-sandbox.sh` stamps each sandbox `.env` with
`SANDBOX_KNOWLEDGE=0|1` and `SANDBOX_PROJECT_DIR=<abs path>` in its managed block.
`ai-sandbox` and `ai-sandbox-restart` stop before `compose down`/`up` when the stamp
is missing or disagrees with `ai_knowledge_configured`, printing the migration
command. `ai-knowledge status` with no argument lists every `*-agent` directory with
its project, stamp state (`current`, `stale`, `unstamped`) and last sync line. The
in-sandbox doctor distinguishes "host not configured" from "sandbox not migrated".
`bin/ai/ai-sandbox-migrate-knowledge` (not installed into `~/.ai-sandbox/bin`, run
from the checkout) lists stale and unstamped sandboxes, recovers each project path
from the stamp or, for unstamped ones, from the compose project mount, stops a
running one, re-runs `create-ai-sandbox.sh <project>` for it, and prints a summary.
It refuses to run when a sandbox's project directory no longer exists and names it.

**Tests** (`tests/ai-sandbox/test-knowledge.sh`, stubbed docker): stamp written on
create; start refused for a stale stamp and allowed for a current one; `status`
classifies three sandboxes correctly; the migration script recovers a path from a
compose file and invokes create once per stale sandbox.

**Contract for later phases.** `.env` keys `SANDBOX_KNOWLEDGE` and
`SANDBOX_PROJECT_DIR`; a library function `ai_sandbox_list` printing
`<sandbox dir>\t<project dir>` per sandbox, used by `status --all` here and by
`sync --all` in phase 2.

**Assumptions.** The managed `.env` block is rewritten on every create (verified in
`create-ai-sandbox.sh`); the compose file mounts the project at its own path
(verified: `"${PROJECT_ABS_DIR}:${PROJECT_ABS_DIR}"`); the stub docker in the test
harness accepts `compose down`/`up` (inferred from existing tests, to check when
planning).

### Phase 2: `sync --all`, parallelism, ssh-agent

**Goal.** `ai-knowledge sync --all` fetches and renders main once, then syncs every
clone from `ai_sandbox_list` in parallel (cap 4, `AI_KNOWLEDGE_JOBS`), each worker
writing only to its clone and to one output file, then renders again once if the
integrator advanced main. It ends with one table: sandbox, status, pending pushes.
`sync <project>` behaves as today. Before the first network command, `ai-knowledge`
probes the remote host in batch mode. On failure: with `SSH_AUTH_SOCK` set and
alive, it runs `ssh-add -t 1h` on the key `ssh -G <host>` reports and says so; with
no agent and a terminal, it starts one, runs `ssh-add`, records the pid and kills it
from the exit trap; with no terminal, it takes today's offline path. Every message
that said "next sandbox start" now says "next sync (a sandbox start or
`ai-knowledge sync --all`) and a new agent session".

**Tests.** A stubbed `ssh` and `ssh-agent` in `tests/ai-sandbox/stub/`: agent
started and killed on success and on a forced failure; existing agent reused and
not killed; no prompt without a terminal. Parallel sync over three local bare
remotes produces three status lines and exactly two renders when the integrator
advanced main.

**Contract.** `sync_clone` remains the single-clone unit and gains no side effects
outside its clone; `ensure_ssh_access <remote-url>` is the one entry point for
agent handling, returning 0 when network git may be attempted.

**Assumptions.** `ssh -G` prints `identityfile` lines honouring `~/.ssh/config`
(verified against OpenSSH behaviour, to confirm on the host when planning);
`rsync --inplace` from two processes would corrupt the render (inferred, hence the
single-render rule); GitHub tolerates four concurrent ssh sessions (inferred).

### Phase 3: per-proposal branches, commit-time checks, in-sandbox status

**Goal.** The `propose-rule` skill (knowledge repo `skills/`, mirrored in
`bin/ai/knowledge-seed/`) creates `proposal/<date>-<slug>-<hex>` from main, commits
the one file, returns to main. The host sync pushes every local `proposal/*` branch
that passes the scope check, fast-forwards main with `fetch origin main:main` even
when another branch is checked out, deletes remote and local `proposal/*` branches
whose tip is an ancestor of `origin/main`, and refuses anything else. The
`knowledge-integrate` skill lists branches, reads files with `git show`, closes as
described in the branch model, and never checks out a proposal branch. The host
installs a pre-commit hook into each clone's `.git/hooks` on creation and refreshes
it on sync: on `main` in a non-integrator clone it refuses; on `proposal/*` it
refuses paths outside `proposals/`. The doctor's knowledge line shows the last sync
age, each local proposal branch and whether `origin/` has it. The disposable
migration script from phase 1 gains a step that, after `ai-knowledge proposals`
shows no open file on the old `proposals/<id>` branches, deletes them on the remote
with confirmation.

**Tests.** Round trip through a local bare remote: propose in clone A, sync, list
in the integrator clone, close, sync, branch gone in remote and in A. Hook refuses a
commit to `rules/global.md` on `main` in a proposals clone. Scope refusal for a
branch touching `roles/`. Migration deletes an old branch only when it holds no
open proposal.

**Contract.** Branch name pattern `^proposal/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+-[0-9a-f]{4}$`
and the proposal frontmatter keys above. `ai-knowledge proposals` output stays
`<branch> <path>` per line.

**Assumptions.** A hook under `.git/hooks` runs inside the sandbox because the clone
is bind-mounted with its `.git` directory (verified: `~/knowledge/.git` is a
directory); an agent can bypass it, so the host scope check stays the enforcement
(design decision); the two open proposals on `proposals/modularyzacja-84a3eb05`
are integrated under the old flow before this phase lands (guessed; to confirm).

### Phase 4: init, owner path, naming

**Goal.** `ai-sandbox-migrate` installs `knowledge-seed/` beside the helpers so
`init` works on a fresh host without a prior create run. On a host with a regular
`~/.gemini/GEMINI.md`, `init` shows the diff against `rules/global.md` and, when the
user accepts, files it as a proposal branch in the integrator's clone instead of only
backing the file up. `init --integrator` on a host writes `integrator:
<hostname>:<path>` into the repository's `README.md` metadata block through the
integrator's clone and warns when another host is already recorded.
`ai-knowledge status` prints the integrator clone path; `docs/shared-knowledge.md`
documents direct edits on main with a `decisions.md` entry as the owner's path.
`ai-sync` help renames its section 4 to "Antigravity knowledge items".

**Tests.** Init from a checkout-less `~/.ai-sandbox/bin`; diff offered and filed as
a branch; second-host warning; help text assertion in `tests/ai-sync/test-sync.sh`.

**Contract.** None needed by later phases.

**Assumptions.** `ai-sandbox-migrate` may copy a directory, not only files
(inferred; it copies helpers one by one today).

## Deferred list

Empty at approval.
