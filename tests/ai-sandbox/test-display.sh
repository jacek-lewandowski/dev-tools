#!/usr/bin/env bash
# Two sandboxes must never share an X display number: the second one cannot
# authenticate to a server started with the first one's cookie.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"

run()  { bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$1" >"$tmp/out" 2>&1 || true; }
dir()  { printf '%s' "$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$1")-agent"; }
num()  { sed -n 's/^SANDBOX_DISPLAY_NUM=//p' "$(dir "$1")/.env" | tail -n 1; }
# The historical formula: 80 slots, so collisions are easy to manufacture.
slot() { printf '%s' "$(( $(printf '%s' "$(ai_sandbox_project_id "$1")" | cksum | cut -d' ' -f1) % 80 ))"; }

a="$tmp/work/a"; mkdir -p "$a"
i=0
while b="$tmp/work/b$i"; [ "$(slot "$b")" != "$(slot "$a")" ]; do i=$((i + 1)); done
mkdir -p "$b"

run "$a"; run "$b"
assert_eq "first sandbox keeps the hash-derived number" "$(num "$a")" "$(( 100 + $(slot "$a") ))"
assert_ne "colliding sandbox gets a different number"   "$(num "$b")" "$(num "$a")"
assert_contains "start-display.sh uses the allocated number" \
    "$(cat "$(dir "$b")/start-display.sh")" "NUM=\"$(num "$b")\""

before=$(num "$b")
run "$b"
assert_eq "the number is sticky across re-runs" "$(num "$b")" "$before"

# A sandbox created before numbers were recorded still occupies its implicit slot.
sed -i '/^SANDBOX_DISPLAY_NUM=/d' "$(dir "$b")/.env"
rm -rf "$(dir "$a")"
run "$a"
assert_ne "a legacy sandbox's implicit number is avoided" "$(num "$a")" "$(( 100 + $(slot "$a") ))"

# --- O11: the socket directory is made, filled and emptied without following a link (T09, W9, D20, D26)
# Stand-ins for the X servers: Xephyr binds the socket path of its display number and waits.
stubs="$tmp/xstubs"; mkdir -p "$stubs"
printf '%s\n' '#!/usr/bin/env python3' 'import os, socket, sys, time' \
    'p = "/tmp/.X11-unix/X" + sys.argv[1].lstrip(":")' 'os.path.lexists(p) and os.unlink(p)' \
    's = socket.socket(socket.AF_UNIX); s.bind(p)' 'time.sleep(120)' > "$stubs/Xephyr"
printf '#!/bin/sh\nexit 0\n' > "$stubs/Xvfb"; cp "$stubs/Xvfb" "$stubs/xpra"; chmod +x "$stubs"/*
x11_made=no; [ -d /tmp/.X11-unix ] || { mkdir -p /tmp/.X11-unix && x11_made=yes; }
cleanup_x() {
    pkill -f "$stubs/Xephyr" 2>/dev/null || true
    [ -z "${sockdir:-}" ] || { rm -f "${sockdir:?}/X${xnum:-0}"; rmdir "$sockdir" 2>/dev/null || true; }
    [ -z "${xnum:-}" ] || rm -f "/tmp/.X11-unix/X$xnum"
    [ "$x11_made" = yes ] && rmdir /tmp/.X11-unix 2>/dev/null || true
}
trap cleanup_x EXIT
createx() {   # <mode> <project>
    PATH="$stubs:$PATH" bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display="$1" --no-start "$2" >"$tmp/outx" 2>&1 || cat "$tmp/outx"
}
pn="$tmp/work/nested"; mkdir -p "$pn"; createx nested "$pn"
px="$tmp/work/xpra"; mkdir -p "$px"; createx xpra "$px"
for pj in "$pn" "$px"; do
    d=$(dir "$pj")
    for f in "$d/start-display.sh" "$d/stop-display.sh"; do
        assert_eq "O11: $(basename "$f") of $(basename "$pj") holds no mkdir, chmod, ln or rm that names the socket directory" \
            "$(grep -vE '\bnofollow (mkdir|hardlink|remove) ' "$f" | grep -cE '\b(mkdir|chmod|ln|rm)\b.*(SOCK_DIR|SOCK_REL|X11_SOCKET_DIR|\.ai-sandbox-)')" 0
    done
done
assert_eq "O11: display.sh holds no mkdir, chmod, ln or rm that names the socket directory" \
    "$(grep -vE 'ai_sandbox_nofollow|\bnofollow (mkdir|hardlink|remove) ' "$REPO_ROOT/bin/ai/create.d/display.sh" | grep -cE '\b(mkdir|chmod|ln|rm)\b.*(SOCK_DIR|SOCK_REL|X11_SOCKET_DIR)')" 0
assert_contains "O11: start-display.sh makes the directory and publishes the socket through the function" \
    "$(cat "$(dir "$pn")/start-display.sh")" "hardlink"
assert_contains "O11: stop-display.sh removes the socket through the function" "$(cat "$(dir "$pn")/stop-display.sh")" "remove"
sockdir=$(sed -n 's/^SOCK_DIR="\(.*\)"$/\1/p' "$(dir "$pn")/start-display.sh")
xnum=$(num "$pn")
assert_eq "O11: create made the socket directory 0700" "$(stat -c %a "$sockdir")" 700

# Running the generated scripts: the socket is published, then removed at stop
PATH="$stubs:$PATH" bash "$(dir "$pn")/start-display.sh" >"$tmp/start.out" 2>&1; rc=$?
assert_eq "O11: start-display.sh exits 0" "$rc" 0
assert_eq "O11: the socket is published in the directory" "$([ -S "$sockdir/X$xnum" ] && echo yes)" yes
assert_eq "O11: and is the same inode as the server's socket" "$([ "$sockdir/X$xnum" -ef "/tmp/.X11-unix/X$xnum" ] && echo yes)" yes
PATH="$stubs:$PATH" bash "$(dir "$pn")/stop-display.sh" >"$tmp/stop.out" 2>&1; rc=$?
assert_eq "O11: stop-display.sh exits 0" "$rc" 0
assert_eq "O11: and removes the published socket" "$([ -e "$sockdir/X$xnum" ] && echo yes || echo no)" no

# A link a sandbox put at the socket directory (a --display=host sandbox writes /tmp/.X11-unix)
snapt() { ( cd "$1" && find . | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s %s\n' "$f" "$(stat -c %a "$f")" "$([ -f "$f" ] && sha256sum < "$f")"; done ); }
mkdir -p "$tmp/trap"; printf 'trap\n' > "$tmp/trap/X$xnum"; t0=$(snapt "$tmp/trap")
rmdir "$sockdir"; ln -s "$tmp/trap" "$sockdir"
PATH="$stubs:$PATH" bash "$(dir "$pn")/stop-display.sh" >/dev/null 2>&1
assert_eq "O11: stop-display.sh through a link at the directory leaves the trap unchanged" "$(snapt "$tmp/trap")" "$t0"
PATH="$stubs:$PATH" bash "$(dir "$pn")/start-display.sh" >"$tmp/start2.out" 2>&1; rc=$?
assert_eq "O11: start-display.sh through a link at the directory fails" "$([ "$rc" -ne 0 ] && echo yes)" yes
assert_eq "O11: and leaves the trap unchanged" "$(snapt "$tmp/trap")" "$t0"
rm -f "$sockdir"

rm -rf "$tmp"
finish
