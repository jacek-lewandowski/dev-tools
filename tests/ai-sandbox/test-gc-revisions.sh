#!/usr/bin/env bash
# ai-sandbox-gc and the installed revisions (C-INSTALL): the revisions that are not current and the
# partial exports are listed and, after a yes, removed (they are read-only directories); never the
# current one; none while a sandbox container runs.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
inst="$AI_SANDBOX_ROOT/installed"
rm "$inst/current"
for c in c1 c2; do mkdir -p "$inst/rev/$c/bin/ai" "$inst/rev/$c/tools"; echo x > "$inst/rev/$c/bin/ai/f"; done
mkdir -p "$inst/rev/.partial-c3/bin"; echo x > "$inst/rev/.partial-c3/bin/f"
ln -s rev/c2 "$inst/current"
chmod -R a-w "$inst/rev/c1" "$inst/rev/c2" "$inst/rev/.partial-c3"
gc() { bash "$REPO_ROOT/bin/ai/ai-sandbox-gc" "$@"; }

# a sandbox container running: listed as kept, nothing removed, even after a yes
out=$(printf 'y\n' | DOCKER_STUB_PS=abc-agent gc 2>&1)
assert_contains "running: the old revision is listed" "$out" "$inst/rev/c1"
assert_contains "and the partial export" "$out" "$inst/rev/.partial-c3"
assert_contains "as kept" "$out" "Kept: installed revisions"
assert_contains "with the advice to stop the sandboxes" "$out" "stop the running sandboxes first"
assert_eq "the current revision is not listed" "$(printf '%s\n' "$out" | grep -c "$inst/rev/c2")" 0
assert_file "running: rev/c1 stays" "$inst/rev/c1/bin/ai/f"
assert_file "running: the partial export stays" "$inst/rev/.partial-c3/bin/f"

# no sandbox container running: listed, asked, removed after a yes
out=$(printf 'n\n' | DOCKER_STUB_PS= gc 2>&1)
assert_contains "idle: the old revision is listed" "$out" "$inst/rev/c1"
assert_contains "and the partial export" "$out" "$inst/rev/.partial-c3"
assert_eq "never the current one" "$(printf '%s\n' "$out" | grep -c "$inst/rev/c2")" 0
assert_file "declined: rev/c1 stays" "$inst/rev/c1/bin/ai/f"
out=$(printf 'y\n' | DOCKER_STUB_PS= gc 2>&1)
assert_no_file "after y: rev/c1 is gone (a read-only directory)" "$inst/rev/c1"
assert_no_file "and the partial export" "$inst/rev/.partial-c3"
assert_file "the current revision stays" "$inst/rev/c2/bin/ai/f"
assert_eq "current still names it" "$(readlink "$inst/current")" "rev/c2"
out=$(DOCKER_STUB_PS= gc </dev/null 2>&1)
assert_contains "then there is nothing to reclaim" "$out" "Nothing to reclaim."

chmod -R u+w "$inst/rev"; rm -rf "$tmp"
finish
