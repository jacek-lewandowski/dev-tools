#!/usr/bin/env bash
# What create seeds, by mode (phase 7, O1, O2, O10): no authenticating store seeded without
# --host-logins. A fixture home holds a marker unique to each path (its own text) and, in every
# json and xml file, one marker per key; the sandbox must hold exactly the markers the mode lets
# through.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
CREATE="$REPO_ROOT/bin/ai/create-ai-sandbox.sh"
JB=.config/JetBrains/P; AG=.config/Antigravity; AGI='.config/Antigravity IDE'; CD=.config/Claude

mk() {   # <path under $HOME>: a file whose content is its own marker
    mkdir -p "$(dirname "$HOME/$1")"; printf 'MARK:%s\n' "$1" > "$HOME/$1"
}
mkjson() {   # <path> <allowed,keys> <dropped,keys> [comment]: key paths use '/', '[]/k' makes an array of records
    python3 -I - "$HOME/$1" "$1" "$2" "$3" "${4:-}" <<'PY'
import json, sys
f, rel, allowed, dropped, style = sys.argv[1:6]
keys = [k for k in (allowed + "," + dropped).split(",") if k]
if keys[0].startswith("[]/"):
    rec = {k.split("/", 1)[1]: "MARK:%s#%s" % (rel, k) for k in keys}
    rec["args"] = {"t": "MARK:%s#args" % rel}
    doc = [rec, {"args": 1}]
else:
    doc = {}
    for k in keys:
        cur, parts = doc, k.split("/")
        for p in parts[:-1]:
            cur = cur.setdefault(p, {})
        cur[parts[-1]] = "MARK:%s#%s" % (rel, k)
text = json.dumps(doc, indent=2)
if style == "comment":
    text = "// hand edited\n" + text[:-1].rstrip() + ",\n}\n"
open(f, "w").write(text + "\n")
PY
}
mkxml() {   # <path> <allowed components> <dropped components>
    local f="$HOME/$1" c; mkdir -p "$(dirname "$f")"
    { echo '<application>'
      for c in $2 $3; do echo "  <component name=\"$c\"><option name=\"v\" value=\"MARK:$1#$c\" /></component>"; done
      echo '</application>'; } > "$f"
}

# logins (O2's list)
for f in .claude/.credentials.json .codex/auth.json .gemini/oauth_creds.json .gemini/google_accounts.json \
         .gemini/antigravity-cli/antigravity-oauth-token \
         $CD/Cookies "$CD/Local State" "$CD/Trust Tokens" $CD/config.json $CD/claude_desktop_config.json \
         "$CD/Local Storage/l" "$CD/IndexedDB/i" "$CD/Session Storage/s" \
         $AG/Cookies "$AG/Trust Tokens" "$AG/Local Storage/l" "$AG/Session Storage/s" $AG/User/globalStorage/state.vscdb \
         "$AGI/Cookies" "$AGI/Trust Tokens" "$AGI/Local Storage/l" "$AGI/Session Storage/s" "$AGI/User/globalStorage/state.vscdb" \
         .gemini/config/mcp_config.json .gemini/antigravity/mcp_config.json .gemini/antigravity-ide/mcp_config.json \
         $JB/idea.key $JB/x.license; do mk "$f"; done
# history, project lists, other projects' data, the browser profile (in neither list)
for f in .claude/history.jsonl .claude/projects/other/x.jsonl .claude/file-history/f .claude/shell-snapshots/s \
         .claude/session-env/e .claude/sessions/a.key .claude/daemon/control.key \
         .codex/state_5.sqlite .gemini/projects.json .gemini/trustedFolders.json \
         .gemini/antigravity-browser-profile/Default/Cookies .gemini/antigravity-cli/history.jsonl \
         .gemini/antigravity/knowledge/k .gemini/antigravity/brain/b .gemini/antigravity/conversations/c \
         .gemini/antigravity-ide/knowledge/k $CD/git-worktrees.json $AG/User/History/h $AG/Backups/b \
         $JB/options/recentProjects.xml $JB/options/trusted-paths.xml; do mk "$f"; done
