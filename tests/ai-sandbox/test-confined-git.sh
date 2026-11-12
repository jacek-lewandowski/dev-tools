#!/usr/bin/env bash
# C-GIT: how the host runs git. ai_sandbox_host_git refuses a repository a
# sandbox can write and runs a host-owned one, with or without a repository
# discovered; ai_sandbox_writable_path says which is which.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

# Called directly, not via $(), so the exports reach the create run below.
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
git config --global user.email t@example.com; git config --global user.name t
git config --global init.defaultBranch main
REAL_GIT=$(command -v git)

# A git first on PATH that records where it ran and what it was asked, then
# runs the real one: "no git was started" is read from its log.
rec="$tmp/rec"; mkdir -p "$rec"; GITLOG="$tmp/git.log"; export GITLOG
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$PWD" "$*" >> "$GITLOG"\nexec %s "$@"\n' "$REAL_GIT" > "$rec/git"
chmod +x "$rec/git"
host_git() { PATH="$rec:$PATH" ai_sandbox_host_git "$@"; }

# --- a sandbox's directory as create-ai-sandbox.sh leaves it, and one as a
# --- hand-written compose file carrying every mount form the parser reads
proj="$tmp/work/proj"; mkdir -p "$proj"; touch "$HOME/.bashrc"
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/create.out" 2>&1 \
    || { echo "create failed:"; cat "$tmp/create.out"; }
sb=$(ai_sandbox_dir_for "$proj")
assert_file "a real create wrote the compose file" "$sb/docker-compose.yml"

ai_sandbox_writable_path "$proj" && r=0 || r=$?
assert_eq "writable: the project directory a real compose file mounts" "$r" 0
ai_sandbox_writable_path "$proj/sub/dir" && r=0 || r=$?
assert_eq "writable: a subdirectory of the project, not yet created" "$r" 0
ai_sandbox_writable_path "$sb/.claude" && r=0 || r=$?
assert_eq "writable: a state directory of the sandbox (real compose file)" "$r" 0
ai_sandbox_writable_path "$AI_SANDBOX_ROOT/shared/agent-skills/skills" && r=0 || r=$?
assert_eq "not writable: a shared store, mounted :ro in the real compose file" "$r" 1
ai_sandbox_writable_path "$AI_SANDBOX_ROOT/knowledge/main" && r=0 || r=$?
assert_eq "not writable: the host-owned knowledge checkout" "$r" 1
ai_sandbox_writable_path "$sb/knowledge-origin.git" && r=0 || r=$?
assert_eq "not writable: a name that only shares a prefix with a mounted one" "$r" 1

# a second sandbox: the knowledge clone read-write, a read-only mount, a stamp without a compose mount
sb2="$AI_SANDBOX_ROOT/other-12345678-agent"; mkdir -p "$sb2/knowledge" "$sb2/knowledge-origin.git" "$tmp/ro-src" "$tmp/rel/x"
cat > "$sb2/docker-compose.yml" <<COMPOSE
services:
  sandbox:
    environment:
      - "SOME=/not/a/mount:value"
    volumes:
      # a comment between items
      - "$sb2/knowledge:$HOME/knowledge"
      - "$tmp/ro-src:/ro:ro"
      - "./rel:/rel"
      - "named-volume:$HOME/.cache/x"
    mem_limit: "6g"
    volumes_not: []
volumes:
  named-volume:
    name: "named-volume"
    driver_opts:
      o: "$tmp/after-volumes"
COMPOSE
ai_sandbox_writable_path "$sb2/knowledge" && r=0 || r=$?
assert_eq "writable: the clone a compose file mounts read-write" "$r" 0
ai_sandbox_writable_path "$sb2/knowledge/sub" && r=0 || r=$?
assert_eq "writable: inside the clone" "$r" 0
ai_sandbox_writable_path "$tmp/ro-src" && r=0 || r=$?
assert_eq "not writable: a bind source mounted :ro" "$r" 1
ai_sandbox_writable_path "$sb2/rel/x" && r=0 || r=$?
assert_eq "writable: a relative bind source is read against the compose file" "$r" 0
ai_sandbox_writable_path "/not/a/mount" && r=0 || r=$?
assert_eq "not writable: an environment line is no mount" "$r" 1
ai_sandbox_writable_path "$tmp/after-volumes" && r=0 || r=$?
assert_eq "not writable: a line after the volumes section is no mount" "$r" 1
ai_sandbox_writable_path "$sb2/knowledge-origin.git" && r=0 || r=$?
assert_eq "not writable: the origin, which no compose file mounts read-write" "$r" 1

