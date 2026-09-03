# ai-sandbox: per-project accounts, shared assets, stable identity

Date: 2026-09-02
Status: approved design, not yet implemented
Scope: `bin/create-ai-sandbox.sh` and the helper scripts it installs

## Problem

Three distinct defects in the current script.

1. **Host credentials clobber per-project logins.** Per-project state already
   lives under `~/.ai-sandbox/<container>/`, but the script re-rsyncs
   `~/.claude`, `~/.gemini`, `~/.antigravity` and `~/.config/Antigravity*` from
   the host on *every* run. A login made inside the sandbox is overwritten on
   the next invocation, so a project cannot hold its own Claude / Codex / Gemini
   account. Codex is not handled at all.
2. **Each sandbox costs roughly 13 GB, most of it duplicated.** Measured inside
   a live sandbox, ~3.3 GB of per-sandbox state is identical across projects or
   is host state the sandbox has no use for, and the image is tagged per project
   even though nothing in the Dockerfile is project-specific.
3. **Project identity is the directory basename.** Two projects whose
   directories share a basename collide on the same sandbox directory, container
   name and image tag.

### Measurements

Taken with `du -sh` inside a running sandbox on 2026-09-02.

| Path in the sandbox | Size | Nature |
|---|---|---|
| `.config/Antigravity/User/workspaceStorage` | 935M | host state for every workspace the user has opened, copied into each sandbox |
| `.antigravity-ide/extensions` | 720M | IDE extensions; also baked into the image |
| `.antigravity/extensions` | 633M | IDE extensions |
| `.config/Claude/claude-code/{2.1.229,2.1.237}` | 617M | Claude Code version downloads |
| `.config/Antigravity IDE/{CachedExtensionVSIXs,CachedData,WebStorage}` | 150M | cache |
| `.gemini/antigravity-browser-profile/*` model stores | ~125M | regenerable Chrome model blobs |
| `.claude/downloads` | 111M | CLI binary downloads |

`~/.gemini/{antigravity,antigravity-ide}/{brain,conversations}` (8.4 GB) and
`~/.claude/projects` are already live host bind mounts and cost nothing per
sandbox.

Identity-bearing files, all already per-project: `.claude/.credentials.json`,
`.claude.json`, `.gemini/google_accounts.json`, `gcloud/`, and the Electron
profiles under `.config/{Antigravity,Antigravity IDE,Claude}`.
`~/.gemini/config` holds MCP settings and plugins that the host's Antigravity
executes, so it is seeded once per sandbox rather than live-shared.

## Non-goals

- Mounting host installations (Antigravity, Chrome, Python site-packages) into
  the container. Host wheels are built for the host interpreter and glibc, and
  bind-mounting host binaries drags in host system libraries. Explicitly
  rejected: sharing one image across projects achieves the same saving without
  coupling the container to the host distribution.
- Changing the shared-brain arrangement (`~/.gemini/GEMINI.md` symlinked from
  `~/.claude/CLAUDE.md`).

## Design

### 1. Project identity

```
slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/-\{2,\}/-/g' \
          -e 's/^-*//' -e 's/-*$//'; }
PROJECT_ID = "$(slug "$(basename "$ABS")")-$(printf '%s' "$ABS" \
                | sha256sum | cut -c1-8)"
```

`$ABS` is the absolute project path (the git toplevel when there is one). The
sanitisation is the one the script already uses, with one correction: the
current `sed` strips leading non-alphanumerics but not trailing ones, so a
directory like `foo.` yields `foo-`, which would produce the double dash
`foo--<hash>` here and is not a legal Docker repository component. The pinned
version trims both ends. An empty slug falls back to `project`. This is computed in two places -- `create-ai-sandbox.sh` and the
helper library -- so it is pinned here byte-for-byte and both must use the
shared `_lib.sh` definition rather than reimplementing it.

e.g. `dev-tools-3f9a1c4e`, container `dev-tools-3f9a1c4e-agent`. Bounded in
length, readable, collision-free across same-named directories.

Every sandbox directory holds a `project-path` file recording the absolute
project path it belongs to. This is what makes migration deterministic rather
than a basename guess.

Claude Code's history key (`~/.claude/projects/<sanitised-path>`) derives from
the project path, not from this id, and is unaffected.

`NESTED_DISPLAY_NUM` is derived from `PROJECT_ID`, so it changes for existing
sandboxes. Migration stops the old display before renaming.

