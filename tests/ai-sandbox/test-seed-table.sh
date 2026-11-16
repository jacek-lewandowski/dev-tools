#!/usr/bin/env bash
# The seed table (phase 7, O3): ai_sandbox_seed_table, ai_sandbox_seed_keys and the one copy
# function that copies the rows of a class from $HOME into a sandbox directory. Every kind of
# "how" (whole, links, json, xml), the globs, the key filters, the file that does not parse and
# the no-follow writes are tested on the functions themselves; the create command and
# ai-sandbox-account are tested in their own files.
set -uo pipefail
here=${BASH_SOURCE[0]%/*}
. "$here/harness.sh"
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

# --- the table is well formed
table=$(ai_sandbox_seed_table)
bad=$(printf '%s\n' "$table" | awk -F'|' '
    NF != 4 { print "fields: " $0; next }
    $1 != "settings" && $1 != "login" { print "class: " $0 }
    $4 !~ /^(whole|links|json|xml)$/ { print "how: " $0 }
    $2 ~ /^\// || $3 ~ /^\// || $2 ~ /(^|\/)(\.|\.\.|)(\/|$)/ || $3 ~ /(^|\/)(\.|\.\.|)(\/|$)/ { print "path: " $0 }')
assert_eq "every row has four fields, a known class and how, and a clean relative path" "$bad" ""
assert_contains ".claude.json is the one login row cut by key" "$table" $'login|.claude.json|.claude.json|json\n'
assert_contains "the credentials are a login row" "$table" 'login|.claude/.credentials.json|.claude/.credentials.json|whole'
assert_contains "the codex login is a login row" "$table" 'login|.codex/auth.json|.codex/auth.json|whole'
assert_contains "agy's token is a login row" "$table" 'login|.gemini/antigravity-cli/antigravity-oauth-token|'
assert_contains "the JetBrains licence is a login row (U-b (a))" "$table" 'login|.config/JetBrains/*/*.key|jetbrains-config/*/*.key|whole'
assert_contains "skills are links only (U-d (a))" "$table" 'settings|.claude/skills|.claude/skills|links'
assert_eq "no row names the Codex configuration (T09 writes a default instead)" "$(printf '%s\n' "$table" | grep -c 'config.toml')" 0
assert_eq "no row names history or a list of projects" \
    "$(printf '%s\n' "$table" | grep -cE 'history|projects|trustedFolders|recentProjects|trusted-paths|browser-profile|knowledge|[|/](brain|conversations)')" 0
assert_eq "a settings row never sits in the login class: no key, cookie or token name in settings" \
    "$(printf '%s\n' "$table" | grep '^settings|' | grep -ciE 'credentials|oauth|auth.json|cookies|\.key|\.license|mcp_config|state.vscdb')" 0

# --- the key allow-lists
assert_eq "the keys of .claude.json" "$(ai_sandbox_seed_keys .claude.json | paste -sd' ')" 'oauthAccount userID hasCompletedOnboarding'
assert_contains "claude settings keep the model" "$(ai_sandbox_seed_keys .claude/settings.json)" model
for k in env apiKeyHelper hooks statusLine permissions enabledPlugins extraKnownMarketplaces mcpServers; do
    assert_eq "claude settings do not allow $k" "$(ai_sandbox_seed_keys .claude/settings.json | grep -cx "$k")" 0
done
assert_eq "gemini settings: three key paths" "$(ai_sandbox_seed_keys .gemini/settings.json | paste -sd' ')" \
    'general/enablePromptCompletion general/previewFeatures security/auth/selectedType'
assert_eq "agy settings: colorScheme only" "$(ai_sandbox_seed_keys .gemini/antigravity-cli/settings.json)" colorScheme
assert_eq "both editors share their allow-list" \
    "$(ai_sandbox_seed_keys '.config/Antigravity/User/settings.json' | md5sum)" "$(ai_sandbox_seed_keys '.config/Antigravity IDE/User/settings.json' | md5sum)"
assert_eq "keybindings: key, command, when" "$(ai_sandbox_seed_keys '.config/Antigravity/User/keybindings.json' | paste -sd' ')" '[]/key []/command []/when'
assert_eq "no args in keybindings" "$(ai_sandbox_seed_keys '.config/Antigravity IDE/User/keybindings.json' | grep -c args)" 0
assert_eq "editor.xml: two components" "$(ai_sandbox_seed_keys '.config/JetBrains/*/options/editor.xml' | paste -sd' ')" 'EditorSettings CodeInsightSettings'
assert_eq "a row without a filter prints no keys" "$(ai_sandbox_seed_keys .codex/auth.json)" ""
# every json and xml row has an allow-list, no other row has one
miss=""
while IFS='|' read -r _ host _ how; do
    n=$(ai_sandbox_seed_keys "$host" | grep -c .)
    case $how in json|xml) [ "$n" -gt 0 ] || miss="$miss $host" ;; *) [ "$n" -eq 0 ] || miss="$miss $host(extra)" ;; esac