# a stamp names a project directory even where no compose file mounts it
sb3="$AI_SANDBOX_ROOT/third-87654321-agent"; mkdir -p "$sb3" "$tmp/work/stamped" "$tmp/work/envstamped"
printf '%s\n' "$tmp/work/stamped" > "$sb3/project-path"
printf 'SANDBOX_PROJECT_DIR=%s\n' "$tmp/work/envstamped" > "$sb3/.env"
ai_sandbox_writable_path "$tmp/work/stamped/deep/er" && r=0 || r=$?
assert_eq "writable: below a project the project-path stamp names" "$r" 0
ai_sandbox_writable_path "$tmp/work/envstamped" && r=0 || r=$?
assert_eq "writable: a project the .env stamp names" "$r" 0
ai_sandbox_writable_path "$tmp/work/unrelated" && r=0 || r=$?
assert_eq "not writable: a directory no stamp or mount names" "$r" 1

# links are resolved on both sides
mkdir -p "$tmp/links"; ln -sfn "$sb2/knowledge" "$tmp/links/into-clone"; ln -sfn "$tmp/ro-src" "$tmp/links/into-ro"
ai_sandbox_writable_path "$tmp/links/into-clone" && r=0 || r=$?
assert_eq "writable: a link that points into the clone" "$r" 0
ai_sandbox_writable_path "$tmp/links/into-ro" && r=0 || r=$?
assert_eq "not writable: a link that points at a read-only mount" "$r" 1
ln -sfn "$tmp/links" "$tmp/work/stamped/escape"
ai_sandbox_writable_path "$tmp/work/stamped/escape/into-ro" && r=0 || r=$?
assert_eq "not writable: a link planted in a project that leads out of it" "$r" 1
ai_sandbox_writable_path "$tmp/work/stamped/escape/into-clone" && r=0 || r=$?
assert_eq "writable: a link planted in a project that leads into a clone" "$r" 0

# --- ai_sandbox_host_git: refuses with 3 and starts no git; runs a host-owned repository
for bad in "$sb2/knowledge" "$tmp/links/into-clone" "$tmp/work/stamped/sub" "$proj"; do
    : > "$GITLOG"
    host_git "$bad" status >/dev/null 2>"$tmp/refuse.err"; rc=$?
    assert_eq "refused with 3: $(basename "$bad")" "$rc" 3
    assert_eq "no git started for: $(basename "$bad")" "$(wc -c < "$GITLOG" | tr -d ' ')" 0
done
assert_contains "the refusal says why" "$(cat "$tmp/refuse.err")" "a sandbox can write it"

mkdir -p "$AI_KNOWLEDGE_ROOT"; git init -q "$AI_KNOWLEDGE_ROOT/main"
git -C "$AI_KNOWLEDGE_ROOT/main" commit -q --allow-empty -m one
git init -q --bare "$sb/knowledge-origin.git"
: > "$GITLOG"
out=$(host_git "$AI_KNOWLEDGE_ROOT/main" log --format=%s); rc=$?
assert_eq "a host-owned checkout runs: exit" "$rc" 0
assert_eq "a host-owned checkout runs: output" "$out" one
assert_eq "git ran in the repository's own directory" "$(cut -d'|' -f1 "$GITLOG")" "$AI_KNOWLEDGE_ROOT/main"
host_git "$sb/knowledge-origin.git" rev-parse --is-bare-repository >"$tmp/bare.out" 2>&1; rc=$?
assert_eq "the origin beside a sandbox runs: exit" "$rc" 0
assert_eq "the origin beside a sandbox runs: output" "$(cat "$tmp/bare.out")" true
ln -sfn "$AI_KNOWLEDGE_ROOT/main" "$tmp/links/to-host-owned"
assert_eq "a link to a host-owned repository runs" "$(host_git "$tmp/links/to-host-owned" log --format=%s)" one
host_git "$tmp/no/such/dir" status >/dev/null 2>&1; rc=$?
assert_ne "a repository that does not exist fails" "$rc" 0

