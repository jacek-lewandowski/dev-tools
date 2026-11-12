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

# Host audio is off unless asked for (the socket carries capture as well as
# playback, so sharing it hands the sandbox the microphone); --audio turns it
# on, the request is remembered per project, --no-audio drops it, and the value
# the old default wrote is no request.
sound_notice='used to be the default'
env_value() { sed -n 's/^SANDBOX_WITH_AUDIO=//p' "$dir/.env"; }
assert_eq "no flag and no stored value shares no sound socket" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
assert_eq "the default is recorded as off" "$(env_value)" '0'
TESTS_RUN=$((TESTS_RUN + 1))
case "$brain" in
    *parec*) _fail "the default does not advertise capture tools" "found parec" ;;
    *)       _pass "the default does not advertise capture tools" ;;
esac
assert_contains "the default log says audio is not shared and how to opt in" "$(cat "$tmp/out")" 'not shared by default'
assert_contains "the default log names --audio" "$(cat "$tmp/out")" '--audio'
audio --audio
assert_contains "--audio shares the socket" "$(cat "$dir/docker-compose.yml")" "$rt/pulse/native:/run/sandbox-pulse"
assert_eq "--audio is recorded as a request" "$(env_value)" '2'
assert_contains "--audio warns that the microphone is included" "$(cat "$tmp/out")" 'microphone'
assert_contains "--audio warns that the host's sound server acts on the sandbox's requests" "$(cat "$tmp/out")" 'act on its requests'
assert_contains "--audio says how to drop it" "$(cat "$tmp/out")" '--no-audio'
audio
assert_contains "a stored request keeps audio on" "$(cat "$dir/docker-compose.yml")" 'sandbox-pulse'
assert_eq "a stored request stays recorded" "$(env_value)" '2'
assert_contains "a kept request repeats the warning" "$(cat "$tmp/out")" 'act on its requests'
audio --no-audio
assert_eq "--no-audio turns it off" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
assert_eq "--no-audio is recorded" "$(env_value)" '0'
TESTS_RUN=$((TESTS_RUN + 1))
case "$(cat "$HOME/.gemini/GEMINI.md")" in
    *parec*) _fail "--no-audio does not advertise capture tools" "found parec" ;;
    *)       _pass "--no-audio does not advertise capture tools" ;;
esac
audio
assert_eq "a stored 0 keeps audio off" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
# The old shape: every run before audio became opt-in wrote 1, whether audio
# was on by default or asked for, so 1 cannot count as a request.
sed -i 's/^SANDBOX_WITH_AUDIO=.*/SANDBOX_WITH_AUDIO=1/' "$dir/.env"
audio
assert_eq "a stored 1 is no request" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
assert_eq "a stored 1 is rewritten as off" "$(env_value)" '0'
assert_contains "a stored 1 gets a notice" "$(cat "$tmp/out")" "$sound_notice"
audio
assert_eq "the notice is not repeated" "$(grep -c "$sound_notice" "$tmp/out")" '0'
sed -i 's/^SANDBOX_WITH_AUDIO=.*/SANDBOX_WITH_AUDIO=1/' "$dir/.env"
audio --audio
assert_contains "--audio over a stored 1 shares the socket" "$(cat "$dir/docker-compose.yml")" 'sandbox-pulse'
assert_eq "--audio over a stored 1 is recorded as a request" "$(env_value)" '2'
audio --no-audio
sed -i 's/^SANDBOX_WITH_AUDIO=.*/SANDBOX_WITH_AUDIO=bogus/' "$dir/.env"
audio
assert_eq "an unknown stored value is no request" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
assert_eq "an unknown stored value is rewritten as off" "$(env_value)" '0'
rm -f "$dir/.env"
audio --audio
no_sock="$tmp/no-runtime"; mkdir -p "$no_sock"
XDG_RUNTIME_DIR="$no_sock" bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=none --no-start --audio "$proj" >"$tmp/out" 2>&1 || true
assert_contains "--audio with no host sound socket says so" "$(cat "$tmp/out")" "no sound socket at $no_sock/pulse/native"
assert_eq "and mounts no socket" "$(grep -c 'sandbox-pulse' "$dir/docker-compose.yml")" '0'
audio --no-audio
bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --audio --no-audio "$proj" >"$tmp/both" 2>&1 && rc=0 || rc=$?
assert_eq "both audio flags exit 2" "$rc" '2'
help=$(bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --help 2>&1)
assert_contains "help documents --audio" "$help" '--audio '
assert_contains "help says audio is off by default" "$help" 'Off by default'
assert_contains "help says the microphone is included" "$help" 'microphone included'
assert_contains "help says a program can make the sound server act on its requests" "$help" 'act on its requests'
assert_contains "help says --audio is remembered" "$help" 'Remembered until --no-audio'
assert_contains "help says --no-audio drops a remembered request" "$help" 'Drop a remembered --audio'

