#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

assert_eq "slug lowercases"            "$(ai_sandbox_slug 'DevTools')"     'devtools'
assert_eq "slug replaces separators"   "$(ai_sandbox_slug 'my_project')"   'my-project'
assert_eq "slug collapses runs"        "$(ai_sandbox_slug 'a...b')"        'a-b'
assert_eq "slug trims leading"         "$(ai_sandbox_slug '.hidden')"      'hidden'
assert_eq "slug trims trailing"        "$(ai_sandbox_slug 'foo.')"         'foo'
assert_eq "slug of separators only"    "$(ai_sandbox_slug '...')"          ''

# The whole point of the change: same basename, different path, different id.
a=$(ai_sandbox_project_id /home/u/work/dev-tools)
b=$(ai_sandbox_project_id /home/u/play/dev-tools)
assert_eq "id keeps the basename"  "${a%-*}" 'dev-tools'
if [ "$a" = "$b" ]; then
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "same basename must not collide" "both were '$a'"
else
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "same basename must not collide"
fi
assert_eq "id is stable"           "$(ai_sandbox_project_id /home/u/work/dev-tools)" "$a"
assert_eq "id hash is 8 hex"       "$(printf '%s' "${a##*-}" | wc -c | tr -d ' ')" '8'

# A trailing-dash slug must not produce a double dash, which is an illegal
# Docker repository component.
assert_contains "no double dash" "$(ai_sandbox_project_id /home/u/foo.)" 'foo-'
id=$(ai_sandbox_project_id /home/u/foo.)
case "$id" in *--*) TESTS_RUN=$((TESTS_RUN+1)); _fail "no double dash in id" "$id" ;;
              *)   TESTS_RUN=$((TESTS_RUN+1)); _pass "no double dash in id" ;; esac

assert_eq "empty slug falls back" "$(ai_sandbox_project_id /home/u/...)" \
          "project-$(printf '%s' /home/u/... | sha256sum | cut -c1-8)"

# Pin the redirected root literally: comparing against $AI_SANDBOX_ROOT on both
# sides would hold even if fake_home's redirection never took effect.
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
assert_eq "dir_for uses AI_SANDBOX_ROOT" \
    "$(ai_sandbox_dir_for /home/u/work/dev-tools)" "$tmp/home/.ai-sandbox/${a}-agent"
rm -rf "$tmp"

# C-STAMP: ai_sandbox_project_root answers from the stamps under AI_SANDBOX_ROOT
# alone and starts no git process (a recording git first on PATH sees no call).
# The lookups run in a fake home so no real stamp is read.
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
REAL_GIT=$(command -v git)
rec="$tmp/rec"; mkdir -p "$rec"; GITLOG="$tmp/git.log"; export GITLOG; : > "$GITLOG"
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$PWD" "$*" >> "$GITLOG"\nexec %s "$@"\n' "$REAL_GIT" > "$rec/git"
chmod +x "$rec/git"
stamp() {   # <dir the sandbox directory is named for> [project-path content]
    local d; d=$(ai_sandbox_dir_for "$1"); mkdir -p "$d"
    printf '%s\n' "${2:-$1}" > "$d/project-path"
}
root_of() { PATH="$rec:$PATH" ai_sandbox_project_root "$@"; }

w="$tmp/work"; mkdir -p "$w/proj/sub/deep" "$w/proj/repo/inner" "$w/plain/x" "$w/gitonly/sub"
git init -q "$w/proj/repo"; git init -q "$w/gitonly"
stamp "$w/proj"
assert_eq "the project's own directory" "$(root_of "$w/proj")" "$w/proj"
assert_eq "a subdirectory of the project" "$(root_of "$w/proj/sub/deep")" "$w/proj"
assert_eq "no argument: the current directory" "$(cd "$w/proj/sub" && root_of)" "$w/proj"
assert_eq "a repository below a sandboxed parent without a sandbox of its own" \
    "$(root_of "$w/proj/repo/inner")" "$w/proj"
assert_eq "no git process started by the lookup" "$(wc -l < "$GITLOG" | tr -d ' ')" 0

