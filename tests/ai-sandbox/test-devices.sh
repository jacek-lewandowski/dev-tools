#!/usr/bin/env bash
# Device passthrough is per node: no blanket USB exposure.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"

# A fake PulseAudio socket, so the audio mount can be observed.
rt="$tmp/rt"; mkdir -p "$rt/pulse"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$rt/pulse/native"
audio() { XDG_RUNTIME_DIR="$rt" bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$@" "$proj" >"$tmp/out" 2>&1 || true; }

audio
dir="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj")-agent"
compose=$(cat "$dir/docker-compose.yml")

# Mounting the whole /dev/bus/usb tree, with a wildcard rule on the USB major,
# handed the container every USB device on the host (webcam, fingerprint
# reader, network adapter), not only the ones passed through explicitly.
TESTS_RUN=$((TESTS_RUN + 1))
case "$compose" in
    *"/dev/bus/usb"*) _fail "compose does not mount /dev/bus/usb" "found a mount of the whole USB tree" ;;
    *)                _pass "compose does not mount /dev/bus/usb" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "$compose" in
    *"c 189:*"*) _fail "compose has no wildcard rule on the USB major" "found 'c 189:*'" ;;
    *)           _pass "compose has no wildcard rule on the USB major" ;;
esac

# The agents inside act on this block, so it must not promise more isolation
# than the compose file delivers.
brain=$(cat "$HOME/.gemini/GEMINI.md")
assert_contains "the shared brain lists the other host mounts" "$brain" \
    "The only other host paths mounted are the"
assert_contains "the shared brain does not claim USB passthrough" "$brain" \
    "Only explicitly passed-through serial ports are visible under /dev."

# Host audio is on by default (the socket carries capture as well as playback,
# so this hands the sandbox the microphone); --no-audio turns it off and the
# choice is remembered per project.
assert_contains "no flag and no stored value mounts the pulse socket" "$compose" "$rt/pulse/native:/run/sandbox-pulse"
assert_contains "the default is recorded as on" "$(cat "$dir/.env")" 'SANDBOX_WITH_AUDIO=1'
assert_contains "the default advertises capture tools" "$brain" 'parec'
assert_contains "the default log tells how to drop audio" "$(cat "$tmp/out")" '--no-audio'
audio --no-audio
assert_eq "--no-audio turns it off" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
assert_contains "--no-audio is recorded" "$(cat "$dir/.env")" 'SANDBOX_WITH_AUDIO=0'
TESTS_RUN=$((TESTS_RUN + 1))
case "$(cat "$HOME/.gemini/GEMINI.md")" in
    *parec*) _fail "--no-audio does not advertise capture tools" "found parec" ;;
    *)       _pass "--no-audio does not advertise capture tools" ;;
esac
audio
assert_eq "a stored 0 keeps audio off" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
audio --audio
assert_contains "--audio turns it back on" "$(cat "$dir/docker-compose.yml")" 'sandbox-pulse'
assert_contains "--audio is recorded" "$(cat "$dir/.env")" 'SANDBOX_WITH_AUDIO=1'
audio
assert_contains "a stored 1 keeps audio on" "$(cat "$dir/docker-compose.yml")" 'sandbox-pulse'
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --audio --no-audio "$proj" >"$tmp/both" 2>&1 && rc=0 || rc=$?
assert_eq "both audio flags exit 2" "$rc" '2'
assert_contains "help documents --audio" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)" '--no-audio'

rm -rf "$tmp"
finish
