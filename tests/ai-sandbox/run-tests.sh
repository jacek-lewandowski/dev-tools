#!/usr/bin/env bash
# Runs every test-*.sh and reports a combined result.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# C-INSTALL: a host entry point; not from a tree a sandbox can write.
. "$here/../../bin/ai/ai-sandbox-lib.sh"
ai_sandbox_refuse_writable_self "${BASH_SOURCE[0]}" || exit 3
rc=0
for t in "$here"/test-*.sh; do
    printf '\n# %s\n' "$(basename "$t")"
    bash "$t" || rc=1
done
[ "$rc" -eq 0 ] && printf '\nALL SUITES PASSED\n' || printf '\nSOME SUITES FAILED\n' >&2
exit "$rc"
