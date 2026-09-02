#!/usr/bin/env bash
# Runs every test-*.sh and reports a combined result.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rc=0
for t in "$here"/test-*.sh; do
    printf '\n# %s\n' "$(basename "$t")"
    bash "$t" || rc=1
done
[ "$rc" -eq 0 ] && printf '\nALL SUITES PASSED\n' || printf '\nSOME SUITES FAILED\n' >&2
exit "$rc"
