#!/usr/bin/env bash
# The structural rule for host git starts (C-GIT): under bin/ai, a command whose
# name or any argument is the word git belongs in the body of ai_sandbox_host_git
# or ai_sandbox_confined_git, nowhere else. The rule is sg/rules/host-git.yml.
#
# Declared dependency of the suite: ast-grep (verified with 0.51.0). A missing
# ast-grep fails this file; it never skips it. A version that parses differently
# fails the known cases below, which is the version check.
set -uo pipefail
here=${BASH_SOURCE[0]%/*}
. "$here/harness.sh"

if ! command -v ast-grep >/dev/null 2>&1; then
    TESTS_RUN=1
    _fail "ast-grep is installed (a declared dependency of this suite)" "ast-grep is not on PATH"
    finish; exit
fi

SG="$REPO_ROOT/tests/ai-sandbox/sg"
# In-image programs are not host helpers (O22); the rule does not apply to them.
NAMED_EXCEPTIONS="bin/ai/ai-delegate bin/ai/sandbox-knowledge-sync"
# The inline rule the coverage check uses: every file the configuration parses as bash has one program node.
COVERAGE_RULE=$'id: coverage\nlanguage: bash\nrule: {kind: program}\nseverity: hint\nmessage: parsed'

# "<path relative to <dir>>:<line>" for every finding of a rule run, in file and line order.
sg_findings() {   # <dir> [ast-grep scan options...]
    local dir=$1; shift
    ast-grep scan -c "$SG/sgconfig.yml" "$@" "$dir" --json=stream 2>/dev/null \
        | python3 -I -c '
import json, sys
dir = sys.argv[1].rstrip("/") + "/"
rows = []
for line in sys.stdin:
    d = json.loads(line)
    f = d["file"]
    rows.append((f[len(dir):] if f.startswith(dir) else f, d["range"]["start"]["line"] + 1))
for f, n in sorted(rows):
    print("%s:%d" % (f, n))
' "$dir"
}
sg_reports() { sg_findings "$1"; }
# The bash files under <root>/bin/ai: name ends .sh, or the first line names bash or sh.
bash_files() {   # <root>: paths relative to <root>
    local f
    ( cd "$1" && find bin/ai -type f | LC_ALL=C sort ) | while IFS= read -r f; do
        case $f in *.sh) echo "$f"; continue ;; esac
        head -n1 "$1/$f" | command grep -qaE '^#!.*\b(ba)?sh\b' && echo "$f"
    done
}
# Files that are bash but neither parsed by the configuration nor named as exceptions.
uncovered() {   # <root> <named exceptions>
    local parsed f
    parsed=$(sg_findings "$1/bin/ai" --inline-rules "$COVERAGE_RULE" | sed 's/:[0-9]*$//')
    bash_files "$1" | while IFS= read -r f; do
        case " $2 " in *" $f "*) continue ;; esac
        printf '%s\n' "$parsed" | command grep -qxF "${f#bin/ai/}" || echo "$f"
    done
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# --- the known case: one start of each form, the exempt forms, a heredoc
mkdir -p "$tmp/known"
cat > "$tmp/known/ai-known" <<'EOF'
#!/usr/bin/env bash
git status
/usr/bin/git status
command git log
exec nice -n 5 git gc
if ! { GIT_INDEX_FILE=$idx git -C "$r" read-tree x; }; then :; fi
nice timeout 5 git fetch
"git" status
'git' status
"/usr/bin/git" status
timeout 5 "git" fetch
require git
hint git push
command -v git
cat <<'DOC'
git rev-parse HEAD
DOC
EOF
reports=$(sg_reports "$tmp/known")
assert_eq "the known case gives exactly the ten starts" "$(printf '%s\n' "$reports" | command grep -c .)" 10
assert_eq "the ten starts are the ten lines of the forms" "$(printf '%s\n' "$reports" | sed 's/.*://' | tr '\n' ' ')" "2 3 4 5 6 7 8 9 10 11 "
assert_eq "the exempt forms and the heredoc body give no report" \
    "$(printf '%s\n' "$reports" | sed 's/.*://' | command grep -cE '^(12|13|14|16)$')" 0
assert_contains "an extensionless file is scanned" "$reports" "ai-known:2"

# a start inside one of the two C-GIT functions is the rule's own place; inside any other function it is reported
mkdir -p "$tmp/fn"
cat > "$tmp/fn/ai-fn" <<'EOF'
#!/usr/bin/env bash
ai_sandbox_host_git() {
    git "$@"
}
ai_sandbox_confined_git() {
    timeout 5 git "$@"
}
some_other_function() {
    git status
}
EOF
assert_eq "only the start outside the two C-GIT bodies is reported" "$(sg_reports "$tmp/fn")" "ai-fn:9"

# a file the configuration does not map is not parsed: the failure mode the coverage check guards
mkdir -p "$tmp/unmapped"
printf '#!/usr/bin/env bash\ngit status\n' > "$tmp/unmapped/plain-script"
assert_eq "a bash file the configuration does not map gives no report" "$(sg_reports "$tmp/unmapped" | command grep -c .)" 0

# --- every bash file under bin/ai is parsed or a named exception
mkdir -p "$tmp/cov/bin/ai"
cp "$tmp/known/ai-known" "$tmp/cov/bin/ai/ai-known"
printf '#!/usr/bin/env bash\ntrue\n' > "$tmp/cov/bin/ai/newhelper"
printf '#!/bin/sh\ntrue\n' > "$tmp/cov/bin/ai/other.sh"
printf '# a note\n' > "$tmp/cov/bin/ai/NOTES.md"
assert_eq "a new bash file the configuration does not map is found" "$(uncovered "$tmp/cov" "" | tr '\n' ' ')" "bin/ai/newhelper "
assert_eq "a named exception is not required to be parsed" "$(uncovered "$tmp/cov" "bin/ai/newhelper" | tr '\n' ' ')" ""
assert_eq "every bash file under bin/ai is parsed or a named exception" "$(uncovered "$REPO_ROOT" "$NAMED_EXCEPTIONS")" ""
assert_ne "the bash files of bin/ai are found at all" "$(bash_files "$REPO_ROOT" | command grep -c .)" 0

# --- the named exceptions are not host helpers
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
for e in $NAMED_EXCEPTIONS; do
    assert_eq "${e##*/} is no installed helper" "$(ai_sandbox_helpers | command grep -cxF "${e##*/}")" 0
    assert_file "${e##*/} exists, so the exception names a real file" "$REPO_ROOT/$e"