# dropped settings rows, and a name no row holds in each directory the base's seed copied
for f in .claude/agents/a.md .codex/agents/a.toml .gemini/agents/a.md .antigravity/argv.json .antigravity-ide/argv.json \
         $AG/User/snippets/s.json "$AGI/User/snippets/s.json" $JB/templates/t.xml $JB/idea64.vmoptions \
         $JB/options/terminal.xml $JB/options/advancedSettings.xml $JB/options/ide.general.xml .codex/config.toml \
         .claude/noname.txt .codex/noname.txt .gemini/noname.txt .gemini/config/noname.txt .gemini/antigravity/noname.txt \
         .gemini/antigravity-cli/noname.txt .antigravity/noname.txt .antigravity-ide/noname.txt \
         $AG/noname.txt "$AGI/noname.txt" $CD/noname.txt $JB/noname.txt $JB/options/noname.txt; do mk "$f"; done
# the host's Codex configuration: a marker and the host's own project list (O12)
printf 'MARK:codex-config\nmodel = "MARK:model"\n[projects."/host/other/path"]\ntrust_level = "trusted"\n' > "$HOME/.codex/config.toml"
# settings rows: whole, links
WHOLE=(.codex/AGENTS.md .gemini/config/AGENTS.md $JB/codestyles/c.xml $JB/colors/c.icls $JB/keymaps/k.xml $JB/disabled_plugins.txt)
for f in "${WHOLE[@]}"; do mk "$f"; done
mkdir -p "$HOME/.agents/skills/shared"
for t in claude codex gemini; do mk ".$t/skills/own/SKILL.md"; ln -s ../../.agents/skills/shared "$HOME/.$t/skills/shared"; done
# settings rows: json and xml, allowed and dropped keys by name
CS_A=model,modelSettings,language,theme,editorMode,autoCompactEnabled,idleCompaction,autoContinueAtUsageLimit,agentPushNotifEnabled,inputNeededNotifEnabled,remoteControlAtStartup,voice,voiceEnabled
mkjson .claude/settings.json "$CS_A" env,apiKeyHelper,hooks,statusLine,permissions,enabledPlugins,extraKnownMarketplaces,mcpServers,nokey
mkjson .gemini/settings.json general/enablePromptCompletion,general/previewFeatures,security/auth/selectedType tools,context,mcpServers,general/other,security/auth/token
mkjson .gemini/antigravity-cli/settings.json colorScheme permissions,trustedWorkspaces
ED_A=editor.fontSize,diffEditor.ignoreTrimWhitespace,workbench.colorTheme,workbench.iconTheme,files.autoSave,terminal.integrated.fontSize,debug.console.fontSize,scm.inputFontSize,git.autofetch,git.confirmSync,json.schemaDownload.enable,redhat.telemetry.enabled,extensions.ignoreRecommendations,markdown-preview-enhanced.previewTheme,python.languageServer,playwright.reuseBrowser,playwright.showTrace,claudeCode.preferredLocation
ED_D=terminal.integrated.env.linux,dart.flutterSdkPath,'[markdown]/editor.wordWrap',nokey
mkjson $AG/User/settings.json "$ED_A" "$ED_D" comment
mkjson "$AGI/User/settings.json" "$ED_A" "$ED_D"
mkjson $AG/User/keybindings.json '[]/key,[]/command,[]/when' ''
mkdir -p "$HOME/$AGI/User"
printf '[{"key": "ctrl+a" "broken"\n' > "$HOME/$AGI/User/keybindings.json"
mkxml $JB/options/editor.xml "EditorSettings CodeInsightSettings" InlineCompletionOnboarding
mkxml $JB/options/editor-font.xml DefaultFont X1
mkxml $JB/options/console-font.xml ConsoleFont X2
mkxml $JB/options/terminal-font.xml TerminalFontOptions X3
mkxml $JB/options/laf.xml LafManager X4
mkxml $JB/options/ui.lnf.xml UISettings DependencyUISettings
mkxml $JB/options/colors.scheme.xml EditorColorsManagerImpl X5
mkxml $JB/options/keymapFlags.xml KeymapFlagsStorage X6
# .claude.json: three allowed keys, two project maps
printf '{"oauthAccount": {"e": "MARK:.claude.json#oauthAccount"}, "userID": "MARK:.claude.json#userID", "hasCompletedOnboarding": true, "projects": {"/x": "MARK:.claude.json#projects"}, "githubRepoPaths": {"r": "MARK:.claude.json#githubRepoPaths"}}\n' > "$HOME/.claude.json"

