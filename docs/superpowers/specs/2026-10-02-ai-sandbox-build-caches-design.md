# ai-sandbox: host build caches through an ephemeral overlay

Date: 2026-10-02
Status: approved 2026-10-02; phases 1-3 done, phase 4 host acceptance passed 2026-10-02 (offline Gradle build, reset on start, host caches untouched, rm clean)
Input: [2026-10-02-ai-sandbox-build-caches-brief.md](2026-10-02-ai-sandbox-build-caches-brief.md)
(the user's decisions there are fixed and are not restated as open questions)
Scope: `bin/ai/create-ai-sandbox.sh`, `bin/ai/ai-sandbox-lib.sh`, the start
helpers, `ai-sandbox-rm`, `ai-sandbox-gc`, `tests/ai-sandbox/`

## Goal

An agent in a sandbox can run `./gradlew --offline ...` against the
dependencies and wrapper distributions the host has already downloaded. The
sandbox gets no host credentials and cannot modify the host's caches. Writes
made inside the sandbox stay in that sandbox and are discarded at its next
container start.

## Design summary

Three host directories are the read-only lower layers of three overlayfs
mounts, one Docker `local` volume each (`type=overlay`), mounted by the host
daemon and declared in the sandbox's compose file:

| Key | Host path (lower) | Container path |
|---|---|---|
| `gradle-caches` | `~/.gradle/caches` | `~/.gradle/caches` |
| `gradle-wrapper-dists` | `~/.gradle/wrapper/dists` | `~/.gradle/wrapper/dists` |
| `m2-repository` | `~/.m2/repository` | `~/.m2/repository` |

Container and host home paths are equal (`CONTAINER_HOME="$HOME"`), so the
absolute paths Gradle records in its caches line up. Each volume's upper and
work directories live in the sandbox directory, owned by the host user. Every
start the scripts perform on a stopped container first swaps in fresh, empty
upper and work directories.

## Invariants

- **I1 Lower is never written from a sandbox.** The three host directories
  reach a container only as overlay `lowerdir`; there is no bind mount of them
  and no path through which a container writes them. The host's only write is
  `mkdir -p` of the three directories by `create-ai-sandbox.sh`.
- **I2 Nothing else from `~/.gradle` or `~/.m2`.** Never `gradle.properties`,
  `init.d`, `settings.xml`, `settings-security.xml`, `jdks`, `daemon` or any
  other entry. The container's own `~/.gradle` and `~/.m2` come from the image.
- **I3 No new privilege.** The feature adds no capability, device,
  `security_opt` or privileged flag to the container; the daemon performs the
  mount.
- **I4 Upper is per sandbox.** No two sandboxes share an upper or work
  directory; one sandbox's writes are never visible in another.
- **I5 Clear on start, never while running.** Upper and work are replaced with
  empty directories before every `compose up` that the scripts run while the
  sandbox's container is not running, and at no other time. Entering a running
  container never touches them.
- **I6 Network unchanged.** Offline is possible, not enforced.
- **I7 Ownership.** Upper and work are created by the scripts as the host user,
  before Docker could create them as root.
- **I8 No migration.** A sandbox gets the feature when `create-ai-sandbox.sh`
  is re-run for it. Until then every helper works on it exactly as today and
  touches nothing of this feature. `ai-sandbox-migrate` is not changed.
- **I9 Volumes are replaced only by `create-ai-sandbox.sh`.** An existing
  volume whose options differ from the compose file is removed and recreated
  only by `create-ai-sandbox.sh`, with the container stopped, and it says so in
  its output. Every other script stops with instructions instead. No script
  names `ai-sandbox-rm` as the repair.
- **I10 `create-ai-sandbox.sh` never runs against a running container.** It
  refuses before writing anything, telling the user to run `ai-sandbox-stop`.

## Non-goals

- Maven itself using `~/.m2` (only Gradle's `mavenLocal()` is a goal).
- Enforcing offline builds, or any network restriction.
- The host changing the lower directories while a sandbox has them mounted.
- Writing anything back to the host caches, or keeping the upper across starts.
- Builds that need the host's `gradle.properties`, `init.d` scripts or Maven
  settings (credentials, repository mirrors). They are excluded by I2.
- Clearing the upper when something other than these scripts recreates the
  container (a hand-run `docker compose up`).
- Detecting whether `compose up` would recreate a running container (user
  decision, third round; replaced by I10).
- Caches of other tools (npm, pip, cargo), rootless host Docker, kernel-specific
  overlay options (`volatile`, `index`, `metacopy`).
- Handling a host without these directories beyond `mkdir -p` (user decision).

## Decisions on the items the brief left open

**D1 Volume naming.** Compose top-level volume keys are the table's keys; each
carries an explicit `name: <container name>-<key>`, for example
`dev-tools-3f9a1c4e-agent-gradle-caches`. Reason: the container name is already
unique per project and is a legal volume name; an explicit name does not depend
on compose's project-name derivation. The volumes are compose-managed (not
`external`), so compose creates them on first `up` and `ai-sandbox-rm`'s
existing `compose down -v` removes them.

**D2 Options mismatch.** Before every `compose up`, the scripts compare each
existing volume's `type`, `device` and `o` options (`docker volume inspect`)
with the compose file. A missing volume is fine (compose creates it). A volume
that exists but cannot be read as that triple counts as a difference, not as
missing. That covers options that are null or lack a field, for example a plain
`local` volume reusing the name.

- `create-ai-sandbox.sh` repairs a difference itself. The container is not
  running (I10), so it removes the stopped container (`compose down` without
  `-v`), then the volumes that differ (`docker volume rm`), logs each one it
  removed, and lets `compose up` create them again. Nothing is lost: a volume
  holds only options, and the data is in the upper, which the reset replaces
  anyway.
- `ai-sandbox` and `ai-sandbox-restart` only check. A difference is reachable
  there only after a `--no-start` regeneration. They stop before `up` (the
  restart before `down`), naming the volume and the repair:
  `ai-sandbox-stop` if the container is running, then
  `create-ai-sandbox.sh <project>`.

Reason: the user's rule is to ask for the least the user must do, and never
`ai-sandbox-rm`, which also wipes the project's logins. `create-ai-sandbox.sh`
is the only script that runs with the container known to be stopped, so it is
the only one that removes anything. The volume is removed only after the
container, because `ai-sandbox-stop` (`compose stop`) keeps the container, and
Docker refuses to remove a volume that any container, even a stopped one, still
references. An explicit check does not depend on how a given compose version
reacts to a differing volume (warn, prompt, or reuse silently). The brief's
"Open" list still names `ai-sandbox-rm`; the third-round decision supersedes
it.

**D3 Where upper and work live.**
`<sandbox dir>/build-caches/<key>/upper` and `.../work`. Reason: siblings in one
directory are on one filesystem, as overlay requires; `~/.ai-sandbox` is on the
host's home filesystem, not on an overlay (assumption A5); the directory is
owned by the host user (I7) inside the 0700 sandbox directory; it is per sandbox
(I4) and goes away with the sandbox.

**D4 How the clear works.** The reset renames `build-caches/<key>` to
`build-caches/.trash/<key>-<unique suffix>`, creates a fresh `<key>/upper` and
`<key>/work`, then deletes the trash. Reason: the rename always succeeds for the
host user, so a start is never blocked by an entry the host user cannot delete.
Phase 1 showed that a plain `rm -rf` works in the ordinary case, root-owned
whiteouts and `work/work` included (A4). The case it did not exercise is still
reachable: the container user has passwordless sudo, so root-owned directories
with contents can appear in the upper, and the host user cannot delete those. A failed
deletion only warns; `ai-sandbox-gc` lists and removes the leftovers, naming
`sudo rm -rf` when plain removal fails. Swapping `work` together with `upper`
keeps the pair consistent whatever the kernel's overlay defaults are.

**D5 When the clear runs.** Each start path takes a `flock` on
`<sandbox dir>/build-caches/.lock` and holds it until `compose up` has
returned. In `ai-sandbox-restart` the lock spans from the check, across `down`,
to `up`. Under the lock, `ai-sandbox` and `create-ai-sandbox.sh` first look
again at whether the container is running:
- `ai-sandbox` enters a container now found running, with no check, reset or
  `up`.
- `create-ai-sandbox.sh` refuses it exactly as I10 does, since its first I10
  check ran before the image build.

The lock closes the race of two terminals starting one sandbox at once, which
would otherwise rename an upper while the other's mount is being made. Anything
that can leave long-lived children (knowledge sync, `start-display.sh`) runs
before the lock is taken: the children would inherit the lock's file
descriptor and keep it held, hanging every later start. Per entry point:

| Entry point | Behaviour |
|---|---|
| `ai-sandbox`, container running | enter; no reset, no check |
| `ai-sandbox`, container stopped or absent | check (D2), reset, `up` |
| `ai-sandbox-restart` | check before `down` (a refusal leaves it running), `down`, reset, `up` |
| `create-ai-sandbox.sh`, container running (with or without `--no-start`) | refuses before writing anything; names `ai-sandbox-stop` (I10) |
| `create-ai-sandbox.sh`, container not running | prepare, repair (D2), reset, `up` |
| `create-ai-sandbox.sh --no-start`, container not running | prepare directories only; no check, no reset |
| `ai-sandbox-stop` | unchanged; the next start resets |

Reason for refusing a running container (user decision, third round): compose
would recreate it inside `up`, with no gap in which to reset. Refusing is
simpler than predicting whether a recreation is pending. The refusal comes
early, before the image build and the capacity check. It applies to
`--no-start` too, which costs nothing: `ai-sandbox-migrate-knowledge` stops the
running sandboxes before it calls `--no-start`.

**D6 The rest of `~/.gradle` and `~/.m2`.** The image creates `~/.gradle`,
`~/.gradle/wrapper` and `~/.m2` owned by the user, in the Dockerfile's existing
home `mkdir` list. Without them Docker would create the mount points' parents
root-owned inside the container and Gradle could not write `~/.gradle/daemon`
or `~/.gradle/native` (assumption A9). Everything there except the three mounts
lives in the container's writable layer: kept across stop and start, lost on
recreation, consistent with an ephemeral upper. The Dockerfile change alters the
build hash, so the shared image is rebuilt once; a sandbox not yet re-created
runs the new image harmlessly (empty directories, no mounts).

**D7 Old sandboxes.** `create-ai-sandbox.sh` writes `SANDBOX_BUILD_CACHES=1` to
the managed `.env`. Every caches function is a no-op for a sandbox without that
stamp (I8).

**D8 Surfaces.** `ai-sandbox-rm`: `compose down -v` already removes the volumes;
it also reports any part of the sandbox directory `rm -rf` could not remove,
with the `sudo rm -rf` to finish, instead of failing mid-way. `ai-sandbox-gc`:
lists `*/build-caches/.trash/*` as reclaimable. Orphan volumes are not
collected: they hold only options, and a recreated sandbox reuses an identical
one. Tool notes: one bullet, unconditional, and the "host paths mounted"
sentence names the caches. `sandbox-doctor`: one row per mount. `usage()`: a
"Build caches" paragraph and `build-caches/` in the layout list. `PROJECT_MAP.md`
is updated.

**D9 Path syntax.** Overlay options separate fields with `,` and lower layers
with `:`. `create-ai-sandbox.sh` stops with an error when `$HOME` or the sandbox
directory contains `,`, `:` or whitespace, rather than generating a mount that
fails at start.

## Contracts

These are the interfaces later phases build on. Names are binding; bodies are
the implementer's.

```bash
# ai-sandbox-lib.sh -- table: <key>|<path under $HOME, host and container>
ai_sandbox_build_caches()        # prints the three rows of the table above
ai_sandbox_caches_volume()       # <container name> <key> -> "<container name>-<key>"
ai_sandbox_caches_opts()         # <sandbox dir> <key> <host lower path>
                                 #   -> "lowerdir=<lower>,upperdir=<sandbox dir>/build-caches/<key>/upper,workdir=<sandbox dir>/build-caches/<key>/work"
ai_sandbox_caches_enabled()      # <sandbox dir> -> 0 when .env has SANDBOX_BUILD_CACHES=1
ai_sandbox_caches_prepare()      # <sandbox dir> -> mkdir -p the three lowers and every upper/work; never empties anything
                                 #   (create-ai-sandbox.sh calls it after writing the .env stamp, since it is a no-op without it)
ai_sandbox_caches_check()        # <sandbox dir> <container name> -> 0, or 1 with the D2 message on stderr
ai_sandbox_caches_repair()       # <sandbox dir> <container name> -> D2 repair; precondition: container not running;
                                 #   used only by create-ai-sandbox.sh
ai_sandbox_caches_reset()        # <sandbox dir> -> D4; caller holds the lock and has seen the container not running
```

Every function except the first three returns 0 and does nothing when
`ai_sandbox_caches_enabled` is false.

Compose shape (paths absolute, as generated; `<C>` the container name, `<SB>`
the sandbox directory):

```yaml
services:
  <C>:
    volumes:
      - "gradle-caches:<HOME>/.gradle/caches"
      - "gradle-wrapper-dists:<HOME>/.gradle/wrapper/dists"
      - "m2-repository:<HOME>/.m2/repository"
volumes:
  gradle-caches:
    name: "<C>-gradle-caches"
    driver: local
    driver_opts:
      type: overlay
      device: overlay
      o: "lowerdir=<HOME>/.gradle/caches,upperdir=<SB>/build-caches/gradle-caches/upper,workdir=<SB>/build-caches/gradle-caches/work"
  # gradle-wrapper-dists and m2-repository: same shape
```

On-disk layout added to each sandbox directory:

```
<sandbox dir>/build-caches/
  .lock
  .trash/                       renamed-aside layers awaiting deletion
  gradle-caches/{upper,work}/
  gradle-wrapper-dists/{upper,work}/
  m2-repository/{upper,work}/
```

## Assumptions

Status: **verified** (read in the tree), **inferred** (follows from documented
behaviour, not observed here), **guessed**. Everything not verified is checked
by phase 1, because this spec was written inside a sandbox with no Docker and no
host `~/.gradle`.

| # | Assumption | Status | Checked by |
|---|---|---|---|
| A1 | The rootful host daemon mounts a `local` volume with `type=overlay`, `device=overlay` and the `o` above, lower in the host's home | **verified** (P1 run 1: `volume gc created` ... `mounted while running: gc=1 wd=1 m2=1`; Docker 29.8.1, compose 5.5.1, kernel 6.8.0-138) | P1 |
| A2 | The overlay is mounted when a container using the volume starts and unmounted when the last such container stops, so a stopped sandbox's upper can be renamed safely | **verified** (run 1: `mounted after the container exited: gc=0`, `mounted after stop: gc=0`, `mounted after start: gc=1`) | P1 |
| A3 | Several overlays share one lower at once (up to three sandboxes run together) | **verified** (run 1: `second overlay on the same lower: ok`, listing `8.14.3 8.14.4 8.14.5` while the first container ran) | P1 |
| A4 | Files the container user writes land in the upper owned by the host uid; whiteouts and `work/work` can be removed by the host user after unmount | **verified** (run 1: `jlewandowski:jlewandowski 644 f .../gc/upper/smoke-probe`; whiteout `root:root 0 c .../qdox-2.1.0.pom`; `root:root 0 d .../gc/work/work`; `plain rm -rf of upper and work: ok`). Not exercised: files made root-owned by the container user's sudo | P1 |
| A5 | `~/.ai-sandbox` is on a filesystem that can hold an overlay upper (ext4, xfs with ftype=1, btrfs; not overlay, ecryptfs or NFS) | **verified** (run 1: `ext2/ext3 /home/jlewandowski/.ai-sandbox`, the `stat -f` name for the ext family; overlay mounted on it per A1) | P1 |
| A6 | `./gradlew --offline` with no network builds a project the host has built, using only the overlaid caches and wrapper dists | **verified for the wrapper and dependency resolution** (run 2: the wrapper started offline and wrote `20K .../wd/upper`; `67 actionable tasks: 32 executed, 35 from cache`). The build then failed on a non-ASCII file name because the image sets no `LANG` (`Failed to create MD5 hash for file: .../Kampus_Panorama-Wroc??aw-768x460.jpg`); run 3 with `-e LANG=C.UTF-8` cleared that error (user's report, no log). The locale fix is a separate task (`docs/superpowers/specs/2026-10-02-ai-sandbox-locale-brief.md`), outside this spec; a complete offline build is re-checked in phase 4 | P1, P4 |
| A7 | The lower is unchanged after use, and `docker volume rm` leaves lower and upper contents alone | **verified** for new, deleted and appended files (run 1: `lower entries changed since the start (expect none):` followed by nothing; `upper after volume rm (expect smoke-probe): smoke-probe`). Not checked after a build (run 2 had no `find`); re-checked in phase 4 | P1, P4 |
| A8 | withdrawn: the recreation detection it supported was dropped (third round) | - | - |
| A9 | Docker creates a missing in-container parent of a mount point root-owned | **verified** (run 1: `parent of mount point: root 755 /home/jlewandowski/.gradle`), so D6 is required | P1 |
| A10 | The container user's uid/gid equal the host user's | verified (`USER_ID=$HOST_UID` build args) | - |
| A11 | Container `$HOME` equals host `$HOME` | verified (`CONTAINER_HOME="$HOME"`, `USER_HOME` build arg) | - |
| A12 | After a host reboot the container stays stopped, so its next start goes through a script and resets | verified (`restart: "no"` in the generated compose) | - |
| A13 | Copy-up of Gradle's writable index files leaves the upper at a size acceptable per sandbox | **verified** (run 2: `6,1M .../gc/upper`, `4,0K .../m2/upper` after 67 tasks) | P1 |
| A14 | Docker refuses `volume rm` while a stopped container references the volume, and allows it once the container is removed | **verified** (run 1: `volume rm refused while a stopped container uses it: ok`; after `docker rm -f`, step 5's `docker volume rm` printed all four names) | P1 |

Phase 1 is closed: the guessed and inferred assumptions held. A6 and A7 are
complete apart from what phase 4 re-checks. The `UnknownHostException` in run 2
comes from `--network none` (the container's hostname could not be resolved).
Sandboxes keep their network (I6), so it does not apply to them.
Run 1 also showed `overlay.index=N`, `redirect_dir=N` and `metacopy=N`.

## Phases

### Phase 1 -- host smoke test (user-run, no code change)

**Goal.** Every assumption marked guessed or inferred is confirmed or refuted on
the real host, and the assumption table is updated from the log before phase 2
is planned.

**Contract needed.** None; it uses the existing shared image
`ai-sandbox:base-u<uid>` and plain `docker` commands. It writes only under
`~/.ai-sandbox/smoke-build-caches` and removes what it creates (four volumes
named `smoke-bc-*`, one container `smoke-bc-a`).

**Request to the user (one batch).** Edit `P` (a git repository with a committed
`./gradlew` that you have built on this host recently) and `T` (the task to
run). Do not run
Gradle on the host while it runs. Then paste the whole of
`~/build-caches-smoke.log` back.

```bash
P="$HOME/dev/CHANGE-ME"   # git repo with ./gradlew, built on this host recently
T="assemble"              # Gradle task to run offline
set -u
S="$HOME/.ai-sandbox/smoke-build-caches"; IMG="ai-sandbox:base-u$(id -u)"; U="$(id -u):$(id -g)"
LOG="$HOME/build-caches-smoke.log"
mkvol() { docker volume create --driver local --opt type=overlay --opt device=overlay \
  --opt "o=lowerdir=$2,upperdir=$S/$1/upper,workdir=$S/$1/work" "smoke-bc-$1" >/dev/null && echo "volume $1 created"; }
mounted() { local f="/proc/$(pgrep -xo dockerd)/mountinfo"; [ -r "$f" ] || f=/proc/self/mountinfo
  grep -c "upperdir=$S/$1/upper" "$f"; }
VOLS=(-v "smoke-bc-gc:$HOME/.gradle/caches" -v "smoke-bc-wd:$HOME/.gradle/wrapper/dists" -v "smoke-bc-m2:$HOME/.m2/repository")
HOMES=(-v "$S/gh:$HOME/.gradle" -v "$S/mh:$HOME/.m2")
docker rm -f smoke-bc-a >/dev/null 2>&1; docker volume rm smoke-bc-gc smoke-bc-wd smoke-bc-m2 smoke-bc-gc2 >/dev/null 2>&1
{
echo "== 1 environment"
uname -r; docker version --format 'docker {{.Server.Version}}'; docker compose version --short
stat -f -c '%T %n' "$HOME/.ai-sandbox" "$HOME/.gradle/caches" "$HOME/.gradle/wrapper/dists" "$HOME/.m2/repository"
for p in index redirect_dir metacopy; do echo "overlay.$p=$(cat /sys/module/overlay/parameters/$p 2>&1)"; done
docker image inspect -f 'image {{.Id}}' "$IMG"
echo "== 2 volumes"
rm -rf "$S"; mkdir -p "$S/gh/caches" "$S/gh/wrapper/dists" "$S/mh/repository"
for k in gc wd m2 gc2; do mkdir -p "$S/$k/upper" "$S/$k/work"; done
touch "$S/mark"; sleep 2
mkvol gc "$HOME/.gradle/caches"; mkvol wd "$HOME/.gradle/wrapper/dists"
mkvol m2 "$HOME/.m2/repository"; mkvol gc2 "$HOME/.gradle/caches"
echo "== 3 offline build, no network"
docker run --rm --network none --memory 6g --user "$U" -e HOME="$HOME" --entrypoint bash \
  "${HOMES[@]}" "${VOLS[@]}" -v "$HOME/.sdkman:$HOME/.sdkman:ro" -v "$P:$P:ro" "$IMG" -c '
  export JAVA_HOME="$HOME/.sdkman/candidates/java/current"; export PATH="$JAVA_HOME/bin:$PATH"
  findmnt -no TARGET,FSTYPE "$HOME/.gradle/caches" "$HOME/.gradle/wrapper/dists" "$HOME/.m2/repository"
  git clone -q "$0" /tmp/p && cd /tmp/p && ./gradlew --offline --no-daemon "$1" >/tmp/g.log 2>&1; rc=$?
  tail -25 /tmp/g.log; echo "gradle exit $rc"' "$P" "$T"
echo "mounted after the container exited: gc=$(mounted gc) (expect 0)"
du -sh "$S/gc/upper" "$S/wd/upper" "$S/m2/upper"
echo "== 4 writes, ownership, sharing, mount lifecycle"
docker run -d --name smoke-bc-a --user "$U" -e HOME="$HOME" --entrypoint sleep "${HOMES[@]}" "${VOLS[@]}" "$IMG" infinity >/dev/null
echo "mounted while running: gc=$(mounted gc) wd=$(mounted wd) m2=$(mounted m2) (expect 1 1 1)"
docker exec smoke-bc-a bash -c '
  echo probe > "$HOME/.gradle/caches/smoke-probe" && echo "new file: ok"
  f=$(find "$HOME/.m2/repository" -type f -name "*.pom" | sed -n 1p); [ -n "$f" ] && rm -f "$f" && echo "delete lower file: ok"
  g=$(find "$HOME/.m2/repository" -type f -name "*.pom" | sed -n 2p); [ -n "$g" ] && echo "<!-- x -->" >> "$g" && echo "append to lower file: ok"'
find "$S/gc/upper" "$S/m2/upper" \( -type f -o -type c \) -printf '%u:%g %m %y %p\n' | head -20
find "$S/gc/work" "$S/m2/work" -printf '%u:%g %m %y %p\n'
docker run --rm --user "$U" -e HOME="$HOME" --entrypoint bash -v "smoke-bc-gc2:$HOME/.gradle/caches" "$IMG" -c '
  stat -c "parent of mount point: %U %a %n" "$HOME/.gradle"; ls "$HOME/.gradle/caches" | head -3
  [ -e "$HOME/.gradle/caches/smoke-probe" ] && echo "PROBE LEAKED into a second overlay" || echo "second overlay on the same lower: ok"'
docker stop smoke-bc-a >/dev/null; echo "mounted after stop: gc=$(mounted gc) (expect 0)"
docker volume rm smoke-bc-gc >/dev/null 2>&1 && echo "VOLUME REMOVED although a stopped container uses it" || echo "volume rm refused while a stopped container uses it: ok"
docker start smoke-bc-a >/dev/null; echo "mounted after start: gc=$(mounted gc) (expect 1)"
docker rm -f smoke-bc-a >/dev/null
echo "== 5 volume removal, lower untouched, host-user cleanup"
docker volume rm smoke-bc-gc smoke-bc-wd smoke-bc-m2 smoke-bc-gc2
echo "upper after volume rm (expect smoke-probe): $(ls "$S/gc/upper" | tr '\n' ' ')"
echo "lower entries changed since the start (expect none):"
find "$HOME/.gradle/caches" "$HOME/.gradle/wrapper/dists" "$HOME/.m2/repository" -cnewer "$S/mark" | head -20
rm -rf "$S" && echo "plain rm -rf of upper and work: ok" || { echo "rm -rf FAILED; left:"; find "$S" -printf '%u:%g %m %y %p\n' | head -20; }
} 2>&1 | tee "$LOG"
```

If step 5 reports `rm -rf FAILED`, finish with `sudo rm -rf ~/.ai-sandbox/smoke-build-caches`
(that result is itself the answer to A4).

**Tests that prove it.** The pasted log, read against the "expect" markers and
the assumption table. The log is evidence for the table; it is not committed.

**Done when.** The assumption table in this spec shows each of A1-A7, A9, A13
and A14 as verified or refuted, with the log line that shows it.

### Phase 2 -- the overlay volumes and the reset on start

**Goal.** A sandbox created or re-created by `create-ai-sandbox.sh` has the
three overlay mounts; every start the scripts perform on a stopped container
begins with empty upper and work directories; entering a running container
leaves them alone; `create-ai-sandbox.sh` refuses a running container and
repairs a volume with differing options itself, while the other start paths
stop with the D2 message; a sandbox without the stamp behaves exactly as before.

**Contract from phase 1.** A1, A2, A6 and A14 verified.

**Delivers.** The lib functions and compose shape under Contracts; the `.env`
stamp (D7); the Dockerfile directories (D6); the D9 path check; the I10 refusal; the D2 check and repair; the D5 behaviour
in `ai-sandbox`, `ai-sandbox-restart` and `create-ai-sandbox.sh`.

**Tests.** A new `tests/ai-sandbox/test-build-caches.sh`, run with
`bash tests/ai-sandbox/test-build-caches.sh`, on the stub `docker` (extended to
answer `volume inspect` and record `volume rm`). It proves: the generated compose file carries exactly the three
volumes with the contract's options and nothing under `~/.gradle` or `~/.m2`
beyond them (no `gradle.properties`, `init.d`, `settings`); the lowers are
created on the fake host home; upper/work exist after `--no-start`; a stopped
container's start empties a probe in the upper, a running one keeps it;
`ai-sandbox-restart` empties it; `create-ai-sandbox.sh`, with or without
`--no-start`, exits non-zero naming `ai-sandbox-stop` when the stub reports the
container running, and writes no compose file; with a stubbed options difference
and a stopped container, `create-ai-sandbox.sh` logs `down` (without `-v`), then
`volume rm` of exactly the differing volume, then `up`; the same difference makes
`ai-sandbox` and `ai-sandbox-restart` exit non-zero naming `create-ai-sandbox.sh`
and not `ai-sandbox-rm`, with no `up`, `down` or `volume rm` in the stub log; an
unstamped sandbox gets no `build-caches/` and no volume queries; a `,` in the
home path is refused. The whole suite, `bash tests/ai-sandbox/run-tests.sh`,
stays green apart from failures known before this work (test-tools case 23,
`~/.sdkman` on `PATH`, inside a sandbox; the brief's "case 20" was wrong).

**Assumptions.** A1-A7, A9 and A14 as left by phase 1.

### Phase 3 -- surfaces: rm, gc, doctor, tool notes, help

**Goal.** The feature is visible and maintainable: `ai-sandbox-rm` removes a
sandbox with build caches and reports anything left with the command to finish;
`ai-sandbox-gc` lists and removes trash leftovers; `sandbox-doctor` shows one
row per mount (`overlay` with a note that writes are discarded at the next
start, or "not mounted -- re-run create-ai-sandbox.sh on the host"); the tool
notes carry the Gradle bullet and the mounted-paths sentence names the caches,
and tell an agent whose `sandbox-doctor` says "not mounted" to ask for a re-run;
`usage()` documents the feature and `build-caches/`; `PROJECT_MAP.md` is current.

**Contract from phase 2.** The lib functions, the layout and the stamp.

**Tests.** Extensions of `tests/ai-sandbox/test-gc.sh` (trash listed and
removed with `--yes`) and of the build-caches suite (tool notes text in the
rendered block, `usage()` text, `ai-sandbox-rm` answering `y` removes the
directory), run with `bash tests/ai-sandbox/test-gc.sh` and
`bash tests/ai-sandbox/test-build-caches.sh`; then the whole suite.

**Assumptions.** A4 as left by phase 1 (decides only the wording of the rm and
gc messages).

### Phase 4 -- host acceptance (user-run)

**Goal.** On the host, with the real scripts: `create-ai-sandbox.sh` on a Gradle
project (refused while its container runs, accepted after `ai-sandbox-stop`); inside, `sandbox-doctor` shows three overlay rows and
`./gradlew --offline <task>` succeeds; a probe file written to
`~/.gradle/caches` survives a second `ai-sandbox` entry and disappears after
`ai-sandbox-restart` and after `ai-sandbox-stop` + `ai-sandbox`; the host's
three directories show no entry changed since the start; `ai-sandbox-rm` on a
throwaway project leaves nothing behind. The exact commands are written by the
phase 3 plan, batched into one request, like phase 1. The offline build
relies on the image locale fix (a separate task, see A6), which landed in
8d724a1.

**Contract from phase 3.** The finished feature.

**Assumptions.** None beyond phase 1's.

## Decisions for the user

None open. The third-round decisions settled D2 and D5. Phase 1 needs the
user's host run; phase 4 will need another.

## Deferred list

Empty. Cap: ten open entries; see the planner rules for folding, keeping and
dropping.
