#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

# Build a legacy sandbox by hand: basename-keyed dir, no project-path file.
make_legacy() {
    local name=$1 project=$2
    local dir="$AI_SANDBOX_ROOT/${name}-agent"
    mkdir -p "$dir/.claude" "$dir/antigravity-data/User"
    printf 'working_dir: "%s"\n' "$project" > "$dir/docker-compose.yml"
    printf 'token-for-%s\n' "$name" > "$dir/.claude/.credentials.json"
    printf 'history-for-%s\n' "$name" > "$dir/antigravity-data/User/History"
    printf '%s' "$dir"
}

# Called directly, not via $(), so the exports inside fake_home actually
# reach this shell. See the comment on fake_home in harness.sh.
fake_home >/dev/null
tmp="$FAKE_HOME_DIR"
p1="$tmp/work/dev-tools"; mkdir -p "$p1"
old=$(make_legacy dev-tools "$p1")

bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" >"$tmp/m1" 2>&1 || { echo FAILED; cat "$tmp/m1"; }

id=$(ai_sandbox_project_id "$p1")
new="$AI_SANDBOX_ROOT/${id}-agent"
assert_file    "legacy dir renamed"        "$new"
assert_no_file "old dir gone"              "$old"
assert_eq      "project-path written"      "$(cat "$new/project-path")" "$p1"
assert_eq      "credentials survived"      "$(cat "$new/.claude/.credentials.json")" "token-for-dev-tools"
assert_eq      "antigravity history survived" \
               "$(cat "$new/antigravity-data/User/History")" "history-for-dev-tools"
assert_eq      "schema version recorded"   "$(cat "$AI_SANDBOX_ROOT/.schema-version")" '2'

# Idempotent: a second run changes nothing and says nothing.
out=$(bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" 2>&1)
assert_eq "second run is silent" "$out" ''
assert_file "still there after re-run" "$new"

# Same basename, different paths: both migrate, to different directories.
fake_home >/dev/null
tmp2="$FAKE_HOME_DIR"
a="$tmp2/work/app"; b="$tmp2/play/app"; mkdir -p "$a" "$b"
mkdir -p "$AI_SANDBOX_ROOT/app-agent" "$AI_SANDBOX_ROOT/legacy2-agent"
printf 'working_dir: "%s"\n' "$a" > "$AI_SANDBOX_ROOT/app-agent/docker-compose.yml"
printf 'working_dir: "%s"\n' "$b" > "$AI_SANDBOX_ROOT/legacy2-agent/docker-compose.yml"
bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" >/dev/null 2>&1
assert_file "first same-named migrated"  "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$a")-agent"
assert_file "second same-named migrated" "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$b")-agent"

# A directory with no usable compose file is left alone and reported.
fake_home >/dev/null
tmp3="$FAKE_HOME_DIR"
mkdir -p "$AI_SANDBOX_ROOT/orphan-agent"
out=$(bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" 2>&1)
assert_file     "unparsable dir left in place" "$AI_SANDBOX_ROOT/orphan-agent"
assert_contains "unparsable dir reported"      "$out" 'orphan-agent'

# A target that already exists is a hard stop for that one sandbox.
fake_home >/dev/null
tmp4="$FAKE_HOME_DIR"
p="$tmp4/work/dup"; mkdir -p "$p"
mkdir -p "$AI_SANDBOX_ROOT/dup-agent" "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$p")-agent"
printf 'working_dir: "%s"\n' "$p" > "$AI_SANDBOX_ROOT/dup-agent/docker-compose.yml"
out=$(bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" 2>&1)
assert_file     "conflicting source kept" "$AI_SANDBOX_ROOT/dup-agent"
assert_contains "conflict reported"       "$out" 'already exists'

rm -rf "$tmp" "$tmp2" "$tmp3" "$tmp4"
# A running container must block its own migration: moving the directory would
# strand a live container's bind mounts, and force-removing it would destroy
# whatever is running inside.
fake_home >/dev/null; tmpR="$FAKE_HOME_DIR"
pr="$tmpR/work/live"; mkdir -p "$pr"
live="$AI_SANDBOX_ROOT/live-agent"; mkdir -p "$live/.claude"
printf 'working_dir: "%s"\n' "$pr" > "$live/docker-compose.yml"
echo token > "$live/.claude/.credentials.json"
out=$(DOCKER_STUB_RUNNING=true bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" 2>&1)
assert_file     "running sandbox not moved"    "$live/docker-compose.yml"
assert_eq       "its credentials untouched"    "$(cat "$live/.claude/.credentials.json")" 'token'
assert_no_file  "no new dir created for it"    "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$pr")-agent"
assert_contains "refusal explains what to do"  "$out" 'ai-sandbox-stop'
assert_no_file "refusal leaves .schema-version unwritten" "$AI_SANDBOX_ROOT/.schema-version"
# Once stopped, the same sandbox migrates normally.
out=$(bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" 2>&1)
assert_file "migrates once stopped" "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$pr")-agent/.claude/.credentials.json"
assert_eq   "clean run records the schema version" "$(cat "$AI_SANDBOX_ROOT/.schema-version")" "$AI_SANDBOX_SCHEMA_VERSION"
rm -rf "$tmpR"

# M2 obeys the same rule: a running sandbox's bulk stays where its bind mounts
# expect it. Once stopped, it is lifted into shared/.
fake_home >/dev/null; tmpS="$FAKE_HOME_DIR"
ps="$tmpS/work/bulk"; mkdir -p "$ps"
sb="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$ps")-agent"
mkdir -p "$sb/.claude/downloads"; printf '%s\n' "$ps" > "$sb/project-path"
echo blob > "$sb/.claude/downloads/x"
out=$(DOCKER_STUB_RUNNING=true bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" 2>&1)
assert_file     "running sandbox keeps its bulk"  "$sb/.claude/downloads/x"
assert_no_file  "nothing lifted while running"    "$AI_SANDBOX_ROOT/shared/claude-downloads/x"
assert_contains "M2 refusal explains what to do"  "$out" 'ai-sandbox-stop'
assert_no_file  "M2 refusal leaves .schema-version unwritten" "$AI_SANDBOX_ROOT/.schema-version"
bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" >/dev/null 2>&1
assert_file     "lifted once stopped"            "$AI_SANDBOX_ROOT/shared/claude-downloads/x"
assert_no_file  "per-project copy gone"          "$sb/.claude/downloads/x"
assert_file     "schema version recorded after"  "$AI_SANDBOX_ROOT/.schema-version"
# .schema-version is read back: a store written by a newer dev-tools is left
# alone rather than reinterpreted with this script's older rules.
echo 99 > "$AI_SANDBOX_ROOT/.schema-version"
mkdir -p "$AI_SANDBOX_ROOT/late-agent"
printf 'working_dir: "%s"\n' "$tmpS/work/late" > "$AI_SANDBOX_ROOT/late-agent/docker-compose.yml"
out=$(bash "$REPO_ROOT/bin/ai/ai-sandbox-migrate" 2>&1)
assert_contains "newer schema is refused"        "$out" 'schema 99'
assert_file     "newer store untouched"          "$AI_SANDBOX_ROOT/late-agent"
assert_eq       "newer marker not overwritten"   "$(cat "$AI_SANDBOX_ROOT/.schema-version")" '99'
rm -rf "$tmpS"

finish