done
for f in ai_sandbox_host_git ai_sandbox_confined_git; do
    assert_eq "the lib defines $f, the name the rule exempts" "$(command grep -cE "^$f\(\) \{" "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh")" 1
    assert_eq "the rule file names $f" "$(command grep -cF "$f" "$SG/rules/host-git.yml")" 1
done

# --- the tree: no report outside the two bodies and the named exceptions
tree=$(sg_reports "$REPO_ROOT/bin/ai" | while IFS= read -r r; do
    case " $NAMED_EXCEPTIONS " in *" bin/ai/${r%:*} "*) continue ;; esac
    echo "$r"
done)
assert_eq "no report outside the two bodies and the named exceptions" "$(printf '%s\n' "$tree" | command grep -vc '^$')" 0

# a direct start planted in a copy of a real helper is reported by the same run that finds nothing in the real one
mkdir -p "$tmp/planted"
cp "$REPO_ROOT/bin/ai/ai-sandbox-restart" "$tmp/planted/ai-sandbox-restart"
assert_eq "the real helper gives no report" "$(sg_reports "$tmp/planted" | command grep -c .)" 0
printf 'git -C "$AI_SANDBOX_PROJECT" status\n' >> "$tmp/planted/ai-sandbox-restart"
assert_eq "a planted direct start in it is reported" "$(sg_reports "$tmp/planted" | sed 's/.*://' | command grep -c .)" 1

# --- a missing ast-grep fails the file: run it with a PATH that has no ast-grep
mkdir -p "$tmp/nobin"
for c in dirname mktemp rm; do ln -s "$(command -v $c)" "$tmp/nobin/$c"; done
out=$(PATH="$tmp/nobin" /bin/bash "${BASH_SOURCE[0]}" 2>&1); r=$?
assert_eq "a missing ast-grep fails the file" "$r" 1
assert_contains "a missing ast-grep is reported, not skipped" "$out" "not ok 1 - ast-grep is installed"

finish
