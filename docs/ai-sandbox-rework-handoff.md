# ai-sandbox rework — handoff and host verification

Written 2026-09-02, from inside a sandbox container with no access to the host
Docker daemon. Everything below the "Verify" heading has to happen on the host.

Branch: `ai-sandbox`. Work starts at `72d35ed` (the last docs-only commit) and
runs to `5915042`. Nothing is merged.

- Design: `docs/superpowers/specs/2026-09-02-ai-sandbox-sharing-design.md`
- Plan: `docs/superpowers/plans/2026-09-02-ai-sandbox-sharing.md`
- Verification script: `verify-ai-sandbox-on-host.sh` (untracked, repo root)

---

## What changed

Three problems, from the original request plus what the work turned up.

**1. Per-project AI accounts.** The seed rsyncs re-ran on every invocation, so a
login made inside a sandbox was overwritten by the host's the next time the
script ran. Seeding is now one-shot, guarded by a `.seeded` marker; later runs
leave a project's logins alone. `~/.codex` joins the per-project set and the
codex CLI is installed in the image, so Claude, Codex and Gemini can each be a
different account per project. `ai-sandbox-account status|refresh|reset` is the
deliberate way to change that; `refresh` backs up whatever it replaces.

**2. Disk.** Measured inside a live sandbox, ~3.3 GB per sandbox was either
identical across projects or host state a single-project sandbox cannot use:

| Path | Size | Disposition |
|---|---|---|
| `.config/Antigravity/User/workspaceStorage` | 935M | no longer seeded (host state for every workspace ever opened) |
| `.antigravity-ide/extensions` | 720M | `shared/`, and no longer baked into the image |
| `.antigravity/extensions` | 633M | `shared/` |
| `.config/Claude/claude-code/*` | 617M | `shared/` |
| IDE `CachedExtensionVSIXs`/`CachedData`/`WebStorage` | 150M | `shared/` |
| browser-profile model stores | ~125M | no longer seeded (regenerable) |
| `.claude/downloads` | 111M | `shared/` |

The 8.4 GB in `.gemini/*/brain` was already a live host bind mount and never
cost anything per sandbox. Separately, the image is now built once as
`ai-sandbox:<variant>-u<uid>` instead of tagged per project — nothing in the
generated Dockerfile was ever project-specific.

**3. Same-name project collisions.** Sandboxes are keyed on
`<slug>-<first 8 hex of sha256 of the absolute project path>`, so two
directories sharing a basename no longer collide. Every sandbox records its
project path in a `project-path` file.

Supporting changes: the `~/.bashrc` function block became real executables in
`~/.ai-sandbox/bin` plus a one-line PATH stub; `--with-docker` is sticky like
`--display` (a bare re-run used to silently disable it) with `--no-docker` to
reverse it; `usage()` rewritten; `/etc/subuid` append guarded (useradd already
allocates a range, leaving a duplicate line).

## Layout after migration

```
~/.ai-sandbox/
  bin/                      ai-sandbox, -account, -gc, -extensions, -migrate, ...
  config                    DEV_TOOLS_DIR=<repo>
  .schema-version           2
  image/build/              the one build context
  image/<variant>-u<uid>.stamp
  shared/                   extensions, downloads, caches — one copy for all
  <slug>-<hash>-agent/      per project: credentials, tool state, compose, .seeded
```

## Migration

`~/.ai-sandbox/bin/ai-sandbox-migrate` runs automatically before every start and
from `create-ai-sandbox.sh`. Idempotent and silent when there is nothing to do.

- **M1** renames legacy `<basename>-agent` directories. It reads the true
  project path from `working_dir:` in each sandbox's own `docker-compose.yml`,
  which is why two same-named projects both migrate correctly.
- **M2** moves shared bulk into `shared/`. The first sandbox donates its copy;
  later ones are reported, not deleted.
- **M3** reports images left from the old per-project naming.

**Migration never deletes.** Directories move with `mv`. It refuses to touch a
sandbox whose container is running (stop it first). `ai-sandbox-gc` is the only
thing that deletes, and it lists everything and confirms first.

---

## Verify (on the host)

