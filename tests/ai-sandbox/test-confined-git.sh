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

# --- ai_sandbox_confined_git: one docker run with the confining options; git's status,
# --- standard input and output; 125 without an image; 124 on the time limit
served="$tmp/served"; mkdir -p "$served"; git init -q "$served/repo"
git -C "$served/repo" commit -q --allow-empty -m "served one"; mkdir -p "$served/repo/pkg/inner"
ubase=$(ai_sandbox_image_name base); udocker=$(ai_sandbox_image_name docker)
confined() { DOCKER_STUB_IMAGES="${IMAGES-$ubase}" ai_sandbox_confined_git "$@"; }
runs() { grep -c '^run ' "$DOCKER_STUB_LOG"; }
runline() { grep '^run ' "$DOCKER_STUB_LOG" | head -1; }

: > "$DOCKER_STUB_LOG"
out=$(confined "$served" repo log --format=%s 2>&1); rc=$?
assert_eq "confined: exit 0 for a git that succeeds" "$rc" 0
assert_eq "confined: git's standard output comes back" "$out" "served one"
assert_eq "confined: exactly one docker run" "$(runs)" 1
line=$(runline)
assert_contains "confined: removed afterwards" "$line" " --rm "
assert_contains "confined: standard input attached" "$line" " -i "
assert_contains "confined: no image pull" "$line" "--pull never"
assert_contains "confined: no network" "$line" "--network none"
assert_contains "confined: the host's uid and gid" "$line" "--user $(id -u):$(id -g) "
assert_contains "confined: the root is mounted read-only at its own path" "$line" " -v $served:$served:ro "
assert_eq "confined: the root is the only mount" "$(printf '%s' "$line" | grep -o ' -v \| --mount\| --volume' | wc -l | tr -d ' ')" 1
assert_contains "confined: git works in the subdirectory" "$line" " -w $served/repo "
assert_contains "confined: the image's entrypoint is replaced by git" "$line" "--entrypoint git "
assert_contains "confined: the base image when it exists" "$line" " $ubase log --format=%s"
for bad in --env-file ' -e ' --env= ' --env ' --privileged --cap-add --device --network=host --pid --ipc --volumes-from; do
    case "$line" in *"$bad"*) TESTS_RUN=$((TESTS_RUN + 1)); _fail "confined: no '$bad' option" "$line" ;;
                    *) TESTS_RUN=$((TESTS_RUN + 1)); _pass "confined: no '$bad' option" ;; esac
done
assert_eq "confined: nothing is pulled and no other image is fetched" "$(grep -cE '^(pull|image pull|build|compose)' "$DOCKER_STUB_LOG")" 0

: > "$DOCKER_STUB_LOG"
IMAGES="$udocker" confined "$served" repo log --format=%s >/dev/null 2>&1
assert_contains "confined: the docker variant when the base image is absent" "$(runline)" " $udocker "
: > "$DOCKER_STUB_LOG"
IMAGES="$ubase $udocker" confined "$served" repo log --format=%s >/dev/null 2>&1
assert_contains "confined: the base image wins when both exist" "$(runline)" " $ubase "
: > "$DOCKER_STUB_LOG"
out=$(IMAGES=none confined "$served" repo log --format=%s 2>&1); rc=$?
assert_eq "confined: no image gives 125" "$rc" 125
assert_eq "confined: and starts no container" "$(runs)" 0
assert_contains "confined: and says what is missing" "$out" "no sandbox image"
DOCKER_STUB_IMAGES="$ubase" DOCKER_STUB_RUN_EXIT=125 ai_sandbox_confined_git "$served" repo log >/dev/null 2>&1; rc=$?
assert_eq "confined: a container that cannot start gives 125" "$rc" 125

