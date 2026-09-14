#!/usr/bin/env bash
# The shared knowledge repository: read-only rules for every sandbox, a
# proposals branch per sandbox, all network git on the host.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

# The lib derives its paths from AI_SANDBOX_ROOT when sourced, so the fake home
# has to exist first.
fake_home >/dev/null; tmp="$FAKE_HOME_DIR"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

assert_eq "knowledge root derives from the sandbox root" "$AI_KNOWLEDGE_ROOT" "$AI_SANDBOX_ROOT/knowledge"
assert_eq "render lives in the shared store" "$AI_KNOWLEDGE_RENDER" "$AI_SANDBOX_ROOT/shared/knowledge"
ai_knowledge_configured && r=yes || r=no
assert_eq "not configured without the config file" "$r" no
assert_contains "ai-knowledge is an installed helper" "$(ai_sandbox_helpers)" "ai-knowledge"

rm -rf "$tmp"
finish
