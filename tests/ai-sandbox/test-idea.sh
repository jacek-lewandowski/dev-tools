#!/usr/bin/env bash
# IntelliJ IDEA: mounted read-only from the host, runnable, state persisted.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

CREATE="$REPO_ROOT/bin/ai/create-ai-sandbox.sh"

# --- a host with no IDEA: nothing is mounted, nothing is created ------------
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"
IDEA_HOST_DIR="$tmp/absent" bash "$CREATE" --display=none --no-start "$proj" >"$tmp/out0" 2>&1 || true
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
compose=$(cat "$dir/docker-compose.yml")
TESTS_RUN=$((TESTS_RUN + 1))
case "$compose" in
    *"$tmp/absent"*|*SANDBOX_IDEA_HOME*) _fail "no IDEA on the host means no IDEA of its own" \
        "compose mounts the absent install or sets SANDBOX_IDEA_HOME" ;;
    *) _pass "no IDEA on the host means no IDEA of its own" ;;
esac
assert_no_file "and no settings directory is made" "$dir/jetbrains-config"
assert_no_file "and no index directory is made"    "$dir/jetbrains-cache"
# The shared plugins row is unconditional, like every other shared row: an
# empty directory mounted on a host with no IDE is inert, and keeping every row
# in ai_sandbox_shared_mounts unconditional is what lets gc reason about them.
assert_contains "the shared plugins row is still emitted" \
    "$compose" "shared/jetbrains-plugins:$HOME/.local/share/JetBrains:ro\""

# --- a host with IDEA ------------------------------------------------------
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"
idea="$tmp/idea-IU"; mkdir -p "$idea/bin"
printf '#!/bin/sh\nexit 0\n' > "$idea/bin/idea"; chmod +x "$idea/bin/idea"
echo '{"name":"IntelliJ IDEA","version":"2025.1"}' > "$idea/product-info.json"
# Host-side IDE state: a licence to carry in, and a plugin to share.
mkdir -p "$HOME/.config/JetBrains/IntelliJIdea2025.1/options" \
         "$HOME/.local/share/JetBrains/IntelliJIdea2025.1/some-plugin/lib"
echo 'LICENCE' > "$HOME/.config/JetBrains/IntelliJIdea2025.1/idea.key"
echo 'jar'     > "$HOME/.local/share/JetBrains/IntelliJIdea2025.1/some-plugin/lib/p.jar"

IDEA_HOST_DIR="$idea" bash "$CREATE" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
compose=$(cat "$dir/docker-compose.yml")

# The installation: read-only, and at the SAME path, so IDEA's own absolute
# references and anything it logs line up between host and sandbox.
assert_contains "installation mounted read-only at its host path" "$compose" \
    "\"$idea:$idea:ro\""
assert_contains "the wrapper is told where it is" "$compose" \
    "\"SANDBOX_IDEA_HOME=$idea\""

# Settings per sandbox, plugins shared, indexes per sandbox.
assert_contains "settings are per sandbox"  "$compose" \
    "\"$dir/jetbrains-config:$HOME/.config/JetBrains\""
assert_contains "plugins come from the shared store, read-only" "$compose" \
    "shared/jetbrains-plugins:$HOME/.local/share/JetBrains:ro\""
assert_contains "indexes are per sandbox"   "$compose" \
    "\"$dir/jetbrains-cache:$HOME/.cache/JetBrains\""

# The index dir is nested inside the per-sandbox ~/.cache mount, and Docker
# applies the deeper mount last, so it wins.
assert_contains "the per-sandbox ~/.cache mount is still there" "$compose" \
    "\"$dir/cache:$HOME/.cache\""

assert_eq "the licence is seeded from the host" \
    "$(cat "$dir/jetbrains-config/IntelliJIdea2025.1/idea.key")" 'LICENCE'
assert_eq "the plugin lands in the shared store" \
    "$(cat "$AI_SANDBOX_ROOT/shared/jetbrains-plugins/IntelliJIdea2025.1/some-plugin/lib/p.jar")" 'jar'
assert_file "the index directory is created, not left to Docker" "$dir/jetbrains-cache"

# --- the launcher ----------------------------------------------------------
wrapper="$AI_SANDBOX_ROOT/image/build/sandbox-idea"
assert_file "launcher in the build context" "$wrapper"
TESTS_RUN=$((TESTS_RUN + 1))
if bash -n "$wrapper" 2>"$tmp/w.err"; then _pass "launcher is valid bash"
else _fail "launcher is valid bash" "$(cat "$tmp/w.err")"; fi
assert_contains "image installs it as 'idea'" \
    "$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")" 'COPY sandbox-idea     /usr/local/bin/idea'
# The image is shared by every project, so the path cannot be baked in.
assert_contains "launcher reads the path from the environment" \
    "$(cat "$wrapper")" 'IDEA_HOME="${SANDBOX_IDEA_HOME:-/opt/idea-IU}"'

# --- a re-run must not clobber what the sandbox changed --------------------
echo 'CHANGED-INSIDE' > "$dir/jetbrains-config/IntelliJIdea2025.1/idea.key"
IDEA_HOST_DIR="$idea" bash "$CREATE" --display=none --no-start "$proj" >"$tmp/out2" 2>&1 || true
assert_eq "sandbox-local settings survive a re-run" \
    "$(cat "$dir/jetbrains-config/IntelliJIdea2025.1/idea.key")" 'CHANGED-INSIDE'

# --- and 'ai-sandbox-account reset' must not delete the IDE licence --------
TESTS_RUN=$((TESTS_RUN + 1))
if ai_sandbox_seed_paths | grep -q 'JetBrains'; then
    _fail "IDE state is not treated as an AI credential" \
        "jetbrains is in ai_sandbox_seed_paths, so 'ai-sandbox-account reset' would rm -rf it"
else _pass "IDE state is not treated as an AI credential"; fi

finish
