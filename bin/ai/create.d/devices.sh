# create.d/devices.sh -- audio, serial devices, device cgroup rules and security_opt.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

devices_audio() {
# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------

# Off unless --audio asks for it, and then remembered until --no-audio. The
# socket carries capture as well as playback, and neither PulseAudio nor
# PipeWire's compatibility socket can restrict one client to playback, so
# sharing it is sharing the microphone, and the host's sound server, which runs
# as the user, acts on requests from the sandbox.
PULSE_SOCKET_HOST="${XDG_RUNTIME_DIR:-/run/user/$HOST_UID}/pulse/native"
if [ "$AUDIO_OLD_VALUE" = "yes" ] && [ "$WITH_AUDIO" != "yes" ]; then
    warn "Audio: the host's sound was shared with this sandbox because that used to be the default. It is now off. Pass --audio to share it again."
fi
# The sound devices are mounted only with a display (the device section below
# reads AUDIO_DEVICES), so the warning names only what this run shares.
AUDIO_DEVICES="no"
[ "$WITH_AUDIO" = "yes" ] && [ -d "$HOST_SND_DIR" ] && [ "$DISPLAY_MODE" != "none" ] && AUDIO_DEVICES="yes"
if [ "$WITH_AUDIO" != "yes" ]; then
    if [ "$WITH_AUDIO_EXPLICIT" = "yes" ] || [ "$AUDIO_STORED_OFF" = "yes" ]; then
        log "Audio: not shared; pass --audio to share the host's sound, microphone included."
    else
        log "Audio: not shared by default; pass --audio to share the host's sound, microphone included."
    fi
else
    audio_shared=""
    [ -S "$PULSE_SOCKET_HOST" ] && audio_shared="sound socket"
    [ "$AUDIO_DEVICES" = "yes" ] && audio_shared="${audio_shared:+$audio_shared and }sound devices"
    if [ -n "$audio_shared" ]; then
        audio_warning="Audio is shared (--audio): the sandbox gets the host's ${audio_shared}, microphone included."
        if [ -S "$PULSE_SOCKET_HOST" ]; then
            audio_warning="${audio_warning}
   A program in the sandbox can make the host's sound server, which runs as you,
   act on its requests, so this sandbox is outside the promise that a
   sandbox is given no host daemon's socket but its display's."
        fi
        warn "${audio_warning}
   Pass --no-audio to drop it."
    fi
    if [ -S "$PULSE_SOCKET_HOST" ]; then
        add_env "PULSE_SERVER=unix:/run/sandbox-pulse"
        add_vol "\"${PULSE_SOCKET_HOST}:/run/sandbox-pulse\""
    else
        warn "Audio is on, but there is no sound socket at $PULSE_SOCKET_HOST (pass --no-audio to silence this)."
    fi
fi
}

devices_enumerate() {
# ---------------------------------------------------------------------------
# Devices
#
# The host /dev is deliberately NOT bind-mounted. Doing so would hand the
# container the host's devpts (every terminal in your session) and the host's
# virtual consoles. Instead each needed device node is passed through
# explicitly, and cgroup rules are added only for majors that are inherently
# per-device (USB serial, ALSA) rather than blanket wildcards. /dev/bus/usb
# is never mounted: that tree, and the 189:* major behind it, is every USB
# device on the host (webcam, fingerprint reader, network adapter).
# ---------------------------------------------------------------------------

step "Enumerating devices"

DEVICE_LINES=""
CGROUP_LINES=""
declare -gA SEEN_CGROUP=()

add_device() { DEVICE_LINES="${DEVICE_LINES}      - \"$1:$1\""$'\n'; }
add_cgroup() {
    [ -n "${SEEN_CGROUP[$1]:-}" ] && return 0
    SEEN_CGROUP[$1]=1
    CGROUP_LINES="${CGROUP_LINES}      - '$1'"$'\n'
}

pass_through_tty() {
    local dev=$1 major minor
    [ -c "$dev" ] || return 0
    major=$(stat -c '%t' "$dev"); minor=$(stat -c '%T' "$dev")
    major=$((16#$major));         minor=$((16#$minor))
    add_device "$dev"
    add_cgroup "c ${major}:${minor} rwm"
    log "serial: $dev (${major}:${minor})"
}

shopt -s nullglob
for dev in /dev/ttyUSB* /dev/ttyACM*; do
    pass_through_tty "$dev"
done
# Only real hardware UARTs. Every kernel registers 32 legacy ttyS slots whose
# /sys entries all exist regardless of hardware, so presence is not a usable
# test -- 'type' is what distinguishes them: 0 means PORT_UNKNOWN, i.e. the
# kernel probed that slot and found nothing behind it.
skipped_uarts=0
for dev in /dev/ttyS*; do
    node=${dev##*/}
    port_type=$(cat "/sys/class/tty/${node}/type" 2>/dev/null || true)
    if [ -z "$port_type" ]; then
        # 'type' unreadable: fall back to the weaker test rather than drop a
        # port that might be real.
        [ -e "/sys/class/tty/${node}/device" ] || continue
    elif [ "$port_type" = "0" ]; then
        skipped_uarts=$((skipped_uarts + 1))
        continue
    fi
    pass_through_tty "$dev"
done
if [ "$skipped_uarts" -gt 0 ]; then
    log "serial: skipped $skipped_uarts unpopulated legacy UART slot(s)"
fi
shopt -u nullglob

# Hot-plugged USB serial adapters get new minors. These majors are exclusively
# USB serial / USB raw, so wildcarding them exposes nothing else, and lets
# 'ai-sandbox-attach' create the node later without recreating the container.
add_cgroup 'c 188:* rwm'    # ttyUSB
add_cgroup 'c 166:* rwm'    # ttyACM

if [ "$AUDIO_DEVICES" = "yes" ]; then
    add_vol "\"${HOST_SND_DIR}:/dev/snd\""
    add_cgroup 'c 116:* rwm'
    log "audio: /dev/snd (ALSA)"
fi

SECURITY_OPT_BLOCK=""
if [ "$WITH_DOCKER" = "yes" ]; then
    [ -c /dev/fuse ]    && { add_device /dev/fuse;    add_cgroup 'c 10:229 rwm'; }
    [ -c /dev/net/tun ] && { add_device /dev/net/tun; add_cgroup 'c 10:200 rwm'; }
    SECURITY_OPT_BLOCK=$'    security_opt:\n      - seccomp:unconfined\n      - apparmor:unconfined\n'
    warn "--with-docker relaxes seccomp and AppArmor for this container so that a
   nested rootless daemon can run. That is a real reduction in isolation."
fi

# Virtual serial ports are created inside the container with socat against its
# own private devpts, so no host device is involved. Nothing to pass through.
}