### 2. Directory layout

Two new top-level siblings. Per-project directories keep their current internal
paths, so no credential path changes and no risk of losing a login.

```
~/.ai-sandbox/
  .schema-version            migration gate
  config                     records the dev-tools source dir
  bin/                       installed helper executables + _lib.sh
  image/
    build/                   Dockerfile + entrypoint + sandbox-* helpers
    <variant>-u<uid>.stamp   hash of build inputs
  shared/                    bulk code, synced from the host, mounted READ-ONLY
    antigravity-extensions/       -> ~/.antigravity/extensions
    antigravity-ide-extensions/   -> ~/.antigravity-ide/extensions
    claude-downloads/             -> ~/.claude/downloads
    claude-desktop-versions/      -> ~/.config/Claude/claude-code
    ide-vsix/                     -> ~/.config/Antigravity IDE/CachedExtensionVSIXs
    jetbrains-plugins/            -> ~/.local/share/JetBrains
  <PROJECT_ID>-agent/
    project-path  .seeded  .env  docker-compose.yml
    x11auth/  start-display.sh  stop-display.sh
    .claude/ .claude.json .codex/ .gemini/ gcloud/
    antigravity-data/ antigravity-ide-data/ claude-data/ .antigravity/
    cache/ npm/                -> ~/.cache, ~/.npm: per sandbox, writable
```

`~/.antigravity-ide/` is deliberately absent from the per-project set: only its
`extensions` subdirectory is mounted (from `shared/`), and the rest stays in the
container's writable layer, as it does today.

The `shared/*` directories are nested bind mounts inside the per-project mounts.
Docker orders mounts by destination depth, so this works; `~/.claude/projects`
already relies on it today.

**Trust between sandboxes.** Sandboxes are not one trust domain: an agent in one
project must not be able to run code in another. Every `shared/*` store holds
executable code -- IDE extensions, JetBrains plugins, Claude Code and Claude
Desktop binaries -- so all of them are mounted read-only, and only the host
writes them. `create-ai-sandbox.sh` syncs the host's own copy of each store in
on every run, and `ai-sandbox-extensions` installs, from a throwaway container,
what the host does not have. Installing or updating on the host and re-running
the script is how a change reaches the sandboxes; installing inside a sandbox
fails. Whatever a sandbox must write at run time -- `~/.cache`, `~/.npm`, the
IDE's `CachedData` -- is therefore per sandbox (`cache/`, `npm/` and
`antigravity-ide-data/CachedData` in the project directory), one copy per
project by design. The one exception is migration step M2 below, a one-off lift
of a legacy sandbox's copy into an empty `shared/`.

### 3. One shared image

- Build context moves to `~/.ai-sandbox/image/build/`.
- Image name `ai-sandbox:<variant>-u<uid>`, variant `base` or `docker`
  (`--with-docker` genuinely adds layers). The uid suffix prevents two host
  users on one daemon from fighting over a tag.
- Per-project `docker-compose.yml` drops its `build:` block and names the image
  only, so `docker compose up` can never retag per project. The script builds
  with `docker build` when needed.
- Rebuild fires when the image is absent, when the build-input hash differs from `<variant>-u<uid>.stamp`, or on `--rebuild`.
  `--rebuild` now rebuilds the image every project shares; the help text says so.
  The build-input hash is `sha256` over: every file in `image/build/` fed in
  `LC_ALL=C sort` order as `<relative-path>\0<sha256-of-contents>\0`, then the
  build args (`USER_ID`, `GROUP_ID`, `USER_NAME`, `USER_HOME`) and the variant.
  Sorting by path under a fixed locale is what makes it reproducible.
- The extension-install layers leave the Dockerfile; that is the 720M. Extensions
  live in `shared/antigravity-ide-extensions/` instead, populated once by a
  bootstrap step that runs when the directory is empty:
  1. if the host has `~/.antigravity-ide/extensions`, copy it in;
  2. otherwise run a throwaway container from the image with the shared
     directory mounted at the extensions path and invoke
     `antigravity2-ide --install-extension` for each extension there.
  The same applies to `shared/antigravity-extensions/`. Because the image no
  longer carries extensions, the bootstrap is the only source -- it must not be
  skipped silently. `ai-sandbox-account`-style re-runs are available via
  `ai-sandbox-gc`'s sibling command `ai-sandbox-extensions refresh`.
- `USER_HOME` becomes a build arg set to the host `$HOME`, so container and host
  home paths match rather than being hardcoded to `/home/$USER`.
