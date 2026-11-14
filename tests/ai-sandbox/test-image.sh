#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
a="$tmp/work/a"; b="$tmp/work/b"; mkdir -p "$a" "$b"
uid=$(id -u)
tag="ai-sandbox:base-u${uid}"

bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$a" >"$tmp/o1" 2>&1 || true
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$b" >"$tmp/o2" 2>&1 || true

ca="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$a")-agent/docker-compose.yml"
cb="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$b")-agent/docker-compose.yml"

assert_contains "project A uses the shared tag" "$(cat "$ca")" "image: \"$tag\""
assert_contains "project B uses the same tag"   "$(cat "$cb")" "image: \"$tag\""
case "$(cat "$ca")" in
    *"build:"*) TESTS_RUN=$((TESTS_RUN+1)); _fail "compose has no build: block" "found one" ;;
    *)          TESTS_RUN=$((TESTS_RUN+1)); _pass "compose has no build: block" ;;
esac
assert_file    "shared build context" "$AI_SANDBOX_ROOT/image/build/Dockerfile"
assert_no_file "no per-project build" "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$a")-agent/build"

# Container home must match the host home, so paths line up on both sides.
assert_contains "USER_HOME build arg" "$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")" 'ARG USER_HOME'
assert_contains "container home matches the host home" "$(cat "$ca")" ":$HOME/tools:ro"

# Without a UTF-8 LANG, Java reports sun.jnu.encoding=ANSI_X3.4-1968 and cannot
# open files whose names have non-ASCII characters.
assert_contains "Dockerfile sets UTF-8 LANG" "$(cat "$AI_SANDBOX_ROOT/image/build/Dockerfile")" 'LANG=C.UTF-8'

# The hash must be stable across runs, and change when any input changes.
h1=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev base)
h2=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev base)
assert_eq "build hash is stable" "$h1" "$h2"
assert_eq "build hash is a sha256" "$(printf '%s' "$h1" | wc -c | tr -d ' ')" '64'
h3=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1001 1000 dev /home/dev base)
if [ "$h1" = "$h3" ]; then TESTS_RUN=$((TESTS_RUN+1)); _fail "build hash covers build args" "unchanged"
else TESTS_RUN=$((TESTS_RUN+1)); _pass "build hash covers build args"; fi
echo '# poke' >> "$AI_SANDBOX_ROOT/image/build/Dockerfile"
h4=$(ai_sandbox_build_hash "$AI_SANDBOX_ROOT/image/build" 1000 1000 dev /home/dev base)
if [ "$h1" = "$h4" ]; then TESTS_RUN=$((TESTS_RUN+1)); _fail "build hash covers file contents" "unchanged"
else TESTS_RUN=$((TESTS_RUN+1)); _pass "build hash covers file contents"; fi

# The docker variant is a separate tag, so the two never overwrite each other.
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start --with-docker "$a" >>"$tmp/o1" 2>&1 || true
assert_contains "docker variant tag" "$(cat "$ca")" "ai-sandbox:docker-u${uid}"
# A bare re-run keeps the docker tag: the sticky flag must be read from .env
# before the tag is derived, or the docker Dockerfile lands under the base tag.
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$a" >>"$tmp/o1" 2>&1 || true
assert_contains "docker tag survives a bare re-run" "$(cat "$ca")" "ai-sandbox:docker-u${uid}"