done <<<"$table"
assert_eq "exactly the json and xml rows have keys" "$miss" ""

# --- the fixture home: a marker unique to each path
mk() { mkdir -p "$(dirname "$1")"; printf 'marker:%s\n' "${1#$HOME/}" > "$1"; }
JB="$HOME/.config/JetBrains"
mk "$HOME/.claude/.credentials.json"; chmod 600 "$HOME/.claude/.credentials.json"
mk "$HOME/.claude/history.jsonl"; mk "$HOME/.claude/noname.txt"
mk "$HOME/.codex/auth.json"; mk "$HOME/.codex/config.toml"; mk "$HOME/.codex/AGENTS.md"; chmod 640 "$HOME/.codex/AGENTS.md"
mk "$HOME/.gemini/oauth_creds.json"; mk "$HOME/.gemini/projects.json"; mk "$HOME/.gemini/config/AGENTS.md"
mk "$HOME/.gemini/antigravity-cli/antigravity-oauth-token"; mk "$HOME/.gemini/antigravity-cli/history.jsonl"
mk "$HOME/.gemini/antigravity/brain/b.md"
mk "$HOME/.config/Claude/Local Storage/leveldb/000001.ldb"; mk "$HOME/.config/Claude/Cookies"; mk "$HOME/.config/Claude/git-worktrees.json"
mk "$HOME/.config/Antigravity/User/globalStorage/state.vscdb"; mk "$HOME/.config/Antigravity/User/History/h"
mk "$JB/IntelliJIdea2025.3/idea.key"; mk "$JB/IntelliJIdea2025.3/x.license"; mk "$JB/IntelliJIdea2025.3/idea64.vmoptions"
mk "$JB/CLion2025.2/clion.key"
mk "$JB/IntelliJIdea2025.3/disabled_plugins.txt"; mk "$JB/IntelliJIdea2025.3/colors/a.icls"; mk "$JB/IntelliJIdea2025.3/options/recentProjects.xml"
mk "$JB/CLion2025.2/codestyles/s.xml"
mkdir -p "$HOME/.agents/skills/shared" "$HOME/.claude/skills/own"
mk "$HOME/.claude/skills/own/SKILL.md"
ln -s ../../.agents/skills/shared "$HOME/.claude/skills/shared"
ln -s /abs/target "$HOME/.claude/skills/abs"
cat > "$HOME/.claude/settings.json" <<'EOF'
{
  // a comment
  "model": "opus", "theme": "dark", "voice": {"enabled": true, "mode": "tap"},
  "env": {"TOKEN": "env-marker"}, "apiKeyHelper": "helper-marker", "hooks": {"x": 1},
  "mcpServers": {"m": 1}, "enabledPlugins": {"p": true}, "unlisted": "unlisted-marker",
  "url": "http://example.test/a//b", /* block */
}
EOF
cat > "$HOME/.gemini/settings.json" <<'EOF'
{"general": {"enablePromptCompletion": true, "previewFeatures": false, "other": "other-marker"},
 "security": {"auth": {"selectedType": "oauth-personal", "secret": "s-marker"}}, "tools": {"x": 1}, "context": {"y": 1}}