- `@openai/codex` is added to the node globals.
- The unconditional `echo "${USER_NAME}:100000:65536" >> /etc/subuid` (and the
  `subgid` twin) becomes conditional. `useradd` on Ubuntu 22.04 already
  allocates subordinate ranges for a new non-system user, so the append produces
  a duplicate line in each file, confirmed present in the running image. Whether
  duplicate identical ranges upset `newuidmap` has not been verified; the append
  is redundant either way and should only run when the user has no range yet.

Legacy `ai-sandbox-<project>:latest` images are reported, never deleted
automatically. `ai-sandbox-gc` removes them after confirmation.

### 4. Seeding and per-project accounts

Seeding becomes one-shot. On first creation the script copies host credentials
and tool state in as it does today and writes `.seeded`. On every later run
those rsyncs are skipped entirely, so an in-sandbox login is never overwritten.

The seed also stops copying what a sandbox cannot use: `workspaceStorage`,
`.config/Claude/claude-code/`, `.claude/downloads`, the Antigravity IDE caches
and the browser profile's model stores. That is ~1.2 GB per sandbox that is
never written in the first place.

`~/.codex` joins the per-project set, seeded and frozen like the rest.

New helper `ai-sandbox-account`:

- `status` -- which account each tool is currently on, per project
- `refresh` -- re-pull host credentials, after backing up the current ones
- `reset` -- wipe to a clean login prompt

### 5. Helpers become real scripts

The `~/.bashrc` block currently defines shell functions and is rewritten on
every run; open shells keep the stale copy, and `_ai_sandbox_dir()` duplicates
identity logic that must now stay in sync with migration.

Instead, helpers become ordinary executables checked into `bin/` in this repo
and installed into `~/.ai-sandbox/bin/`:

```
ai-sandbox  ai-sandbox-stop  ai-sandbox-restart  ai-sandbox-attach
ai-sandbox-rm  ai-sandbox-account  ai-sandbox-gc  ai-sandbox-migrate
_lib.sh     identity, paths, compose invocation -- one definition, sourced by all
```

`create-ai-sandbox.sh` sources the repo's `_lib.sh` too, so the id function
exists exactly once.

The `~/.bashrc` block shrinks to a single stable line that prepends
`~/.ai-sandbox/bin` to `PATH`, and never needs changing again. The installed
copies are refreshed from the source directory recorded in `~/.ai-sandbox/config`
by `ai-sandbox-migrate`, which runs on every sandbox start.

None of the helpers need to mutate the calling shell, so executables are a
faithful replacement for the functions.

### 6. Migration

`~/.ai-sandbox/bin/ai-sandbox-migrate`, invoked by `create-ai-sandbox.sh` and by
`ai-sandbox` before every start. Idempotent, silent when there is nothing to do,
gated by `~/.ai-sandbox/.schema-version`.

**M1 -- rename to path-derived identity.** For every legacy `<name>-agent/`
lacking a `project-path` file, read `working_dir:` from that sandbox's own
`docker-compose.yml`; the script already writes the real project path there, so
it is authoritative and same-basename ambiguity never arises. Then: run the old
`stop-display.sh`, `mv` the directory to `<PROJECT_ID>-agent`, write
`project-path`, remove the legacy container and its stale
`/tmp/.X11-unix/.ai-sandbox-<name>-agent` socket directory. If the compose file
is missing or unreadable, or the target id already exists, leave that sandbox
untouched and warn.

Removing the legacy container is safe: every piece of durable state is in a bind
mount, and the container's writable layer holds only caches and shell history.

**M2 -- lift shared bulk out of existing sandboxes.** The first sandbox to
migrate `mv`s its extensions, downloads, `claude-code` versions and IDE caches
into `shared/`. Later sandboxes find `shared/` populated and are only reported
as holding reclaimable duplicates.

**M3 -- legacy images.** Reported, never removed automatically.

Migration never deletes. Directories move with `mv`; there is no copy-then-
delete anywhere. Reclaiming leftover duplicates and old per-project images is
`ai-sandbox-gc`, which confirms first.

### 7. History safety

Antigravity's brain and conversations and Claude Code's `projects/` live on the
host, outside `~/.ai-sandbox`, and are mounted live into every sandbox. Renaming
sandbox directories cannot reach them. Per-project history --
`.config/Antigravity/User/{History,workspaceStorage}`, the Electron profiles,
`.claude/`, `.gemini/` -- travels with the `mv`. The seed exclusions in section 4
change only what is copied in at first creation and never remove anything from an
existing sandbox.