# --- display or not: the GUI applications are in the -gui image only -------
# Stubs only to get past the require/xauth calls of the display modes (as test-resources.sh).
xs="$tmp/xstub"; mkdir -p "$xs"
for t in xpra Xvfb; do printf '#!/bin/sh\nexit 0\n' > "$xs/$t"; done
printf '#!/bin/sh\nexit 0\n' > "$xs/xauth"
printf '#!/bin/sh\necho 0123456789abcdef0123456789abcdef\n' > "$xs/mcookie"
chmod +x "$xs"/*
create() { PATH="$xs:$PATH" bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" ${NOSTART---no-start} "$@" >>"$tmp/o3" 2>&1 || true; }
compose_of() { printf '%s' "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$1")-agent/docker-compose.yml"; }
image_of() { grep -o 'image: "[^"]*"' "$(compose_of "$1")"; }
bdf() { cat "$AI_SANDBOX_ROOT/image/build/Dockerfile"; }
gui_only='claude-desktop antigravity-repo google-chrome-stable Antigravity.tar.gz Antigravity%20IDE openbox'
headless_layer='cli_linux_x64.tar.gz playwright@${PLAYWRIGHT_VERSION} puppeteer-core@${PUPPETEER_CORE_VERSION} PUPPETEER_EXECUTABLE_PATH PLAYWRIGHT_MCP_EXECUTABLE_PATH'
c="$tmp/work/c"; mkdir -p "$c"

# The stamp is written by the build, which --no-start skips: these two runs build (stub docker).
stampdir="$AI_SANDBOX_ROOT/image"
NOSTART= create --display=none "$c"
stamp_none=$(ls "$stampdir" | grep '\.stamp$' | tr '\n' ' ')
# (A Wayland socket stands in for the display: xpra would start a real display launcher.)
wl="$tmp/xdg"; mkdir -p "$wl"; python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$wl/wayland-t"
XDG_RUNTIME_DIR="$wl" WAYLAND_DISPLAY=wayland-t NOSTART= create --display=wayland "$c"
stamp_both=$(ls "$stampdir" | grep '\.stamp$' | tr '\n' ' ')
create --display=none "$c"
none_df=$(bdf)
for w in $headless_layer; do assert_contains "none: the Dockerfile has $w" "$none_df" "$w"; done
for w in $gui_only; do
    TESTS_RUN=$((TESTS_RUN+1))
    case "$none_df" in *"$w"*) _fail "none: the Dockerfile has no $w" "found it" ;; *) _pass "none: the Dockerfile has no $w" ;; esac
done
assert_eq "none: the headless tag"  "$(image_of "$c")" "image: \"ai-sandbox:base-u${uid}\""

create --display=xpra "$c"
gui_df=$(bdf)
for w in $headless_layer $gui_only; do assert_contains "xpra: the Dockerfile has $w" "$gui_df" "$w"; done
assert_eq "xpra: the -gui tag" "$(image_of "$c")" "image: \"ai-sandbox:base-gui-u${uid}\""
# O4: one variant, two builds, two stamp names (the build hash differs anyway; the name is the part that could collide).
assert_eq "none leaves base-u<uid>.stamp"             "$stamp_none" "base-u${uid}.stamp "
assert_contains "a display build adds its own stamp, not the same" "$stamp_both" "base-gui-u${uid}.stamp"
assert_contains "and the headless stamp stays"          "$stamp_both" "base-u${uid}.stamp"

# O2: the remembered mode picks the tag when no flag is given; an explicit none overrides a remembered xpra.
create "$c"
assert_eq "remembered xpra, no flag: -gui" "$(image_of "$c")" "image: \"ai-sandbox:base-gui-u${uid}\""
create --display=none "$c"
assert_eq "--display=none over a remembered xpra: headless" "$(image_of "$c")" "image: \"ai-sandbox:base-u${uid}\""
create --display=xpra --with-docker "$c"
assert_eq "docker and display: docker-gui" "$(image_of "$c")" "image: \"ai-sandbox:docker-gui-u${uid}\""
create --display=none --with-docker "$c"
assert_eq "docker and no display: docker" "$(image_of "$c")" "image: \"ai-sandbox:docker-u${uid}\""
# --display=auto takes the suffix of the mode display_resolve picks (xpra with the stubs above).
d="$tmp/work/d"; mkdir -p "$d"
create --display=auto "$d"
assert_eq "auto resolved to xpra: -gui" "$(image_of "$d")" "image: \"ai-sandbox:base-gui-u${uid}\""
assert_eq "the remembered mode is the resolved one" "$(sed -n 's/^SANDBOX_DISPLAY_MODE=//p' "$(dirname "$(compose_of "$d")")/.env")" xpra

rm -rf "$tmp"
finish
