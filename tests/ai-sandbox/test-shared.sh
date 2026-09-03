#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

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
mkdir -p "$HOME/.gemini/config/plugins"
echo '{"mcpServers":{}}' > "$HOME/.gemini/config/mcp_config.json"

bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"

assert_eq "credentials still seeded" "$(cat "$dir/.claude/.credentials.json")" 'keep'
assert_no_file "workspaceStorage not copied" "$dir/antigravity-data/User/workspaceStorage"
assert_no_file "claude-code not copied"      "$dir/claude-data/claude-code"
assert_no_file "downloads not copied"        "$dir/.claude/downloads"
assert_no_file "extensions not copied"       "$dir/.antigravity/extensions"
assert_no_file "vsix cache not copied"       "$dir/antigravity-ide-data/CachedExtensionVSIXs"

for d in antigravity-extensions antigravity-ide-extensions claude-downloads \
         claude-desktop-versions ide-vsix jetbrains-plugins; do
    assert_file "shared/$d exists" "$AI_SANDBOX_ROOT/shared/$d"
done

# The host is the only writer of shared/: its own copy is synced in, so a
# sandbox never has to (and, mounted read-only, never can) populate it.
assert_eq "claude-code versions synced from the host" \
    "$(cat "$AI_SANDBOX_ROOT/shared/claude-desktop-versions/9.9.9/bin")" 'bulk'
assert_eq "downloads synced from the host" \
    "$(cat "$AI_SANDBOX_ROOT/shared/claude-downloads/cli")" 'bulk'
assert_eq "vsix cache synced from the host" \
    "$(cat "$AI_SANDBOX_ROOT/shared/ide-vsix/x.vsix")" 'bulk'
assert_eq "extensions synced from the host" \
    "$(cat "$AI_SANDBOX_ROOT/shared/antigravity-extensions/ext-a/package.json")" 'bulk'

compose=$(cat "$dir/docker-compose.yml")
assert_contains "ide extensions mounted from shared, read-only" "$compose" \
    "shared/antigravity-ide-extensions:$HOME/.antigravity-ide/extensions:ro\""
assert_contains "downloads mounted from shared, read-only" "$compose" \
    "shared/claude-downloads:$HOME/.claude/downloads:ro\""
assert_contains "claude-code versions mounted, read-only" "$compose" \
    "shared/claude-desktop-versions:$HOME/.config/Claude/claude-code:ro\""
assert_contains "a container path containing a space survives" "$compose" \
    "Antigravity IDE/CachedExtensionVSIXs:ro\""
# Sandboxes are not one trust domain: every shared store holds code, so no
# shared mount may be writable from inside a sandbox.
assert_eq "every shared mount is read-only" \
    "$(printf '%s\n' "$compose" | grep -c '/shared/')" \
    "$(printf '%s\n' "$compose" | grep -c '/shared/.*:ro"')"
# What a sandbox writes at run time is its own: caches hold code too.
assert_contains "~/.cache is per sandbox" "$compose" "\"$dir/cache:$HOME/.cache\""
assert_contains "~/.npm is per sandbox"   "$compose" "\"$dir/npm:$HOME/.npm\""
assert_file "the cache directory is created, not left to Docker" "$dir/cache"
assert_file "the npm directory is created, not left to Docker"   "$dir/npm"
for d in cache npm ide-cacheddata; do
    assert_no_file "shared/$d is no longer a store" "$AI_SANDBOX_ROOT/shared/$d"
done

# Updating on the host is what updates the sandboxes: a re-run syncs again.
mkdir -p "$HOME/.config/Claude/claude-code/9.9.10"
echo newer > "$HOME/.config/Claude/claude-code/9.9.10/bin"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out2" 2>&1 || true
assert_eq "a re-run syncs the host's newer copy into shared" \
    "$(cat "$AI_SANDBOX_ROOT/shared/claude-desktop-versions/9.9.10/bin")" 'newer'
# ~/.gemini/config holds mcp_config.json and plugins/, which the host's
# Antigravity executes. It is seeded once per sandbox, never live-shared, so
# a sandbox cannot register an MCP server or plugin on the host.
assert_file "gemini config seeded into the sandbox" "$dir/.gemini/config/mcp_config.json"
case "$compose" in
    *"$HOME/.gemini/config:"*) TESTS_RUN=$((TESTS_RUN + 1)); _fail "host ~/.gemini/config is not mounted" "found a live mount of the host directory" ;;
    *) TESTS_RUN=$((TESTS_RUN + 1)); _pass "host ~/.gemini/config is not mounted" ;;
esac

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