# The closing check: a sandbox with a display, a host sound socket and a host
# sound-device directory (both faked). Nothing of the host's sound is shared
# unless it is asked for, and the only host socket a default sandbox is given
# is its display's.
stubs="$tmp/xstub"; mkdir -p "$stubs"
for t in xpra Xvfb; do printf '#!/bin/sh\nexit 0\n' > "$stubs/$t"; done
printf '#!/bin/sh\nexit 0\n'                                 > "$stubs/xauth"
printf '#!/bin/sh\necho 0123456789abcdef0123456789abcdef\n' > "$stubs/mcookie"
chmod +x "$stubs"/*
snd="$tmp/snd"; mkdir -p "$snd"
proj2="$tmp/work/q"; mkdir -p "$proj2"
shown() { PATH="$stubs:$PATH" XDG_RUNTIME_DIR="$rt" HOST_SND_DIR="$snd" \
    bash "$REPO_ROOT/bin/ai/create-ai-sandbox.sh" --display=xpra --no-start "$@" "$proj2" >"$tmp/out2" 2>&1 || true; }
dir2="$AI_SANDBOX_ROOT/$(ai_sandbox_project_id "$proj2")-agent"
x11_dir="/tmp/.X11-unix/.ai-sandbox-$(ai_sandbox_project_id "$proj2")-agent"
shares_none() {
    local c; c=$(cat "$dir2/docker-compose.yml")
    assert_eq "$1: no sound socket mount" "$(grep -c 'sandbox-pulse' <<<"$c")" '0'
    assert_eq "$1: no sound server variable" "$(grep -c 'PULSE_SERVER' <<<"$c")" '0'
    assert_eq "$1: no sound device mount" "$(grep -c '/dev/snd' <<<"$c")" '0'
    assert_eq "$1: no sound device rule" "$(grep -c 'c 116:' <<<"$c")" '0'
}

# The host sockets the compose file binds, by source: a source that is a socket
# on this machine, the faked sound socket, or a directory that holds it, is
# a host daemon's socket handed to the sandbox. The display's own directory
# is the one exception.
daemon_binds() {
    local line src
    while IFS= read -r line; do
        src=${line#*\"}; src=${src%%:*}
        case "$src" in "$x11_dir") continue ;; esac
        if [ -S "$src" ] || [ "$src" = "$rt/pulse/native" ] || [[ "$rt/pulse/native" == "$src"/* ]]; then
            printf '%s\n' "$src"
        fi
    done < <(sed -n '/^    volumes:/,/^volumes:/{s/^      - \("[^"]*"\).*/- \1/p}' "$dir2/docker-compose.yml")
}

shown
shares_none "a new sandbox"
assert_eq "a new sandbox: the default is recorded as off" "$(sed -n 's/^SANDBOX_WITH_AUDIO=//p' "$dir2/.env")" '0'
TESTS_RUN=$((TESTS_RUN + 1))
case "$(cat "$HOME/.gemini/GEMINI.md")" in
    *parec*) _fail "a new sandbox: no capture tools advertised" "found parec" ;;
    *)       _pass "a new sandbox: no capture tools advertised" ;;