stamp "$w/proj/repo"
assert_eq "the nearest stamped ancestor wins" "$(root_of "$w/proj/repo/inner")" "$w/proj/repo"
assert_eq "an ancestor above it still answers for its other subdirectories" "$(root_of "$w/proj/sub")" "$w/proj"

# No stamped ancestor: the directory itself, git's toplevel plays no part
assert_eq "unstamped plain directory: itself" "$(root_of "$w/plain")" "$w/plain"
assert_eq "unstamped subdirectory: itself" "$(root_of "$w/plain/x")" "$w/plain/x"
assert_eq "unstamped repository, from a subdirectory: the subdirectory itself" "$(root_of "$w/gitonly/sub")" "$w/gitonly/sub"
ln -s "$w/plain" "$tmp/plain-link"
assert_eq "unstamped, reached through a link: the directory with links resolved" "$(root_of "$tmp/plain-link/x")" "$w/plain/x"

# A stamp counts only where its project-path names the directory it is filed for
stamp "$w/other" "$w/proj/sub"
mkdir -p "$w/other/below"
assert_eq "a stamp whose project-path names another directory is not found" "$(root_of "$w/other/below")" "$w/other/below"
printf '%s' "$w/other" > "$(ai_sandbox_dir_for "$w/other")/project-path"
assert_eq "a project-path without its trailing newline counts" "$(root_of "$w/other/below")" "$w/other"

# Both path forms today's function stored are found from a linked parent: a
# repository was stored with git's resolved toplevel, anything else as given.
mkdir -p "$w/real/repo/sub" "$w/real/dir/sub"; git init -q "$w/real/repo"
ln -s "$w/real" "$tmp/lnk"
stamp "$w/real/repo"
stamp "$tmp/lnk/dir"
assert_eq "resolved stamp, reached through the link" "$(root_of "$tmp/lnk/repo/sub")" "$w/real/repo"
assert_eq "resolved stamp, reached directly" "$(root_of "$w/real/repo/sub")" "$w/real/repo"
assert_eq "unresolved stamp, reached through the link" "$(root_of "$tmp/lnk/dir/sub")" "$tmp/lnk/dir"
assert_eq "no git process started with links either" "$(wc -l < "$GITLOG" | tr -d ' ')" 0

# found or not: the predicate init uses
ai_sandbox_stamped "$w/proj" && r=0 || r=$?
assert_eq "stamped: a directory whose stamp names it" "$r" 0
ai_sandbox_stamped "$w/proj/sub" && r=0 || r=$?
assert_eq "stamped: not a subdirectory of a stamped one" "$r" 1
ai_sandbox_stamped "$w/plain" && r=0 || r=$?
assert_eq "stamped: not a directory without a stamp" "$r" 1

# Nonexistent directory fails
nonexist="$tmp/this-dir-definitely-does-not-exist"
result=$(root_of "$nonexist" 2>&1) && exit_code=0 || exit_code=$?
assert_eq "project_root fails for a nonexistent directory" "$exit_code" 1
assert_eq "project_root prints nothing for a nonexistent directory" "$result" ""
rm -rf "$tmp"

# The image tag is composed once, in ai_sandbox_image_name (the search that
# missed a third copy at planning time, S22). The pattern is a tag built from a
# variable or a literal variant, or a '-u<uid>' suffix, under bin/ai. Known
# case first: a scratch file with each of the forms the base had must be reported.
tagpat='ai-sandbox:(\$|base-|docker-)|-u\$\{?[A-Za-z_]*[Uu][Ii][Dd]'
tagdir=$(mktemp -d)
printf '%s\n' 'IMAGE_NAME="ai-sandbox:${IMAGE_VARIANT}-u${HOST_UID}"' \
    'IMAGE_STAMP="$D/${IMAGE_VARIANT}-u${HOST_UID}.stamp"' \
    'tag="ai-sandbox:${variant}-u${uid}"' 'tag=ai-sandbox:base-u1000' > "$tagdir/known"
assert_eq "tag search reports every composed form in its known case" "$(command grep -cE "$tagpat" "$tagdir/known")" 4
rm -rf "$tagdir"
assert_eq "no image tag is composed under bin/ai outside ai_sandbox_image_name" \
    "$(command grep -rnaE "$tagpat" "$REPO_ROOT/bin/ai" | wc -l | tr -d ' ')" 0

finish
