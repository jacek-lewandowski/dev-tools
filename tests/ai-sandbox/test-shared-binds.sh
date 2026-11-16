#!/usr/bin/env bash
# O8: no read-write bind of a host directory or file is shared with another sandbox, but the two
# files phase 10 owns under S-10: $HOME/.gitignore, and without knowledge $HOME/.gemini/GEMINI.md
# (bound at ~/.gemini/GEMINI.md and ~/.claude/CLAUDE.md). Two disjoint projects per case, default
# options, with and without knowledge, with --display=nested and --display=xpra. "Shared" is a
# read-write bind source of one sandbox that equals, contains or lies inside one of the other's.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
export AI_KNOWLEDGE_GIT_TIMEOUT=20

stubs=""
# the read-write bind sources of a compose file (absolute, without a variable, not ':ro'), one per line
rw_sources() {
    awk '
      /^    volumes:[[:space:]]*$/ { inv = 1; next }
      inv && $0 !~ /^[[:space:]]*(#.*)?$/ { match($0, /^ */); if (RLENGTH <= 4) inv = 0 }
      inv && /^[[:space:]]+-[[:space:]]+"[^"]*"[[:space:]]*$/ {
          item = $0; sub(/^[[:space:]]+-[[:space:]]+"/, "", item); sub(/"[[:space:]]*$/, "", item)
          n = split(item, f, ":")
          if (n >= 2 && f[1] ~ /^\// && f[1] !~ /\$/) { if (n >= 3 && f[n] ~ /(^|,)ro(,|$)/) next; print f[1] }
      }' "$1" | while IFS= read -r s; do readlink -m -- "$s"; done | LC_ALL=C sort -u
}
# the sources of $1 that equal, contain or lie inside a source of $2
shared() {
    local a b
    while IFS= read -r a; do
        while IFS= read -r b; do
            case "$a/" in "$b"/*) printf '%s\n' "$a"; break ;; esac
            case "$b/" in "$a"/*) printf '%s\n' "$a"; break ;; esac
        done < <(printf '%s\n' "$2")
    done < <(printf '%s\n' "$1") | LC_ALL=C sort -u
}
sandbox_compose() { echo "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$1")-agent/docker-compose.yml"; }

host() {   # <knowledge yes|no>
    fake_home >/dev/null; tmp=$FAKE_HOME_DIR
    . "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
    stubs="$tmp/xstubs"; mkdir -p "$stubs"; printf '#!/bin/sh\nexit 0\n' > "$stubs/Xephyr"; cp "$stubs/Xephyr" "$stubs/Xvfb"; cp "$stubs/Xephyr" "$stubs/xpra"; chmod +x "$stubs"/*
    mkdir -p "$HOME/.gemini" "$HOME/.claude"; echo '# brain' > "$HOME/.gemini/GEMINI.md"; echo ig > "$HOME/.gitignore"
    if [ "$1" = yes ]; then
        git config --global user.email t@example.com; git config --global user.name t; git config --global init.defaultBranch main
        local remote="$tmp/remote.git" integ="$tmp/work/dev-tools"
        git init -q --bare "$remote"; mkdir -p "$integ"; git -C "$integ" init -q
        mkdir -p "$(ai_sandbox_dir_for "$integ")"
        bash "$REPO_ROOT/bin/ai/ai-knowledge" init "file://$remote" --integrator "$integ" >/dev/null 2>&1 </dev/null
    fi
}
mk() { mkdir -p "$1"; git -C "$1" init -q; PATH="$stubs:$PATH" bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display="$2" --no-start "$1" >"$tmp/out.$(basename "$1")" 2>&1 </dev/null; }

for knowledge in no yes; do
    host "$knowledge"
    [ "$knowledge" = yes ] && assert_file "knowledge is configured" "$AI_KNOWLEDGE_CONFIG"
    for display in nested xpra; do
        a="$tmp/work/a-$display"; b="$tmp/work/b-$display"
        mk "$a" "$display"; mk "$b" "$display"
        ca=$(rw_sources "$(sandbox_compose "$a")"); cb=$(rw_sources "$(sandbox_compose "$b")")
        assert_ne "knowledge=$knowledge display=$display: the sandbox has read-write binds" "$(printf '%s' "$ca" | wc -l)" 0
        if [ "$knowledge" = yes ]; then want="$HOME/.gitignore"
        else want=$(printf '%s\n%s\n' "$HOME/.gemini/GEMINI.md" "$HOME/.gitignore" | LC_ALL=C sort); fi
        assert_eq "knowledge=$knowledge display=$display: exactly the files phase 10 owns are shared (a sees b)" "$(shared "$ca" "$cb")" "$want"
        assert_eq "knowledge=$knowledge display=$display: and the same from b" "$(shared "$cb" "$ca")" "$want"
    done
done

# known case of the checker: nested sources are found in both directions
assert_eq "known case: a parent and its child are shared" "$(shared "$(printf '/x/p\n/y/q')" "$(printf '/x/p/c')")" "/x/p"
assert_eq "known case: a child and its parent are shared" "$(shared "$(printf '/x/p/c')" "$(printf '/x/p')")" "/x/p/c"
assert_eq "known case: a sibling with a common prefix is not" "$(shared "/x/pq" "/x/p")" ""

rm -rf "$tmp"
finish