# git's own status, standard input and the subdirectory
confined "$served" repo rev-parse --verify -q no-such-ref >/dev/null 2>&1; rc=$?
( cd "$served/repo" && "$REAL_GIT" rev-parse --verify -q no-such-ref >/dev/null 2>&1 ); want=$?
assert_ne "(control: that git command fails)" "$want" 0
assert_eq "confined: a git failure keeps git's status" "$rc" "$want"
assert_eq "confined: standard input reaches git" "$(printf 'piped\n' | confined "$served" repo hash-object --stdin)" "$(printf 'piped\n' | "$REAL_GIT" hash-object --stdin)"
assert_eq "confined: the subdirectory is entered" "$(confined "$served" repo/pkg/inner rev-parse --show-prefix)" "pkg/inner/"
ln -s "$served" "$tmp/served-link"
: > "$DOCKER_STUB_LOG"
confined "$tmp/served-link" repo log -1 >/dev/null 2>&1
assert_contains "confined: a root given through a link is mounted by its resolved path" "$(runline)" " -v $served:$served:ro "

# nothing of the caller's environment reaches git
envgit="$tmp/envgit"; mkdir -p "$envgit"
printf '#!/bin/sh\nenv | grep -c "^SECRET_FROM_CALLER="\n' > "$envgit/git"; chmod +x "$envgit/git"
assert_eq "(control: the probe sees a variable it is given)" "$(SECRET_FROM_CALLER=1 PATH="$envgit:$PATH" git)" 1
assert_eq "confined: a variable of the caller does not reach git" "$(SECRET_FROM_CALLER=1 PATH="$envgit:$PATH" confined "$served" repo anything)" 0

# the time limit: 124, quickly, and the named container is removed
: > "$DOCKER_STUB_LOG"; SECONDS=0
PATH="$slow:$PATH" AI_SANDBOX_GIT_TIMEOUT=1 confined "$served" repo fetch >/dev/null 2>&1; rc=$?
assert_eq "confined: a run that exceeds AI_SANDBOX_GIT_TIMEOUT exits 124" "$rc" 124
assert_eq "confined: and was cut short" "$([ "$SECONDS" -lt 9 ] && echo yes || echo no)" yes
cname=$(runline | sed -n 's/.* --name \([^ ]*\) .*/\1/p')
assert_ne "(the run was named)" "$cname" ""
assert_contains "confined: and the named container is removed" "$(stub_docker_log)" "rm -f $cname"
: > "$DOCKER_STUB_LOG"
AI_SANDBOX_GIT_TIMEOUT=5 confined "$served" repo log --format=%s >/dev/null 2>&1; rc=$?
assert_eq "confined: a run inside the limit keeps git's status" "$rc" 0
assert_eq "confined: and removes nothing" "$(grep -c '^rm ' "$DOCKER_STUB_LOG")" 0

# --- ai_sandbox_confined_fetch (O19, called directly): a fetch from a tree a sandbox can write, through
# --- the confined git as the remote program, that changes refs of the host-owned repository only below
# --- its prefix; a served tree holding a ref of every kind a clone can hold
srv="$tmp/fetch-root"; mkdir -p "$srv"; git init -q "$srv/knowledge"
sg() { git -C "$srv/knowledge" "$@"; }
sg commit -q --allow-empty -m "served one"; c1=$(sg rev-parse HEAD)
sg commit -q --allow-empty -m "served two"; c2=$(sg rev-parse HEAD)
sg branch proposal/p1 "$c1"
sg update-ref refs/reports/r1 "$c1"; sg update-ref refs/reports-closed/r1 "$c2"
# refs a host could resolve as its own short names, and refs of kinds no pattern asks for
sg update-ref refs/tags/main "$c2"; sg update-ref refs/tags/origin/main "$c2"; sg update-ref refs/remotes/origin/main "$c2"
sg update-ref refs/stash "$c1"; sg update-ref refs/notes/commits "$c1"; sg update-ref refs/odd/kind "$c1"
hostrepo="$tmp/fetch-host.git"; git init -q --bare "$hostrepo"
hg() { git -C "$hostrepo" "$@"; }
hg fetch -q --no-tags "$srv/knowledge" "$c2:refs/heads/main" 2>/dev/null
hg update-ref refs/remotes/origin/main "$c1"; hg update-ref refs/tags/t0 "$c1"
hg update-ref refs/sandbox/other/heads/main "$c1"; hg update-ref refs/sandbox/other/reports/old "$c1"
hg update-ref refs/pushed-reports/other/old "$c1"
refs_of() { hg for-each-ref --format='%(refname) %(objectname)' "$@" | LC_ALL=C sort; }
fetchc() { DOCKER_STUB_IMAGES="${IMAGES-$ubase}" PATH="$rec:$PATH" ai_sandbox_confined_fetch "$@"; }
PATS=('refs/heads/*' 'refs/reports/*' 'refs/reports-closed/*')
other_before=$(refs_of refs/sandbox/other refs/pushed-reports)
outside_before=$(refs_of | grep -v '^refs/sandbox/a/')

