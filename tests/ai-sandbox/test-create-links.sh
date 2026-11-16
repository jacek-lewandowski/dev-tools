#!/usr/bin/env bash
# create-ai-sandbox.sh writes nothing through a link a sandbox placed in a bind source (O9).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
create() { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/create.out" 2>"$tmp/create.err" </dev/null; }

# A host with SDKMAN (two versions, a default, a gradle), a legacy brain file, a project with a generated .agentrules.
host() {
    fake_home >/dev/null; tmp=$FAKE_HOME_DIR
    . "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
    proj="$tmp/work/p"; mkdir -p "$proj"
    local SD="$HOME/.sdkman"
    mkdir -p "$SD/bin" "$SD/libexec" "$SD/src" "$SD/contrib" "$SD/etc" "$SD/var" \
        "$SD/candidates/java/21.0.8-tem/bin" "$SD/candidates/java/17.0.16-tem/bin" "$SD/candidates/gradle/9.6.1/bin"
    echo init > "$SD/bin/sdkman-init.sh"; echo fn > "$SD/src/sdkman-default.sh"
    echo 'sdkman_auto_answer=false' > "$SD/etc/config"; echo 5.20.0 > "$SD/var/version"
    ln -s 21.0.8-tem "$SD/candidates/java/current"
    mkdir -p "$HOME/.gemini/antigravity-ide/brain"; printf 'legacy\n' > "$HOME/.gemini/antigravity-ide/brain/CLAUDE.md"
    printf '# Agent Environment Context\nold\n' > "$proj/.agentrules"
    trap_dir="$tmp/trap"; mkdir -p "$trap_dir/dir"; printf 'trap\n' > "$trap_dir/file"; printf 'trap\n' > "$trap_dir/dir/inner"
    dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
}

# <label> <path under the sandbox dir, or an absolute one> <dir|file> <after|before: planted after the first create, or before it> <named: yes|no>
plant_case() {
    local label=$1 path=$2 kind=$3 when=$4 named=$5 t0 rc target
    host
    case $path in /*) full=$path ;; *) full="$dir/$path" ;; esac
    if [ "$kind" = dir ]; then target="$trap_dir/dir"; else target="$trap_dir/file"; fi
    if [ "$when" = after ]; then create; rm -rf "$full"; else mkdir -p "$(dirname "$full")"; fi
    mkdir -p "$(dirname "$full")"; ln -s "$target" "$full"
    t0=$(snap "$trap_dir")
    create; rc=$?
    assert_eq "O9 $label: create exits 0" "$rc" 0
    assert_eq "O9 $label: the trap is unchanged" "$(snap "$trap_dir")" "$t0"
    if [ "$named" = yes ]; then assert_contains "O9 $label: the skipped write is named on standard error" "$(cat "$tmp/create.err")" "${path##*/}"; fi
}
plant_case "farm bin" sdkman/bin dir after no
plant_case "farm src" sdkman/src dir after no
plant_case "farm etc" sdkman/etc dir after yes
plant_case "farm etc/config" sdkman/etc/config file after no
plant_case "farm var" sdkman/var dir after yes
plant_case "farm candidates/java" sdkman/candidates/java dir after yes
plant_case "farm candidates/java/21.0.8-tem" sdkman/candidates/java/21.0.8-tem dir after no
plant_case "farm candidates/java/current" sdkman/candidates/java/current dir after no
plant_case ".claude/projects" .claude/projects dir after yes
host; create; rm -f "$dir/.antigravity-ide/argv.json"; mkdir -p "$dir/.antigravity"; printf '{}\n' > "$dir/.antigravity/argv.json"
ln -s "$trap_dir/file" "$dir/.antigravity-ide/argv.json.dangling"; rm -f "$dir/.antigravity-ide/argv.json.dangling"
ln -s "$trap_dir/dir/absent" "$dir/.antigravity-ide/argv.json"; t0=$(snap "$trap_dir"); create; rc=$?
assert_eq "O9 argv.json (absent target): create exits 0" "$rc" 0
assert_eq "O9 argv.json (absent target): the trap is unchanged" "$(snap "$trap_dir")" "$t0"
host
mkdir -p "$HOME/.gemini/antigravity-ide/brain"; ln -s "$trap_dir/dir" "$HOME/.gemini/antigravity-ide/brain/CLAUDE.md.superseded"; t0=$(snap "$trap_dir"); create; rc=$?
assert_eq "O9 legacy brain .superseded: create exits 0" "$rc" 0
assert_eq "O9 legacy brain .superseded: the trap is unchanged" "$(snap "$trap_dir")" "$t0"
assert_eq "O9 legacy brain .superseded: the legacy file was retired" "$([ -f "$HOME/.gemini/antigravity-ide/brain/CLAUDE.md.superseded" ] && [ ! -L "$HOME/.gemini/antigravity-ide/brain/CLAUDE.md.superseded" ] && echo yes)" yes
host
ln -s "$trap_dir/dir" "$proj/.agentrules.superseded"; t0=$(snap "$trap_dir"); create; rc=$?
assert_eq "O9 .agentrules.superseded: create exits 0" "$rc" 0
assert_eq "O9 .agentrules.superseded: the trap is unchanged" "$(snap "$trap_dir")" "$t0"
finish