esac
assert_contains "a new sandbox: the output says audio is not shared by default" "$(cat "$tmp/out2")" 'not shared by default'
assert_contains "a new sandbox: the output names --audio" "$(cat "$tmp/out2")" '--audio'
assert_eq "a new sandbox: binds no host socket but its display's" "$(daemon_binds)" ''
assert_contains "the display's own directory is bound" "$(cat "$dir2/docker-compose.yml")" "$x11_dir:/tmp/.X11-unix"

sed -i 's/^SANDBOX_WITH_AUDIO=.*/SANDBOX_WITH_AUDIO=1/' "$dir2/.env"
shown
shares_none "an old stored 1"
assert_eq "an old stored 1: recorded as off" "$(sed -n 's/^SANDBOX_WITH_AUDIO=//p' "$dir2/.env")" '0'
assert_contains "an old stored 1: one notice" "$(cat "$tmp/out2")" "$sound_notice"
assert_eq "an old stored 1: the notice appears once" "$(grep -c "$sound_notice" "$tmp/out2")" '1'
assert_contains "an old stored 1: the notice names --audio" "$(cat "$tmp/out2")" 'Pass --audio'
shown
shares_none "a bare run after the notice"
assert_eq "a bare run after the notice does not repeat it" "$(grep -c "$sound_notice" "$tmp/out2")" '0'

shown --audio
c2=$(cat "$dir2/docker-compose.yml")
assert_contains "--audio with a display: the socket is mounted" "$c2" "$rt/pulse/native:/run/sandbox-pulse"
assert_contains "--audio with a display: the server variable is set" "$c2" 'PULSE_SERVER=unix:/run/sandbox-pulse'
assert_contains "--audio with a display: the device directory is mounted" "$c2" "$snd:/dev/snd"
assert_contains "--audio with a display: the device rule is set" "$c2" "c 116:* rwm"
assert_eq "--audio with a display: recorded as a request" "$(sed -n 's/^SANDBOX_WITH_AUDIO=//p' "$dir2/.env")" '2'
assert_contains "--audio with a display: the warning names the microphone" "$(cat "$tmp/out2")" 'microphone included'
assert_contains "--audio with a display: the warning says the sandbox is outside the default isolation" "$(cat "$tmp/out2")" 'outside'
shown
assert_contains "a bare run after --audio keeps the socket" "$(cat "$dir2/docker-compose.yml")" 'sandbox-pulse'
assert_contains "a bare run after --audio keeps the device mount" "$(cat "$dir2/docker-compose.yml")" "$snd:/dev/snd"
assert_eq "a bare run after --audio keeps the request" "$(sed -n 's/^SANDBOX_WITH_AUDIO=//p' "$dir2/.env")" '2'
assert_contains "a bare run after --audio repeats the warning" "$(cat "$tmp/out2")" 'act on its requests'
assert_contains "a bare run after --audio says how to drop it" "$(cat "$tmp/out2")" '--no-audio'
shown --no-audio
shares_none "--no-audio"
assert_eq "--no-audio: recorded as off" "$(sed -n 's/^SANDBOX_WITH_AUDIO=//p' "$dir2/.env")" '0'
shown
shares_none "a bare run after --no-audio"

# With no display the sound devices stay out even when asked for: only the socket is shared.
HOST_SND_DIR="$snd" audio --audio
assert_contains "--audio with no display still mounts the socket" "$(cat "$dir/docker-compose.yml")" 'sandbox-pulse'
assert_eq "--audio with no display mounts no sound device and sets no rule" "$(grep -cE '/dev/snd|c 116:' "$dir/docker-compose.yml")" '0'

rm -rf "$x11_dir" 2>/dev/null

rm -rf "$tmp"
finish
