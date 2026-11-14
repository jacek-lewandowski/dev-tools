# create.d/install.sh -- create's side of C-INSTALL: a revision is installed.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

# Before anything is written: the compose file mounts the installed revision's tools, and
# the commands a sandbox start runs are the installed ones. ai-sandbox-install installs
# a revision; create never does.
install_require_revision() {
    [ -d "$AI_SANDBOX_INSTALLED/current/tools" ] \
        || die "No revision is installed ($AI_SANDBOX_INSTALLED/current/tools is missing). Install one first: ai-sandbox-install --from <the directory holding bin/ai>"
}
