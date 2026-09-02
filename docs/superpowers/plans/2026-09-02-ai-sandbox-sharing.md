# ai-sandbox Per-Project Accounts and Shared Assets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each project its own frozen AI credentials, cut ~3.3 GB of duplicated state per sandbox, and make project identity path-derived so same-named directories stop colliding.

**Architecture:** `bin/create-ai-sandbox.sh` keeps generating the build context and compose file, but identity, paths and compose invocation move into a sourced `bin/ai-sandbox-lib.sh` shared with a set of new `bin/ai-sandbox-*` executables that replace the shell functions previously injected into `~/.bashrc`. One image is built for all projects; per-project directories hold only identity-bearing state, and bulk read-mostly data moves to `~/.ai-sandbox/shared/`. A migration script runs on every sandbox start and moves existing sandboxes onto the new scheme.

**Tech Stack:** Bash 5, Docker Engine + compose v2, rsync, python3 (already used for in-place file edits), sha256sum. No test framework is available in this environment, so tests are plain bash with a small assert library and a stubbed `docker` on `PATH`.

**Spec:** `docs/superpowers/specs/2026-09-02-ai-sandbox-sharing-design.md`

## Global Constraints

- Bash: `set -euo pipefail` in every script; helpers are executables with a `#!/usr/bin/env bash` shebang, `ai-sandbox-lib.sh` is sourced and must never be executed.
- The identity formula is pinned in the spec and defined exactly once, in `ai_sandbox_project_id()`. No other file may recompute it.
- Schema version: `AI_SANDBOX_SCHEMA_VERSION=2`. Written to `~/.ai-sandbox/.schema-version`.
- Image tag: `ai-sandbox:<variant>-u<uid>`, variant is `base` or `docker`.
- Build-input hash: `sha256` over every file in `image/build/` in `LC_ALL=C sort` order as `<relative-path>\0<sha256-of-contents>\0`, then build args `USER_ID`, `GROUP_ID`, `USER_NAME`, `USER_HOME`, then the variant.
- Migration never deletes. Directories move with `mv`; there is no copy-then-delete anywhere.
- Pinned upstream versions stay pinned; do not float existing `readonly` version constants.
- Tests run with `AI_SANDBOX_ROOT` and `HOME` pointed at a temp dir and a stub `docker` first on `PATH`. No test may touch the real `~/.ai-sandbox` or invoke the real Docker daemon.
- This work cannot be built or run from inside the sandbox container. Every task's verification is `bash -n` plus the bash test suite; the image build and end-to-end run are host-side and out of scope for task completion.

---

### Task 1: Identity library and test harness

**Files:**
- Create: `bin/ai-sandbox-lib.sh`
- Create: `tests/ai-sandbox/harness.sh`
- Create: `tests/ai-sandbox/stub/docker`
- Create: `tests/ai-sandbox/run-tests.sh`
- Create: `tests/ai-sandbox/test-identity.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `ai_sandbox_slug <text>`, `ai_sandbox_project_id <abs-path>`, `ai_sandbox_project_root [dir]`, `ai_sandbox_dir_for <abs-path>`, and the variables `AI_SANDBOX_ROOT` and `AI_SANDBOX_SCHEMA_VERSION`. Test helpers `assert_eq`, `assert_contains`, `assert_file`, `assert_no_file`, `fake_home`, `stub_docker_log`.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/harness.sh`:

```bash
#!/usr/bin/env bash
# Minimal assert library. No framework is available in this environment.
TESTS_RUN=0
TESTS_FAILED=0

_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'not ok %d - %s\n' "$TESTS_RUN" "$1" >&2
    printf '        %s\n' "$2" >&2
}
_pass() { printf 'ok %d - %s\n' "$TESTS_RUN" "$1"; }

assert_eq() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$2" = "$3" ]; then _pass "$1"
    else _fail "$1" "expected '$3', got '$2'"; fi
}
assert_contains() {
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$2" in
        *"$3"*) _pass "$1" ;;
        *)      _fail "$1" "expected to contain '$3', got '$2'" ;;
    esac
}
assert_file() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -e "$2" ]; then _pass "$1"; else _fail "$1" "missing path: $2"; fi
}
assert_no_file() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -e "$2" ]; then _pass "$1"; else _fail "$1" "path should not exist: $2"; fi
}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# A throwaway HOME with the stub docker first on PATH. Echoes the temp dir.
fake_home() {
    local tmp
    tmp=$(mktemp -d)
    export HOME="$tmp/home"
    export AI_SANDBOX_ROOT="$HOME/.ai-sandbox"
    export DOCKER_STUB_LOG="$tmp/docker.log"
    export PATH="$REPO_ROOT/tests/ai-sandbox/stub:$PATH"
    mkdir -p "$HOME" "$AI_SANDBOX_ROOT"
    : > "$DOCKER_STUB_LOG"
    printf '%s' "$tmp"
}

stub_docker_log() { cat "$DOCKER_STUB_LOG"; }

finish() {
    printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
    [ "$TESTS_FAILED" -eq 0 ]
}
```

Create `tests/ai-sandbox/stub/docker`:

```bash
#!/usr/bin/env bash
# Records every invocation and answers the few queries the script makes.
printf '%s\n' "$*" >> "${DOCKER_STUB_LOG:-/dev/null}"
case "$1 $2" in
    "compose version") exit 0 ;;
esac
case "$1" in
    image)
        # 'docker image inspect TAG': missing unless the test pre-seeded it.
        [ -n "${DOCKER_STUB_IMAGES:-}" ] || exit 1
        case " $DOCKER_STUB_IMAGES " in *" $3 "*) exit 0 ;; *) exit 1 ;; esac
        ;;
    container)
        # 'docker container inspect -f {{.State.Running}} NAME'
        echo "${DOCKER_STUB_RUNNING:-false}"; exit 0
        ;;
    build|compose|rename|rm|rmi|images|exec|inspect) exit 0 ;;
esac
exit 0
```

Create `tests/ai-sandbox/test-identity.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

assert_eq "slug lowercases"            "$(ai_sandbox_slug 'DevTools')"     'devtools'
assert_eq "slug replaces separators"   "$(ai_sandbox_slug 'my_project')"   'my-project'
assert_eq "slug collapses runs"        "$(ai_sandbox_slug 'a...b')"        'a-b'
assert_eq "slug trims leading"         "$(ai_sandbox_slug '.hidden')"      'hidden'
assert_eq "slug trims trailing"        "$(ai_sandbox_slug 'foo.')"         'foo'
assert_eq "slug of separators only"    "$(ai_sandbox_slug '...')"          ''

# The whole point of the change: same basename, different path, different id.
a=$(ai_sandbox_project_id /home/u/work/dev-tools)
b=$(ai_sandbox_project_id /home/u/play/dev-tools)
assert_eq "id keeps the basename"  "${a%-*}" 'dev-tools'
if [ "$a" = "$b" ]; then
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "same basename must not collide" "both were '$a'"
else
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "same basename must not collide"
fi
assert_eq "id is stable"           "$(ai_sandbox_project_id /home/u/work/dev-tools)" "$a"
assert_eq "id hash is 8 hex"       "$(printf '%s' "${a##*-}" | wc -c | tr -d ' ')" '8'

# A trailing-dash slug must not produce a double dash, which is an illegal
# Docker repository component.
assert_contains "no double dash" "$(ai_sandbox_project_id /home/u/foo.)" 'foo-'
id=$(ai_sandbox_project_id /home/u/foo.)
case "$id" in *--*) TESTS_RUN=$((TESTS_RUN+1)); _fail "no double dash in id" "$id" ;;
              *)   TESTS_RUN=$((TESTS_RUN+1)); _pass "no double dash in id" ;; esac

assert_eq "empty slug falls back" "$(ai_sandbox_project_id /home/u/...)" \
          "project-$(printf '%s' /home/u/... | sha256sum | cut -c1-8)"

tmp=$(fake_home)
assert_eq "dir_for uses AI_SANDBOX_ROOT" \
    "$(ai_sandbox_dir_for /home/u/work/dev-tools)" "$AI_SANDBOX_ROOT/${a}-agent"
rm -rf "$tmp"

finish
```

Create `tests/ai-sandbox/run-tests.sh`:

```bash
#!/usr/bin/env bash
# Runs every test-*.sh and reports a combined result.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rc=0
for t in "$here"/test-*.sh; do
    printf '\n# %s\n' "$(basename "$t")"
    bash "$t" || rc=1
done
[ "$rc" -eq 0 ] && printf '\nALL SUITES PASSED\n' || printf '\nSOME SUITES FAILED\n' >&2
exit "$rc"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
chmod +x tests/ai-sandbox/run-tests.sh tests/ai-sandbox/stub/docker
bash tests/ai-sandbox/test-identity.sh
```

Expected: FAIL — `bin/ai-sandbox-lib.sh: No such file or directory`.

- [ ] **Step 3: Write minimal implementation**

Create `bin/ai-sandbox-lib.sh`:

