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
assert_eq    "project-path content"                 "$(cat "$dir/project-path")" "$proj"
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
