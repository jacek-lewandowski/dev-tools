#!/usr/bin/env bash
# Every Python a host program under bin/ai starts runs isolated (python3 -I), so it reads
# neither the working directory nor PYTHON* variables, which a sandbox can plant (D27, O19).
# The rule is sg/rules/host-python.yml; programs of bin/ai/image/ run in the container and
# are left out by directory. Declared dependency: ast-grep, as for test-host-git.sh.
set -uo pipefail
here=${BASH_SOURCE[0]%/*}
. "$here/harness.sh"

if ! command -v ast-grep >/dev/null 2>&1; then
    TESTS_RUN=1
    _fail "ast-grep is installed (a declared dependency of this suite)" "ast-grep is not on PATH"
    finish; exit
fi

SG="$REPO_ROOT/tests/ai-sandbox/sg"
# "<path relative to <dir>>:<line>" for every finding of the rule, in file and line order.
reports() {   # <dir>
    local dir=$1
    ast-grep scan -c "$SG/sgconfig.yml" --filter '^host-python' "$dir" --json=stream 2>/dev/null \
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

tmp=$(mktemp -d); trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT

# --- the tree: no host Python without -I
assert_eq "no host Python call without -I in bin/ai" "$(reports "$REPO_ROOT/bin/ai" | command grep -c .)" 0

# --- known cases, each in a copy of bin/ai
mkdir -p "$tmp/copy/bin"; cp -r "$REPO_ROOT/bin/ai" "$tmp/copy/bin/ai"; chmod -R u+w "$tmp/copy"; ai=$tmp/copy/bin/ai
host=ai-sandbox-restart
assert_eq "the copy gives no report" "$(reports "$tmp/copy" | command grep -c .)" 0
n=$(wc -l < "$ai/$host")
printf 'python3 - "$1" <<'"'"'EOF'"'"'\nprint(1)\nEOF\n' >> "$ai/$host"
assert_eq "a planted python3 without -I is one finding, naming file and line" \
    "$(reports "$tmp/copy")" "bin/ai/$host:$((n + 1))"
cp "$REPO_ROOT/bin/ai/$host" "$ai/$host"; chmod u+w "$ai/$host"
for planted in \
    'python3 -I - "$1" <<'"'"'EOF'"'"'' \
    'VAR=x python3 -I -c "print(1)"' \
    'command -v python3 >/dev/null 2>&1 || true' \
    'require python3' \
    'echo hi | python3 -sI -c "print(1)"'; do
    printf '%s\nprint(1)\nEOF\n' "$planted" >> "$ai/$host"
done
assert_eq "with -I, command -v python3 and require python3: no finding" "$(reports "$tmp/copy" | command grep -c .)" 0
cp "$REPO_ROOT/bin/ai/$host" "$ai/$host"; chmod u+w "$ai/$host"
for planted in 'exec python3 -m pkg' 'x=$(echo | python3 -c "print(1)")' 'VAR=x /usr/bin/python3 - <<EOF'; do
    cp "$REPO_ROOT/bin/ai/$host" "$ai/$host"; chmod u+w "$ai/$host"
    printf '%s\n' "$planted" >> "$ai/$host"
    assert_eq "a planted '$planted' is reported" "$(reports "$tmp/copy" | sed 's/.*://' | command grep -c .)" 1
done
for planted in 'python3.10 -c "print(1)"' 'python3 - "$f" -I' 'python3 script.py -I'; do
    cp "$REPO_ROOT/bin/ai/$host" "$ai/$host"; chmod u+w "$ai/$host"
    printf '%s\n' "$planted" >> "$ai/$host"
    assert_eq "a planted '$planted' is reported" "$(reports "$tmp/copy" | sed 's/.*://' | command grep -c .)" 1
done
for planted in 'python3.10 -I -c "print(1)"' 'python3 -I script.py -x'; do
    cp "$REPO_ROOT/bin/ai/$host" "$ai/$host"; chmod u+w "$ai/$host"
    printf '%s\n' "$planted" >> "$ai/$host"
    assert_eq "a planted '$planted' is not reported" "$(reports "$tmp/copy" | command grep -c .)" 0
done
cp "$REPO_ROOT/bin/ai/$host" "$ai/$host"; chmod u+w "$ai/$host"
printf '#!/usr/bin/env bash\npython3 - <<EOF\nprint(1)\nEOF\n' > "$ai/image/planted-in-image"
assert_eq "the same line under bin/ai/image/ is not reported" "$(reports "$tmp/copy" | command grep -c .)" 0
cp "$ai/image/planted-in-image" "$ai/planted-outside.sh"
assert_eq "known case: the same file outside bin/ai/image/ is reported" "$(reports "$tmp/copy")" "bin/ai/planted-outside.sh:2"

finish