```bash
#!/usr/bin/env bash
# Shared definitions for create-ai-sandbox.sh and the ai-sandbox-* helpers.
# This file is SOURCED, never executed. It must not call 'set -e' or exit.
#
# Identity is defined here exactly once. create-ai-sandbox.sh and every helper
# must call these functions rather than recomputing a project id, because a
# divergence between two implementations silently orphans a sandbox directory.

AI_SANDBOX_ROOT="${AI_SANDBOX_ROOT:-$HOME/.ai-sandbox}"
AI_SANDBOX_SCHEMA_VERSION=2

# Lowercase, replace every non-alphanumeric with '-', collapse runs, trim both
# ends. Trimming the trailing end matters: 'foo.' would otherwise yield 'foo-',
# and 'foo-' + '-' + hash is a double dash, which Docker rejects in a
# repository component.
ai_sandbox_slug() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed -e 's/[^a-z0-9]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-*//' -e 's/-*$//'
}

# <slug of basename>-<first 8 hex of sha256 of the absolute path>.
ai_sandbox_project_id() {
    local abs=$1 slug hash
    slug=$(ai_sandbox_slug "$(basename "$abs")")
    [ -n "$slug" ] || slug=project
    hash=$(printf '%s' "$abs" | sha256sum | cut -c1-8)
    printf '%s-%s' "$slug" "$hash"
}

# The git toplevel when there is one, so running from a subdirectory is safe.
ai_sandbox_project_root() {
    local dir=${1:-$PWD}
    (
        cd "$dir" 2>/dev/null || exit 1
        if git rev-parse --show-toplevel >/dev/null 2>&1; then
            git rev-parse --show-toplevel
        else
            pwd
        fi
    )
}

ai_sandbox_dir_for() {
    printf '%s/%s-agent' "$AI_SANDBOX_ROOT" "$(ai_sandbox_project_id "$1")"
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED`, 12 assertions run, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add bin/ai-sandbox-lib.sh tests/ai-sandbox
git commit -m "feat(ai-sandbox): path-derived project identity and bash test harness"
```

---

### Task 2: Use path-derived identity in create-ai-sandbox.sh

**Files:**
- Modify: `bin/create-ai-sandbox.sh:161-200` (project resolution and directory creation)
- Modify: `bin/create-ai-sandbox.sh:243` (`NESTED_DISPLAY_NUM`)
- Create: `tests/ai-sandbox/test-create-identity.sh`

**Interfaces:**
- Consumes: `ai_sandbox_project_id`, `ai_sandbox_project_root`, `ai_sandbox_dir_for`, `AI_SANDBOX_ROOT` from Task 1.
- Produces: `PROJECT_ID` (replaces `PROJECT_NAME` as the identity key), `SANDBOX_DIR` at `$AI_SANDBOX_ROOT/$PROJECT_ID-agent`, and a `project-path` file inside it containing the absolute project path with a trailing newline.

`PROJECT_NAME` is retained for cosmetic use only (the container hostname and log lines). Everything that must be unique uses `PROJECT_ID`.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-create-identity.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

tmp=$(fake_home)
proj="$tmp/work/dev-tools"
mkdir -p "$proj"
( cd "$proj" && git init -q . && git config user.email t@e && git config user.name t )

bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 \
    || { echo "script failed:"; cat "$tmp/out"; }

id=$(ai_sandbox_project_id "$proj")
dir="$AI_SANDBOX_ROOT/${id}-agent"
assert_file  "sandbox dir uses the path-derived id" "$dir"
assert_file  "project-path recorded"                "$dir/project-path"
assert_eq    "project-path content"                 "$(cat "$dir/project-path")" "$proj"
assert_no_file "no basename-only dir"               "$AI_SANDBOX_ROOT/dev-tools-agent"
assert_contains "compose names the new container"   "$(cat "$dir/docker-compose.yml")" \
                "container_name: \"${id}-agent\""
assert_contains "compose keeps the real project path" \
                "$(cat "$dir/docker-compose.yml")" "\"${proj}:${proj}\""

# Two projects with the same basename must land in different directories.
proj2="$tmp/play/dev-tools"
mkdir -p "$proj2"
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj2" >>"$tmp/out" 2>&1 || true
id2=$(ai_sandbox_project_id "$proj2")
assert_file "second same-named project gets its own dir" "$AI_SANDBOX_ROOT/${id2}-agent"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/ai-sandbox/test-create-identity.sh
```

Expected: FAIL — the sandbox lands in `dev-tools-agent`, so `sandbox dir uses the path-derived id` and `project-path recorded` both fail and `no basename-only dir` fails.

- [ ] **Step 3: Write minimal implementation**

In `bin/create-ai-sandbox.sh`, immediately after the `require` block ends (after `log "ok"`), source the library. `SCRIPT_DIR` is currently computed further down; move that resolution block up to just before this point, unchanged, so the library can be found:

```bash
# Identity and path helpers, shared with the ai-sandbox-* commands so the two
# can never compute a different id for the same project.
# shellcheck source=bin/ai-sandbox-lib.sh
. "$SCRIPT_DIR/ai-sandbox-lib.sh"
```

Replace the project-resolution block (currently `cd "${PROJECT_ARG:-.}"` through the `IMAGE_NAME=` assignment) with:

```bash
PROJECT_ABS_DIR=$(ai_sandbox_project_root "${PROJECT_ARG:-.}") \
    || die "Cannot enter ${PROJECT_ARG:-.}"
cd "$PROJECT_ABS_DIR"

# Cosmetic only: hostname and log lines. Never used as a unique key, because
# two projects can share a basename.
PROJECT_NAME=$(ai_sandbox_slug "${PROJECT_ABS_DIR##*/}")
[ -n "$PROJECT_NAME" ] || PROJECT_NAME="project"

PROJECT_ID=$(ai_sandbox_project_id "$PROJECT_ABS_DIR")
CONTAINER_NAME="${PROJECT_ID}-agent"

SANDBOX_DIR="$AI_SANDBOX_ROOT/${CONTAINER_NAME}"
```

Delete the `IMAGE_NAME="ai-sandbox-${PROJECT_NAME}:latest"` line; Task 6 introduces the shared tag. Until then, add a temporary line directly below `SANDBOX_DIR=` so the script still runs:

```bash
IMAGE_NAME="ai-sandbox-${PROJECT_ID}:latest"   # replaced by the shared tag in Task 6
```

After the existing `mkdir -p "$SANDBOX_DIR"` / `chmod 700` pair, record the identity:

```bash
# The authoritative record of which project this sandbox belongs to. Migration
# reads it to tell an already-migrated directory from a legacy one.
printf '%s\n' "$PROJECT_ABS_DIR" > "$SANDBOX_DIR/project-path"
```

Change `NESTED_DISPLAY_NUM` to key off the id rather than the basename:

```bash
NESTED_DISPLAY_NUM=$(( 100 + $(printf '%s' "$PROJECT_ID" | cksum | cut -d' ' -f1) % 80 ))
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash -n bin/create-ai-sandbox.sh && bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED`.

- [ ] **Step 5: Commit**

```bash
git add bin/create-ai-sandbox.sh tests/ai-sandbox/test-create-identity.sh
git commit -m "feat(ai-sandbox): key sandboxes on the project path, not the directory basename"
```

---

### Task 3: Extract the shell helpers into real scripts

**Files:**
- Create: `bin/ai-sandbox`, `bin/ai-sandbox-stop`, `bin/ai-sandbox-restart`, `bin/ai-sandbox-attach`, `bin/ai-sandbox-rm`
- Modify: `bin/create-ai-sandbox.sh:1404-1520` (replace the `HELPERS` heredoc and its installation)
- Create: `tests/ai-sandbox/test-helpers.sh`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces: `ai_sandbox_require_ctx` in `ai-sandbox-lib.sh`, which sets `AI_SANDBOX_DIR`, `AI_SANDBOX_NAME` and `AI_SANDBOX_PROJECT` or returns 1 with a message on stderr; and `ai_sandbox_compose <args...>`. Helpers are installed to `$AI_SANDBOX_ROOT/bin/` and the dev-tools source directory is recorded in `$AI_SANDBOX_ROOT/config` as `DEV_TOOLS_DIR=<path>`.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-helpers.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

tmp=$(fake_home)
proj="$tmp/work/proj"; mkdir -p "$proj"
touch "$HOME/.bashrc"
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 \
    || { echo "script failed:"; cat "$tmp/out"; }

for h in ai-sandbox ai-sandbox-stop ai-sandbox-restart ai-sandbox-attach ai-sandbox-rm; do
    assert_file "installed $h" "$AI_SANDBOX_ROOT/bin/$h"
done
assert_file "installed the library" "$AI_SANDBOX_ROOT/bin/ai-sandbox-lib.sh"
assert_file "recorded the source dir" "$AI_SANDBOX_ROOT/config"
assert_contains "config points at the repo" "$(cat "$AI_SANDBOX_ROOT/config")" \
                "DEV_TOOLS_DIR=$REPO_ROOT"

# The bashrc block must be the stable one-liner, not a pile of functions.
block=$(sed -n '/>>> dev-tools ai-sandbox helpers >>>/,/<<< dev-tools ai-sandbox helpers <<</p' "$HOME/.bashrc")
assert_contains "bashrc adds bin to PATH" "$block" '.ai-sandbox/bin'
case "$block" in
    *"_ai_sandbox_dir()"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "bashrc defines no functions" "still defines _ai_sandbox_dir" ;;
    *) TESTS_RUN=$((TESTS_RUN+1)); _pass "bashrc defines no functions" ;;
esac

# The helper must resolve the same project the script did.
id=$(ai_sandbox_project_id "$proj")
out=$( cd "$proj" && AI_SANDBOX_ROOT="$AI_SANDBOX_ROOT" \
       bash "$AI_SANDBOX_ROOT/bin/ai-sandbox" --print-context 2>&1 )
assert_contains "helper resolves the same sandbox" "$out" "${id}-agent"

# Re-running create refreshes stale installed copies.
echo '# stale' > "$AI_SANDBOX_ROOT/bin/ai-sandbox-stop"
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj" >>"$tmp/out" 2>&1 || true
assert_contains "stale helper refreshed" "$(cat "$AI_SANDBOX_ROOT/bin/ai-sandbox-stop")" 'compose stop'

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/ai-sandbox/test-helpers.sh
```

Expected: FAIL — `installed ai-sandbox` and every following assertion, because `$AI_SANDBOX_ROOT/bin/` does not exist.

- [ ] **Step 3: Write minimal implementation**

Append to `bin/ai-sandbox-lib.sh`:

```bash
# Resolve the sandbox for the current directory. Sets AI_SANDBOX_DIR,
# AI_SANDBOX_NAME and AI_SANDBOX_PROJECT, or returns 1 with a message.
ai_sandbox_require_ctx() {
    AI_SANDBOX_PROJECT=$(ai_sandbox_project_root) || return 1
    AI_SANDBOX_DIR=$(ai_sandbox_dir_for "$AI_SANDBOX_PROJECT")
    AI_SANDBOX_NAME=$(basename "$AI_SANDBOX_DIR")
    if [ ! -f "$AI_SANDBOX_DIR/docker-compose.yml" ]; then
        echo "No sandbox configured for this project ($AI_SANDBOX_DIR)." >&2
        echo "Create one with: create-ai-sandbox.sh" >&2
        return 1
    fi
}

