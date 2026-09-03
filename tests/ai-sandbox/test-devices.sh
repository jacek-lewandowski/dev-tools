#!/usr/bin/env bash
# Device passthrough is per node: no blanket USB exposure.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
proj="$tmp/work/p"; mkdir -p "$proj"

bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$proj" >"$tmp/out" 2>&1 || true
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

# Audio is opt-in: the PulseAudio socket carries capture as well as playback,
# so sharing it by default handed every sandbox the host microphone.
assert_eq "no pulse socket by default" "$(grep -c 'sandbox-pulse' <<<"$compose")" '0'
assert_eq "no /dev/snd by default"     "$(grep -c '/dev/snd'      <<<"$compose")" '0'
assert_eq "no ALSA cgroup rule by default" "$(grep -c 'c 116:'   <<<"$compose")" '0'
assert_contains "the shared brain does not advertise capture tools" "$brain" 'sox'
TESTS_RUN=$((TESTS_RUN + 1))
case "$brain" in
    *parec*) _fail "the shared brain does not advertise capture tools" "found parec" ;;
    *)       _pass "the shared brain does not advertise capture tools" ;;
esac

rt="$tmp/rt"; mkdir -p "$rt/pulse"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$rt/pulse/native"
audio() { XDG_RUNTIME_DIR="$rt" bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start "$@" "$proj" >"$tmp/out" 2>&1 || true; }
audio --audio
assert_contains "--audio mounts the pulse socket" "$(cat "$dir/docker-compose.yml")" "$rt/pulse/native:/run/sandbox-pulse"
assert_contains "--audio is recorded" "$(cat "$dir/.env")" 'SANDBOX_WITH_AUDIO=1'
assert_contains "--audio advertises capture tools" "$(cat "$HOME/.gemini/GEMINI.md")" 'parec'
audio
assert_contains "--audio is sticky" "$(cat "$dir/docker-compose.yml")" 'sandbox-pulse'
audio --no-audio
assert_eq "--no-audio turns it off" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --audio --no-audio "$proj" >"$tmp/both" 2>&1 && rc=0 || rc=$?
assert_eq "both audio flags exit 2" "$rc" '2'
assert_contains "help documents --audio" "$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)" '--no-audio'

rm -rf "$tmp"
finish