# git's own exit status comes back
host_git "$AI_KNOWLEDGE_ROOT/main" rev-parse --verify -q refs/heads/nothing >/dev/null 2>&1; rc=$?
assert_eq "git's failure status is the function's" "$rc" 1

# --- the call's variables reach git; GIT_DIR, which would override the vetted repository, does not
out=$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=probe.key GIT_CONFIG_VALUE_0=probe-value host_git "$AI_KNOWLEDGE_ROOT/main" config probe.key)
assert_eq "a variable set for the call reaches git" "$out" probe-value
assert_eq "a GIT_DIR in the environment does not redirect the repository" \
    "$(GIT_DIR="$sb2/knowledge/.git" host_git "$AI_KNOWLEDGE_ROOT/main" rev-parse --git-dir)" .git
assert_eq "standard input reaches git" "$(printf 'abc' | host_git "$AI_KNOWLEDGE_ROOT/main" hash-object --stdin)" "$(printf 'abc' | "$REAL_GIT" hash-object --stdin)"

# --- the no-repository form discovers none: a repository's own settings cannot redirect a URL
bare="$tmp/remote.git"; git init -q --bare "$bare"
git -C "$bare" symbolic-ref HEAD refs/heads/main
seed="$tmp/seed"; git init -q "$seed"; git -C "$seed" commit -q --allow-empty -m seed; git -C "$seed" push -q "$bare" HEAD:refs/heads/main
trap_proj="$tmp/work/trap"; git init -q "$trap_proj"
# a setting of the repository's own that rewrites the remote's address
git -C "$trap_proj" config "url.file://$tmp/nowhere.insteadOf" "file://$bare"
( cd "$trap_proj" && "$REAL_GIT" ls-remote "file://$bare" >/dev/null 2>&1 ) && r=0 || r=$?
assert_ne "control: a plain git in that directory is redirected" "$r" 0
: > "$GITLOG"
out=$( cd "$trap_proj" && host_git - ls-remote "file://$bare" 2>&1 ); rc=$?
assert_eq "the - form reaches the real remote from inside such a repository: exit" "$rc" 0
assert_contains "the - form reaches the real remote: refs listed" "$out" "refs/heads/main"
assert_eq "the - form runs in /" "$(cut -d'|' -f1 "$GITLOG")" "/"
out=$( cd "$trap_proj" && GIT_DIR="$trap_proj/.git" host_git - rev-parse --git-dir 2>&1 ); rc=$?
assert_ne "the - form finds no repository even under a GIT_DIR in the environment" "$rc" 0

# --- AI_SANDBOX_GIT_TIMEOUT: 124 when it expires, git's status otherwise
slow="$tmp/slow"; mkdir -p "$slow"
printf '#!/bin/sh\ncase " $* " in *" fetch "*) exec sleep 10 ;; esac\nexec %s "$@"\n' "$REAL_GIT" > "$slow/git"; chmod +x "$slow/git"
SECONDS=0
PATH="$slow:$PATH" AI_SANDBOX_GIT_TIMEOUT=1 ai_sandbox_host_git "$AI_KNOWLEDGE_ROOT/main" fetch >/dev/null 2>&1; rc=$?
assert_eq "a run that exceeds AI_SANDBOX_GIT_TIMEOUT exits 124" "$rc" 124
assert_eq "and was cut short" "$([ "$SECONDS" -lt 8 ] && echo yes || echo no)" yes
AI_SANDBOX_GIT_TIMEOUT=5 ai_sandbox_host_git "$AI_KNOWLEDGE_ROOT/main" log --format=%s >/dev/null 2>&1; rc=$?
assert_eq "a run inside the limit keeps git's status" "$rc" 0
unset AI_SANDBOX_GIT_TIMEOUT