# The markers the default seed lets through: the whole rows, and the allowed key of each cut file
allowed_json() {   # <path> <allowed,keys>
    local k; for k in ${2//,/ }; do echo "MARK:$1#$k"; done
}
DEFAULT=$( { for f in "${WHOLE[@]}"; do echo "MARK:$f"; done
    allowed_json .claude/settings.json "$CS_A"
    allowed_json .gemini/settings.json general/enablePromptCompletion,general/previewFeatures,security/auth/selectedType
    allowed_json .gemini/antigravity-cli/settings.json colorScheme
    allowed_json $AG/User/settings.json "$ED_A"; allowed_json "$AGI/User/settings.json" "$ED_A"
    allowed_json $AG/User/keybindings.json '[]/key,[]/command,[]/when'
    for c in EditorSettings CodeInsightSettings; do echo "MARK:$JB/options/editor.xml#$c"; done
    echo "MARK:$JB/options/editor-font.xml#DefaultFont" "MARK:$JB/options/console-font.xml#ConsoleFont" \
         "MARK:$JB/options/terminal-font.xml#TerminalFontOptions" "MARK:$JB/options/laf.xml#LafManager" \
         "MARK:$JB/options/ui.lnf.xml#UISettings" "MARK:$JB/options/colors.scheme.xml#EditorColorsManagerImpl" \
         "MARK:$JB/options/keymapFlags.xml#KeymapFlagsStorage" | tr ' ' '\n'
    } | LC_ALL=C sort -u )
LOGINS=$( { for f in .claude/.credentials.json .codex/auth.json .gemini/oauth_creds.json .gemini/google_accounts.json \
         .gemini/antigravity-cli/antigravity-oauth-token \
         $CD/Cookies "$CD/Local State" "$CD/Trust Tokens" $CD/config.json $CD/claude_desktop_config.json \
         "$CD/Local Storage/l" "$CD/IndexedDB/i" "$CD/Session Storage/s" \
         $AG/Cookies "$AG/Trust Tokens" "$AG/Local Storage/l" "$AG/Session Storage/s" $AG/User/globalStorage/state.vscdb \
         "$AGI/Cookies" "$AGI/Trust Tokens" "$AGI/Local Storage/l" "$AGI/Session Storage/s" "$AGI/User/globalStorage/state.vscdb" \
         .gemini/config/mcp_config.json .gemini/antigravity/mcp_config.json .gemini/antigravity-ide/mcp_config.json \
         $JB/idea.key $JB/x.license; do echo "MARK:$f"; done
    for k in oauthAccount userID; do echo "MARK:.claude.json#$k"; done; } | LC_ALL=C sort -u )

markers() {   # the markers found below a sandbox directory, one per line, sorted
    grep -rhoE 'MARK:[^"<>]+' "$1" 2>/dev/null | LC_ALL=C sort -u
}
idea="$tmp/idea-IU"; mkdir -p "$idea/bin"; printf '#!/bin/sh\nexit 0\n' > "$idea/bin/idea"; chmod +x "$idea/bin/idea"
export IDEA_HOST_DIR="$idea"
mkp() { local p="$tmp/work/$1"; mkdir -p "$p"; echo "$p"; }
run() {   # <project> [options]
    local p=$1; shift
    bash "$CREATE" --display=none --no-start "$@" "$p" >"$tmp/out" 2>"$tmp/err"; echo $?
}
dir_of() { echo "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$1")-agent"; }
diffset() { diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | head -8 | paste -sd';'; }

# --- O1: no authenticating store seeded without --host-logins
p1=$(mkp p1); d1=$(dir_of "$p1")
assert_eq "create without options exits 0" "$(run "$p1")" 0
assert_eq "no authenticating store seeded without --host-logins: exactly the settings markers are in the sandbox" \
    "$(diffset "$(markers "$d1")" "$DEFAULT")" ""
assert_eq ".claude.json is {}" "$(tr -d ' \n' < "$d1/.claude.json")" '{}'
assert_eq ".env records the inside mode" "$(ai_sandbox_env_value "$d1" SANDBOX_HOST_LOGINS)" 0
assert_eq "a whole row is byte-identical" "$(cmp "$HOME/.codex/AGENTS.md" "$d1/.codex/AGENTS.md" && echo same)" same
assert_link "a links row keeps the link and its text" "$d1/.claude/skills/shared" ../../.agents/skills/shared
assert_link "codex skills the same" "$d1/.codex/skills/shared" ../../.agents/skills/shared
assert_link "gemini skills the same" "$d1/.gemini/skills/shared" ../../.agents/skills/shared
assert_no_file "a skill directory is not copied (U-d (a))" "$d1/.claude/skills/own"
assert_eq "the host's Codex configuration is not copied: no host marker in .codex/config.toml" "$(grep -c -e 'MARK:' -e '/host/other/path' "$d1/.codex/config.toml")" 0
assert_eq "the cut files parse (the one with comments included)" \
    "$(for f in .claude/settings.json .gemini/settings.json .gemini/antigravity-cli/settings.json antigravity-data/User/settings.json antigravity-ide-data/User/settings.json antigravity-data/User/keybindings.json; do python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$d1/$f" || echo "bad $f"; done)" ""
