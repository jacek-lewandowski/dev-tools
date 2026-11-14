#!/usr/bin/env bash
# O12, the sweep: no host write follows a link a sandbox placed below a directory it can write (I3c).
# Self-enumerating: run 1 records every path the host creates or changes below a writable bind
# source (the compose file's sources without :ro, and the project directory) while create,
# ai-knowledge sync and ai-sandbox-account refresh and reset run; run 2 replaces each recorded
# path (and the directories on its way) by a link into a trap and runs the same commands.
# A command added later that writes a new place is recorded by run 1, so it is swept with no edit here.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
export AI_KNOWLEDGE_GIT_TIMEOUT=20
kn() { DOCKER_STUB_IMAGES="$kimages" bash "$REPO_ROOT/bin/ai/ai-knowledge" "$@"; }
snap() { ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do   # modes too: a chmod through a link is a write
    if [ -L "$f" ]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; elif [ -f "$f" ]; then printf '%s %s %s\n' "$f" "$(stat -c %a "$f")" "$(sha256sum < "$f")"; else printf '%s %s\n' "$f" "$(stat -c %a "$f")"; fi; done ); }
mkproj() { mkdir -p "$1"; git -C "$1" init -q; }

# A host: knowledge configured, a host SDKMAN, a host Claude account, a project; one sandbox created, then a
# legacy brain file and a generated .agentrules put back so that create has files to retire.
host() {
    fake_home >/dev/null; tmp=$FAKE_HOME_DIR
    . "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
    git config --global user.email t@example.com; git config --global user.name t; git config --global init.defaultBranch main
    kimages="$(ai_sandbox_image_name base) $(ai_sandbox_image_name docker) $(ai_sandbox_image_name base gui) $(ai_sandbox_image_name docker gui)"
    local SD="$HOME/.sdkman" remote="$tmp/remote.git"
    mkdir -p "$SD/bin" "$SD/libexec" "$SD/src" "$SD/contrib" "$SD/etc" "$SD/var" \
        "$SD/candidates/java/21.0.8-tem/bin" "$SD/candidates/java/17.0.16-tem/bin" "$SD/candidates/gradle/9.6.1/bin"
    echo init > "$SD/bin/sdkman-init.sh"; echo fn > "$SD/src/sdkman-default.sh"
    echo 'sdkman_auto_answer=false' > "$SD/etc/config"; echo 5.20.0 > "$SD/var/version"
    ln -s 21.0.8-tem "$SD/candidates/java/current"
    mkdir -p "$HOME/.claude/sub" "$HOME/.codex" "$HOME/.gemini"
    echo host-token > "$HOME/.claude/.credentials.json"; echo host-file > "$HOME/.claude/sub/file"; echo '{"a":"host"}' > "$HOME/.claude.json"
    echo host-codex > "$HOME/.codex/auth.json"; printf '# Rules\n' > "$HOME/.gemini/GEMINI.md"
    git init -q --bare "$remote"
    integ="$tmp/work/dev-tools"; mkproj "$integ"
    mkdir -p "$(ai_sandbox_dir_for "$integ")"
    kn init "file://$remote" --integrator "$integ" >/dev/null 2>&1 </dev/null
    git clone -q "$remote" "$tmp/seedclone"; mkdir -p "$tmp/seedclone/skills/newskill"
    printf -- '---\nname: newskill\ndescription: d\n---\nx\n' > "$tmp/seedclone/skills/newskill/SKILL.md"
    git -C "$tmp/seedclone" add -A; git -C "$tmp/seedclone" commit -qm "skill"; git -C "$tmp/seedclone" push -q origin main
    proj="$tmp/work/p"; mkproj "$proj"
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/create0.out" 2>&1 </dev/null
    sb="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
    rm -f "$sb/.gemini/GEMINI.md" "$sb/.claude/CLAUDE.md" "$sb/.codex/AGENTS.md"   # a sandbox may delete its mount targets
    mkdir -p "$HOME/.gemini/antigravity-ide/brain"; printf 'legacy\n' > "$HOME/.gemini/antigravity-ide/brain/CLAUDE.md"
    printf '# Agent Environment Context\nold\n' > "$proj/.agentrules"
    trap_dir="$tmp/trap"; mkdir -p "$trap_dir/dir"; printf 'trap\n' > "$trap_dir/file"; printf 'trap\n' > "$trap_dir/dir/inner"
    key=$(printf %s "$proj" | sed 's|[/.]|-|g')
}

