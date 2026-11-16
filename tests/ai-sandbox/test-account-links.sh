#!/usr/bin/env bash
# ai-sandbox-account refresh and reset write nothing through a link a sandbox placed in its state (O10).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
create() { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start --host-logins "$proj" >>"$tmp/out" 2>&1 || true; }
acct() { ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" "$@" 2>&1 ); }

host() {
    fake_home >/dev/null; tmp=$FAKE_HOME_DIR
    . "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
    proj="$tmp/work/p"; mkdir -p "$proj"
    mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/Claude/Local Storage"
    echo host-token > "$HOME/.claude/.credentials.json"; echo host-file > "$HOME/.config/Claude/Local Storage/file"; echo '{"a":"host"}' > "$HOME/.claude.json"
    echo '{"theme":"host"}' > "$HOME/.claude/settings.json"
    echo host-codex > "$HOME/.codex/auth.json"
    create; dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
    trap_dir="$tmp/trap"; mkdir -p "$trap_dir/dir"; printf 'trap\n' > "$trap_dir/file"; printf 'trap\n' > "$trap_dir/dir/inner"
}

# <label> <command> <path under the sandbox dir> <dir|file>
case_of() {
    local label=$1 cmd=$2 path=$3 kind=$4 t0 out rc target
    host
    if [ "$kind" = dir ]; then target="$trap_dir/dir"; else target="$trap_dir/file"; fi
    rm -rf "${dir:?}/$path"; ln -s "$target" "$dir/$path"
    t0=$(snap "$trap_dir")
    out=$(acct "$cmd" --yes); rc=$?
    assert_eq "O10 $label: $cmd exits 0" "$rc" 0
    assert_eq "O10 $label: $cmd leaves the trap unchanged" "$(snap "$trap_dir")" "$t0"
}
case_of "a login directory row (claude-data/Local Storage)" refresh "claude-data/Local Storage" dir
case_of "a login file row (.claude/.credentials.json)" refresh .claude/.credentials.json file
case_of "the projects mount (.claude/projects)" refresh .claude/projects dir
case_of "a login directory row (claude-data/Local Storage)" reset "claude-data/Local Storage" dir
case_of "a login file row (.claude/.credentials.json)" reset .claude/.credentials.json file
case_of "a settings row (.claude/settings.json)" reset .claude/settings.json file
case_of "the projects mount (.claude/projects)" reset .claude/projects dir
case_of "the Codex default (.codex/config.toml)" reset .codex/config.toml file
case_of "agy's settings (.gemini/antigravity-cli/settings.json)" reset .gemini/antigravity-cli/settings.json file
case_of "agy's directory (.gemini/antigravity-cli)" reset .gemini/antigravity-cli dir
case_of "the brain's parent (.gemini/antigravity)" reset .gemini/antigravity dir
# a link at the mount's parent is refused, named on standard error, and left (the sandbox's own business)
host; rm -rf "${dir:?}/.claude/projects"; ln -s "$trap_dir/dir" "$dir/.claude/projects"
assert_contains "O10 reset names the refusal at .claude/projects" "$(acct reset --yes)" 'refused'

# Without links the result is what test-account.sh expects: the host's logins arrive, the mounts stay
host
mkdir -p "$dir/.claude/projects/mine"; echo mine > "$dir/.claude/projects/mine/keep"
echo changed > "$HOME/.claude/.credentials.json"; echo changed-file > "$HOME/.config/Claude/Local Storage/file"
acct refresh --yes >/dev/null
assert_eq "refresh pulls the host token" "$(cat "$dir/.claude/.credentials.json")" changed
assert_eq "refresh pulls a login directory's file" "$(cat "$dir/claude-data/Local Storage/file")" changed-file
assert_file "refresh keeps the projects mount" "$dir/.claude/projects/mine/keep"
# I-1: a name a sandbox chose reaches the host's stderr without control characters, whichever
# command prints it (nofollow's refusal for reset, the backup's skip line for refresh)
for cmd in reset refresh; do
    host
    evil=$'P\e]0;PWNED\a'
    mkdir -p "$trap_dir/jb"; : > "$trap_dir/jb/x.key"
    mkdir -p "$dir/jetbrains-config"; ln -s "$trap_dir/jb" "$dir/jetbrains-config/$evil"
    out=$(acct "$cmd" --yes)
    assert_contains "I-1 $cmd still reports the planted name" "$out" 'PWNED'
    case $out in *$'\e'*|*$'\a'*) bad=1 ;; *) bad=0 ;; esac
    assert_eq "I-1 $cmd prints no ESC or BEL from a sandbox name" "$bad" 0
done

finish