: > "$DOCKER_STUB_LOG"; : > "$GITLOG"
fetchc "$hostrepo" refs/sandbox/a "$srv" knowledge "${PATS[@]}" >"$tmp/cf.out" 2>&1; rc=$?
assert_eq "fetch: exit 0" "$rc" 0
assert_eq "fetch: prints nothing" "$(cat "$tmp/cf.out")" ""
assert_eq "fetch: heads arrive below <prefix>/heads" "$(refs_of refs/sandbox/a/heads)" "$(printf 'refs/sandbox/a/heads/main %s\nrefs/sandbox/a/heads/proposal/p1 %s' "$c2" "$c1")"
assert_eq "fetch: reports arrive below <prefix>/reports" "$(refs_of refs/sandbox/a/reports)" "refs/sandbox/a/reports/r1 $c1"
assert_eq "fetch: tombstones arrive below <prefix>/reports-closed" "$(refs_of refs/sandbox/a/reports-closed)" "refs/sandbox/a/reports-closed/r1 $c2"
assert_eq "fetch: nothing else is below <prefix>" "$(refs_of refs/sandbox/a | grep -vc '^refs/sandbox/a/\(heads\|reports\|reports-closed\)/')" 0
assert_eq "fetch: no ref outside <prefix> changed, none was added" "$(refs_of | grep -v '^refs/sandbox/a/')" "$outside_before"
assert_eq "fetch: a second prefix and the pushed-report records are as they were" "$(refs_of refs/sandbox/other refs/pushed-reports)" "$other_before"
assert_eq "fetch: no served tag arrived as a host tag" "$(hg for-each-ref --format='%(refname)' refs/tags | tr '\n' ' ')" "refs/tags/t0 "
assert_eq "fetch: the short name origin/main still resolves to the host's own ref" "$(hg rev-parse origin/main)" "$c1"
# the form of the run: B1a's options, upload-pack as git's program, no tag followed
line=$(grep '^run ' "$DOCKER_STUB_LOG" | head -1)
assert_eq "fetch: one container run" "$(grep -c '^run ' "$DOCKER_STUB_LOG")" 1
assert_contains "fetch: removed afterwards, stdin attached" "$line" "run --rm -i "
assert_contains "fetch: no image pull, no network" "$line" "--pull never --network none"
assert_contains "fetch: the host's uid and gid" "$line" "--user $(id -u):$(id -g) "
assert_contains "fetch: the root is the only mount, read-only at its own path" "$line" " -v $srv:$srv:ro "
assert_eq "fetch: only one mount" "$(printf '%s' "$line" | grep -o ' -v \| --mount\| --volume' | wc -l | tr -d ' ')" 1
assert_contains "fetch: the image's entrypoint is git" "$line" "--entrypoint git "
assert_contains "fetch: the remote program is upload-pack on the served path" "$line" " $ubase upload-pack $srv/knowledge"
for bad in --env-file ' -e ' --env= ' --env ' --privileged --cap-add --device --network=host; do
    case "$line" in *"$bad"*) TESTS_RUN=$((TESTS_RUN + 1)); _fail "fetch: no '$bad' option" "$line" ;;
                    *) TESTS_RUN=$((TESTS_RUN + 1)); _pass "fetch: no '$bad' option" ;; esac