`ai-sandbox-rm` is updated to leave `shared/` and `image/` alone.

### 8. CLI surface and help

`--with-docker` becomes sticky, exactly as `--display` already is. Today
`WITH_DOCKER` is hardcoded to `no` at the top of the script and set only by the
flag, with no restore-from-`.env` step, so re-running `create-ai-sandbox.sh`
bare on a project created with `--with-docker` silently regenerates it without
Docker: the Dockerfile loses the daemon, `security_opt` disappears from the
compose file, and `SANDBOX_WITH_DOCKER` flips to `0`. The next container start
then has no daemon and no explanation. The `--display` restore exists to prevent
precisely this class of bug; Docker gets the same treatment, reading
`SANDBOX_WITH_DOCKER` back from `.env` when neither flag is given.

`--no-docker` is added so a sticky choice can be reversed, mirroring how an
explicit `--display=` overrides a stored mode.

`--with-docker` stays opt-in rather than becoming the default. It sets
`seccomp:unconfined` and `apparmor:unconfined` and passes through `/dev/fuse`
and `/dev/net/tun`; the nested daemon's own image store also lives in the
container's writable layer, duplicating gigabytes per sandbox and defeating
section 3. Stickiness gives the ergonomics of a default without the cost.

`usage()` is rewritten to cover the whole surface. Known gaps in the current
text:

- the `auto` description says "wayland if available, else nested", but the code
  tries wayland, then xpra, then nested. `xpra` is missing from the fallback
  chain it documents.
- `--no-docker` and the stickiness of both `--display` and `--with-docker` are
  undocumented.
- `--rebuild` no longer means "rebuild this project's image"; it rebuilds the
  image every project shares, and must say so.
- the helper list omits the in-container commands (`sandbox-doctor`,
  `sandbox-desktop`) and all the new ones (`ai-sandbox-account`,
  `ai-sandbox-gc`, `ai-sandbox-migrate`, `ai-sandbox-extensions`).
- nothing explains the on-disk layout: what is per-project, what is shared
  between projects, and what is mounted live from the host.

The rewritten help documents each option with its default and whether it is
remembered, the positional `PROJECT_DIR`, both helper groups, and a short
layout summary pointing at `~/.ai-sandbox/`.


## Error handling

- Migration failure on one sandbox warns and continues to the next; it never
  aborts the start of the sandbox actually being launched.
- A missing or unparsable legacy `docker-compose.yml` leaves that directory in
  place under its old name; it is reported once per run, not silently skipped.
- A target `<PROJECT_ID>-agent` that already exists is a hard stop for that one
  sandbox, reported with both paths, for manual resolution.
- Image build failure aborts, as today.
- `--with-docker` and `--no-docker` together is a usage error, not a silent
  last-one-wins.
- Extension bootstrap failure is reported loudly and leaves the shared directory
  empty rather than half-populated, so the next run retries it. The sandbox still
  starts; the IDE simply has no extensions until the bootstrap succeeds.

## Testing

This work is being written from inside a sandbox container with no access to the
host Docker daemon, so it cannot be built or run here. `shellcheck` is not
available in the sandbox image either.

What can be checked here: `bash -n` on every script, and a review of the
generated Dockerfile / compose output against the current behaviour.

What must be verified on the host, by the user:

1. `create-ai-sandbox.sh --no-start` on a project that already has a legacy
   sandbox; confirm M1 renamed it, `project-path` is correct, and credentials
   are intact.
2. `create-ai-sandbox.sh` on a second project; confirm no image rebuild occurs
   and both projects reference the same image tag.
3. Log into a different Claude account inside one sandbox, re-run
   `create-ai-sandbox.sh`, confirm the login survives.
4. `ai-sandbox-account status` in both projects shows different accounts.
5. `du -sh ~/.ai-sandbox/*` shows the per-sandbox drop and a single populated
   `shared/`.
6. Antigravity conversation history is present in a migrated sandbox.
7. `create-ai-sandbox.sh --with-docker`, then a bare re-run; confirm the compose
   file still carries `security_opt` and `SANDBOX_WITH_DOCKER=1`. Then
   `--no-docker`, and confirm both are gone.
8. `create-ai-sandbox.sh --help` lists every option, both helper groups and the
   layout summary.
