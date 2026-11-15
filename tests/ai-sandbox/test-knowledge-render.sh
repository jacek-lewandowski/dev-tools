#!/usr/bin/env bash
# The render takes only regular files below rules/, roles/ and skills/, and role names of a fixed
# alphabet (O3, O4): a refusal keeps the previous render and writes nothing outside its temporary directory.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"
main="$AI_KNOWLEDGE_ROOT/main"
render() { bash "$REPO_ROOT/bin/ai/ai-knowledge" render >"$tmp/render.out" 2>"$tmp/render.err"; }

mkmain() {   # a fresh checkout of regular files
    rm -rf "$main"; mkdir -p "$main/rules" "$main/roles" "$main/skills/s/sub"
    printf '# Rules\n\n- be brief\n' > "$main/rules/global.md"
    printf -- '---\nname: planner\ndescription: d\n---\nbody\n' > "$main/roles/planner.md"
    printf -- '---\nname: s\ndescription: d\n---\nskill\n' > "$main/skills/s/SKILL.md"
    printf 'sub\n' > "$main/skills/s/sub/f.md"
}
snap() { ( cd "$1" && find . -type f -o -type l | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(sha256sum < "$f" 2>/dev/null)"; done ); }
marker=MARKER-OUTSIDE-THE-CHECKOUT
mkdir -p "$tmp/outside/dir"; printf '%s\n' "$marker" > "$tmp/outside/file.md"; printf '%s\n' "$marker" > "$tmp/outside/dir/global.md"
printf '%s\n' "$marker" > "$tmp/outside/dir/SKILL.md"
mkdir -p "$tmp/outside/dir/sub"; printf '%s\n' "$marker" > "$tmp/outside/dir/sub/f.md"
home_files() { find "$HOME" "$tmp/outside" -type f 2>/dev/null | LC_ALL=C sort | xargs cat 2>/dev/null | grep -c "$marker"; }

mkmain; render; rc=$?
assert_eq "baseline: the clean checkout renders" "$rc" 0
before=$(snap "$AI_KNOWLEDGE_RENDER")

# --- O3: a link at any level refuses the whole render
refuse_case() {   # <label> <path under main> <link target> <is dir: dir|file>
    mkmain; rm -rf "$main/$2"; ln -s "$3" "$main/$2"
    render; rc=$?
    assert_eq "O3 $1: refused" "$([ "$rc" -ne 0 ] && echo yes)" yes
    assert_eq "O3 $1: the previous render is byte-identical" "$(snap "$AI_KNOWLEDGE_RENDER")" "$before"
    assert_eq "O3 $1: the marker is in no rendered or linked place" \
        "$( { grep -rl "$marker" "$AI_KNOWLEDGE_RENDER" "$HOME/.agents/skills" "$HOME/.claude/agents" "$AI_SANDBOX_ROOT/shared/agent-skills" 2>/dev/null; } | wc -l | tr -d ' ')" 0
    assert_contains "O3 $1: standard error names the path" "$(cat "$tmp/render.err")" "$2"
}
refuse_case "rules" rules "$tmp/outside/dir"
refuse_case "rules/global.md" rules/global.md "$tmp/outside/file.md"
refuse_case "roles" roles "$tmp/outside/dir"
refuse_case "roles/planner.md" roles/planner.md "$tmp/outside/file.md"
refuse_case "skills" skills "$tmp/outside/dir"
refuse_case "skills/s" skills/s "$tmp/outside/dir"
refuse_case "skills/s/SKILL.md" skills/s/SKILL.md "$tmp/outside/file.md"
refuse_case "skills/s/sub/f.md" skills/s/sub/f.md "$tmp/outside/file.md"
mkmain; render; assert_eq "O3: the same checkout without a link renders" "$?" 0

# --- O4: role names come from [a-z0-9][a-z0-9-]{0,63}
mkdir -p "$tmp/abs"
name_case() {   # <label> <front-matter name, or empty for none> <file name>
    mkmain; rm -f "$main/roles/planner.md"
    if [ -n "$2" ]; then printf -- '---\nname: %s\ndescription: d\n---\nbody\n' "$2" > "$main/roles/$3"
    else printf 'body\n' > "$main/roles/$3"; fi
    local files; files=$(find "$tmp" -type f | LC_ALL=C sort)
    render; rc=$?
    assert_eq "O4 $1: refused" "$([ "$rc" -ne 0 ] && echo yes)" yes
    assert_eq "O4 $1: the previous render is byte-identical" "$(snap "$AI_KNOWLEDGE_RENDER")" "$before"
    assert_eq "O4 $1: no new file anywhere under the test's home" "$(find "$tmp" -type f | LC_ALL=C sort | diff - <(printf '%s\n' "$files") | grep -c '^<' | tr -d ' ')" 0
    assert_contains "O4 $1: standard error names the role file" "$(cat "$tmp/render.err")" "roles/$3"
}
name_case "dotdot" "../evil" x.md
name_case "absolute" "$tmp/abs/evil" x.md
name_case "space" "a b" x.md
name_case "slash" "a/b" x.md
name_case "file name without front matter" "" "Bad Name.md"
name_case "leading dash" "-a" x.md
name_case "65 characters" "$(printf 'a%.0s' $(seq 1 65))" x.md
assert_eq "O4: nothing was written to the absolute name" "$(ls "$tmp/abs" | wc -l | tr -d ' ')" 0
mkmain; rm -f "$main/roles/planner.md"; printf -- '---\nname: good-name1\ndescription: d\n---\nbody\n' > "$main/roles/x.md"
render; assert_eq "O4: a name of the alphabet renders" "$?" 0
assert_file "O4: its role is rendered" "$AI_KNOWLEDGE_RENDER/claude/agents/good-name1.md"
mkmain; rm -f "$main/roles/planner.md"; printf -- '---\nname: %s\ndescription: d\n---\nbody\n' "$(printf 'a%.0s' $(seq 1 64))" > "$main/roles/x.md"
render; assert_eq "O4: 64 characters render" "$?" 0

finish
