#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"

# A host carrying the bulk the seed must now skip.
mkdir -p "$HOME/.config/Antigravity/User/workspaceStorage/ws1" \
         "$HOME/.config/Claude/claude-code/9.9.9" \
         "$HOME/.claude/downloads" \
         "$HOME/.antigravity/extensions/ext-a" \
         "$HOME/.config/Antigravity IDE/CachedExtensionVSIXs"
echo bulk > "$HOME/.config/Antigravity/User/workspaceStorage/ws1/state"
echo bulk > "$HOME/.config/Claude/claude-code/9.9.9/bin"
echo bulk > "$HOME/.claude/downloads/cli"
echo bulk > "$HOME/.antigravity/extensions/ext-a/package.json"
echo bulk > "$HOME/.config/Antigravity IDE/CachedExtensionVSIXs/x.vsix"
echo keep > "$HOME/.claude/.credentials.json"

bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"

assert_eq "credentials still seeded" "$(cat "$dir/.claude/.credentials.json")" 'keep'
assert_no_file "workspaceStorage not copied" "$dir/antigravity-data/User/workspaceStorage"
assert_no_file "claude-code not copied"      "$dir/claude-data/claude-code"
assert_no_file "downloads not copied"        "$dir/.claude/downloads"
assert_no_file "extensions not copied"       "$dir/.antigravity/extensions"
assert_no_file "vsix cache not copied"       "$dir/antigravity-ide-data/CachedExtensionVSIXs"

for d in antigravity-extensions antigravity-ide-extensions claude-downloads \
         claude-desktop-versions ide-vsix ide-cacheddata cache npm; do
    assert_file "shared/$d exists" "$AI_SANDBOX_ROOT/shared/$d"
done

compose=$(cat "$dir/docker-compose.yml")
assert_contains "ide extensions mounted from shared" "$compose" \
    "shared/antigravity-ide-extensions:$HOME/.antigravity-ide/extensions"
assert_contains "downloads mounted from shared" "$compose" \
    "shared/claude-downloads:$HOME/.claude/downloads"
assert_contains "cache mounted from shared" "$compose" "shared/cache:$HOME/.cache"
assert_contains "claude-code versions mounted" "$compose" \
    "shared/claude-desktop-versions:$HOME/.config/Claude/claude-code"
assert_contains "a container path containing a space survives" "$compose" \
    "Antigravity IDE/CachedExtensionVSIXs"

# The table's third field is the path inside the SANDBOX dir, which differs from
# the container path for the Electron dirs, and is empty where the data lives
# only in the container's writable layer. Migration and gc depend on this.
rows=$(ai_sandbox_shared_mounts)
assert_contains "electron row maps to the sandbox dir name" "$rows" \
    "claude-desktop-versions|.config/Claude/claude-code|claude-data/claude-code"
assert_contains "container-only row has an empty third field" "$rows" \
    "antigravity-ide-extensions|.antigravity-ide/extensions|"
assert_eq "every row has three fields" \
    "$(printf '%s\n' "$rows" | awk -F'|' 'NF!=3' | wc -l | tr -d ' ')" '0'

rm -rf "$tmp"
finish
