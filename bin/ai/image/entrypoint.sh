#!/bin/bash
# Sandbox entrypoint. Brings up optional per-container services, records the
# resulting environment for interactive shells, then hands off.
set -u

RUNTIME_DIR="${SANDBOX_RUNTIME_DIR:-/run/user/$(id -u)}"   # override: tests only
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
chmod 700 "$RUNTIME_DIR" 2>/dev/null || true
ENV_SNAPSHOT="$RUNTIME_DIR/sandbox-env.sh"
: > "$ENV_SNAPSHOT"

# --- D-Bus -----------------------------------------------------------------
if command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS
    echo "export DBUS_SESSION_BUS_ADDRESS='${DBUS_SESSION_BUS_ADDRESS}'" >> "$ENV_SNAPSHOT"
fi

# --- Xwayland --------------------------------------------------------------
# In wayland mode the container runs its own X server against the host
# compositor, so X11-only applications work without any host X access.
if [ "${SANDBOX_START_XWAYLAND:-0}" = "1" ] && command -v Xwayland >/dev/null 2>&1; then
    Xwayland :99 >/tmp/xwayland.log 2>&1 &
    for _ in $(seq 1 50); do
        [ -S /tmp/.X11-unix/X99 ] && break
        sleep 0.1
    done
    if [ -S /tmp/.X11-unix/X99 ]; then
        echo "export DISPLAY=:99" >> "$ENV_SNAPSHOT"
    else
        echo "sandbox: Xwayland failed to start; see /tmp/xwayland.log" >&2
    fi
fi

# --- Window manager --------------------------------------------------------
# Without a window manager, apps on a nested display appear undecorated, cannot
# be moved, and ignore the screen resizing when the Xephyr window is resized.
if [ "${SANDBOX_START_WM:-0}" = "1" ] && [ -n "${DISPLAY:-}" ] && command -v openbox >/dev/null 2>&1; then
    for _ in $(seq 1 100); do
        xdpyinfo >/dev/null 2>&1 && break
        sleep 0.1
    done
    if xdpyinfo >/dev/null 2>&1; then
        openbox >/tmp/openbox.log 2>&1 &
    else
        echo "sandbox: X display ${DISPLAY} not reachable; window manager not started" >&2
    fi
fi

# --- Rootless Docker -------------------------------------------------------
if [ "${SANDBOX_WITH_DOCKER:-0}" = "1" ]; then
    if command -v dockerd-rootless.sh >/dev/null 2>&1; then
        export XDG_RUNTIME_DIR="$RUNTIME_DIR"
        dockerd-rootless.sh >/tmp/dockerd-rootless.log 2>&1 &
        echo "export DOCKER_HOST=unix://${RUNTIME_DIR}/docker.sock" >> "$ENV_SNAPSHOT"
        for _ in $(seq 1 100); do
            [ -S "${RUNTIME_DIR}/docker.sock" ] && break
            sleep 0.2
        done
        if [ ! -S "${RUNTIME_DIR}/docker.sock" ]; then
            echo "sandbox: rootless dockerd did not come up; see /tmp/dockerd-rootless.log" >&2
        fi
    else
        # Never advertise a DOCKER_HOST that cannot exist.
        echo "sandbox: --with-docker was requested but dockerd-rootless.sh is missing" >&2
    fi
fi

# --- Timezone ----------------------------------------------------------------
# The image's /etc/localtime is a symlink to Etc/UTC; follow TZ (the host's zone,
# set by the compose file) so tools that ignore TZ agree. Needs root: sudo is
# passwordless in the image. Edited here, not baked, so a zone that changes
# between creates needs no image rebuild. SANDBOX_ETC_DIR/SANDBOX_ZONEINFO_DIR: tests only.
tz_etc="${SANDBOX_ETC_DIR:-/etc}"; tz_zi="${SANDBOX_ZONEINFO_DIR:-/usr/share/zoneinfo}"
if [ -n "${TZ:-}" ]; then
    if [ -f "$tz_zi/$TZ" ]; then
        { ln -sfn "$tz_zi/$TZ" "$tz_etc/localtime" && printf '%s\n' "$TZ" > "$tz_etc/timezone"; } 2>/dev/null \
            || { sudo -n ln -sfn "$tz_zi/$TZ" "$tz_etc/localtime" \
                 && printf '%s\n' "$TZ" | sudo -n tee "$tz_etc/timezone" >/dev/null; } 2>/dev/null \
            || echo "sandbox: could not set /etc/localtime and /etc/timezone for TZ=$TZ" >&2
    else
        echo "sandbox: no $tz_zi/$TZ in the image; /etc/localtime keeps its default (TZ=$TZ still applies)" >&2
    fi