```bash
cd ~/dev/public/dev-tools && ./verify-ai-sandbox-on-host.sh 2>&1 | tail -120
```

Stop running sandboxes first. Phases A–B are read-only; B takes a hardlink
backup at `~/.ai-sandbox.pre-migration` (near-instant, near-zero space, and
since migration only ever `mv`s, it fully protects the contents). C onward
mutates. The script deliberately stops before building the image or starting a
container.

What to look for:

- **Phase D** — every sandbox shows `claude-creds=yes` and its Antigravity
  history intact. Host-side conversation directories must be unchanged; they
  live outside `~/.ai-sandbox` and a rename cannot reach them.
- **Phase E** — one `image:` tag shared by all projects, no `build:` blocks.
- **Phase F** — `SANDBOX_WITH_DOCKER=1` survives a bare re-run; `--no-docker`
  sets 0; passing both exits 2.
- **Phase A** — "distinct image IDs" answers the question never measured from
  inside the container: whether the old per-project images were genuinely
  separate copies or were already sharing layers.

Then, deliberately: `./bin/ai/create-ai-sandbox.sh` (builds ~10GB once, starts).

## If it goes wrong

Restore the state directory (hardlink backup, so contents are byte-identical):

```bash
rm -rf ~/.ai-sandbox && mv ~/.ai-sandbox.pre-migration ~/.ai-sandbox
```

Restore the code:

```bash
cd ~/dev/public/dev-tools
git checkout 72d35ed -- bin/          # pre-rework scripts
./bin/create-ai-sandbox.sh --no-start # rewrites the ~/.bashrc block back
```

To abandon the branch entirely: `git reset --hard 72d35ed` (this also drops the
design, plan and this file — copy anything you want first).

## What is NOT verified

The tests run against a temp `HOME` with a stubbed `docker`: 133 assertions over
8 suites (`bash tests/ai-sandbox/run-tests.sh`, no framework needed). They cover
identity, migration behaviour including refusal cases, seed-once semantics,
option handling, and the generated compose/Dockerfile text. The compose output
was confirmed to parse as valid YAML with the expected structure.

Never exercised anywhere: the image actually building, a container actually
starting, the nested `shared/` bind mounts resolving at runtime, and the
extension bootstrap (`ai-sandbox-extensions`). Those need the host.

## Decisions taken without asking

- **Worked on the `ai-sandbox` branch, not a git worktree** — only the repo is
  bind-mounted into the container, so a sibling worktree path is not writable.
- **Shared-mount table carries three fields, not two.** As designed, the table
  mapped `shared/` subdir to container path, but migration and gc need the
  path inside the *sandbox directory*, and the two differ (`~/.config/Claude`
  vs `claude-data/`). An empty third field marks data that exists only in the
  container's writable layer, which those two skip. Without this, M2 and gc
  would have silently matched nothing for the Electron directories.
- **`CONTAINER_HOME` changed to `$HOME`**, not just the new `USER_HOME` build
  arg. The spec wanted container and host home paths to match; passing the arg
  while leaving `CONTAINER_HOME=/home/$USER` would still diverge on a host whose
  home is not `/home/<user>`. No effect on this host.
- **Migration refuses a running sandbox** rather than force-removing its
  container, which is what the plan specified. Force-removal would destroy
  whatever is running inside — including, since migration runs before every
  start, the session that invoked it.
- **Accepted a transient break between two commits**: `b91ce81` switched the
  script to path-derived ids while the `~/.bashrc` helper still used basenames.
  `5739aef` deletes that helper. Nothing user-visible broke in between, because
  the block only reaches `~/.bashrc` when the script is run on the host.
- **`--with-docker` stays opt-in.** It sets `seccomp:unconfined` and
  `apparmor:unconfined` and the nested daemon's image store lives inside the
  container, costing GBs per sandbox. Stickiness gives the ergonomics of a
  default without the cost.

## Not done

`review.md` (untracked, repo root) flags `~/.sdkman` being mounted read-write as
a critical escape path: an agent can replace `java`/`gradle` binaries that the
host then executes. Real, and out of scope for this change. It is a one-word fix
(`:ro`) but changes behaviour for anyone installing SDKs from inside a sandbox,
so it deserves its own decision.
