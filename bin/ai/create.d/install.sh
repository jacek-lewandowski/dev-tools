# create.d/install.sh -- helper installation and the ~/.bashrc block.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

install_helpers() {
# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------

step "Installing helper commands"

BASHRC_FILE="$HOME/.bashrc"

mkdir -p "$AI_SANDBOX_ROOT/bin"
while IFS= read -r helper; do
    install -m 0755 "$SCRIPT_DIR/$helper" "$AI_SANDBOX_ROOT/bin/$helper"
done < <(ai_sandbox_helpers)
# ai-delegate runs only inside the image; an earlier run installed a host copy.
if [ -e "$AI_SANDBOX_ROOT/bin/ai-delegate" ] || [ -L "$AI_SANDBOX_ROOT/bin/ai-delegate" ]; then
    rm -f "$AI_SANDBOX_ROOT/bin/ai-delegate"
    log "removed $AI_SANDBOX_ROOT/bin/ai-delegate: it runs only inside the image"
fi
# ai-sandbox-lib.sh is sourced, not run.
chmod 0644 "$AI_SANDBOX_ROOT/bin/ai-sandbox-lib.sh"
# The knowledge seed travels with the helper, so 'ai-knowledge init' on a fresh
# host needs no dev-tools checkout to find it.
rsync -a --delete "$SCRIPT_DIR/knowledge-seed/" "$AI_SANDBOX_ROOT/bin/knowledge-seed/"

# Recorded so ai-sandbox-migrate can refresh these copies without being told
# where the repository lives. Only this script's own line is replaced: the
# file also holds the user's hand-written AI_SANDBOX_MEMORY_BUDGET_GB. Written
# beside the file and moved into place, so a concurrent helper reading or
# sourcing it never sees it truncated. awk, not sed: a hand-written last line
# may lack its newline, and awk terminates every line it keeps, so the new
# line never gets glued onto the budget.
CONFIG_TMP=$(mktemp "$AI_SANDBOX_CONFIG.XXXXXX")
{
    [ ! -f "$AI_SANDBOX_CONFIG" ] || awk '!/^DEV_TOOLS_DIR=/' "$AI_SANDBOX_CONFIG"
    printf 'DEV_TOOLS_DIR=%s\n' "$DEV_TOOLS_DIR"
} > "$CONFIG_TMP"
chmod 0644 "$CONFIG_TMP"
mv "$CONFIG_TMP" "$AI_SANDBOX_CONFIG"
unset CONFIG_TMP
log "$AI_SANDBOX_ROOT/bin"

ai_sandbox_write_bashrc_block "$BASHRC_FILE"
log "~/.ai-sandbox/bin added to PATH in ~/.bashrc (run 'source ~/.bashrc' or open a new shell)"
}
