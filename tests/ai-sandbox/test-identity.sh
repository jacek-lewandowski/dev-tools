#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

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

tmp=$(fake_home)
assert_eq "dir_for uses AI_SANDBOX_ROOT" \
    "$(ai_sandbox_dir_for /home/u/work/dev-tools)" "$AI_SANDBOX_ROOT/${a}-agent"
rm -rf "$tmp"

finish