ai_sandbox_compose() {
    docker compose -f "$AI_SANDBOX_DIR/docker-compose.yml" \
                   --env-file "$AI_SANDBOX_DIR/.env" "$@"
}
```

Create `bin/ai-sandbox`:

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"

ai_sandbox_require_ctx || exit 1

if [ "${1:-}" = "--print-context" ]; then
    printf 'dir=%s\nname=%s\nproject=%s\n' \
        "$AI_SANDBOX_DIR" "$AI_SANDBOX_NAME" "$AI_SANDBOX_PROJECT"
    exit 0
fi

# Must precede 'compose up': Docker would otherwise create the display's mount
# source itself, as root, and Xephyr could no longer bind its socket.
if [ -x "$AI_SANDBOX_DIR/start-display.sh" ]; then
    "$AI_SANDBOX_DIR/start-display.sh" || exit 1
fi
if [ "$(docker container inspect -f '{{.State.Running}}' "$AI_SANDBOX_NAME" 2>/dev/null)" != "true" ]; then
    echo "Starting $AI_SANDBOX_NAME..."
    ai_sandbox_compose up -d || exit 1
fi

if [ "$#" -eq 0 ]; then
    ai_sandbox_compose exec "$AI_SANDBOX_NAME" bash
elif [ "$#" -eq 1 ]; then
    # A single argument is treated as a shell snippet: ai-sandbox 'cd src && make'
    ai_sandbox_compose exec "$AI_SANDBOX_NAME" bash -lc "$1"
else
    # Several arguments are a command and its arguments; quoting is preserved.
    ai_sandbox_compose exec "$AI_SANDBOX_NAME" bash -lc 'exec "$@"' ai-sandbox "$@"
fi
```

Create `bin/ai-sandbox-stop`:

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"
ai_sandbox_require_ctx || exit 1
ai_sandbox_compose stop
[ -x "$AI_SANDBOX_DIR/stop-display.sh" ] && "$AI_SANDBOX_DIR/stop-display.sh"
exit 0
```

Create `bin/ai-sandbox-restart`:

```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"
ai_sandbox_require_ctx || exit 1
ai_sandbox_compose down
if [ -x "$AI_SANDBOX_DIR/start-display.sh" ]; then
    "$AI_SANDBOX_DIR/start-display.sh" || exit 1
fi
ai_sandbox_compose up -d
```

Create `bin/ai-sandbox-attach`:

```bash
#!/usr/bin/env bash
# Expose a device plugged in after the container started, without recreating
# it. The device cgroup already permits USB serial majors.
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"
ai_sandbox_require_ctx || exit 1

dev=${1:-}
if [ -z "$dev" ] || [ ! -e "$dev" ]; then
    echo "Usage: ai-sandbox-attach /dev/ttyUSB0" >&2
    exit 1
fi
major=$((16#$(stat -c '%t' "$dev")))
minor=$((16#$(stat -c '%T' "$dev")))
docker exec -u 0 "$AI_SANDBOX_NAME" bash -c \
    "rm -f '$dev'; mknod '$dev' c $major $minor && chgrp dialout '$dev' && chmod 660 '$dev'"
echo "Attached $dev ($major:$minor) to $AI_SANDBOX_NAME."
```

Create `bin/ai-sandbox-rm`:

```bash
#!/usr/bin/env bash
# Removes ONE project's sandbox. Never touches shared/ or image/, which other
# projects depend on.
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"
ai_sandbox_require_ctx || exit 1

printf 'Remove %s and all credentials in %s? [y/N] ' "$AI_SANDBOX_NAME" "$AI_SANDBOX_DIR"
read -r reply
case "$reply" in
    y|Y) ;;
    *) echo "Cancelled."; exit 1 ;;
esac
ai_sandbox_compose down -v 2>/dev/null || true
[ -x "$AI_SANDBOX_DIR/stop-display.sh" ] && "$AI_SANDBOX_DIR/stop-display.sh"
rm -rf "$AI_SANDBOX_DIR"
echo "Removed $AI_SANDBOX_DIR."
echo "Shared assets in $AI_SANDBOX_ROOT/shared and the image were left in place."
```

In `bin/create-ai-sandbox.sh`, replace the entire `HELPERS=$(cat <<'HELPERS_EOF' ... HELPERS_EOF)` assignment with an installation step, and change the `HELPERS` value used by the existing python block to the one-line PATH stub:

```bash
step "Installing helper commands"

mkdir -p "$AI_SANDBOX_ROOT/bin"
for helper in ai-sandbox-lib.sh ai-sandbox ai-sandbox-stop ai-sandbox-restart \
              ai-sandbox-attach ai-sandbox-rm; do
    install -m 0755 "$SCRIPT_DIR/$helper" "$AI_SANDBOX_ROOT/bin/$helper"
done
# ai-sandbox-lib.sh is sourced, not run.
chmod 0644 "$AI_SANDBOX_ROOT/bin/ai-sandbox-lib.sh"

# Recorded so ai-sandbox-migrate can refresh these copies without being told
# where the repository lives.
printf 'DEV_TOOLS_DIR=%s\n' "$DEV_TOOLS_DIR" > "$AI_SANDBOX_ROOT/config"
log "$AI_SANDBOX_ROOT/bin"

# The block below is deliberately trivial and stable: the helpers are real
# files now, so an open shell picks up a new version without re-sourcing
# anything, and this text should never need to change again.
HELPERS='# Helpers for dev-tools/bin/create-ai-sandbox.sh live in ~/.ai-sandbox/bin.
case ":$PATH:" in
    *":$HOME/.ai-sandbox/bin:"*) ;;
    *) PATH="$HOME/.ai-sandbox/bin:$PATH" ;;
esac'
```

The existing python block that splices `HELPERS` between `BASHRC_BEGIN` and `BASHRC_END` is unchanged.

- [ ] **Step 4: Run test to verify it passes**

```bash
chmod +x bin/ai-sandbox bin/ai-sandbox-stop bin/ai-sandbox-restart \
         bin/ai-sandbox-attach bin/ai-sandbox-rm
bash -n bin/ai-sandbox bin/ai-sandbox-stop bin/ai-sandbox-restart \
        bin/ai-sandbox-attach bin/ai-sandbox-rm bin/ai-sandbox-lib.sh \
        bin/create-ai-sandbox.sh
bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED`.

- [ ] **Step 5: Commit**

```bash
git add bin/ai-sandbox bin/ai-sandbox-stop bin/ai-sandbox-restart \
        bin/ai-sandbox-attach bin/ai-sandbox-rm bin/ai-sandbox-lib.sh \
        bin/create-ai-sandbox.sh tests/ai-sandbox/test-helpers.sh
git commit -m "refactor(ai-sandbox): replace bashrc functions with installed helper scripts"
```

---

### Task 4: Migration M1 — rename legacy sandboxes

**Files:**
- Create: `bin/ai-sandbox-migrate`
- Modify: `bin/ai-sandbox` (call migration before starting)
- Modify: `bin/create-ai-sandbox.sh` (call migration before resolving the sandbox dir)
- Create: `tests/ai-sandbox/test-migrate.sh`

**Interfaces:**
- Consumes: everything from Tasks 1 and 3.
- Produces: `ai-sandbox-migrate` (idempotent, exit 0 when there is nothing to do), and `$AI_SANDBOX_ROOT/.schema-version` containing `2`.

A legacy directory is any `*-agent/` without a `project-path` file. Its true project is read from `working_dir:` in its own `docker-compose.yml`, which the script has always written as the absolute project path.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-migrate.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

# Build a legacy sandbox by hand: basename-keyed dir, no project-path file.
make_legacy() {
    local name=$1 project=$2 dir="$AI_SANDBOX_ROOT/${name}-agent"
    mkdir -p "$dir/.claude" "$dir/antigravity-data/User"
    printf 'working_dir: "%s"\n' "$project" > "$dir/docker-compose.yml"
    printf 'token-for-%s\n' "$name" > "$dir/.claude/.credentials.json"
    printf 'history-for-%s\n' "$name" > "$dir/antigravity-data/User/History"
    printf '%s' "$dir"
}

tmp=$(fake_home)
p1="$tmp/work/dev-tools"; mkdir -p "$p1"
old=$(make_legacy dev-tools "$p1")

bash "$REPO_ROOT/bin/ai-sandbox-migrate" >"$tmp/m1" 2>&1 || { echo FAILED; cat "$tmp/m1"; }

id=$(ai_sandbox_project_id "$p1")
new="$AI_SANDBOX_ROOT/${id}-agent"
assert_file    "legacy dir renamed"        "$new"
assert_no_file "old dir gone"              "$old"
assert_eq      "project-path written"      "$(cat "$new/project-path")" "$p1"
assert_eq      "credentials survived"      "$(cat "$new/.claude/.credentials.json")" "token-for-dev-tools"
assert_eq      "antigravity history survived" \
               "$(cat "$new/antigravity-data/User/History")" "history-for-dev-tools"
assert_eq      "schema version recorded"   "$(cat "$AI_SANDBOX_ROOT/.schema-version")" '2'

# Idempotent: a second run changes nothing and says nothing.
out=$(bash "$REPO_ROOT/bin/ai-sandbox-migrate" 2>&1)
assert_eq "second run is silent" "$out" ''
assert_file "still there after re-run" "$new"

# Same basename, different paths: both migrate, to different directories.
tmp2=$(fake_home)
a="$tmp2/work/app"; b="$tmp2/play/app"; mkdir -p "$a" "$b"
mkdir -p "$AI_SANDBOX_ROOT/app-agent" "$AI_SANDBOX_ROOT/legacy2-agent"
printf 'working_dir: "%s"\n' "$a" > "$AI_SANDBOX_ROOT/app-agent/docker-compose.yml"
printf 'working_dir: "%s"\n' "$b" > "$AI_SANDBOX_ROOT/legacy2-agent/docker-compose.yml"
bash "$REPO_ROOT/bin/ai-sandbox-migrate" >/dev/null 2>&1
assert_file "first same-named migrated"  "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$a")-agent"
assert_file "second same-named migrated" "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$b")-agent"

# A directory with no usable compose file is left alone and reported.
tmp3=$(fake_home)
mkdir -p "$AI_SANDBOX_ROOT/orphan-agent"
out=$(bash "$REPO_ROOT/bin/ai-sandbox-migrate" 2>&1)
assert_file     "unparsable dir left in place" "$AI_SANDBOX_ROOT/orphan-agent"
assert_contains "unparsable dir reported"      "$out" 'orphan-agent'

# A target that already exists is a hard stop for that one sandbox.
tmp4=$(fake_home)
p="$tmp4/work/dup"; mkdir -p "$p"
mkdir -p "$AI_SANDBOX_ROOT/dup-agent" "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$p")-agent"
printf 'working_dir: "%s"\n' "$p" > "$AI_SANDBOX_ROOT/dup-agent/docker-compose.yml"
out=$(bash "$REPO_ROOT/bin/ai-sandbox-migrate" 2>&1)
assert_file     "conflicting source kept" "$AI_SANDBOX_ROOT/dup-agent"
assert_contains "conflict reported"       "$out" 'already exists'

rm -rf "$tmp" "$tmp2" "$tmp3" "$tmp4"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/ai-sandbox/test-migrate.sh
```