done
gl=$(grep '|fetch ' "$GITLOG" | head -1)
assert_eq "fetch: git runs in the host-owned repository" "${gl%%|*}" "$(readlink -f "$hostrepo")"
assert_contains "fetch: no tag followed, pruned, by a remote program" "$gl" "fetch -q --no-tags --prune --upload-pack="
assert_contains "fetch: the refspecs name only the namespace" "$gl" "+refs/heads/*:refs/sandbox/a/heads/* +refs/reports/*:refs/sandbox/a/reports/* +refs/reports-closed/*:refs/sandbox/a/reports-closed/*"
assert_eq "fetch: no other git ran in the host-owned repository (the host's one fetch)" "$(grep -c "^$(readlink -f "$hostrepo")|" "$GITLOG")" 1

# a ref the served tree no longer holds is dropped below <prefix>, and only there
sg update-ref -d refs/heads/proposal/p1; sg update-ref -d refs/reports/r1
fetchc "$hostrepo" refs/sandbox/a "$srv" knowledge "${PATS[@]}" >/dev/null 2>&1; rc=$?
assert_eq "fetch again: exit 0" "$rc" 0
assert_eq "fetch again: a deleted head is pruned" "$(refs_of refs/sandbox/a/heads)" "refs/sandbox/a/heads/main $c2"
assert_eq "fetch again: a deleted report is pruned" "$(refs_of refs/sandbox/a/reports | wc -l | tr -d ' ')" 0
assert_eq "fetch again: the second prefix is as it was" "$(refs_of refs/sandbox/other refs/pushed-reports)" "$other_before"
assert_eq "fetch again: nothing outside <prefix> changed" "$(refs_of | grep -v '^refs/sandbox/a/')" "$outside_before"
# a second prefix fetched from the same tree does not touch the first
fetchc "$hostrepo" refs/sandbox/b "$srv" knowledge "${PATS[@]}" >/dev/null 2>&1
assert_eq "second prefix: delivered" "$(refs_of refs/sandbox/b/heads)" "refs/sandbox/b/heads/main $c2"
assert_eq "second prefix: the first is as it was" "$(refs_of refs/sandbox/a/heads)" "refs/sandbox/a/heads/main $c2"
hg update-ref -d refs/sandbox/b/heads/main; hg update-ref -d refs/sandbox/b/reports-closed/r1
# a root given through a link
ln -s "$srv" "$tmp/fetch-root-link"
: > "$DOCKER_STUB_LOG"
fetchc "$hostrepo" refs/sandbox/a "$tmp/fetch-root-link" knowledge "${PATS[@]}" >/dev/null 2>&1; rc=$?
assert_eq "fetch: a root given through a link works" "$rc" 0
assert_contains "fetch: and is mounted by its resolved path" "$(grep '^run ' "$DOCKER_STUB_LOG" | head -1)" " -v $srv:$srv:ro "

# the negative case: the same fetch without the confinement (no --no-tags, no namespace) sees a ref outside it
negrepo="$tmp/fetch-neg.git"; git init -q --bare "$negrepo"
git -C "$negrepo" fetch -q --prune "$srv/knowledge" '+refs/heads/*:refs/sandbox/a/heads/*' >/dev/null 2>&1
assert_ne "negative control: without --no-tags a served tag lands outside the namespace" \
    "$(git -C "$negrepo" for-each-ref --format='%(refname)' | grep -v '^refs/sandbox/a/' | tr '\n' ' ')" ""

