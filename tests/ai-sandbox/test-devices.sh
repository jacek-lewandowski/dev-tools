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

finish