EOF
printf '{"colorScheme": "light", "permissions": {"allow": ["p-marker"]}, "trustedWorkspaces": ["/other/project"]}\n' > "$HOME/.gemini/antigravity-cli/settings.json"
mkdir -p "$HOME/.config/Antigravity/User" "$HOME/.config/Antigravity IDE/User"
cat > "$HOME/.config/Antigravity/User/settings.json" <<'EOF'
{
    // editor settings, hand edited
    "editor.fontSize": 14,
    "editor.fontLigatures": true,
    "workbench.colorTheme": "Dark",
    "terminal.integrated.env.linux": {"X": "env-marker"},
    "dart.flutterSdkPath": "/host/flutter",
    "[markdown]": {"editor.wordWrap": "on"},
    "noallow": "noallow-marker",
}
EOF
printf '[{"key": "ctrl+a", "command": "x.y", "when": "editorFocus", "args": {"text": "args-marker"}}, {"args": 1}, {"key": "ctrl+b", "command": "z"}]\n' \
    > "$HOME/.config/Antigravity/User/keybindings.json"
printf '[{"key": "ctrl+a" "broken"\n' > "$HOME/.config/Antigravity IDE/User/keybindings.json"
printf '{"editor.fontSize": 16}\n' > "$HOME/.config/Antigravity IDE/User/settings.json"
cat > "$JB/IntelliJIdea2025.3/options/editor.xml" <<'EOF'
<application>
  <component name="EditorSettings"><option name="X" value="editor-marker" /></component>
  <component name="InlineCompletionOnboarding"><option name="Y" value="onboarding-marker" /></component>
  <component name="CodeInsightSettings"><option name="Z" value="ci-marker" /></component>
</application>
EOF
mkdir -p "$JB/CLion2025.2/options"
cat > "$JB/CLion2025.2/options/editor-font.xml" <<'EOF'
<application><component name="DefaultFont"><option name="FONT_SIZE" value="13" /></component></application>
EOF
printf '<application><component name="Broken">\n' > "$JB/CLion2025.2/options/laf.xml"

sb="$tmp/sb"; mkdir -p "$sb"
out="$tmp/copy.out"; err="$tmp/copy.err"
ai_sandbox_seed_copy "$sb" settings >"$out" 2>"$err"
assert_eq "copy of the settings class exits 0" "$?" 0

jq_() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d, sort_keys=True))' "$1"; }
# json
assert_eq "claude settings: only the allowed keys, comments and trailing comma accepted" \
    "$(jq_ "$sb/.claude/settings.json")" '{"model": "opus", "theme": "dark", "voice": {"enabled": true, "mode": "tap"}}'
assert_eq "gemini settings: nested key paths, the rest dropped" "$(jq_ "$sb/.gemini/settings.json")" \
    '{"general": {"enablePromptCompletion": true, "previewFeatures": false}, "security": {"auth": {"selectedType": "oauth-personal"}}}'
assert_eq "agy settings: colorScheme, never permissions or trustedWorkspaces" "$(jq_ "$sb/.gemini/antigravity-cli/settings.json")" '{"colorScheme": "light"}'
assert_eq "editor settings: globs over key names, the rest dropped" "$(jq_ "$sb/antigravity-data/User/settings.json")" \
    '{"editor.fontLigatures": true, "editor.fontSize": 14, "workbench.colorTheme": "Dark"}'
assert_eq "keybindings: every element cut to key, command, when; an empty element is dropped" "$(jq_ "$sb/antigravity-data/User/keybindings.json")" \
    '[{"command": "x.y", "key": "ctrl+a", "when": "editorFocus"}, {"command": "z", "key": "ctrl+b"}]'
