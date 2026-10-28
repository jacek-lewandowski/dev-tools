#!/usr/bin/env bash
# The gitleaks hooks must refuse a secret at commit and at push, let clean work
# through, and fail closed when gitleaks is missing. Needs gitleaks on PATH.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../ai-sandbox/harness.sh"

command -v gitleaks >/dev/null || { echo "gitleaks is required on PATH to run this suite" >&2; exit 1; }

tmp=$(mktemp -d)
export HOME="$tmp/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Composed at runtime so this file never contains a token-shaped literal.
secret="ghp_$(printf '%s' 'x7Kq9ZpL2mVb' 'R4tYw8NcD3sFh6JgA1eU')"
printf '# fixture\ntoken = "%s"\n' "$secret" > "$tmp/leaky"

git init -q --bare "$tmp/remote.git"
git init -q -b main "$tmp/work"
cd "$tmp/work" || exit 1
git config core.hooksPath "$REPO_ROOT/.githooks"
git remote add origin "$tmp/remote.git"

commit() { git commit -q -m "$1" >"$tmp/out" 2>&1; echo $?; }

# --- commit
echo clean > a.txt; git add a.txt
assert_eq "a clean file commits" "$(commit clean)" 0

cp "$tmp/leaky" leak.txt; git add leak.txt
rc=$(commit leak)
assert_ne "a staged secret is refused at commit" "$rc" 0
assert_contains "the file is named" "$(cat "$tmp/out")" "leak.txt"
assert_eq "the line is named" "$(grep -cE '^Line: +2$' "$tmp/out")" 1
assert_eq "the secret is redacted" "$(grep -c "$secret" "$tmp/out")" 0
git reset -q; rm leak.txt

# --- push
git push -q origin main >"$tmp/out" 2>&1
assert_eq "a clean push succeeds" "$?" 0

cp "$tmp/leaky" leak.txt; git add leak.txt
git commit -q --no-verify -m leak
git push origin main >"$tmp/out" 2>&1; rc=$?
assert_ne "a --no-verify commit with a secret is refused at push" "$rc" 0
assert_eq "the refused push left the remote untouched" \
    "$(git --git-dir="$tmp/remote.git" rev-parse main)" "$(git rev-parse main~1)"

# A new branch carries the leaking commit even though a later commit is clean.
git rm -q --cached leak.txt; rm leak.txt; git commit -q --no-verify -m "drop the leak"
git checkout -q -b feature
echo more > b.txt; git add b.txt
assert_eq "a clean commit on the new branch" "$(commit more)" 0
git push origin feature >"$tmp/out" 2>&1; rc=$?
assert_ne "a new branch with a secret in an earlier commit is refused" "$rc" 0
assert_eq "the new branch was not created on the remote" \
    "$(git --git-dir="$tmp/remote.git" branch --list feature | wc -l)" 0

# A ref deletion pushes no commits and must not be scanned or blocked.
git push -q --no-verify origin main:scratch >/dev/null 2>&1
git push origin --delete scratch >"$tmp/out" 2>&1
assert_eq "a ref deletion is not blocked" "$?" 0

# --- fail closed without gitleaks
nobin="$tmp/nobin"; mkdir -p "$nobin"
for t in git sh bash env dirname cat; do ln -s "$(command -v "$t")" "$nobin/$t"; done
git checkout -q main; echo c > c.txt; git add c.txt
PATH="$nobin" git commit -q -m nogl >"$tmp/out" 2>&1; rc=$?
assert_ne "commit is refused when gitleaks is missing" "$rc" 0
assert_contains "the message names the releases page" "$(cat "$tmp/out")" "github.com/gitleaks/gitleaks/releases"
assert_contains "the message names the sandbox rebuild" "$(cat "$tmp/out")" "create-ai-sandbox.sh"

# --- a gitleaks that errors is told apart from a finding, and still refuses
errbin="$tmp/errbin"; mkdir -p "$errbin"
printf '#!/bin/sh\necho "boom from stub" >&2\nexit 126\n' > "$errbin/gitleaks"; chmod +x "$errbin/gitleaks"
echo d > d.txt; git add d.txt
PATH="$errbin:$PATH" git commit -q -m err >"$tmp/out" 2>&1; rc=$?
assert_ne "commit is refused when gitleaks itself fails" "$rc" 0
assert_contains "the message says gitleaks failed" "$(cat "$tmp/out")" "gitleaks itself failed (exit 126)"
assert_contains "the tool's output is shown" "$(cat "$tmp/out")" "boom from stub"
assert_eq "a tool error is not reported as a secret" "$(grep -c 'secret found' "$tmp/out")" 0

cd /; rm -rf "$tmp"
finish
