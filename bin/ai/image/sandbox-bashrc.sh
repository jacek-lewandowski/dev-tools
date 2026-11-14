# shellcheck shell=bash
# ai-sandbox interactive shell setup.

# Everything a non-interactive shell needs too (PATH, SDKMAN, the entrypoint's
# environment) lives in /etc/ai-sandbox-env.sh, so it is defined once.
# shellcheck disable=SC1091
. /etc/ai-sandbox-env.sh

# The 'sdk' shell function and its completion, for interactive use. Everywhere
# else /usr/local/bin/sdk stands in for it.
# shellcheck disable=SC1091
[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && . "$SDKMAN_DIR/bin/sdkman-init.sh"

# Git identity is passed in from the host; only set it once.
if [ -n "${HOST_GIT_NAME:-}" ] && [ -z "$(git config --global user.name || true)" ]; then
    git config --global user.name "$HOST_GIT_NAME"
fi
if [ -n "${HOST_GIT_EMAIL:-}" ] && [ -z "$(git config --global user.email || true)" ]; then
    git config --global user.email "$HOST_GIT_EMAIL"
fi
git config --global core.excludesfile "$HOME/.gitignore"

_sandbox_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
export PS1='\[\033[01;33m\][sandbox]\[\033[00m\] \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;35m\]$(_sandbox_git_branch)\[\033[00m\]\$ '
