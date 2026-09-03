#!/usr/bin/env bash
# Minimal assert library. No framework is available in this environment.
TESTS_RUN=0
TESTS_FAILED=0

_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'not ok %d - %s\n' "$TESTS_RUN" "$1" >&2
    printf '        %s\n' "$2" >&2
}
_pass() { printf 'ok %d - %s\n' "$TESTS_RUN" "$1"; }

assert_eq() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$2" = "$3" ]; then _pass "$1"
    else _fail "$1" "expected '$3', got '$2'"; fi
}
assert_contains() {
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$2" in
        *"$3"*) _pass "$1" ;;
        *)      _fail "$1" "expected to contain '$3', got '$2'" ;;
    esac
}
assert_file() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -e "$2" ]; then _pass "$1"; else _fail "$1" "missing path: $2"; fi
}
# The sandbox's SDKMAN farm is symlinks whose targets are container paths, so
# they dangle when read from the host: -e follows the link and reports nothing
# there, which makes it silently blind to both presence and absence.
assert_link() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -L "$2" ]; then _fail "$1" "not a symlink: $2"
    elif [ "$(readlink "$2")" != "$3" ]; then
        _fail "$1" "expected link to '$3', got '$(readlink "$2")'"
    else _pass "$1"; fi
}
assert_no_link() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -L "$2" ] || [ -d "$2" ]; then _fail "$1" "still present: $2"
    else _pass "$1"; fi
}
assert_no_file() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -e "$2" ]; then _pass "$1"; else _fail "$1" "path should not exist: $2"; fi
}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# A throwaway HOME with the stub docker first on PATH.
#
# Command substitution forks a subshell, so `tmp=$(fake_home)` cannot make the
# exports below visible to the calling shell -- only the printed path survives
# that. That is harmless for a suite that only compares $AI_SANDBOX_ROOT
# against itself, but a suite that shells out to create-ai-sandbox.sh needs
# the real isolation, so call this directly (`fake_home`, no `$()`) and read
# $FAKE_HOME_DIR for the temp dir; the printed value keeps working for
# existing `tmp=$(fake_home)` callers that don't need the exports.
fake_home() {
    local tmp
    tmp=$(mktemp -d)
    export HOME="$tmp/home"
    export AI_SANDBOX_ROOT="$HOME/.ai-sandbox"
    export DOCKER_STUB_LOG="$tmp/docker.log"
    export PATH="$REPO_ROOT/tests/ai-sandbox/stub:$PATH"
    mkdir -p "$HOME" "$AI_SANDBOX_ROOT"
    : > "$DOCKER_STUB_LOG"
    FAKE_HOME_DIR="$tmp"
    printf '%s' "$tmp"
}

stub_docker_log() { cat "$DOCKER_STUB_LOG"; }

finish() {
    printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
    [ "$TESTS_FAILED" -eq 0 ]
}