fi

# --- Knowledge clone -------------------------------------------------------
# SANDBOX_KNOWLEDGE=2: the host keeps the read-only origin and the status file; this
# brings ~/knowledge up to date from them. Never fails the start, and never holds it long.
if [ "${SANDBOX_KNOWLEDGE:-0}" = "2" ] && command -v sandbox-knowledge-sync >/dev/null 2>&1; then
    timeout 60 sandbox-knowledge-sync || echo "sandbox: sandbox-knowledge-sync did not finish; sandbox-doctor shows the host's last status" >&2
fi

# --- agy grants ------------------------------------------------------------
# Merge the sandbox's agy grants into its own agy settings; never fail the
# start. read_url(*) is web access (agent-roles design D21). command(<name>)
# lets agy run that program headlessly, whatever its arguments; agy requires a
# grant for every program in a line, so "ls && touch x" is denied while
# "ls -la" runs (verified on agy 1.4.0, D29). The list holds read-only tools:
# no sed, awk, tee, xargs or git, which can write or run other programs.
# read_file(<dir>) lets agy read the shared knowledge clone outside its workspace; a
# trailing glob is not accepted (verified on agy 1.4.0), a plain directory path is.
python3 - "$HOME/.gemini/antigravity-cli/settings.json" <<'PYEOF' 2>/dev/null || true
import json, os, sys
TOOLS = "ls cat head tail wc grep rg find sort uniq cut tr diff file stat du df which pwd date echo tree realpath basename dirname jq".split()
GRANTS = ["read_url(*)"] + ["command(%s)" % t for t in TOOLS]
GRANTS.append("read_file(%s)" % os.path.expanduser("~/knowledge"))
path = sys.argv[1]
if os.path.isfile(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    perms = data.setdefault("permissions", {})
    allow = perms.setdefault("allow", [])
    missing = [g for g in GRANTS if g not in allow]
    if missing:
        allow.extend(missing)
        # Rewritten in place so mode and owner stay as they are.
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
PYEOF

# --- Claude Code compaction -------------------------------------------------
# Context is managed by handover and /clear, so both compaction settings default
# to false (idleCompaction and autoCompactEnabled, checked in the claude binary
# of 2.1.323). Written to the user's settings, not the managed ones, and only
# when absent: managed settings outrank the user's, so they could not be undone.
python3 - "$HOME/.claude/settings.json" <<'PYEOF' 2>/dev/null || true
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.isfile(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
changed = False
for key in ("idleCompaction", "autoCompactEnabled"):
    if key not in data:
        data[key] = False
        changed = True
if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
PYEOF

# --- Claude Code plugins -----------------------------------------------------
# ~/.claude is a bind mount, so plugins cannot be baked into the image. In the
# background (network), add the marketplace if unknown and install only the
# plugins absent from the list: `plugin install` re-enables a disabled plugin,
# which would undo the user's `claude plugin disable`. Never fails the start.
: "${CLAUDE_PLUGINS_LIST:=/usr/local/share/claude-plugins.list}"
: "${CLAUDE_PLUGINS_LOG:=/tmp/claude-plugins.log}"
(
    command -v claude >/dev/null 2>&1 && [ -r "$CLAUDE_PLUGINS_LIST" ] || exit 0
    echo "--- $(date -u +%FT%TZ)"
    if timeout 60 claude plugin marketplace list --json \
        | python3 -c 'import json,sys; sys.exit(0 if any(m.get("name") == sys.argv[1] for m in json.load(sys.stdin)) else 1)' @MARKETPLACE@; then
        :
    else
        timeout 120 claude plugin marketplace add @MARKETPLACE_SOURCE@ 2>&1 || true
    fi
    installed=$(claude plugin list --json 2>/dev/null) || { echo "plugin list failed; not installing"; exit 0; }
    missing=$(printf '%s' "$installed" | python3 -c '
import json, sys
have = {p.get("id") for p in json.load(sys.stdin)}
for line in open(sys.argv[1]):
    line = line.strip()
    if line and line not in have:
        print(line)' "$CLAUDE_PLUGINS_LIST") || { echo "plugin list unparsable; not installing"; exit 0; }
    if [ -n "$missing" ]; then
        timeout 120 claude plugin marketplace update @MARKETPLACE@ 2>&1 || true
        for id in $missing; do
            timeout 180 claude plugin install "$id" -y 2>&1 || true
        done
    fi
    echo "done"
) >>"$CLAUDE_PLUGINS_LOG" 2>&1 &

exec "$@"
