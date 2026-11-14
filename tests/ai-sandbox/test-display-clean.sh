#!/usr/bin/env bash
# One display filter (E4, D12, O13): ai_sandbox_display_clean in the lib is the only place that
# decides what text from a sandbox-writable source may show on a terminal or in a status line.
set -uo pipefail
here=${BASH_SOURCE[0]%/*}
. "$here/harness.sh"
fake_home >/dev/null
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

# every code point the contract drops, among text that stays
in=$(printf 'a\xc2\x9bb\033c\rd\x7fe\xe2\x80\xaef\xe2\x80\xacg\xe2\x81\xa6h\xe2\x81\xa9i\xe2\x80\x8ej\xe2\x80\x8fk\xd8\x9cl raw\x9bm\x00n\tTAB\nline2')
out=$(printf '%s' "$in" | ai_sandbox_display_clean; echo x); out=${out%x}
exp=$(printf 'abcdefghijkl rawmn\tTAB\nline2x')
assert_eq "the filter drops C0, DEL, C1, bidi marks, embeddings, isolates and undecodable bytes, keeps newline, tab and the rest" "$out" "${exp%x}"
printf '' | ai_sandbox_display_clean; assert_eq "an empty input gives exit 0" "$?" 0
printf '\xff\xfe' | ai_sandbox_display_clean >/dev/null; assert_eq "undecodable input gives exit 0" "$?" 0
assert_eq "text with accents and CJK is kept" "$(printf 'zażółć 日本' | ai_sandbox_display_clean)" "zażółć 日本"

# no usable python3: the filter lets through printable ASCII only and still exits 0
mkdir -p "$FAKE_HOME_DIR/nopy"; printf '#!/bin/sh\nexit 1\n' > "$FAKE_HOME_DIR/nopy/python3"; chmod +x "$FAKE_HOME_DIR/nopy/python3"
out=$(printf 'ok \xc2\x9b\033x \xe2\x80\xaey\tz\n' | PATH="$FAKE_HOME_DIR/nopy:$PATH" ai_sandbox_display_clean; echo "rc=$?")
assert_eq "without python3 only printable ASCII, tab and newline remain" "$out" $'ok x y\tz\nrc=0'

# O13: the old copies are gone, the one filter lives in the lib
cd "$REPO_ROOT" || exit 1
assert_eq "O13: no C0-only filter copy in bin/ai outside image/" \
    "$(git grep -nE "tr -d '(\[:cntrl:\]|\\\\000-)" -- bin/ai ':!bin/ai/image' | wc -l | tr -d ' ')" 0
assert_eq "O13: unicodedata only in the lib" "$(git grep -l unicodedata -- bin/ai | tr '\n' ' ')" "bin/ai/ai-sandbox-lib.sh "

finish
