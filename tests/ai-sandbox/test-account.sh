#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"
mkdir -p "$HOME/.claude" "$HOME/.codex"
echo 'host-token'   > "$HOME/.claude/.credentials.json"
echo '{"a":"host"}' > "$HOME/.claude.json"
echo 'host-codex'   > "$HOME/.codex/auth.json"

create() { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start --host-logins "$proj" >>"$tmp/out" 2>&1 || true; }
create
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"

assert_file "seed marker written" "$dir/.seeded"
assert_eq   "claude creds seeded" "$(cat "$dir/.claude/.credentials.json")" 'host-token'
assert_eq   "codex creds seeded"  "$(cat "$dir/.codex/auth.json")"          'host-codex'

# Log in to a different account inside the sandbox, then re-run the script.
echo 'project-token' > "$dir/.claude/.credentials.json"
echo 'project-codex' > "$dir/.codex/auth.json"
echo '{"a":"proj"}'  > "$dir/.claude.json"
create
assert_eq "claude login survives re-run" "$(cat "$dir/.claude/.credentials.json")" 'project-token'
assert_eq "codex login survives re-run"  "$(cat "$dir/.codex/auth.json")"          'project-codex'
assert_eq "claude.json survives re-run"  "$(cat "$dir/.claude.json")"              '{"a":"proj"}'

# ...even after the host re-authenticates to a different account.
echo 'host-token-2' > "$HOME/.claude/.credentials.json"
create
assert_eq "host re-auth does not leak in" "$(cat "$dir/.claude/.credentials.json")" 'project-token'

assert_contains "compose mounts .codex" "$(cat "$dir/docker-compose.yml")" \
    "$dir/.codex:$HOME/.codex"
assert_contains "image installs the codex CLI" \
    "$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")" '@openai/codex'

