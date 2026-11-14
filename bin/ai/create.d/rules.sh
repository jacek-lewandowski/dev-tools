readonly MARKER_BEGIN='<!-- BEGIN dev-tools:ai-sandbox-environment -->'
readonly MARKER_END='<!-- END dev-tools:ai-sandbox-environment -->'

rules_shared_brain() {
# ---------------------------------------------------------------------------
# Shared brain
#
# Antigravity reads global rules from ~/.gemini/GEMINI.md and workspace rules
# from .agents/rules/. Claude Code reads ~/.claude/CLAUDE.md. Making the latter
# a symlink to the former is what actually gives both tools one brain, on the
# host as well as inside the container.
# ---------------------------------------------------------------------------

step "Wiring the shared brain"

mkdir -p "$HOME/.gemini" "$CLAUDE_PROJECT_DIR" "$HOME/.antigravity" "$HOME/.antigravity-ide" \
         "$HOME/.config/Antigravity" "$HOME/.config/Antigravity IDE" "$HOME/.config/Claude" \
         "$HOME/.gemini/antigravity/brain" "$HOME/.gemini/antigravity/conversations" \
         "$HOME/.gemini/antigravity-ide/brain" "$HOME/.gemini/antigravity-ide/conversations"
touch "$HOME/.gitignore"

SHARED_BRAIN="$HOME/.gemini/GEMINI.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
touch "$SHARED_BRAIN"

# Fold any pre-existing Claude Code global memory into the shared file once,
# then make the Claude path a symlink so the two can never drift again.
if [ -e "$CLAUDE_MD" ] && [ ! -L "$CLAUDE_MD" ]; then
    if [ -s "$CLAUDE_MD" ] && ! cmp -s "$CLAUDE_MD" "$SHARED_BRAIN"; then
        backup="${CLAUDE_MD}.pre-ai-sandbox.$(date +%Y%m%d%H%M%S)"
        cp -a "$CLAUDE_MD" "$backup"
        log "Backed up existing ~/.claude/CLAUDE.md -> ${backup##*/}"
        MERGE_SRC="$CLAUDE_MD" python3 - "$SHARED_BRAIN" <<'PYEOF'
import os, sys
target = sys.argv[1]
addition = open(os.environ["MERGE_SRC"], encoding="utf-8").read().strip()
existing = open(target, encoding="utf-8").read()
if addition and addition not in existing:
    sep = "\n\n" if existing.strip() else ""
    with open(target, "a", encoding="utf-8") as f:
        f.write(sep + addition + "\n")
    print("  Merged ~/.claude/CLAUDE.md into ~/.gemini/GEMINI.md")
PYEOF
    fi
    rm -f "$CLAUDE_MD"
fi
ln -sfn "$SHARED_BRAIN" "$CLAUDE_MD"
# shellcheck disable=SC2088  # literal text for display, not a path to expand
log "~/.claude/CLAUDE.md -> ~/.gemini/GEMINI.md"

# Retire the file the previous version of this script used, so the two brains
# do not silently compete.
LEGACY_BRAIN="$HOME/.gemini/antigravity-ide/brain/CLAUDE.md"
if [ -f "$LEGACY_BRAIN" ] && [ ! -L "$LEGACY_BRAIN" ]; then
    mv "$LEGACY_BRAIN" "${LEGACY_BRAIN}.superseded"
    log "Retired legacy brain file -> ${LEGACY_BRAIN##*/}.superseded (Antigravity never read it)"
fi

# Shared knowledge repository: when configured, the rendered main branch is what
# the tools read, and the sandbox gets its own clone. All network git runs here,
# on the host, and never blocks the start.
KNOWLEDGE="no"
if ai_knowledge_configured; then
    step "Shared knowledge repository"
    "$SCRIPT_DIR/ai-knowledge" sync "$PROJECT_ABS_DIR" || warn "knowledge sync reported a problem; see above"
    KNOWLEDGE="yes"
fi

# Build the tooling notes from the feature set that is actually enabled, so the
# agents are never told about tools that were not installed.
HOST_SDKMAN="$HOME/.sdkman"      # the SDKMAN section below keys off the same path
# Bare plugin names for the notes, derived from CLAUDE_PLUGINS.
CLAUDE_PLUGIN_NAMES=""
for _p in "${CLAUDE_PLUGINS[@]}"; do
    CLAUDE_PLUGIN_NAMES+="${CLAUDE_PLUGIN_NAMES:+, }\`${_p%@*}\`"
done
unset _p
TOOL_NOTES="- \`headroom\` -- token compression for tool output, logs and files
  (\`headroom wrap <tool>\`, \`headroom proxy --port 8787\`, \`headroom doctor\`, \`headroom mcp\`),
  or \`from headroom import compress\`. Use it to shrink large JSON payloads, logs or
  command output before they land in context.
- \`socat\` -- create virtual serial port pairs, e.g.
  \`socat -d -d pty,raw,echo=0 pty,raw,echo=0\`.
- \`sox\`/\`ffmpeg\` -- audio and video conversion.
- ImageMagick 6.
- \`sg\` (ast-grep) and \`comby\` -- structural search and replace.
- \`pnpm\` and \`yarn\` -- through corepack; a project's \`packageManager\` field is honoured.
- \`firebase\`, \`gcloud\`, \`gh\`, \`cloudflared\`, \`agy\`, \`codex\` -- already installed; do not reinstall them.
- \`gitleaks\` -- secret scanner behind the repository's git hooks (\`git config core.hooksPath .githooks\`).
- Claude Code plugins ${CLAUDE_PLUGIN_NAMES} are installed at container start (log: \`/tmp/claude-plugins.log\`); \`sandbox-doctor\` lists any missing.
- \`nano\` and \`net-tools\` (\`ifconfig\`, \`netstat\`, \`route\`) are also installed.
- \`agy -p \"<prompt>\" --model <id>\` may receive project content (it is an
  approved model provider here). Call it as one bare command with the prompt
  right after \`-p\`, before \`--model\`; do not chain it with other commands. If
  \`agy models\` says it is not signed in, use Claude instead. Headless agy may
  fetch URLs and run read-only shell tools (\`ls\`, \`cat\`, \`grep\`, \`find\`,
  \`diff\` and the like; the list is in the entrypoint); it cannot write files
  or run anything else, and a denied call cancels its run.
- For scout, writer and second-reviewer tasks, use \`ai-delegate <role> <task-file>\`
  first; spawn the Claude subagent of the same name only when it exits 3 (agy not
  signed in) or 1 (agy failed). Never spawn \`second-reviewer\` as a Claude subagent.
  Only the lead runs \`ai-delegate\`; subagents never call it. Give its Bash call a
  timeout of at least 600000 ms or run it in the background: agy may take 9 minutes.
  It prints \`ai-delegate: conversation_id=<id>\` on stderr; round 2 of a second
  review passes that id as \`--conversation <id>\` to continue round 1.
- \`./gradlew --offline\` works for what the host has downloaded, and the
  network stays available; writes to the Gradle and Maven caches are
  discarded at the next container start; the host's \`gradle.properties\`,
  \`init.d\` and Maven settings are absent. If \`sandbox-doctor\` reports the
  caches as not mounted, ask the user to re-run \`create-ai-sandbox.sh\` on the
  host."

if [ -d "$HOST_SDKMAN" ]; then
    TOOL_NOTES="${TOOL_NOTES}
- \`sdk\` -- SDKMAN, and the only source of JDKs and other toolchains: \`java\` is
  on PATH and JAVA_HOME is set in every shell, so never apt-get install a JDK.
  \`ls ~/.sdkman/candidates/java\` lists the versions the host has; \`sdk default
  java <version>\` switches this sandbox to one of them (the host and other
  sandboxes keep theirs) and works from non-interactive shells too. \`sdk install\`
  writes inside the sandbox."
fi

if [ "$WITH_AUDIO" = "yes" ]; then
    TOOL_NOTES="${TOOL_NOTES}
- \`parec\`/\`paplay\`, \`arecord\`/\`aplay\` -- capture from and play to the host's sound devices."
fi

if [ -d "$IDEA_HOST_DIR" ]; then
    TOOL_NOTES="${TOOL_NOTES}
- \`idea\` -- IntelliJ IDEA, mounted read-only from the host at
  \`${IDEA_HOST_DIR}\`. Start it with \`idea &\`. Its settings, plugins and indexes
  belong to this sandbox, and it picks up the SDKMAN JDKs under \`~/.sdkman\`."
fi

if [ "$WITH_DOCKER" = "yes" ]; then
    TOOL_NOTES="${TOOL_NOTES}
- \`docker\` -- rootless Docker daemon running inside this container. Run
  \`sandbox-doctor\` if it is not responding.
- \`earthly\` -- Earthly builds, using that internal daemon."
fi

case "$DISPLAY_MODE" in
    wayland) DISPLAY_NOTE="GUI apps render through the host Wayland compositor; X11-only apps use a container-private Xwayland on :99." ;;
    xpra)    DISPLAY_NOTE="GUI apps render on a private virtual display and are forwarded to the user's desktop by xpra, one window each." ;;
    nested)  DISPLAY_NOTE="GUI apps render into a dedicated Xephyr window on the host; a window manager is started automatically." ;;
    host)    DISPLAY_NOTE="GUI apps render on the host's real X display." ;;
    none)    DISPLAY_NOTE="There is no display. Do not try to start GUI applications." ;;
esac

KNOWLEDGE_NOTE=""
if [ "$KNOWLEDGE" = "yes" ]; then
KNOWLEDGE_NOTE="
Shared knowledge: the global rules and roles you read are rendered read-only from
a private git repository. Your own clone of it is at ~/knowledge with main checked
out. A project sandbox proposes a generic rule with the \`propose-rule\` skill: one
file on a branch proposal/<date>-<slug>-<hex>, never a commit on main (a hook
refuses it), never a push; the host pushes on the next sync (a sandbox start or
\`ai-knowledge sync --all\`) and the integrator sandbox, which commits on main,
decides with the \`knowledge-integrate\` skill. \`sandbox-doctor\` shows what is
pushed and pending. A \`process-report\` report is filed the same way, as a ref
refs/reports/<date>-<project>-<hex>, outside main and every branch; only the
integrator sandbox receives it.
"
fi

SANDBOX_BLOCK="${MARKER_BEGIN}
## AI sandbox environment (dev-tools/bin/ai/create-ai-sandbox.sh)

This section applies only when you are running inside an ai-sandbox container
created by \`dev-tools/bin/ai/create-ai-sandbox.sh\` (Ubuntu 22.04, full CLI access
and passwordless sudo). It does not apply when running natively on the host.
You can tell which you are in: inside the sandbox, \`/etc/ai-sandbox-release\` exists.

Available in addition to the usual tooling:

${TOOL_NOTES}

Environment notes:
- ${DISPLAY_NOTE}
- Networking is bridged, not host. The host's own services are reachable at
  \`host.docker.internal\`, not at \`localhost\`.
- The container is capped at ${MEMORY_LIMIT} of RAM with no swap and ${CPUSET_WANT} CPU core(s);
  \`nproc\` reports that number and it is the ceiling for build and test
  parallelism: an over-parallel build is OOM-killed, not merely slowed.
  (\`free\` and /proc/cpuinfo describe the host, not this container.)
- The sandbox uses the host's timezone (TZ=${HOST_TZ}); \`date\` agrees with the host.
- The project is mounted read-write at its real host path, so edits are real
  edits to the user's working tree. The only other host paths mounted are the
  shared AI rules file, the Antigravity brain and conversations, this project's
  Claude Code history and memory, and ~/.gitignore (read-write), plus the
  dev-tools helpers, IntelliJ IDEA and SDKMAN (read-only, when present) and the
  host's Gradle and Maven caches (overlaid: read-only underneath, with writes
  kept in this sandbox until its next start). The rest of the host filesystem
  is not mounted.
- Only explicitly passed-through serial ports are visible under /dev. No other
  host USB device is reachable: /dev/bus/usb is not mounted.
- The subagent prompt-cache TTL is already one hour here, set by the
  environment variable CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL, which overrides
  settings.json. Do not set it again.
${KNOWLEDGE_NOTE}
Double-check what you are doing, and whether it addresses the request, before acting.
${MARKER_END}"

if [ "$KNOWLEDGE" = "yes" ]; then
    # The rules file is rendered from the knowledge repository. The block lives
    # beside the checkout and the render appends it; it never enters the repository.
    printf '%s\n' "$SANDBOX_BLOCK" > "$AI_KNOWLEDGE_ROOT/sandbox-environment.md"
    "$SCRIPT_DIR/ai-knowledge" render >/dev/null || warn "knowledge render failed; see above"
    log "Updated the ai-sandbox block in $AI_KNOWLEDGE_ROOT/sandbox-environment.md (rendered into GLOBAL.md)"
else
SANDBOX_BLOCK="$SANDBOX_BLOCK" python3 - "$SHARED_BRAIN" "$MARKER_BEGIN" "$MARKER_END" <<'PYEOF'
import os, re, sys
path, begin, end = sys.argv[1], sys.argv[2], sys.argv[3]
block = os.environ["SANDBOX_BLOCK"]
with open(path, encoding="utf-8") as f:
    content = f.read()
pattern = re.compile(r"\n*" + re.escape(begin) + r".*?" + re.escape(end) + r"\n*", re.DOTALL)
content = pattern.sub("\n", content).rstrip("\n")
with open(path, "w", encoding="utf-8") as f:
    f.write((content + "\n\n" if content else "") + block + "\n")
PYEOF
log "Updated the ai-sandbox block in ~/.gemini/GEMINI.md"
fi

# The previous version generated a .agentrules file in every project. Neither
# Claude Code nor Antigravity reads that filename, and it claimed the agent was
# sandboxed even when read on the host. Move it aside rather than deleting it.
if [ -f "$PROJECT_ABS_DIR/.agentrules" ] \
   && head -n 1 "$PROJECT_ABS_DIR/.agentrules" | grep -q '^# Agent Environment Context$'; then
    mv "$PROJECT_ABS_DIR/.agentrules" "$PROJECT_ABS_DIR/.agentrules.superseded"
    log "Retired generated .agentrules -> .agentrules.superseded (no tool reads that path)"
fi
}
