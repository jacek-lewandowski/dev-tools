# Brief: host build caches in the ai-sandbox through an ephemeral overlay

Date: 2026-10-02. Input for the spec author; decisions below are the user's.

## Goal

An agent in the sandbox can run Gradle builds offline against the host's
already-downloaded dependencies, without the sandbox getting any host
credentials and without being able to modify the host's caches.

## User decisions

- Shared from the host, and nothing else from `~/.gradle` or `~/.m2`:
  `~/.gradle/caches`, `~/.gradle/wrapper/dists`, `~/.m2/repository`.
  Never `gradle.properties`, `init.d`, `settings.xml`, `settings-security.xml`.
- The host directories are the read-only lower layer of an overlayfs; the
  sandbox writes into an ephemeral upper layer. Mechanism: a Docker `local`
  driver volume with `type=overlay` (the host daemon mounts it; the container
  gets no extra capability or device).
- `~/.m2/repository` is used only by Gradle (`mavenLocal()`), not by Maven.
- The host never changes these directories while a sandbox has them mounted;
  concurrent lower-layer modification is out of scope.
- Offline is possible, NOT enforced. The container keeps its network access.
- On by default for every sandbox (no opt-in flag required).
- The upper layer is cleared only when the container (re)starts: container
  recreation by `create-ai-sandbox.sh`, `ai-sandbox-restart`, and `ai-sandbox`
  starting a stopped container. Entering an already running container with
  `ai-sandbox` must NOT clear it.

## Known facts

- Host Docker is rootful: `docker info` SecurityOptions =
  `[name=apparmor,profile=default name=seccomp,profile=builtin name=cgroupns]`.
  Host kernel unknown from the sandbox.
- The spec author works inside a sandbox: no Docker, no host `~/.gradle`.
  Anything that needs the host goes into a batched host smoke-test phase.

## Further user decisions (2026-10-02, second round)

- Missing host directories are not a real case; `create-ai-sandbox.sh` simply
  `mkdir -p`s the three lower directories. No skip/disable logic.
- Upper/work layers are owned by the current host user.
- No migration. Existing sandboxes get the feature only after
  `create-ai-sandbox.sh` is re-run; until then they do not have it, and that
  is acceptable. Do not touch `ai-sandbox-migrate`.

## Further user decisions (2026-10-02, third round, after the first spec draft)

- `create-ai-sandbox.sh` refuses to run while the project's container is
  running: hard stop, telling the user to stop it themselves
  (`ai-sandbox-stop`). No detection of whether compose would recreate the
  container; drop D5's config-hash/image-ID comparison and assumption A8.
- The repair for a volume options mismatch should ask for the least the user
  must do. If stopping suffices, require a stop, not `ai-sandbox-rm` (which
  also wipes the project's logins). Since `create-ai-sandbox.sh` now always
  runs with the container not running, it may remove the stopped container
  and the mismatched volumes itself (their contents are ephemeral and live
  in upper dirs, not in the volume). The spec decides which; the user's
  constraint is: never `ai-sandbox-rm` as the repair when a stop is enough.
  Note `ai-sandbox-stop` is `compose stop` (container kept), so a volume it
  references cannot be removed until the container is removed.

## Open for the spec to settle

- Compose volume naming. A change of `driver_opts` for an existing volume is
  not expected to happen (user decision). The repair is settled by the third
  round below (stop, never `ai-sandbox-rm`).
- Where upper/work live (same filesystem, not itself overlay).
- Interaction with `ai-sandbox-gc`, `ai-sandbox-rm`, the tool notes block in
  `create-ai-sandbox.sh`, `sandbox-doctor`, `usage()` and tests.
