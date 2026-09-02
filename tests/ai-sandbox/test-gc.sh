#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
mkdir -p "$dir/.antigravity/extensions/ext-a" "$AI_SANDBOX_ROOT/shared"
printf '%s\n' "$proj" > "$dir/project-path"
printf 'working_dir: "%s"\n' "$proj" > "$dir/docker-compose.yml"
echo payload > "$dir/.antigravity/extensions/ext-a/package.json"

# M2: the first sandbox to migrate MOVES its copy into shared/.
bash "$REPO_ROOT/bin/ai-sandbox-migrate" >"$tmp/m" 2>&1 || { echo FAILED; cat "$tmp/m"; }
assert_file "extensions moved to shared" \
            "$AI_SANDBOX_ROOT/shared/antigravity-extensions/ext-a/package.json"
assert_no_file "sandbox copy gone" "$dir/.antigravity/extensions/ext-a"

# A second sandbox with its own copy is REPORTED, never silently deleted.
dir2="$AI_SANDBOX_ROOT/other-agent"
mkdir -p "$dir2/.antigravity/extensions/ext-b"
printf '%s\n' "$tmp/work/other" > "$dir2/project-path"
echo payload > "$dir2/.antigravity/extensions/ext-b/package.json"
out=$(bash "$REPO_ROOT/bin/ai-sandbox-migrate" 2>&1)
assert_file     "duplicate left in place" "$dir2/.antigravity/extensions/ext-b/package.json"
assert_contains "duplicate reported"      "$out" 'ai-sandbox-gc'

# Rows whose third field is empty live only in the container: M2 must not invent
# a sandbox-side directory for them.
assert_no_file "container-only row not materialised" "$dir/.antigravity-ide"

# gc removes nothing without confirmation.
bash "$REPO_ROOT/bin/ai-sandbox-gc" </dev/null >"$tmp/gc" 2>&1 || true
assert_file "gc without confirmation removes nothing" \
            "$dir2/.antigravity/extensions/ext-b/package.json"
assert_contains "gc lists what it would remove" "$(cat "$tmp/gc")" 'other-agent'

bash "$REPO_ROOT/bin/ai-sandbox-gc" --yes >/dev/null 2>&1 || true
assert_no_file "gc --yes removes the duplicate" "$dir2/.antigravity/extensions/ext-b"
assert_file    "gc kept the shared copy" \
               "$AI_SANDBOX_ROOT/shared/antigravity-extensions/ext-a/package.json"

# Idempotence: with nothing left to do, migrate is silent.
out=$(bash "$REPO_ROOT/bin/ai-sandbox-migrate" 2>&1)
assert_eq "migrate silent when nothing to do" "$out" ''

# The extension bootstrap seeds from the host when the host has extensions.
fake_home >/dev/null; tmp2="$FAKE_HOME_DIR"
mkdir -p "$AI_SANDBOX_ROOT/bin" "$HOME/.antigravity-ide/extensions/ide-ext"
echo payload > "$HOME/.antigravity-ide/extensions/ide-ext/package.json"
bash "$REPO_ROOT/bin/ai-sandbox-extensions" >"$tmp2/ext" 2>&1 || true
assert_file "extensions seeded from the host" \
            "$AI_SANDBOX_ROOT/shared/antigravity-ide-extensions/ide-ext/package.json"

# The image must no longer bake extensions in -- shared/ is now their only home.
proj2="$tmp2/work/q"; mkdir -p "$proj2"
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj2" >>"$tmp2/o" 2>&1 || true
df=$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")
case "$df" in
    *"--install-extension"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "image bakes no extensions" "still installs them" ;;
    *)                       TESTS_RUN=$((TESTS_RUN+1)); _pass "image bakes no extensions" ;;
esac

rm -rf "$tmp" "$tmp2"
finish
