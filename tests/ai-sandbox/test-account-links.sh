#!/usr/bin/env bash
# ai-sandbox-account refresh and reset write nothing through a link a sandbox placed in its state (O10).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
create() { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >>"$tmp/out" 2>&1 || true; }
acct() { ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" "$@" 2>&1 ); }

host() {
    fake_home >/dev/null; tmp=$FAKE_HOME_DIR
    . "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
    proj="$tmp/work/p"; mkdir -p "$proj"
    mkdir -p "$HOME/.claude/sub" "$HOME/.codex"
    echo host-token > "$HOME/.claude/.credentials.json"; echo host-file > "$HOME/.claude/sub/file"; echo '{"a":"host"}' > "$HOME/.claude.json"
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
case_of "a directory the host's copy holds (.claude/sub)" refresh .claude/sub dir
case_of "a file the host's copy holds (.claude/.credentials.json)" refresh .claude/.credentials.json file
case_of "the projects mount (.claude/projects)" refresh .claude/projects dir
case_of "a directory the host's copy holds (.claude/sub)" reset .claude/sub dir
case_of "the projects mount (.claude/projects)" reset .claude/projects dir
assert_eq "O10 reset: .claude/projects is a real directory again" "$([ -d "$dir/.claude/projects" ] && [ ! -L "$dir/.claude/projects" ] && echo yes)" yes

# Without links the result is what test-account.sh expects: the host's files arrive, the mounts stay
host
mkdir -p "$dir/.claude/projects/mine"; echo mine > "$dir/.claude/projects/mine/keep"; echo stale > "$dir/.claude/stale"
acct refresh --yes >/dev/null
assert_eq "refresh pulls the host token" "$(cat "$dir/.claude/.credentials.json")" host-token
assert_eq "refresh pulls a subdirectory's file" "$(cat "$dir/.claude/sub/file")" host-file
assert_file "refresh keeps the projects mount" "$dir/.claude/projects/mine/keep"
assert_no_file "refresh removes a stale file" "$dir/.claude/stale"
finish