# The roots: the compose file's bind sources without :ro (read as ai_sandbox_writable_path reads them) that are
# directories, and the project directory; resolved, one per line.
roots() {
    { printf '%s\n' "$proj"
      awk '
        /^    volumes:[[:space:]]*$/ { inv = 1; next }
        inv && $0 !~ /^[[:space:]]*(#.*)?$/ { match($0, /^ */); if (RLENGTH <= 4) inv = 0 }
        inv && /^[[:space:]]+-[[:space:]]+"[^"]*"[[:space:]]*$/ {
            item = $0; sub(/^[[:space:]]+-[[:space:]]+"/, "", item); sub(/"[[:space:]]*$/, "", item)
            n = split(item, f, ":")
            if (n >= 2 && f[1] ~ /^\// && f[1] !~ /\$/) { if (n >= 3 && f[n] ~ /(^|,)ro(,|$)/) next; print f[1] }
        }' "$sb/docker-compose.yml"
    } | while IFS= read -r r; do [ -d "$r" ] && readlink -f -- "$r"; done | LC_ALL=C sort -u
}
# path, type, inode and change time of everything below the roots
state() { local r; while IFS= read -r r; do find "$r" -mindepth 1 -printf '%p\t%y\t%i\t%C@\n'; done < <(roots) | LC_ALL=C sort; }

commands() {   # <names the four commands in order; sets RCS and, when <hook> is a function name, calls it after each>
    local hook=${1:-:}
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >>"$tmp/sweep.out" 2>>"$tmp/sweep.err" </dev/null; RCS[0]=$?; "$hook"
    kn sync "$proj" >>"$tmp/sweep.out" 2>>"$tmp/sweep.err" </dev/null; RCS[1]=$?; "$hook"
    ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" refresh --yes ) >>"$tmp/sweep.out" 2>>"$tmp/sweep.err" </dev/null; RCS[2]=$?; "$hook"
    ( cd "$proj" && bash "$REPO_ROOT/bin/ai/ai-sandbox-account" reset --yes ) >>"$tmp/sweep.out" 2>>"$tmp/sweep.err" </dev/null; RCS[3]=$?; "$hook"
}

# Paths and ancestors are written relative to the temporary directory with the sandbox's name and the project's
# Claude key replaced, so that run 2's other temporary directory expands them again.
norm() { sed -e "s|$tmp|@T|g" -e "s|$key|@K|g" -e "s|$(basename "$sb")|@SB|g"; }
expand() { sed -e "s|@K|$key|g" -e "s|@SB|$(basename "$sb")|g" -e "s|@T|$tmp|g"; }

# ---- run 1
host
RCS=(); before=$(state); : > "$tmp/recorded"
record() { local after; after=$(state); comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | cut -f1,2 >> "$tmp/recorded"; before=$after; }
commands record
rc1=("${RCS[@]}")
assert_eq "run 1: create, sync, refresh and reset exit 0" "${rc1[*]}" "0 0 0 0"
# the roots are what the host's own reader calls writable, and a read-only source is not one
while IFS= read -r r; do ai_sandbox_writable_path "$r" && w=yes || w=no; [ "$w" = yes ] || { assert_eq "root $r is a writable path" "$w" yes; }; done < <(roots)
ai_sandbox_writable_path "$AI_SANDBOX_ROOT/shared/agent-skills" && w=yes || w=no
assert_eq "known case: a read-only bind source is not a root" "$w" no
# every ancestor of a recorded path below its root is swept too
rootlist=$(roots)
: > "$tmp/swept"
while IFS=$'\t' read -r p t; do
    printf '%s\t%s\n' "$p" "$t" >> "$tmp/swept"
    a=$(dirname "$p")
    while ! printf '%s\n' "$rootlist" | grep -qxF -- "$a"; do
        [ "$a" = / ] && break
        printf '%s\td\n' "$a" >> "$tmp/swept"; a=$(dirname "$a")
    done