acct() { ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" "$@" 2>&1 ); }
assert_contains "status names the sandbox" "$(acct status)" "$(ai_sandbox_project_id "$proj")"
assert_contains "status reports seeding"   "$(acct status)" 'seeded'

# What the seed leaves out, refresh must leave out too: live-mounted paths,
# caches, and the bulk that lives in shared/.
mkdir -p "$HOME/.claude/projects/-home-other" "$HOME/.claude/downloads" "$HOME/.gemini/antigravity/brain"
echo host-rules > "$HOME/.claude/CLAUDE.md"
echo other      > "$HOME/.claude/projects/-home-other/x.jsonl"
echo bulk       > "$HOME/.claude/downloads/bin"
echo brain      > "$HOME/.gemini/antigravity/brain/CLAUDE.md"
mkdir -p "$dir/.claude/projects/mine" "$dir/.claude/downloads"
echo mine > "$dir/.claude/projects/mine/keep"
acct refresh --yes >/dev/null
assert_no_file "refresh excludes CLAUDE.md"        "$dir/.claude/CLAUDE.md"
assert_no_file "refresh excludes other projects"   "$dir/.claude/projects/-home-other"
assert_no_file "refresh excludes shared downloads" "$dir/.claude/downloads/bin"
assert_no_file "refresh excludes the brain"        "$dir/.gemini/antigravity/brain"
assert_file    "refresh keeps the projects mount"  "$dir/.claude/projects/mine/keep"
assert_file    "refresh keeps the downloads mount" "$dir/.claude/downloads"
assert_eq   "refresh pulls the host token" "$(cat "$dir/.claude/.credentials.json")" 'host-token-2'
assert_file "refresh leaves a backup"      "$dir/.credentials-backup"
assert_eq   "backup holds the replaced login" \
            "$(cat "$dir/.credentials-backup/.claude/.credentials.json")" 'project-token'

assert_file "create made status/ for the read-only bind" "$dir/status"
rm -rf "$dir/status"
acct reset --yes >/dev/null
assert_file "reset recreates status/, a bind source of every sandbox" "$dir/status"
assert_no_file "reset cleared claude creds" "$dir/.claude/.credentials.json"
assert_file    "reset kept the sandbox"     "$dir/docker-compose.yml"
# Bind sources must survive reset, or compose recreates them root-owned.
while IFS= read -r d; do
    [ -n "$d" ] && assert_file "reset kept bind source $d" "$dir/$d"
done < <(ai_sandbox_state_dirs)
# The nested ~/.claude/projects/<key> mount needs its parent to exist too, or
# Docker creates projects/ and projects/<key> root-owned on the next start and
# rm -rf of .claude fails ever after.
assert_file "reset kept .claude/projects for the nested mount" "$dir/.claude/projects"
create
assert_no_file "reset is not undone by a re-run" "$dir/.claude/.credentials.json"

# ---- T05: logins mode, status, refresh (O6), reset (O5), the legacy states (O4) ----
mk_host() {   # the host's login and non-login files, each holding the marker $1
    mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/Claude/Local Storage/leveldb"
    echo "$1-claude-cred" > "$HOME/.claude/.credentials.json"
    echo "{\"oauthAccount\":\"$1-account\"}" > "$HOME/.claude.json"
    echo "$1-codex-auth" > "$HOME/.codex/auth.json"
    echo "$1-local-storage" > "$HOME/.config/Claude/Local Storage/leveldb/000003.log"
    echo "{\"theme\":\"$1-theme\"}" > "$HOME/.claude/settings.json"
    echo "$1-history" > "$HOME/.claude/history.jsonl"
    echo "$1-session" > "$HOME/.codex/session.jsonl"
}
new_sb() {   # <name> [create options]: a sandbox of the current host, created then in $sd
    local n=$1; shift
    proj="$tmp/work/$n"; mkdir -p "$proj"
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$@" "$proj" >"$tmp/out.$n" 2>&1 </dev/null
    sd="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
}
login_markers() { local m; for m in "$1-claude-cred" "$1-account" "$1-codex-auth" "$1-local-storage"; do grep -rlF --exclude-dir=.credentials-backup -- "$m" "$sd" 2>/dev/null; done; }
snap_files() { ( cd "$sd" && find .claude .codex claude-data -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r sha256sum ); }

mk_host H1
new_sb r1 --host-logins
assert_contains "status: host mode" "$(acct status)" 'host'
assert_eq "status: the line says host, not '(not recorded)'" "$(acct status | grep -c 'not recorded')" 0
assert_eq "recorded 1" "$(ai_sandbox_env_value "$sd" SANDBOX_HOST_LOGINS)" 1
assert_ne "the first seed logged its login rows" "$(grep -c credentials.json "$sd/host-logins.log")" 0

# O6: the host's login files change; refresh brings exactly the logins
mk_host H2
echo '{"theme":"inside"}' > "$sd/.claude/settings.json"
log0=$(wc -l < "$sd/host-logins.log")
out=$(acct refresh --yes); r=$?
assert_eq "O6 refresh exits 0" "$r" 0
assert_ne "O6 the new login markers arrive" "$(login_markers H2 | sort -u | wc -l)" 0
assert_eq "O6 every login marker is the new one" "$(login_markers H1 | wc -l)" 0
assert_eq "O6 no history marker" "$(grep -rlF -- H2-history "$sd" | wc -l)" 0
assert_eq "O6 no no-row marker" "$(grep -rlF -- H2-session "$sd" | wc -l)" 0
assert_eq "O6 a settings row the sandbox changed stays as left" "$(cat "$sd/.claude/settings.json")" '{"theme":"inside"}'
assert_eq "O6 the backup holds the replaced login file" "$(cat "$sd/.credentials-backup/.claude/.credentials.json")" 'H1-claude-cred'
assert_eq "O6 and a login directory's file" "$(cat "$sd/.credentials-backup/claude-data/Local Storage/leveldb/000003.log")" 'H1-local-storage'
assert_gt() { TESTS_RUN=$((TESTS_RUN + 1)); if [ "$2" -gt "$3" ]; then _pass "$1"; else _fail "$1" "$2 is not above $3"; fi; }
assert_gt "O6 refresh appended to host-logins.log" "$(wc -l < "$sd/host-logins.log")" "$log0"

# O5: reset from the recorded-1 sandbox lists the logins ever copied, then removes them
echo inside-brain > "$sd/.gemini/keep-me" 2>/dev/null || true
out=$(acct reset --yes); r=$?
assert_eq "O5 reset exits 0" "$r" 0
assert_contains "O5 the listing names a login row" "$out" '.claude/.credentials.json'
assert_contains "O5 and a directory row" "$out" 'claude-data/Local Storage'
assert_eq "O5 no login marker is left" "$(login_markers H2 | wc -l)" 0
assert_eq "O5 the directory row is an empty directory" "$(ls -A "$sd/claude-data/Local Storage" | wc -l)" 0
assert_contains "O5 the settings row is there, as the host has it" "$(cat "$sd/.claude/settings.json")" 'H2-theme'
assert_eq "O5 .claude.json is {}" "$(cat "$sd/.claude.json")" '{}'
assert_eq "O5 the mode is 0" "$(ai_sandbox_env_value "$sd" SANDBOX_HOST_LOGINS)" 0
assert_eq "O5 once" "$(grep -c '^SANDBOX_HOST_LOGINS=' "$sd/.env")" 1
assert_eq "O5 a file outside the table is untouched" "$(cat "$sd/.gemini/keep-me" 2>/dev/null)" inside-brain
assert_contains "status: inside" "$(acct status)" 'inside'
out=$(acct refresh --yes); r=$?
assert_eq "O5 refresh is refused in the inside mode" "$r" 1
assert_contains "O5 and names the way to the host mode" "$out" 'create-ai-sandbox.sh'
assert_contains "O5 with --host-logins" "$out" '--host-logins'
assert_eq "O5 the refusal copied nothing" "$(login_markers H2 | wc -l)" 0

# O5: an answer other than y changes nothing
mk_host H3
new_sb r2 --host-logins
s0=$(snap_files); e0=$(cat "$sd/.env")
out=$(printf 'n\n' | ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" reset 2>&1 )); r=$?
assert_eq "O5 reset answered n exits 1" "$r" 1
assert_eq "O5 reset answered n changes no file" "$(snap_files)" "$s0"
assert_eq "O5 nor .env" "$(cat "$sd/.env")" "$e0"
mk_host H4
out=$(printf 'n\n' | ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" refresh 2>&1 )); r=$?
assert_eq "O6 refresh answered n exits 1" "$r" 1
assert_eq "O6 refresh answered n changes no file" "$(snap_files)" "$s0"

# O5: a reset whose mode write fails leaves .env as before; a second reset completes
mkdir -p "$tmp/failmv"; printf '#!/bin/sh\nfor a; do case $a in */.env) exit 1 ;; esac; done\nexec /bin/mv "$@"\n' > "$tmp/failmv/mv"; chmod +x "$tmp/failmv/mv"
e0=$(cat "$sd/.env")
out=$(cd "$proj" && PATH="$tmp/failmv:$PATH" bash "$REPO_ROOT/bin/ai/ai-sandbox-account" reset --yes 2>&1); r=$?
assert_eq "O5 a failed mode write makes reset exit 1" "$r" 1
assert_eq "O5 .env is as before" "$(cat "$sd/.env")" "$e0"
assert_eq "O5 still recorded 1" "$(ai_sandbox_env_value "$sd" SANDBOX_HOST_LOGINS)" 1
out=$(acct reset --yes); r=$?
assert_eq "O5 a second reset completes" "$r" 0
assert_eq "O5 and records 0" "$(ai_sandbox_env_value "$sd" SANDBOX_HOST_LOGINS)" 0

# O4/O5: an unrecorded sandbox (the base's seed): status, refresh copies, re-create leaves it, reset lists what is present
mk_host H5
new_sb r3 --host-logins
sed -i '/^SANDBOX_HOST_LOGINS=/d' "$sd/.env"
assert_contains "O4 status prints host (not recorded)" "$(acct status)" 'host (not recorded)'
mk_host H6
acct refresh --yes >/dev/null; r=$?
assert_eq "O4 refresh --yes works on an unrecorded sandbox" "$r" 0
assert_ne "O4 and copies the login rows" "$(login_markers H6 | wc -l)" 0
assert_eq "O4 and leaves the key absent" "$(ai_sandbox_env_value "$sd" SANDBOX_HOST_LOGINS)" ""
s0=$(snap_files)
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out.r3b" 2>&1 </dev/null
assert_eq "O4 a re-create leaves the key absent" "$(ai_sandbox_env_value "$sd" SANDBOX_HOST_LOGINS)" ""
assert_eq "O4 and the files the seed would copy byte-identical" "$(snap_files)" "$s0"
out=$(acct reset --yes)
assert_contains "O5 unrecorded: lists the present rows" "$out" '.codex/auth.json'
assert_contains "O5 with the sentence that they may have been made inside" "$out" 'made inside'
assert_eq "O5 unrecorded: no login marker is left" "$(login_markers H6 | wc -l)" 0
assert_eq "O5 unrecorded: records 0" "$(ai_sandbox_env_value "$sd" SANDBOX_HOST_LOGINS)" 0

rm -rf "$tmp"
finish
