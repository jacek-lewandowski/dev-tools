# create.d/start.sh -- capacity check, start under the cache lock and the closing summary.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

start_gate() {
# ---------------------------------------------------------------------------
# Build and start
# ---------------------------------------------------------------------------

if [ "$NO_START" = "yes" ]; then
    step "Done (--no-start)"
    log "Configuration written. Start it with: ai-sandbox"
    exit 0
fi

# Before the image build: a full host should cost a message, not a build.
ai_sandbox_check_capacity "$CONTAINER_NAME" "$MEMORY_GB" || exit 1

# The display must exist before the container starts: Docker creates any missing
# bind-mount source itself, as root, which would then block Xephyr from binding.
if [ "$DISPLAY_MODE" = "nested" ] || [ "$DISPLAY_MODE" = "xpra" ]; then
    step "Starting the isolated display"
    "$SANDBOX_DIR/start-display.sh"
fi
}

start_run() {
step "Starting $CONTAINER_NAME"
# D5/D2: under a lock, so two terminals starting this sandbox at once cannot
# rename an upper while the other's mount is being made, repair any build-cache
# volume whose options differ, then reset (D4) before 'up' recreates it. I10's
# refusal ran minutes ago, before the image build, so it is re-checked here,
# first thing under the lock: a container started by someone else (an
# 'ai-sandbox' that raced this run) is refused exactly as I10 refuses above,
# rather than reset or repaired out from under it.
mkdir -p "$SANDBOX_DIR/build-caches"
exec {CACHES_LOCK_FD}>"$SANDBOX_DIR/build-caches/.lock"
flock "$CACHES_LOCK_FD"
if ai_sandbox_container_running "$CONTAINER_NAME"; then
    die "$CONTAINER_NAME is running. Stop it first: ai-sandbox-stop"
fi
# The check's own message ("If it is running, run: ai-sandbox-stop ...") is
# misleading here: this script is already past I10 and is about to repair the
# volume itself, so its own stderr is discarded at this call site only; the
# repair step (ai_sandbox_caches_repair) says, per volume, that it is
# repairing/recreating it. ai-sandbox and ai-sandbox-restart still show the
# check's message verbatim (I9: only create-ai-sandbox.sh repairs).
if ! ai_sandbox_caches_check "$SANDBOX_DIR" "$CONTAINER_NAME" 2>/dev/null; then
    ai_sandbox_caches_repair "$SANDBOX_DIR" "$CONTAINER_NAME"
fi
ai_sandbox_caches_reset "$SANDBOX_DIR"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
exec {CACHES_LOCK_FD}>&-

if [ "$KNOWLEDGE" = "yes" ]; then
    BRAIN_SUMMARY="$AI_KNOWLEDGE_RENDER/GLOBAL.md  (rendered from the knowledge repository; ~/knowledge is this sandbox's clone)"
else
    BRAIN_SUMMARY="~/.gemini/GEMINI.md  (~/.claude/CLAUDE.md is a symlink to it)"
fi
step "Ready"
cat <<SUMMARY
  Shell:              ai-sandbox           (run 'source ~/.bashrc' first, this once)
                      An interactive shell in the container. Run anything from it,
                      GUI apps included -- 'antigravity2-ide &'. Open as many as
                      you like; each 'ai-sandbox' is a separate shell.
  One-shot command:   ai-sandbox sandbox-doctor
  Shared brain:       ${BRAIN_SUMMARY}
  Sandbox files:      $SANDBOX_DIR
  Display mode:       $DISPLAY_MODE
  Rootless Docker:    $WITH_DOCKER
  Memory limit:       $MEMORY_GB GB RAM, no swap (/dev/shm $SHM_SIZE, counted against it; --memory=GB changes it)
  CPU limit:          $CPUSET_WANT core(s) for $MEMORY_GB GB: host cores $CPUSET (nproc inside agrees)
  Timezone:           $TZ_SUMMARY
SUMMARY

case "$DISPLAY_MODE" in
  xpra)
cat <<'XPRA_HINT'

  GUI apps appear as ordinary windows on your desktop, forwarded one at a time
  by xpra, but they render on a private virtual display -- so nothing in the
  sandbox can read your keystrokes or capture your screen.
      ai-sandbox                 # shell; run 'antigravity2-ide &' from it
  If a window never appears, check xpra-attach.log in the sandbox directory.
XPRA_HINT
    ;;
  nested)
cat <<'NESTED_HINT'

  GUI apps appear inside the Xephyr window, not as separate host windows, and a
  window manager is started for you. If you would rather have them as ordinary
  host windows, as before:
      create-ai-sandbox.sh --display=host
  That shares your real X display, so the sandbox can see your whole session --
  but the network and device isolation stay in place either way. The choice is
  remembered; you do not need to pass --display again.
NESTED_HINT
    ;;
  host)
cat <<'HOST_HINT'

  GUI apps appear as ordinary host windows. Your real X display is shared with
  the sandbox, so anything in it can read your keystrokes and screen.
HOST_HINT
    ;;
esac
}