done < <(LC_ALL=C sort -u "$tmp/recorded")
LC_ALL=C sort -u "$tmp/swept" | norm > "$tmp/swept.norm"
paths_total=$(wc -l < "$tmp/swept.norm")
[ -z "${SWEEP_LIST:-}" ] || sed 's|@T/||' "$tmp/swept.norm" >&2   # SWEEP_LIST=1 prints run 1's paths
list=$(cut -f1 "$tmp/swept.norm")
cat_n() { printf '%s\n' "$list" | grep -cE "$1"; }
assert_ne "run 1 recorded paths: mount targets (CLAUDE.md)" "$(cat_n '/@SB/\.claude/CLAUDE\.md$')" 0
assert_ne "run 1 recorded paths: skill links" "$(cat_n '/@SB/\.(claude|codex|gemini)/skills/')" 0
assert_ne "run 1 recorded paths: the SDKMAN farm" "$(cat_n '/@SB/sdkman/')" 0
assert_ne "run 1 recorded paths: account state" "$(cat_n '/@SB/\.claude/\.credentials\.json$')" 0
assert_ne "run 1 recorded paths: moved legacy files" "$(cat_n '\.superseded$')" 0
assert_eq "run 1 recorded no status file (the host's reports are under the read-only status/)" "$(cat_n '/status(/|$)')" 0
echo "# sweep: $paths_total paths recorded by run 1" >&2

# ---- run 2: every path swept in at least one fresh host; paths that contain one another go to different runs
declare -a groups=()
while IFS=$'\t' read -r p t; do
    placed=no
    for i in "${!groups[@]}"; do
        clash=no
        while IFS= read -r q; do
            case $p in "$q"/*) clash=yes ;; esac
            case $q in "$p"/*) clash=yes ;; esac
            [ "$p" = "$q" ] && clash=yes
        done < <(printf '%s' "${groups[$i]}" | cut -f1 -d$'\t' | sed '/^$/d')
        if [ $clash = no ]; then groups[$i]+="$p"$'\t'"$t"$'\n'; placed=yes; break; fi
    done
    [ $placed = yes ] || groups+=("$p"$'\t'"$t"$'\n')
done < "$tmp/swept.norm"
nruns=${#groups[@]}
for i in "${!groups[@]}"; do
    host; RCS=()
    n=0
    while IFS=$'\t' read -r p t; do
        [ -n "$p" ] || continue
        full=$(printf '%s' "$p" | expand)
        # one trap entry per link, so a write through a link names the link
        n=$((n + 1)); mkdir -p "$trap_dir/e$n"; printf 'trap\n' > "$trap_dir/e$n/inner"; printf '%s\n' "$p" > "$tmp/planted.$n"
        if [ "$t" = d ]; then target="$trap_dir/e$n"; else target="$trap_dir/e$n/inner"; fi
        rm -rf "$full"; mkdir -p "$(dirname "$full")"; ln -s "$target" "$full"
    done <<< "${groups[$i]}"
    t0=$(snap "$trap_dir"); : > "$tmp/sweep.out"; : > "$tmp/sweep.err"
    declare -a pre=(); for ((k = 1; k <= n; k++)); do pre[k]=$(snap "$trap_dir/e$k"); done
    commands
    t1=$(snap "$trap_dir")
    if [ "$t1" != "$t0" ]; then
        for ((k = 1; k <= n; k++)); do
            [ "$(snap "$trap_dir/e$k")" = "${pre[k]}" ] || echo "# written through the link at: $(cat "$tmp/planted.$k")" >&2
        done
    fi
    assert_eq "run 2.$i ($n links planted): the trap is unchanged" "$t1" "$t0"
    assert_eq "run 2.$i: the four commands exit as in run 1" "${RCS[*]}" "${rc1[*]}"
done
assert_ne "run 2 made at least one run" "$nruns" 0
finish