assert_eq "the file that does not parse is not written" "$([ -e "$sb/antigravity-ide-data/User/keybindings.json" ] && echo written || echo absent)" absent
assert_contains "and standard error names it" "$(cat "$err")" 'Antigravity IDE/User/keybindings.json'
assert_eq "once" "$(grep -c 'keybindings.json' "$err" | head -1)" 1
assert_eq "the other editor's settings still arrived" "$(jq_ "$sb/antigravity-ide-data/User/settings.json")" '{"editor.fontSize": 16}'
# xml
comps() { python3 -I -c '
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot(); print(r.tag, " ".join(sorted(c.get("name") for c in r)))' "$1"; }
assert_eq "xml: only the listed components, the root kept" "$(comps "$sb/jetbrains-config/IntelliJIdea2025.3/options/editor.xml")" 'application CodeInsightSettings EditorSettings'
assert_eq "xml: a second product through the same glob" "$(comps "$sb/jetbrains-config/CLion2025.2/options/editor-font.xml")" 'application DefaultFont'
assert_eq "xml: the file that does not parse is not written" "$([ -e "$sb/jetbrains-config/CLion2025.2/options/laf.xml" ] && echo written || echo absent)" absent
assert_contains "and standard error names it" "$(cat "$err")" 'laf.xml'
# whole
assert_eq "whole file: byte-identical" "$(cat "$sb/.codex/AGENTS.md")" "marker:.codex/AGENTS.md"
assert_eq "whole file keeps the host's mode" "$(stat -c %a "$sb/.codex/AGENTS.md")" 640
assert_eq "whole file in a nested directory the sandbox did not have" "$(cat "$sb/.gemini/config/AGENTS.md")" "marker:.gemini/config/AGENTS.md"
assert_eq "whole directory with everything below it" "$(cat "$sb/jetbrains-config/IntelliJIdea2025.3/colors/a.icls")" "marker:.config/JetBrains/IntelliJIdea2025.3/colors/a.icls"
assert_eq "glob: the second product's directory arrives under its own name" "$(cat "$sb/jetbrains-config/CLion2025.2/codestyles/s.xml")" "marker:.config/JetBrains/CLion2025.2/codestyles/s.xml"
assert_eq "whole file: disabled_plugins.txt" "$(cat "$sb/jetbrains-config/IntelliJIdea2025.3/disabled_plugins.txt")" "marker:.config/JetBrains/IntelliJIdea2025.3/disabled_plugins.txt"
# links
assert_link "links: a relative link keeps its text" "$sb/.claude/skills/shared" ../../.agents/skills/shared
assert_link "links: an absolute link keeps its text" "$sb/.claude/skills/abs" /abs/target
assert_no_file "links: a skill directory is not copied" "$sb/.claude/skills/own"
# nothing that no row names, no login row in the settings class
assert_eq "settings copy: no marker of a login, history, project list, no-row name or dropped row" \
    "$(grep -rlF -e 'credentials.json' -e 'auth.json' -e 'history' -e 'projects.json' -e 'noname' -e 'config.toml' -e 'oauth_creds' -e 'idea.key' -e 'vmoptions' -e 'recentProjects' -e 'git-worktrees' -e 'brain' "$sb" 2>/dev/null | head -3)" ""
assert_eq "settings copy: no key-cut dropped value anywhere" "$(grep -rlE 'env-marker|helper-marker|unlisted-marker|p-marker|/other/project|s-marker|noallow-marker|args-marker|onboarding-marker|/host/flutter' "$sb" | head -3)" ""
assert_contains "the printed rows name the sandbox path" "$(cat "$out")" '.claude/settings.json'
assert_eq "a host without the row copies nothing (.codex/skills absent)" "$([ -e "$sb/.codex/skills" ] && echo present || echo absent)" absent

# --- the login class, only on its own call
ai_sandbox_seed_copy "$sb" login >"$out" 2>"$err"
assert_eq "login copy exits 0" "$?" 0
assert_eq "credentials" "$(cat "$sb/.claude/.credentials.json")" "marker:.claude/.credentials.json"
assert_eq "credentials keep mode 600" "$(stat -c %a "$sb/.claude/.credentials.json")" 600
assert_eq "codex login" "$(cat "$sb/.codex/auth.json")" "marker:.codex/auth.json"
assert_eq "gemini login" "$(cat "$sb/.gemini/oauth_creds.json")" "marker:.gemini/oauth_creds.json"
assert_eq "agy token" "$(cat "$sb/.gemini/antigravity-cli/antigravity-oauth-token")" "marker:.gemini/antigravity-cli/antigravity-oauth-token"
assert_eq "desktop app session" "$(cat "$sb/claude-data/Local Storage/leveldb/000001.ldb")" "marker:.config/Claude/Local Storage/leveldb/000001.ldb"
assert_eq "deep file row" "$(cat "$sb/antigravity-data/User/globalStorage/state.vscdb")" "marker:.config/Antigravity/User/globalStorage/state.vscdb"
assert_eq "licence under a glob, both products" "$(cat "$sb/jetbrains-config/IntelliJIdea2025.3/idea.key") $(cat "$sb/jetbrains-config/CLion2025.2/clion.key")" \
    "marker:.config/JetBrains/IntelliJIdea2025.3/idea.key marker:.config/JetBrains/CLion2025.2/clion.key"
assert_eq "second licence name" "$(cat "$sb/jetbrains-config/IntelliJIdea2025.3/x.license")" "marker:.config/JetBrains/IntelliJIdea2025.3/x.license"
assert_eq "no history, project list, browser or brain" \
    "$(find "$sb" -type f \( -name 'history*' -o -name projects.json -o -name 'git-worktrees.json' -o -name 'b.md' -o -name recentProjects.xml -o -name h -o -name '*.vmoptions' -o -name noname.txt -o -name config.toml \) | head -3)" ""
ai_sandbox_seed_copy "$sb" login >/dev/null 2>&1
printf '{"oauthAccount": {"e": 1}, "userID": "u", "hasCompletedOnboarding": true, "projects": {"/x": 1}, "githubRepoPaths": {}}\n' > "$HOME/.claude.json"
chmod 600 "$HOME/.claude.json"
sb2="$tmp/sb2"; mkdir -p "$sb2"
ai_sandbox_seed_copy "$sb2" login >/dev/null 2>&1
assert_eq ".claude.json is cut to the three keys" "$(jq_ "$sb2/.claude.json")" '{"hasCompletedOnboarding": true, "oauthAccount": {"e": 1}, "userID": "u"}'
assert_eq ".claude.json keeps the host's mode 600" "$(stat -c %a "$sb2/.claude.json")" 600

# --- a json root keeps its type when no allowed key is present ({} or [])
printf '{"permissions": {"allow": ["p"]}, "trustedWorkspaces": ["/x"]}\n' > "$tmp/none.json"
assert_eq "json: an object with no allowed key is written as {}" "$(ai_sandbox_seed_filter json "$tmp/none.json" colorScheme)" '{}'
printf '[{"args": 1}, {"args": 2}]\n' > "$tmp/none-list.json"
assert_eq "json: an array with no allowed element is written as []" "$(ai_sandbox_seed_filter json "$tmp/none-list.json" '[]/key' '[]/command')" '[]'

# --- scopes
sb3="$tmp/sb3"; mkdir -p "$sb3"
ai_sandbox_seed_copy "$sb3" settings idea >/dev/null 2>&1
assert_file "scope idea: a JetBrains row" "$sb3/jetbrains-config/IntelliJIdea2025.3/colors/a.icls"
assert_no_file "scope idea: no tool row" "$sb3/.claude/settings.json"
sb4="$tmp/sb4"; mkdir -p "$sb4"
ai_sandbox_seed_copy "$sb4" settings tools >/dev/null 2>&1
assert_file "scope tools: a tool row" "$sb4/.claude/settings.json"
assert_no_file "scope tools: no JetBrains row" "$sb4/jetbrains-config"

# --- the expanded rows, for the callers that back up or remove
rows=$(ai_sandbox_seed_sandbox_paths "$sb" login | tr '\0' '\n')
assert_contains "sandbox paths: a login file present" "$rows" '.claude/.credentials.json'
assert_contains "sandbox paths: a glob expanded in the sandbox directory" "$rows" 'jetbrains-config/CLion2025.2/clion.key'
assert_eq "sandbox paths: nothing for a row the sandbox lacks" "$(printf '%s\n' "$rows" | grep -c 'Cookies$')" 1

# --- I3c: a link a sandbox placed at a destination is replaced, never written through
trap_="$tmp/trap"; mkdir -p "$trap_"; printf 'precious' > "$trap_/file"
sb5="$tmp/sb5"; mkdir -p "$sb5/.claude" "$sb5/.codex"
ln -s "$trap_/file" "$sb5/.claude/settings.json"
ln -s "$trap_" "$sb5/antigravity-data"
ai_sandbox_seed_copy "$sb5" settings >/dev/null 2>"$err"
assert_eq "a link at a file destination: the trap's file is unchanged" "$(cat "$trap_/file")" precious
assert_eq "the link at the destination was replaced by the file" "$([ -L "$sb5/.claude/settings.json" ] && echo link || echo file)" file
assert_eq "a link in place of a directory: nothing written into the trap" "$(ls -A "$trap_" | paste -sd' ')" file
assert_contains "the refusal is named on standard error" "$(cat "$err")" 'refused'

# --- a second call is the same
ai_sandbox_seed_copy "$sb" settings >/dev/null 2>&1
assert_eq "copy is repeatable" "$(jq_ "$sb/.claude/settings.json")" '{"model": "opus", "theme": "dark", "voice": {"enabled": true, "mode": "tap"}}'

rm -rf "$tmp"
finish
