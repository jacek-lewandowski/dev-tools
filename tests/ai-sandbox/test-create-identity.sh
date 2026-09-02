#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai-sandbox-lib.sh"

# Called directly, not via $(), so the exports inside fake_home actually
# reach this shell (and thus the create-ai-sandbox.sh child processes below).
# See the comment on fake_home in harness.sh.
fake_home >/dev/null
tmp="$FAKE_HOME_DIR"
proj="$tmp/work/dev-tools"
mkdir -p "$proj"
( cd "$proj" && git init -q . && git config user.email t@e && git config user.name t )

bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 \
    || { echo "script failed:"; cat "$tmp/out"; }

id=$(ai_sandbox_project_id "$proj")
dir="$AI_SANDBOX_ROOT/${id}-agent"
assert_file  "sandbox dir uses the path-derived id" "$dir"
assert_file  "project-path recorded"                "$dir/project-path"
# $(...) strips ALL trailing newlines, so comparing against "$(cat file)"
# can't tell "$proj\n" apart from "$proj" with no newline at all. Read the
# exact bytes instead (appending 'x' then stripping it is the standard trick
# to stop command substitution from eating a trailing newline) so a
# regression that drops the trailing newline actually fails this assertion.
project_path_bytes=$(cat "$dir/project-path"; printf x)
project_path_bytes=${project_path_bytes%x}
assert_eq    "project-path content (exact bytes, trailing newline included)" \
             "$project_path_bytes" "$proj"$'\n'
assert_no_file "no basename-only dir"               "$AI_SANDBOX_ROOT/dev-tools-agent"
assert_contains "compose names the new container"   "$(cat "$dir/docker-compose.yml")" \
                "container_name: \"${id}-agent\""
assert_contains "compose keeps the real project path" \
                "$(cat "$dir/docker-compose.yml")" "\"${proj}:${proj}\""

# Two projects with the same basename must land in different directories.
proj2="$tmp/play/dev-tools"
mkdir -p "$proj2"
bash "$REPO_ROOT/bin/create-ai-sandbox.sh" --display=none --no-start "$proj2" >>"$tmp/out" 2>&1 || true
id2=$(ai_sandbox_project_id "$proj2")
assert_file "second same-named project gets its own dir" "$AI_SANDBOX_ROOT/${id2}-agent"

rm -rf "$tmp"
finish