assert_no_file "the file that does not parse is absent" "$d1/antigravity-ide-data/User/keybindings.json"
assert_eq "and standard error names it once" "$(grep -c 'keybindings.json' "$tmp/err")" 1
assert_eq "the agy settings hold colorScheme and the project's trust only (O10, O12)" "$(python3 -I -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$d1/.gemini/antigravity-cli/settings.json")" "['colorScheme', 'trustedWorkspaces']"
assert_no_file "no login log without logins" "$d1/host-logins.log"
run "$p1" >/dev/null
assert_eq "a second create changes none of this" "$(diffset "$(markers "$d1")" "$DEFAULT")" ""
assert_eq ".env still 0" "$(ai_sandbox_env_value "$d1" SANDBOX_HOST_LOGINS)" 0

# --- O12: the Codex default, written not copied
codex_want() { printf 'approval_policy = "on-request"\napprovals_reviewer = "auto_review"\nsandbox_mode = "workspace-write"\n\n[projects."%s"]\ntrust_level = "trusted"\n' "$1"; }
proj_of() { ai_sandbox_env_value "$1" SANDBOX_PROJECT_DIR; }
assert_eq "O12 the default sandbox has exactly the four keys and the one project table" "$(cat "$d1/.codex/config.toml")" "$(codex_want "$(proj_of "$d1")")"
assert_eq "O12 one projects table, naming this project" "$(grep -c '^\[projects\.' "$d1/.codex/config.toml")" 1
assert_eq "O12 no default_permissions key" "$(grep -c default_permissions "$d1/.codex/config.toml")" 0
assert_eq "O12 agy trust is exactly the project's entry and the host's colorScheme" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["trustedWorkspaces"], d["colorScheme"])' "$d1/.gemini/antigravity-cli/settings.json")" "['$(proj_of "$d1")'] MARK:.gemini/antigravity-cli/settings.json#colorScheme"
assert_eq "O12 no host trustedWorkspaces marker in the sandbox" "$(grep -rlF 'trustedWorkspaces#' "$d1" | wc -l)" 0
echo 'approval_policy = "never"  # changed inside' > "$d1/.codex/config.toml"
run "$p1" >/dev/null
assert_eq "O12 a re-create leaves a file the sandbox changed byte-identical" "$(cat "$d1/.codex/config.toml")" 'approval_policy = "never"  # changed inside'
rm -f "$d1/.codex/config.toml"
run "$p1" >/dev/null
assert_no_file "O12 a re-create of a seeded sandbox whose file is absent writes none" "$d1/.codex/config.toml"
( cd "$p1" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" reset --yes >/dev/null 2>&1 )
assert_eq "O12 reset writes it anew" "$(cat "$d1/.codex/config.toml")" "$(codex_want "$(proj_of "$d1")")"
assert_eq "O12 reset also writes agy's trust" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["trustedWorkspaces"])' "$d1/.gemini/antigravity-cli/settings.json")" "['$(proj_of "$d1")']"
assert_contains "O12 the lib function carries the reads-outside marker" "$(grep -B1 -A8 '^# The Codex default' "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh")" '# reads-outside: Codex'