Expected: FAIL — `bin/ai-sandbox-migrate: No such file or directory`, every assertion fails.

- [ ] **Step 3: Write minimal implementation**

Create `bin/ai-sandbox-migrate`:

```bash
#!/usr/bin/env bash
# Bring ~/.ai-sandbox up to the current schema. Idempotent, silent when there
# is nothing to do, and safe to run before every sandbox start.
#
# Nothing here deletes user data. Directories MOVE; there is no
# copy-then-delete anywhere in this file.
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"

[ -d "$AI_SANDBOX_ROOT" ] || exit 0

say() { printf 'ai-sandbox: %s\n' "$*"; }

# --- Refresh installed helpers from the recorded source tree ---------------
if [ -f "$AI_SANDBOX_ROOT/config" ]; then
    # shellcheck disable=SC1091
    . "$AI_SANDBOX_ROOT/config"
    if [ -n "${DEV_TOOLS_DIR:-}" ] && [ -d "$DEV_TOOLS_DIR/bin" ]; then
        for helper in ai-sandbox-lib.sh ai-sandbox ai-sandbox-stop \
                      ai-sandbox-restart ai-sandbox-attach ai-sandbox-rm \
                      ai-sandbox-migrate; do
            src="$DEV_TOOLS_DIR/bin/$helper"
            dst="$AI_SANDBOX_ROOT/bin/$helper"
            [ -f "$src" ] || continue
            if ! cmp -s "$src" "$dst"; then
                install -m 0755 "$src" "$dst"
            fi
        done
        chmod 0644 "$AI_SANDBOX_ROOT/bin/ai-sandbox-lib.sh" 2>/dev/null || true
    fi
fi

# --- M1: rename legacy, basename-keyed sandboxes ---------------------------
# 'working_dir:' is the absolute project path; the script has always written
# it. Reading it makes the rename deterministic instead of a basename guess,
# which is what lets two same-named projects migrate correctly.
legacy_project_of() {
    sed -n 's/^[[:space:]]*working_dir:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' \
        "$1" 2>/dev/null | tail -n 1
}

migrated=0
for dir in "$AI_SANDBOX_ROOT"/*-agent; do
    [ -d "$dir" ] || continue
    [ -f "$dir/project-path" ] && continue          # already on the new scheme

    compose="$dir/docker-compose.yml"
    project=""
    [ -f "$compose" ] && project=$(legacy_project_of "$compose")
    if [ -z "$project" ]; then
        say "cannot determine the project for $(basename "$dir"); left unchanged."
        say "  (no readable working_dir: in $compose)"
        continue
    fi

    target="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$project")-agent"
    if [ "$target" = "$dir" ]; then
        printf '%s\n' "$project" > "$dir/project-path"
        continue
    fi
    if [ -e "$target" ]; then
        say "cannot migrate $(basename "$dir"): $(basename "$target") already exists."
        say "  source $dir"
        say "  target $target"
        continue
    fi

    # The display number is derived from the id, so the old server must go
    # before the directory holding its stop script moves.
    [ -x "$dir/stop-display.sh" ] && "$dir/stop-display.sh" >/dev/null 2>&1 || true

    old_name=$(basename "$dir")
    mv "$dir" "$target"
    printf '%s\n' "$project" > "$target/project-path"

    # Safe to drop: every durable thing is a bind mount; the writable layer
    # holds caches and shell history only. Compose recreates it on next start.
    if command -v docker >/dev/null 2>&1; then
        docker rm -f "$old_name" >/dev/null 2>&1 || true
    fi
    rm -rf "/tmp/.X11-unix/.ai-sandbox-${old_name}" 2>/dev/null || true

    say "migrated $old_name -> $(basename "$target")  ($project)"
    migrated=$((migrated + 1))
done

[ "$migrated" -gt 0 ] && say "$migrated sandbox(es) moved to path-derived names."

printf '%s\n' "$AI_SANDBOX_SCHEMA_VERSION" > "$AI_SANDBOX_ROOT/.schema-version"
exit 0
```

In `bin/ai-sandbox`, run migration before resolving the context. Insert directly after the `. ...ai-sandbox-lib.sh` line:

```bash
# Runs on every start so an old layout is repaired without the user having to
# know that anything changed.
"$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-migrate" || true
```

In `bin/create-ai-sandbox.sh`, run it just before `PROJECT_ABS_DIR=` is resolved:

```bash
if [ -x "$AI_SANDBOX_ROOT/bin/ai-sandbox-migrate" ]; then
    "$AI_SANDBOX_ROOT/bin/ai-sandbox-migrate" || true
fi
```

Add `ai-sandbox-migrate` to the `for helper in ...` install list added in Task 3.

- [ ] **Step 4: Run test to verify it passes**

```bash
chmod +x bin/ai-sandbox-migrate
bash -n bin/ai-sandbox-migrate && bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED`.

- [ ] **Step 5: Commit**

```bash
git add bin/ai-sandbox-migrate bin/ai-sandbox bin/create-ai-sandbox.sh \
        tests/ai-sandbox/test-migrate.sh
git commit -m "feat(ai-sandbox): migrate legacy basename-keyed sandboxes on every start"
```

---

### Task 5: Sticky --with-docker, --no-docker, and rewritten help

**Files:**
- Modify: `bin/create-ai-sandbox.sh:39-107` (options, usage, validation)
- Modify: `bin/create-ai-sandbox.sh:1050-1051` (conditional subuid append)
- Create: `tests/ai-sandbox/test-options.sh`

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: `WITH_DOCKER_EXPLICIT` (`yes`/`no`), mirroring the existing `DISPLAY_MODE_EXPLICIT`.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-options.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

run() { bash "$REPO_ROOT/bin/create-ai-sandbox.sh" "$@" >"$tmp/out" 2>&1 || true; }
envfile() { cat "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent/.env"; }

tmp=$(fake_home)
proj="$tmp/work/p"; mkdir -p "$proj"

run --display=none --no-start --with-docker "$proj"
assert_contains "docker recorded" "$(envfile)" 'SANDBOX_WITH_DOCKER=1'

# The bug this fixes: a bare re-run used to silently turn Docker off.
run --display=none --no-start "$proj"
assert_contains "docker is sticky" "$(envfile)" 'SANDBOX_WITH_DOCKER=1'

run --display=none --no-start --no-docker "$proj"
assert_contains "--no-docker turns it off" "$(envfile)" 'SANDBOX_WITH_DOCKER=0'
run --display=none --no-start "$proj"
assert_contains "off is sticky too" "$(envfile)" 'SANDBOX_WITH_DOCKER=0'

# Contradictory flags are a usage error, not last-one-wins.
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --with-docker --no-docker "$proj" \
    >"$tmp/both" 2>&1 && rc=0 || rc=$?
assert_eq       "both flags exit non-zero" "$rc" '2'
assert_contains "both flags explained"     "$(cat "$tmp/both")" 'both'

help=$(bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --help 2>&1)
assert_contains "help documents xpra in auto"  "$help" 'xpra'
assert_contains "help documents --no-docker"   "$help" '--no-docker'
assert_contains "help says rebuild is shared"  "$help" 'shared by every project'
assert_contains "help lists ai-sandbox-account" "$help" 'ai-sandbox-account'
assert_contains "help lists ai-sandbox-gc"     "$help" 'ai-sandbox-gc'
assert_contains "help lists sandbox-doctor"    "$help" 'sandbox-doctor'
assert_contains "help explains the layout"     "$help" '~/.ai-sandbox'
assert_contains "help notes stickiness"        "$help" 'Remembered'

# The Dockerfile must not append a subuid range unconditionally.
df="$AI_SANDBOX_ROOT/image/build/Dockerfile"
[ -f "$df" ] || df="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent/build/Dockerfile"
assert_contains "subuid append is guarded" "$(cat "$df")" 'grep -q'

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/ai-sandbox/test-options.sh
```

Expected: FAIL — `docker is sticky` fails (re-run writes `SANDBOX_WITH_DOCKER=0`), `--no-docker` is rejected as an unknown option, and every `help ...` assertion fails.

- [ ] **Step 3: Write minimal implementation**

In `bin/create-ai-sandbox.sh`, add beside the other option defaults:

```bash
WITH_DOCKER_EXPLICIT="no"
```

Extend the argument loop:

```bash
        --with-docker) WITH_DOCKER="yes"; WITH_DOCKER_EXPLICIT="yes" ;;
        --no-docker)   WITH_DOCKER="no";  WITH_DOCKER_EXPLICIT="yes" ;;
```

Guard the contradiction, immediately after the loop:

```bash
for arg in "$@"; do
    case "$arg" in --with-docker) seen_with=1 ;; --no-docker) seen_without=1 ;; esac
done
if [ -n "${seen_with:-}" ] && [ -n "${seen_without:-}" ]; then
    echo "Pass --with-docker or --no-docker, not both." >&2
    usage >&2
    exit 2
