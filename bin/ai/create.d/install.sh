# create.d/install.sh -- helper installation and the ~/.bashrc block.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

readonly BASHRC_BEGIN='# >>> dev-tools ai-sandbox helpers >>>'
readonly BASHRC_END='# <<< dev-tools ai-sandbox helpers <<<'

install_helpers() {
# ---------------------------------------------------------------------------
# Shell helpers
# ---------------------------------------------------------------------------

step "Installing helper commands"

BASHRC_FILE="$HOME/.bashrc"
touch "$BASHRC_FILE"

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

# The block below is deliberately trivial and stable: the helpers are real
# files now, so an open shell picks up a new version without re-sourcing
# anything, and this text should never need to change again.
HELPERS='# Helpers for dev-tools/bin/ai/create-ai-sandbox.sh live in ~/.ai-sandbox/bin.
case ":$PATH:" in
    *":$HOME/.ai-sandbox/bin:"*) ;;
    *) PATH="$HOME/.ai-sandbox/bin:$PATH" ;;
esac'

SB_BEGIN="$BASHRC_BEGIN" SB_END="$BASHRC_END" SB_HELPERS="$HELPERS" \
python3 - "$BASHRC_FILE" <<'PYEOF'
import os, re, sys
path  = sys.argv[1]
begin = os.environ["SB_BEGIN"]
end   = os.environ["SB_END"]
block = begin + "\n" + os.environ["SB_HELPERS"] + "\n" + end

content = open(path, encoding="utf-8").read()
# Remove this script's marked block, and the unmarked block written by earlier
# versions of the script.
content = re.sub(r"\n*" + re.escape(begin) + r".*?" + re.escape(end) + r"\n*",
                 "\n", content, flags=re.DOTALL)
content = re.sub(r"\n*# Antigravity Sandbox Helper\n.*?\nfunction ai-sandbox-stop\(\)\s*\{.*?\n\}\n",
                 "\n", content, flags=re.DOTALL)
content = content.rstrip("\n")
open(path, "w", encoding="utf-8").write(content + "\n\n" + block + "\n")
PYEOF
log "~/.ai-sandbox/bin added to PATH in ~/.bashrc (run 'source ~/.bashrc' or open a new shell)"
}