# --- O2: --host-logins copies exactly the two lists
p2=$(mkp p2); d2=$(dir_of "$p2")
assert_eq "create --host-logins exits 0" "$(run "$p2" --host-logins)" 0
assert_eq "the markers are the settings markers and the login markers, nothing else" \
    "$(diffset "$(markers "$d2")" "$(printf '%s\n%s\n' "$DEFAULT" "$LOGINS" | LC_ALL=C sort -u)")" ""
assert_eq ".claude.json holds exactly the three keys" "$(python3 -I -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))))' "$d2/.claude.json")" "['hasCompletedOnboarding', 'oauthAccount', 'userID']"
assert_eq "O12 a --host-logins sandbox has the default too" "$(cat "$d2/.codex/config.toml")" "$(printf 'approval_policy = "on-request"\napprovals_reviewer = "auto_review"\nsandbox_mode = "workspace-write"\n\n[projects."%s"]\ntrust_level = "trusted"\n' "$(ai_sandbox_env_value "$d2" SANDBOX_PROJECT_DIR)")"
assert_eq ".env records the host mode" "$(ai_sandbox_env_value "$d2" SANDBOX_HOST_LOGINS)" 1
assert_contains "create says I1 does not hold" "$(cat "$tmp/err")" 'I1 does not hold'
assert_eq "credentials keep their mode" "$(stat -c %a "$d2/.claude/.credentials.json")" "$(stat -c %a "$HOME/.claude/.credentials.json")"
log2=$(cut -f2- "$d2/host-logins.log" | LC_ALL=C sort)
assert_contains "host-logins.log names the credentials" "$log2" '.claude/.credentials.json'
assert_contains "and the licence" "$log2" 'jetbrains-config/P/idea.key'
assert_contains "and .claude.json" "$log2" '.claude.json'
assert_eq "no settings row in the log" "$(printf '%s\n' "$log2" | grep -c -e 'settings.json' -e AGENTS -e codestyles)" 0
assert_eq "every log line has a date" "$(grep -vcE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$d2/host-logins.log")" 0
# an unreadable-in-part directory row is logged with a mark (L5)
chmod u-w "$d2/claude-data/Local Storage" 2>/dev/null
echo changed > "$HOME/$CD/Local Storage/l"
mkdir -p "$HOME/$CD/Local Storage/sub"; echo more > "$HOME/$CD/Local Storage/sub/m"
out=$(ai_sandbox_seed_copy "$d2" login 2>/dev/null)
chmod u+w "$d2/claude-data/Local Storage"
assert_contains "a partly written directory row is printed with a mark" "$out" "$(printf 'claude-data/Local Storage\tpartial')"
assert_contains "a complete row is printed bare" "$out" '.codex/auth.json'

# --- O10: a host without agy settings (deauville) gets no file
p3=$(mkp p3); d3=$(dir_of "$p3")
mv "$HOME/.gemini/antigravity-cli/settings.json" "$tmp/agy-settings.json"
run "$p3" >/dev/null
assert_eq "no agy settings on the host: the file holds only the project's trust (U-e (a))" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])))' "$d3/.gemini/antigravity-cli/settings.json")" "{'trustedWorkspaces': ['$(ai_sandbox_env_value "$d3" SANDBOX_PROJECT_DIR)']}"
printf '{"permissions": {"allow": ["MARK:p"]}, "trustedWorkspaces": ["MARK:t"]}\n' > "$HOME/.gemini/antigravity-cli/settings.json"
p4=$(mkp p4); d4=$(dir_of "$p4"); run "$p4" >/dev/null
assert_eq "a file with only permissions and trustedWorkspaces: only the project's own trust (U-e (a))" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])))' "$d4/.gemini/antigravity-cli/settings.json")" "{'trustedWorkspaces': ['$(ai_sandbox_env_value "$d4" SANDBOX_PROJECT_DIR)']}"

# --- a host with no tool state copies nothing, and the directories still exist
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
export IDEA_HOST_DIR="$tmp/absent"
p5="$tmp/work/p5"; mkdir -p "$p5"; d5=$(dir_of "$p5")
assert_eq "an empty host: create exits 0" "$(run "$p5")" 0
assert_file "the state directories are still made" "$d5/.claude"
assert_eq "and .claude.json is {}" "$(tr -d ' \n' < "$d5/.claude.json")" '{}'

rm -rf "$tmp"
finish