fi
```

Restore the stored choice. Place this next to the existing `DISPLAY_MODE` restore, which reads the same `.env`:

```bash
# A Docker choice made once stays chosen. Without this, re-running the script
# bare silently regenerates the sandbox without the daemon: the Dockerfile
# loses it, security_opt disappears from the compose file, and the next start
# has no daemon and no explanation.
if [ "$WITH_DOCKER_EXPLICIT" = "no" ] && [ -f "$ENV_FILE" ]; then
    STORED_DOCKER=$(sed -n 's/^SANDBOX_WITH_DOCKER=//p' "$ENV_FILE" | tail -n 1)
    case "$STORED_DOCKER" in
        1) WITH_DOCKER="yes"; log "keeping rootless Docker (pass --no-docker to drop it)" ;;
        0) WITH_DOCKER="no" ;;
    esac
fi
```

Make the subuid append conditional in the Dockerfile heredoc, replacing the two `echo ... >> /etc/subuid` / `subgid` lines:

```bash
    if ! grep -q "^${USER_NAME}:" /etc/subuid; then \
        echo "${USER_NAME}:100000:65536" >> /etc/subuid; fi; \
    if ! grep -q "^${USER_NAME}:" /etc/subgid; then \
        echo "${USER_NAME}:100000:65536" >> /etc/subgid; fi; \