# exit statuses: 3 for a repository a sandbox can write (no git, no container), 125 without an image, 124 on the limit
: > "$DOCKER_STUB_LOG"; : > "$GITLOG"
git init -q "$sb2/knowledge"
fetchc "$sb2/knowledge" refs/sandbox/a "$srv" knowledge "${PATS[@]}" >"$tmp/cf-w.out" 2>&1; rc=$?
assert_eq "fetch: a sandbox-writable repository gives 3" "$rc" 3
assert_eq "fetch: and starts no git in it" "$(grep -c "^$(readlink -f "$sb2/knowledge")|" "$GITLOG")" 0
assert_eq "fetch: and no container" "$(grep -c '^run ' "$DOCKER_STUB_LOG")" 0
: > "$DOCKER_STUB_LOG"; before=$(refs_of)
IMAGES=none fetchc "$hostrepo" refs/sandbox/a "$srv" knowledge "${PATS[@]}" >"$tmp/cf-i.out" 2>&1; rc=$?
assert_eq "fetch: no image gives 125" "$rc" 125
assert_contains "fetch: and says what is missing" "$(cat "$tmp/cf-i.out")" "no sandbox image"
assert_eq "fetch: and changes no ref" "$(refs_of)" "$before"
DOCKER_STUB_IMAGES="$ubase" DOCKER_STUB_RUN_EXIT=125 ai_sandbox_confined_fetch "$hostrepo" refs/sandbox/a "$srv" knowledge "${PATS[@]}" >/dev/null 2>&1; rc=$?
assert_eq "fetch: a container that cannot start gives 125" "$rc" 125
slowup="$tmp/slowup"; mkdir -p "$slowup"
# a container that hangs (git prepends its own directory to PATH for the remote program, so the stand-in is docker)
printf '#!/bin/sh\ncase "$1" in run) exec sleep 10 ;; esac\nexec %s "$@"\n' "$(command -v docker)" > "$slowup/docker"; chmod +x "$slowup/docker"
: > "$DOCKER_STUB_LOG"; SECONDS=0
DOCKER_STUB_IMAGES="$ubase" PATH="$slowup:$PATH" AI_SANDBOX_GIT_TIMEOUT=1 ai_sandbox_confined_fetch "$hostrepo" refs/sandbox/a "$srv" knowledge "${PATS[@]}" >/dev/null 2>&1; rc=$?
assert_eq "fetch: a run that exceeds AI_SANDBOX_GIT_TIMEOUT exits 124" "$rc" 124
assert_eq "fetch: and was cut short" "$([ "$SECONDS" -lt 9 ] && echo yes || echo no)" yes
assert_contains "fetch: and the named container is removed" "$(stub_docker_log)" "rm -f ai-sandbox-git-"
AI_SANDBOX_GIT_TIMEOUT=20 fetchc "$hostrepo" refs/sandbox/a "$srv" knowledge "${PATS[@]}" >/dev/null 2>&1; rc=$?
assert_eq "fetch: a run inside the limit exits 0" "$rc" 0
# a served path that is no repository: git's own failure, neither 124 nor 125
fetchc "$hostrepo" refs/sandbox/a "$srv" no-such-dir "${PATS[@]}" >/dev/null 2>&1; rc=$?
assert_ne "fetch: a failing git is not reported as success" "$rc" 0
assert_eq "fetch: nor as a container problem" "$([ "$rc" -eq 124 ] || [ "$rc" -eq 125 ] && echo container || echo git)" git
# arguments that do not fit the contract
for args in "refs/heads/x|$srv|knowledge|refs/heads/*" "refs/tags/x|$srv|knowledge|refs/heads/*" "other|$srv|knowledge|refs/heads/*" \
            "refs/sandbox/a|$srv|..|refs/heads/*" "refs/sandbox/a|$srv|/abs|refs/heads/*" "refs/sandbox/a|$srv|knowledge|heads/*" \
            "refs/sandbox/a|$srv|knowledge|refs/heads/x" "refs/sandbox/a|$srv|knowledge|refs/a/b/*" "refs/sandbox/a|$srv|knowledge"; do
    IFS='|' read -r -a av <<<"$args"
    fetchc "$hostrepo" "${av[@]}" >/dev/null 2>&1; rc=$?
    assert_eq "fetch: arguments outside the contract give 2 ($args)" "$rc" 2
done

rm -rf "$tmp"
finish