# --- ai-knowledge on the host: a --repo directory a sandbox can write is refused, and
# --- with no ~/.ai-sandbox, as inside a sandbox, the same listing works as before
knowledge() { bash "$REPO_ROOT/bin/ai/ai-knowledge" "$@"; }
mkdir -p "$tmp/wk"; git init -q "$tmp/wk/repo"; git -C "$tmp/wk/repo" commit -q --allow-empty -m init
git -C "$tmp/wk/repo" branch proposal/2026-01-01-x-abcd
git -C "$tmp/wk/repo" checkout -q proposal/2026-01-01-x-abcd; mkdir -p "$tmp/wk/repo/proposals"
echo x > "$tmp/wk/repo/proposals/2026-01-01-x.md"; git -C "$tmp/wk/repo" add -A; git -C "$tmp/wk/repo" commit -q -m p; git -C "$tmp/wk/repo" checkout -q main
printf '%s\n' "$tmp/wk" > "$sb3/project-path"
knowledge proposals --repo "$tmp/wk/repo" >"$tmp/prop.out" 2>"$tmp/prop.err"; rc=$?
assert_ne "proposals --repo: a repository below a stamped project is refused" "$rc" 0
assert_eq "and lists nothing" "$(cat "$tmp/prop.out")" ""
assert_contains "and says a sandbox can write it" "$(cat "$tmp/prop.err")" "a sandbox can write"
knowledge reports --repo "$tmp/wk/repo" >/dev/null 2>"$tmp/rep.err"; rc=$?
assert_ne "reports --repo: refused the same way" "$rc" 0
out=$(AI_SANDBOX_ROOT="$tmp/no-such-root" knowledge proposals --repo "$tmp/wk/repo" 2>&1); rc=$?
assert_eq "with no ~/.ai-sandbox the listing works as before: exit" "$rc" 0
assert_eq "with no ~/.ai-sandbox the listing works as before: output" "$out" "proposal/2026-01-01-x-abcd proposals/2026-01-01-x.md"
printf '%s\n' "$tmp/work/stamped" > "$sb3/project-path"

# --- init and sync, started inside a project whose own settings redirect the remote, reach the configured remote
sync_proj="$tmp/work/syncp"; git init -q "$sync_proj"
git -C "$sync_proj" config "url.file://$tmp/nowhere.insteadOf" "file://$bare"
mkdir -p "$HOME/.gemini"; printf '# Rules\n' > "$HOME/.gemini/GEMINI.md"
export AI_KNOWLEDGE_GIT_TIMEOUT=20
rm -rf "$AI_KNOWLEDGE_ROOT/main"   # the host-owned repository the cases above made has no remote
( cd "$sync_proj" && knowledge init "file://$bare" >"$tmp/init.out" 2>&1 ); rc=$?
assert_eq "init from inside such a project: exit" "$rc" 0
assert_file "init from inside such a project cloned the remote" "$AI_KNOWLEDGE_ROOT/main/.git"
mkdir -p "$(ai_sandbox_dir_for "$sync_proj")"
( cd "$sync_proj" && knowledge sync >"$tmp/sync.out" 2>&1 ); rc=$?
assert_eq "sync from inside such a project: exit" "$rc" 0
assert_eq "sync reached the remote: nothing reported as failed" "$(grep -c 'network git failed' "$tmp/sync.out")" 0

# --- a network run that exceeds the limit is reported as today: timed out, with the manual command
git -C "$bare" update-ref refs/heads/main "$(git -C "$bare" rev-parse main)"
PATH="$slow:$PATH" AI_KNOWLEDGE_GIT_TIMEOUT=1 knowledge sync "$sync_proj" >"$tmp/timeout.out" 2>&1; rc=$?
assert_eq "a timed-out fetch does not fail the sync" "$rc" 0
assert_contains "the timeout is reported as before" "$(cat "$tmp/timeout.out")" "timed out after 1s"
assert_contains "and the manual fetch is printed" "$(cat "$tmp/timeout.out")" "fetch --prune origin"

rm -rf "$tmp"
finish