```

Replace `usage()` entirely:

```bash
usage() {
    cat <<'USAGE'
Usage: create-ai-sandbox.sh [OPTIONS] [PROJECT_DIR]

Creates or refreshes an isolated container sandbox for PROJECT_DIR, defaulting
to the current directory. The project's git root is used, so running from a
subdirectory is safe. Sandboxes are keyed on the project's full path, so two
projects whose directories share a name do not collide.

Options:
  --display=MODE   How GUI apps reach a screen. Default: auto. Remembered.
                     wayland  Mount only the host Wayland socket. The container
                              runs its own Xwayland for X11-only apps. Safest;
                              needs a Wayland host session.
                     xpra     Dedicated Xvfb display plus an xpra server with
                              its own cookie. Each app appears as an ordinary
                              window on your desktop but renders on the virtual
                              display, so it cannot read your keystrokes or
                              screen. Needs xpra and xvfb.
                     nested   Dedicated Xephyr server with its own cookie.
                              Sandboxed apps live inside one window. Needs
                              xserver-xephyr.
                     host     Legacy: share the real host X11 display. Anything
                              in the sandbox can keylog and screenshot your
                              whole session. Opt in explicitly.
                     none     No GUI at all. CLI agents only.
                     auto     wayland, else xpra, else nested, else fail with
                              instructions. Never silently falls back to host.
  --with-docker    Install a rootless Docker daemon and Earthly inside the
                   sandbox. Remembered. Requires seccomp:unconfined and
                   apparmor:unconfined for the container, which meaningfully
                   weakens isolation, and the nested daemon's image store lives
                   inside the container, costing disk per sandbox. Off by
                   default.
  --no-docker      Undo a remembered --with-docker.
  --rebuild        Force a no-cache rebuild of the image, which is shared by
                   every project. Other sandboxes pick it up on next start.
  --no-start       Generate configuration but do not build or start anything.
  -h, --help       Show this message.

Options marked "Remembered" persist per project. Re-running with no flags keeps
the last choice; pass the option again to change it.

Commands on the host (installed into ~/.ai-sandbox/bin, added to your PATH):
  ai-sandbox            enter the sandbox for the current project; with
                        arguments, run a command inside it
  ai-sandbox-stop       stop it, and its private display if it has one
  ai-sandbox-restart    recreate the container, picking up new devices
  ai-sandbox-attach     expose a hot-plugged device, e.g.
                        ai-sandbox-attach /dev/ttyUSB0
  ai-sandbox-account    status | refresh | reset -- which AI account this
                        project uses, and re-seeding it from the host
  ai-sandbox-extensions refresh -- reinstall the shared IDE extensions
  ai-sandbox-gc         reclaim duplicated state and unused images (confirms
                        before removing anything)
  ai-sandbox-migrate    bring ~/.ai-sandbox up to the current layout; runs
                        automatically before every start
  ai-sandbox-rm         remove this project's sandbox and its credentials

Commands inside the sandbox:
  sandbox-doctor        report what is and is not working
  sandbox-desktop       start a window manager on the private display

Layout under ~/.ai-sandbox:
  <project>-<hash>-agent/   per project: credentials, tool state, compose file.
                            Seeded from the host once, then never overwritten,
                            so each project can hold a different Claude, Codex
                            or Gemini account.
  shared/                   bulk read-mostly data shared by every sandbox: IDE
                            extensions, CLI downloads, package caches.
  image/                    the build context and stamp for the one image all
                            projects share.

Mounted live from the host into every sandbox: ~/.gemini/GEMINI.md (the shared
brain, also read as ~/.claude/CLAUDE.md), the Antigravity brain and
conversations, and ~/.claude/projects. Edits there are real edits on the host.
USAGE
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash -n bin/create-ai-sandbox.sh && bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED`.

- [ ] **Step 5: Commit**

```bash
git add bin/create-ai-sandbox.sh tests/ai-sandbox/test-options.sh
git commit -m "feat(ai-sandbox): make --with-docker sticky, add --no-docker, rewrite help"
```

---

### Task 6: One shared image for all projects

**Files:**
- Modify: `bin/create-ai-sandbox.sh:170` (`BUILD_DIR`), `:1146-1156` (compose `build:`/`image:`), `:1535-1553` (build and start)
- Create: `tests/ai-sandbox/test-image.sh`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: `IMAGE_VARIANT` (`base`|`docker`), `IMAGE_NAME` (`ai-sandbox:<variant>-u<uid>`), `BUILD_DIR` at `$AI_SANDBOX_ROOT/image/build`, `IMAGE_STAMP` at `$AI_SANDBOX_ROOT/image/<variant>-u<uid>.stamp`, and `ai_sandbox_build_hash <build-dir> <args...>` in `ai-sandbox-lib.sh`.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-image.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

tmp=$(fake_home)
a="$tmp/work/a"; b="$tmp/work/b"; mkdir -p "$a" "$b"
uid=$(id -u)
tag="ai-sandbox:base-u${uid}"

bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$a" >"$tmp/o1" 2>&1 || true
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$b" >"$tmp/o2" 2>&1 || true

ca="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$a")-agent/docker-compose.yml"
cb="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$b")-agent/docker-compose.yml"

assert_contains "project A uses the shared tag" "$(cat "$ca")" "image: \"$tag\""
assert_contains "project B uses the same tag"   "$(cat "$cb")" "image: \"$tag\""
case "$(cat "$ca")" in
    *"build:"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "compose has no build: block" "found one" ;;
    *)          TESTS_RUN=$((TESTS_RUN+1)); _pass "compose has no build: block" ;;
esac
assert_file    "shared build context"  "$AI_SANDBOX_ROOT/image/build/Dockerfile"
assert_no_file "no per-project build"  "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$a")-agent/build"

# The hash must be stable across runs and change when an input changes.
h1=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev)
h2=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev)
assert_eq "build hash is stable" "$h1" "$h2"
h3=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1001 1000 dev /home/dev)
if [ "$h1" = "$h3" ]; then
    TESTS_RUN=$((TESTS_RUN+1)); _fail "build hash covers build args" "unchanged"
else
    TESTS_RUN=$((TESTS_RUN+1)); _pass "build hash covers build args"
fi
echo '# poke' >> "$AI_SANDBOX_ROOT/image/build/Dockerfile"
h4=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev)
if [ "$h1" = "$h4" ]; then
    TESTS_RUN=$((TESTS_RUN+1)); _fail "build hash covers file contents" "unchanged"
else
    TESTS_RUN=$((TESTS_RUN+1)); _pass "build hash covers file contents"
fi

# The docker variant gets its own tag.
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start --with-docker "$a" >>"$tmp/o1" 2>&1 || true
assert_contains "docker variant tag" "$(cat "$ca")" "ai-sandbox:docker-u${uid}"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/ai-sandbox/test-image.sh
```

Expected: FAIL — compose still carries `build:` and a per-project `ai-sandbox-<id>:latest` tag, `ai_sandbox_build_hash` is undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `bin/ai-sandbox-lib.sh`:

```bash
# Deterministic hash over the build context and the build args. Sorting paths
# under a fixed locale is what makes it reproducible across machines.
ai_sandbox_build_hash() {
    local dir=$1; shift
    {
        ( cd "$dir" && find . -type f -print0 | LC_ALL=C sort -z \
            | while IFS= read -r -d '' f; do
                  printf '%s\0%s\0' "${f#./}" "$(sha256sum "$f" | cut -d' ' -f1)"
              done )
        printf '%s\0' "$@"
    } | sha256sum | cut -d' ' -f1
}
```

In `bin/create-ai-sandbox.sh`, replace the `BUILD_DIR` assignment:

```bash
IMAGE_DIR="$AI_SANDBOX_ROOT/image"
BUILD_DIR="$IMAGE_DIR/build"        # ONE build context, shared by every project
```

and drop `"$BUILD_DIR"` from the per-sandbox `mkdir -p` list, adding instead:

```bash
mkdir -p "$BUILD_DIR"
```

Replace the temporary `IMAGE_NAME` line from Task 2 with the variant-derived tag. Place it after the `WITH_DOCKER` restore from Task 5, since the variant depends on it:

```bash
# One image serves every project: nothing in the Dockerfile is project-specific.
# The uid suffix keeps two host users on one daemon from fighting over a tag,
# since the image bakes in USER_ID.
if [ "$WITH_DOCKER" = "yes" ]; then IMAGE_VARIANT="docker"; else IMAGE_VARIANT="base"; fi
IMAGE_NAME="ai-sandbox:${IMAGE_VARIANT}-u${HOST_UID}"
IMAGE_STAMP="$IMAGE_DIR/${IMAGE_VARIANT}-u${HOST_UID}.stamp"
```

In the compose generation, replace the `build:` block and `image:` line with the image reference alone:

```bash
    image: "${IMAGE_NAME}"
```

Replace the build-and-start block at the end of the script:

```bash
step "Image"

BUILD_HASH=$(ai_sandbox_build_hash "$BUILD_DIR" \
             "$HOST_UID" "$HOST_GID" "$HOST_USER" "$CONTAINER_HOME" "$IMAGE_VARIANT")

need_build="no"
if [ "$FORCE_REBUILD" = "yes" ]; then
    need_build="yes"
elif ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    need_build="yes"
elif [ ! -f "$IMAGE_STAMP" ] || [ "$(cat "$IMAGE_STAMP")" != "$BUILD_HASH" ]; then
    need_build="yes"
fi

if [ "$NO_START" = "yes" ]; then
    log "--no-start: not building or starting anything."
    log "image would be $IMAGE_NAME (build needed: $need_build)"
elif [ "$need_build" = "yes" ]; then
    log "building $IMAGE_NAME (shared by every project)"
    build_flags=()
    [ "$FORCE_REBUILD" = "yes" ] && build_flags+=(--no-cache)
    docker build "${build_flags[@]}" \
        --build-arg "USER_ID=$HOST_UID" \
        --build-arg "GROUP_ID=$HOST_GID" \
        --build-arg "USER_NAME=$HOST_USER" \
        --build-arg "USER_HOME=$CONTAINER_HOME" \
        -t "$IMAGE_NAME" "$BUILD_DIR"
    printf '%s\n' "$BUILD_HASH" > "$IMAGE_STAMP"
else
    log "$IMAGE_NAME is up to date"
fi

if [ "$NO_START" != "yes" ]; then
    [ -x "$SANDBOX_DIR/start-display.sh" ] && "$SANDBOX_DIR/start-display.sh"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
fi
```

Add `USER_HOME` to the Dockerfile so the container home matches the host's, replacing the hardcoded `/home/${USER_NAME}` occurrences in the `DOCKERFILE_TAIL` heredoc:

```dockerfile
ARG USER_HOME=/home/developer
...
    useradd -s /bin/bash -l -u "${USER_ID}" -g "${GROUP_ID}" -d "${USER_HOME}" -m "${USER_NAME}"; \
```

and change `WORKDIR /home/${USER_NAME}` to `WORKDIR ${USER_HOME}`, and every other `/home/${USER_NAME}` in that heredoc to `${USER_HOME}`.

- [ ] **Step 4: Run test to verify it passes**

```bash
bash -n bin/create-ai-sandbox.sh && bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED`.

- [ ] **Step 5: Commit**

```bash
git add bin/create-ai-sandbox.sh bin/ai-sandbox-lib.sh tests/ai-sandbox/test-image.sh
git commit -m "feat(ai-sandbox): build one image shared by every project"
```

---

### Task 7: Shared asset directories and a trimmed seed

**Files:**
- Modify: `bin/create-ai-sandbox.sh:617-669` (seed excludes), `:1198-1229` (compose volumes)
- Create: `tests/ai-sandbox/test-shared.sh`

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces: `AI_SANDBOX_SHARED_DIRS`, an array in `ai-sandbox-lib.sh` of `<shared-subdir>|<container-path>` pairs, consumed by both the compose generation here and `ai-sandbox-gc` in Task 9.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-shared.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

tmp=$(fake_home)
proj="$tmp/work/p"; mkdir -p "$proj"

# A host with the bulk the seed must now skip.
mkdir -p "$HOME/.config/Antigravity/User/workspaceStorage/ws1" \
         "$HOME/.config/Claude/claude-code/9.9.9" \
         "$HOME/.claude/downloads" \
         "$HOME/.config/Antigravity IDE/CachedExtensionVSIXs"
echo bulk > "$HOME/.config/Antigravity/User/workspaceStorage/ws1/state"
echo bulk > "$HOME/.config/Claude/claude-code/9.9.9/bin"
echo bulk > "$HOME/.claude/downloads/cli"
echo bulk > "$HOME/.config/Antigravity IDE/CachedExtensionVSIXs/x.vsix"
echo keep > "$HOME/.claude/.credentials.json"

bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"

assert_eq "credentials still seeded" "$(cat "$dir/.claude/.credentials.json")" 'keep'
assert_no_file "workspaceStorage not copied" "$dir/antigravity-data/User/workspaceStorage"
assert_no_file "claude-code not copied"      "$dir/claude-data/claude-code"
assert_no_file "downloads not copied"        "$dir/.claude/downloads"
assert_no_file "vsix cache not copied"       "$dir/antigravity-ide-data/CachedExtensionVSIXs"

for d in antigravity-extensions antigravity-ide-extensions claude-downloads \
         claude-desktop-versions ide-vsix ide-cacheddata cache npm; do
    assert_file "shared/$d exists" "$AI_SANDBOX_ROOT/shared/$d"
done

compose=$(cat "$dir/docker-compose.yml")
assert_contains "extensions mounted from shared" "$compose" \
    "shared/antigravity-ide-extensions:"
assert_contains "downloads mounted from shared"  "$compose" "shared/claude-downloads:"
assert_contains "cache mounted from shared"      "$compose" "shared/cache:"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/ai-sandbox/test-shared.sh
```

Expected: FAIL — the bulk directories are copied and `shared/` does not exist.

- [ ] **Step 3: Write minimal implementation**

Append to `bin/ai-sandbox-lib.sh`:

```bash
# Bulk, read-mostly data that is identical across projects. Each entry is
# '<subdirectory of shared/>|<path inside the container>'. These are nested
# bind mounts inside the per-project mounts; Docker orders mounts by
# destination depth, which is what makes the nesting work.
ai_sandbox_shared_mounts() {
    cat <<'SHARED'
antigravity-extensions|.antigravity/extensions
antigravity-ide-extensions|.antigravity-ide/extensions
claude-downloads|.claude/downloads
claude-desktop-versions|.config/Claude/claude-code
ide-vsix|.config/Antigravity IDE/CachedExtensionVSIXs
ide-cacheddata|.config/Antigravity IDE/CachedData
cache|.cache
npm|.npm
SHARED
}
```

In `bin/create-ai-sandbox.sh`, create the shared directories next to the sandbox `mkdir -p`:

```bash
SHARED_DIR="$AI_SANDBOX_ROOT/shared"
while IFS='|' read -r sub _; do
    [ -n "$sub" ] && mkdir -p "$SHARED_DIR/$sub"
done < <(ai_sandbox_shared_mounts)
```

Extend `COMMON_EXCLUDES` so the seed never copies what a sandbox cannot use:

```bash
COMMON_EXCLUDES=(
    --exclude='*Cache*' --exclude='*cache*' --exclude='BrowserMetrics*'
    --exclude='Crashpad' --exclude='logs' --exclude='tmp'
    # Bulk that is either shared between sandboxes or host state a single-project
    # sandbox has no use for. Excluding it here is ~1.2 GB never written.
    --exclude='workspaceStorage'
    --exclude='claude-code'
    --exclude='downloads'
    --exclude='extensions'
    --exclude='CachedExtensionVSIXs' --exclude='CachedData' --exclude='WebStorage'
    --exclude='Safe Browsing' --exclude='optimization_guide_model_store'
    --exclude='WasmTtsEngine' --exclude='OnDeviceHeadSuggestModel'
    --exclude='CertificateRevocation'
)
```

Append the shared mounts to the compose volume block, after the existing live-host mounts:

```bash
{
    echo "      # Bulk assets shared by every sandbox."
    while IFS='|' read -r sub path; do
        [ -n "$sub" ] || continue
        printf '      - "%s/%s:%s/%s"\n' "$SHARED_DIR" "$sub" "$CONTAINER_HOME" "$path"
    done < <(ai_sandbox_shared_mounts)
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bash -n bin/create-ai-sandbox.sh && bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED`.

- [ ] **Step 5: Commit**

```bash
git add bin/create-ai-sandbox.sh bin/ai-sandbox-lib.sh tests/ai-sandbox/test-shared.sh
git commit -m "feat(ai-sandbox): share bulk assets between sandboxes and trim the seed"
```

---

### Task 8: One-shot seeding, per-project accounts, Codex

**Files:**
- Modify: `bin/create-ai-sandbox.sh:613-674` (guard the seed), Dockerfile npm globals
- Create: `bin/ai-sandbox-account`
- Create: `tests/ai-sandbox/test-account.sh`

**Interfaces:**
- Consumes: Tasks 1-7.
- Produces: `$SANDBOX_DIR/.seeded` (marker), `ai_sandbox_seed_paths()` in the library listing `<host-relative>|<sandbox-relative>` pairs, and `ai-sandbox-account status|refresh|reset`.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-account.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

tmp=$(fake_home)
proj="$tmp/work/p"; mkdir -p "$proj"
mkdir -p "$HOME/.claude" "$HOME/.codex"
echo 'host-token'   > "$HOME/.claude/.credentials.json"
echo '{"a":"host"}' > "$HOME/.claude.json"
echo 'host-codex'   > "$HOME/.codex/auth.json"

create() { bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj" >>"$tmp/out" 2>&1 || true; }
create
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"

assert_file "seed marker written"    "$dir/.seeded"
assert_eq   "claude creds seeded"    "$(cat "$dir/.claude/.credentials.json")" 'host-token'
assert_eq   "codex creds seeded"     "$(cat "$dir/.codex/auth.json")"          'host-codex'

# Log in to a different account inside the sandbox, then re-run the script.
echo 'project-token' > "$dir/.claude/.credentials.json"
echo 'project-codex' > "$dir/.codex/auth.json"
echo '{"a":"proj"}'  > "$dir/.claude.json"
create
assert_eq "claude login survives re-run" "$(cat "$dir/.claude/.credentials.json")" 'project-token'
assert_eq "codex login survives re-run"  "$(cat "$dir/.codex/auth.json")"          'project-codex'
assert_eq "claude.json survives re-run"  "$(cat "$dir/.claude.json")"              '{"a":"proj"}'

# Even when the host credentials change afterwards.
echo 'host-token-2' > "$HOME/.claude/.credentials.json"
create
assert_eq "host re-auth does not leak in" "$(cat "$dir/.claude/.credentials.json")" 'project-token'

acct() { ( cd "$proj" && bash "$REPO_ROOT/bin/ai-sandbox-account" "$@" 2>&1 ); }
assert_contains "status names the project" "$(acct status)" "$(ai_sandbox_project_id "$proj")"
assert_contains "status reports seeding"   "$(acct status)" 'seeded'

# refresh re-pulls the host credentials and backs up what it replaces.
acct refresh --yes >/dev/null
assert_eq   "refresh pulled the host token" "$(cat "$dir/.claude/.credentials.json")" 'host-token-2'
assert_file "refresh left a backup"         "$dir/.credentials-backup"

# reset clears them so the next start prompts for a login.
acct reset --yes >/dev/null
assert_no_file "reset cleared claude creds" "$dir/.claude/.credentials.json"
assert_file    "reset kept the sandbox"     "$dir/docker-compose.yml"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/ai-sandbox/test-account.sh
```

Expected: FAIL — `seed marker written` fails, `claude login survives re-run` fails (the rsync overwrites it), and `ai-sandbox-account` does not exist.

- [ ] **Step 3: Write minimal implementation**

Append to `bin/ai-sandbox-lib.sh`:

```bash
# '<path under $HOME on the host>|<path under the sandbox dir>'. Everything
# here is identity-bearing and is seeded exactly once.
ai_sandbox_seed_paths() {
    cat <<'SEED'
.gemini|.gemini
.antigravity|.antigravity
.claude|.claude
.codex|.codex
.config/Antigravity|antigravity-data
.config/Antigravity IDE|antigravity-ide-data
.config/Claude|claude-data
SEED
}
```

In `bin/create-ai-sandbox.sh`, wrap the whole "Copy tool state into the sandbox" step:

```bash
step "Tool state"

if [ -f "$SANDBOX_DIR/.seeded" ]; then
    log "already seeded; leaving this project's logins alone."
    log "(ai-sandbox-account refresh re-pulls the host credentials)"
else
    log "seeding from the host, once. Later runs will not overwrite this."

    # Everything from the current 'if [ -d "$HOME/.gemini" ]' block down to and
    # including the 'if [ -d "$HOME/.claude" ]' block moves inside this else
    # branch verbatim -- the same rsync invocations, the same excludes, the same
    # log lines. Only the two additions below are new.
    if [ -d "$HOME/.codex" ]; then
        safe_rsync -a "${COMMON_EXCLUDES[@]}" "$HOME/.codex/" "$SANDBOX_DIR/.codex/"
        log ".codex"
    fi
    date -Iseconds > "$SANDBOX_DIR/.seeded"
fi
```

The `.claude.json` freshness comparison inside that block loses its reason to exist once seeding is one-shot; replace it with a plain one-time copy:

```bash
if [ -f "$HOME/.claude.json" ]; then
    cp -f "$HOME/.claude.json" "$SANDBOX_DIR/.claude.json"
else
    echo '{}' > "$SANDBOX_DIR/.claude.json"
fi
chmod 600 "$SANDBOX_DIR/.claude.json"
```

Move `chmod 600 "$SANDBOX_DIR/.claude.json"` outside the `else` branch so permissions are enforced on every run.

Add `.codex` to the per-sandbox `mkdir -p` list and to the compose volumes:

```bash
      - "${SANDBOX_DIR}/.codex:${CONTAINER_HOME}/.codex"
```

Add the CLI to the Dockerfile npm globals:

```dockerfile
RUN npm install -g --force \
        @anthropic-ai/claude-code @openai/codex firebase-tools @google/gemini-cli @ast-grep/cli \
    && npm cache clean --force
```

Create `bin/ai-sandbox-account`:

```bash
#!/usr/bin/env bash
# Inspect and manage the AI accounts this project's sandbox uses.
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"
ai_sandbox_require_ctx || exit 1

cmd=${1:-status}
assume_yes="no"
[ "${2:-}" = "--yes" ] && assume_yes="yes"

confirm() {
    [ "$assume_yes" = "yes" ] && return 0
    printf '%s [y/N] ' "$1"
    read -r reply
    case "$reply" in y|Y) return 0 ;; *) echo "Cancelled."; return 1 ;; esac
}

account_of_claude_json() {
    python3 - "$1" <<'PY' 2>/dev/null || echo unknown
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unknown"); raise SystemExit
acct = d.get("oauthAccount") or {}
print(acct.get("emailAddress") or "not logged in")
PY
}

case "$cmd" in
status)
    printf 'project      %s\n' "$AI_SANDBOX_PROJECT"
    printf 'sandbox      %s\n' "$AI_SANDBOX_NAME"
    if [ -f "$AI_SANDBOX_DIR/.seeded" ]; then
        printf 'seeded       %s (host credentials are no longer copied in)\n' \
               "$(cat "$AI_SANDBOX_DIR/.seeded")"
    else
        printf 'seeded       no\n'
    fi
    printf 'claude       %s\n' "$(account_of_claude_json "$AI_SANDBOX_DIR/.claude.json")"
    for t in "claude:.claude/.credentials.json" "codex:.codex/auth.json" \
             "gemini:.gemini/google_accounts.json"; do
        name=${t%%:*}; path=${t#*:}
        if [ -s "$AI_SANDBOX_DIR/$path" ]; then
            printf '%-12s credentials present\n' "$name"
        else
            printf '%-12s no credentials\n' "$name"
        fi
    done
    ;;
refresh)
    confirm "Replace this project's credentials with the host's?" || exit 1
    backup="$AI_SANDBOX_DIR/.credentials-backup"
    rm -rf "$backup"; mkdir -p "$backup"
    while IFS='|' read -r host_rel sb_rel; do
        [ -n "$host_rel" ] || continue
        [ -e "$AI_SANDBOX_DIR/$sb_rel" ] && cp -a "$AI_SANDBOX_DIR/$sb_rel" "$backup/" 2>/dev/null || true
        [ -d "$HOME/$host_rel" ] || continue
        rsync -a --delete "$HOME/$host_rel/" "$AI_SANDBOX_DIR/$sb_rel/"
    done < <(ai_sandbox_seed_paths)
    [ -f "$AI_SANDBOX_DIR/.claude.json" ] && cp -a "$AI_SANDBOX_DIR/.claude.json" "$backup/"
    [ -f "$HOME/.claude.json" ] && cp -f "$HOME/.claude.json" "$AI_SANDBOX_DIR/.claude.json"
    chmod 600 "$AI_SANDBOX_DIR/.claude.json" 2>/dev/null || true
    date -Iseconds > "$AI_SANDBOX_DIR/.seeded"
    echo "Refreshed from the host. Previous state is in $backup."
    echo "Restart the sandbox for it to take effect: ai-sandbox-restart"
    ;;
reset)
    confirm "Erase this project's AI credentials and start from a clean login?" || exit 1
    while IFS='|' read -r _ sb_rel; do
        [ -n "$sb_rel" ] && rm -rf "${AI_SANDBOX_DIR:?}/$sb_rel"
    done < <(ai_sandbox_seed_paths)
    echo '{}' > "$AI_SANDBOX_DIR/.claude.json"
    chmod 600 "$AI_SANDBOX_DIR/.claude.json"
    date -Iseconds > "$AI_SANDBOX_DIR/.seeded"
    echo "Cleared. Log in inside the sandbox; the host credentials will not come back."
    echo "Restart the sandbox: ai-sandbox-restart"
    ;;
*)
    echo "Usage: ai-sandbox-account [status|refresh|reset] [--yes]" >&2
    exit 2
    ;;
esac
```

Add `ai-sandbox-account` to the install list in `create-ai-sandbox.sh` and to the refresh list in `ai-sandbox-migrate`.

- [ ] **Step 4: Run test to verify it passes**

```bash
chmod +x bin/ai-sandbox-account
bash -n bin/ai-sandbox-account bin/create-ai-sandbox.sh && bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED`.

- [ ] **Step 5: Commit**

```bash
git add bin/ai-sandbox-account bin/ai-sandbox-lib.sh bin/create-ai-sandbox.sh \
        tests/ai-sandbox/test-account.sh
git commit -m "feat(ai-sandbox): seed credentials once per project and add ai-sandbox-account"
```

---

### Task 9: M2/M3, garbage collection, extension bootstrap, docs

**Files:**
- Modify: `bin/ai-sandbox-migrate` (add M2 and M3)
- Create: `bin/ai-sandbox-gc`, `bin/ai-sandbox-extensions`
- Modify: `PROJECT_MAP.md`
- Create: `tests/ai-sandbox/test-gc.sh`

**Interfaces:**
- Consumes: Tasks 1-8.
- Produces: `ai-sandbox-gc` and `ai-sandbox-extensions`; migration reports rather than removes.

- [ ] **Step 1: Write the failing test**

Create `tests/ai-sandbox/test-gc.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

tmp=$(fake_home)
proj="$tmp/work/p"; mkdir -p "$proj"
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
mkdir -p "$dir/.antigravity-ide/extensions/ext-a" "$AI_SANDBOX_ROOT/shared"
printf '%s\n' "$proj" > "$dir/project-path"
printf 'working_dir: "%s"\n' "$proj" > "$dir/docker-compose.yml"
echo payload > "$dir/.antigravity-ide/extensions/ext-a/package.json"

# M2: the first sandbox to migrate MOVES its extensions into shared/.
bash "$REPO_ROOT/bin/ai-sandbox-migrate" >"$tmp/m" 2>&1 || { echo FAILED; cat "$tmp/m"; }
assert_file "extensions moved to shared" \
            "$AI_SANDBOX_ROOT/shared/antigravity-ide-extensions/ext-a/package.json"
assert_no_file "sandbox copy gone" "$dir/.antigravity-ide/extensions/ext-a"

# A second sandbox with its own copy is REPORTED, never silently deleted.
dir2="$AI_SANDBOX_ROOT/other-agent"
mkdir -p "$dir2/.antigravity-ide/extensions/ext-b"
printf '%s\n' "$tmp/work/other" > "$dir2/project-path"
echo payload > "$dir2/.antigravity-ide/extensions/ext-b/package.json"
out=$(bash "$REPO_ROOT/bin/ai-sandbox-migrate" 2>&1)
assert_file     "duplicate left in place" "$dir2/.antigravity-ide/extensions/ext-b/package.json"
assert_contains "duplicate reported"      "$out" 'ai-sandbox-gc'

# gc refuses to remove anything without confirmation.
bash "$REPO_ROOT/bin/ai-sandbox-gc" </dev/null >"$tmp/gc" 2>&1 || true
assert_file "gc without confirmation removes nothing" \
            "$dir2/.antigravity-ide/extensions/ext-b/package.json"
assert_contains "gc lists what it would remove" "$(cat "$tmp/gc")" 'other-agent'

bash "$REPO_ROOT/bin/ai-sandbox-gc" --yes >/dev/null 2>&1 || true
assert_no_file "gc --yes removes the duplicate" "$dir2/.antigravity-ide/extensions/ext-b"
assert_file    "gc kept the shared copy" \
               "$AI_SANDBOX_ROOT/shared/antigravity-ide-extensions/ext-a/package.json"

rm -rf "$tmp"
finish
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/ai-sandbox/test-gc.sh
```

Expected: FAIL — extensions are not moved and `bin/ai-sandbox-gc` does not exist.

- [ ] **Step 3: Write minimal implementation**

Append to `bin/ai-sandbox-migrate`, before the schema-version write:

```bash
# --- M2: lift shared bulk out of existing sandboxes ------------------------
# The first sandbox to migrate donates its copy; later ones are reported, never
# deleted here.
duplicates=0
for dir in "$AI_SANDBOX_ROOT"/*-agent; do
    [ -d "$dir" ] || continue
    while IFS='|' read -r sub path; do
        [ -n "$sub" ] || continue
        src="$dir/$path"
        dst="$AI_SANDBOX_ROOT/shared/$sub"
        [ -d "$src" ] || continue
        [ -n "$(ls -A "$src" 2>/dev/null)" ] || continue
        mkdir -p "$(dirname "$dst")"
        if [ ! -d "$dst" ] || [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
            rm -rf "$dst"
            mv "$src" "$dst"
            mkdir -p "$src"
            say "shared $(basename "$dir")/$path -> shared/$sub"
        else
            duplicates=$((duplicates + 1))
            say "duplicate: $(basename "$dir")/$path (shared/$sub already populated)"
        fi
    done < <(ai_sandbox_shared_mounts)
done
if [ "$duplicates" -gt 0 ]; then
    say "$duplicates duplicate director(ies) can be reclaimed: run ai-sandbox-gc"
fi

# --- M3: report per-project images left over from the old scheme -----------
if command -v docker >/dev/null 2>&1; then
    legacy_images=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
                    | grep '^ai-sandbox-' || true)
    if [ -n "$legacy_images" ]; then
        say "per-project images from the old scheme are no longer used:"
        printf '  %s\n' $legacy_images
        say "remove them with ai-sandbox-gc"
    fi
fi
```

Create `bin/ai-sandbox-gc`:

```bash
#!/usr/bin/env bash
# Reclaim space that migration deliberately left alone: per-sandbox duplicates
# of shared assets, and per-project images from the old naming scheme.
# Removes nothing without confirmation.
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"

assume_yes="no"
[ "${1:-}" = "--yes" ] && assume_yes="yes"

targets=()
for dir in "$AI_SANDBOX_ROOT"/*-agent; do
    [ -d "$dir" ] || continue
    while IFS='|' read -r sub path; do
        [ -n "$sub" ] || continue
        src="$dir/$path"
        dst="$AI_SANDBOX_ROOT/shared/$sub"
        [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ] || continue
        [ -d "$dst" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ] || continue
        targets+=("$src")
    done < <(ai_sandbox_shared_mounts)
done

legacy_images=()
if command -v docker >/dev/null 2>&1; then
    while IFS= read -r img; do
        [ -n "$img" ] && legacy_images+=("$img")
    done < <(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep '^ai-sandbox-' || true)
fi

if [ "${#targets[@]}" -eq 0 ] && [ "${#legacy_images[@]}" -eq 0 ]; then
    echo "Nothing to reclaim."
    exit 0
fi

echo "Duplicated directories (a shared copy already exists):"
for t in "${targets[@]}"; do printf '  %s  %s\n' "$(du -sh "$t" 2>/dev/null | cut -f1)" "$t"; done
if [ "${#legacy_images[@]}" -gt 0 ]; then
    echo "Images from the old per-project naming scheme:"
    printf '  %s\n' "${legacy_images[@]}"
fi

if [ "$assume_yes" != "yes" ]; then
    printf 'Remove all of the above? [y/N] '
    read -r reply || reply=n
    case "$reply" in y|Y) ;; *) echo "Cancelled. Nothing was removed."; exit 0 ;; esac
fi

for t in "${targets[@]}"; do rm -rf "$t"; mkdir -p "$t"; done
for img in "${legacy_images[@]:-}"; do
    [ -n "$img" ] && docker rmi "$img" >/dev/null 2>&1 || true
done
echo "Reclaimed."
```

Create `bin/ai-sandbox-extensions`:

```bash
#!/usr/bin/env bash
# Populate the shared IDE extension stores. The image no longer carries
# extensions, so this is their only source; a failure here must be loud.
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/ai-sandbox-lib.sh"

EXTENSIONS="anthropic.claude-code redhat.java"

shared_ide="$AI_SANDBOX_ROOT/shared/antigravity-ide-extensions"
shared_agy="$AI_SANDBOX_ROOT/shared/antigravity-extensions"
mkdir -p "$shared_ide" "$shared_agy"

populated() { [ -n "$(ls -A "$1" 2>/dev/null)" ]; }

if [ "${1:-}" != "refresh" ] && populated "$shared_ide"; then
    exit 0
fi

# 1. The host's own extensions, when it has them.
for pair in "$HOME/.antigravity-ide/extensions|$shared_ide" \
            "$HOME/.antigravity/extensions|$shared_agy"; do
    src=${pair%%|*}; dst=${pair#*|}
    if [ -d "$src" ] && populated "$src" && ! populated "$dst"; then
        echo "Seeding $(basename "$dst") from the host..."
        rsync -a "$src/" "$dst/"
    fi
done
populated "$shared_ide" && exit 0

# 2. Otherwise install them with a throwaway container.
uid=$(id -u)
for variant in docker base; do
    tag="ai-sandbox:${variant}-u${uid}"
    docker image inspect "$tag" >/dev/null 2>&1 || continue
    echo "Installing IDE extensions into $shared_ide using $tag..."
    for ext in $EXTENSIONS; do
        docker run --rm \
            -v "$shared_ide:$HOME/.antigravity-ide/extensions" \
            --entrypoint antigravity2-ide "$tag" --install-extension "$ext" \
            || echo "WARNING: could not install $ext" >&2
    done
    populated "$shared_ide" && exit 0
done

echo "ERROR: could not populate $shared_ide." >&2
echo "       The IDE will start without extensions. Re-run: ai-sandbox-extensions refresh" >&2
exit 1
```

In `bin/create-ai-sandbox.sh`, remove the two extension-installing `RUN` blocks from the `DOCKERFILE_TAIL` heredoc entirely, add both new helpers to the install list, and call the bootstrap after the image build (skipped under `--no-start`):

```bash
if [ "$NO_START" != "yes" ]; then
    "$AI_SANDBOX_ROOT/bin/ai-sandbox-extensions" || \
        warn "IDE extensions are not installed. Re-run: ai-sandbox-extensions refresh"
fi
```

Add the new rows to `PROJECT_MAP.md` under the `bin/` entries:

```markdown
| [bin/ai-sandbox-lib.sh](bin/ai-sandbox-lib.sh) | Shared bash library: path-derived project identity, sandbox paths, compose invocation, shared-mount and seed tables. Sourced by create-ai-sandbox.sh and every ai-sandbox-* command. |
| [bin/ai-sandbox](bin/ai-sandbox) | Enter or start the current project's sandbox; runs migration first. |
| [bin/ai-sandbox-account](bin/ai-sandbox-account) | Inspect, refresh or reset the AI credentials a project's sandbox uses. |
| [bin/ai-sandbox-migrate](bin/ai-sandbox-migrate) | Idempotent migration of ~/.ai-sandbox to the current layout; runs before every start. |
| [bin/ai-sandbox-gc](bin/ai-sandbox-gc) | Reclaim duplicated per-sandbox assets and old per-project images, after confirmation. |
| [bin/ai-sandbox-extensions](bin/ai-sandbox-extensions) | Populate the shared IDE extension stores from the host or a throwaway container. |
| [bin/ai-sandbox-stop](bin/ai-sandbox-stop), [bin/ai-sandbox-restart](bin/ai-sandbox-restart), [bin/ai-sandbox-attach](bin/ai-sandbox-attach), [bin/ai-sandbox-rm](bin/ai-sandbox-rm) | Lifecycle and device helpers for the current project's sandbox. |
| [tests/ai-sandbox/](tests/ai-sandbox) | Bash test suite for the sandbox tooling; runs against a temp HOME with a stubbed docker. `bash tests/ai-sandbox/run-tests.sh`. |
```

- [ ] **Step 4: Run test to verify it passes**

```bash
chmod +x bin/ai-sandbox-gc bin/ai-sandbox-extensions
bash -n bin/ai-sandbox-gc bin/ai-sandbox-extensions bin/ai-sandbox-migrate \
        bin/create-ai-sandbox.sh
bash tests/ai-sandbox/run-tests.sh
```

Expected: `ALL SUITES PASSED` across all eight suites.

- [ ] **Step 5: Commit**

```bash
git add bin/ai-sandbox-gc bin/ai-sandbox-extensions bin/ai-sandbox-migrate \
        bin/create-ai-sandbox.sh PROJECT_MAP.md tests/ai-sandbox/test-gc.sh
git commit -m "feat(ai-sandbox): shared-asset migration, gc and extension bootstrap"
```

---

## Host verification (not part of any task)

None of the above can build an image or start a container from inside the sandbox. After the tasks are complete, these are run on the host:

1. `create-ai-sandbox.sh --no-start` on a project with a legacy sandbox; confirm M1 renamed it, `project-path` is right, credentials intact.
2. `create-ai-sandbox.sh` on a second project; confirm no rebuild and both compose files name the same image tag.
3. Log into a different Claude account inside one sandbox, re-run the script, confirm the login survives.
4. `ai-sandbox-account status` in both projects shows different accounts.
5. `du -sh ~/.ai-sandbox/*` shows the per-sandbox drop and one populated `shared/`.
6. Antigravity conversation history present in a migrated sandbox.
7. `--with-docker`, then a bare re-run: `security_opt` and `SANDBOX_WITH_DOCKER=1` still present. Then `--no-docker`: both gone.
8. `create-ai-sandbox.sh --help` lists every option, both command groups and the layout.
