# create.d/image.sh -- build context, Dockerfile, image build and stamp; the baked files are in ../image/.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

# Pinned upstream versions. Bump deliberately; do not float.
readonly ANTIGRAVITY_CLI_VERSION='1.4.0-5281842794987520'
readonly ANTIGRAVITY_HUB_VERSION='2.24.0-5780333019398144'
readonly ANTIGRAVITY_IDE_VERSION='2.5.5-4923483625488384'
readonly COMBY_VERSION='1.8.1'
readonly EARTHLY_VERSION='v0.8.15'
readonly GITLEAKS_VERSION='8.30.1'
# uv installs the Python packages; headroom's own 'sandbox' extra has no torch, nvidia or lancedb.
readonly UV_VERSION='0.13.8'
readonly HEADROOM_VERSION='0.42.0'
# From the release's gitleaks_${GITLEAKS_VERSION}_checksums.txt; bump with the version.
readonly GITLEAKS_LINUX_X64_SHA256='551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb'
readonly GOOGLE_CHROME_VERSION='152.0.7977.64-1'
readonly NODE_MAJOR='24'
# The headless browser every sandbox gets (Dockerfile.base); puppeteer-core downloads no browser.
readonly PLAYWRIGHT_VERSION='1.65.1'
readonly PUPPETEER_CORE_VERSION='25.17.0'

# Claude Code plugins every sandbox gets at container start (entrypoint.sh).
# The one place the list lives; it is rendered into claude-plugins.list.
readonly CLAUDE_PLUGINS_MARKETPLACE='claude-plugins-official'
readonly CLAUDE_PLUGINS_MARKETPLACE_SOURCE='anthropics/claude-plugins-official'
readonly -a CLAUDE_PLUGINS=(
    "superpowers@${CLAUDE_PLUGINS_MARKETPLACE}"
    "frontend-design@${CLAUDE_PLUGINS_MARKETPLACE}"
    "code-simplifier@${CLAUDE_PLUGINS_MARKETPLACE}"
    "playwright@${CLAUDE_PLUGINS_MARKETPLACE}"
    "claude-md-management@${CLAUDE_PLUGINS_MARKETPLACE}"
)

image_name() {
# A sandbox with any display mode but 'none' gets the -gui image (Dockerfile.gui); runs after display_resolve.
if [ "$DISPLAY_MODE" = "none" ]; then IMAGE_GUI=""; else IMAGE_GUI="gui"; fi
if [ "$WITH_DOCKER" = "yes" ]; then IMAGE_VARIANT="docker"; else IMAGE_VARIANT="base"; fi
IMAGE_NAME=$(ai_sandbox_image_name "$IMAGE_VARIANT" "$IMAGE_GUI")
IMAGE_VARIANT="${IMAGE_VARIANT}${IMAGE_GUI:+-$IMAGE_GUI}"   # the build hash covers the family too
IMAGE_STAMP="$IMAGE_DIR/${IMAGE_NAME#ai-sandbox:}.stamp"   # <variant>-u<uid>, as before
}

image_context() {
# ---------------------------------------------------------------------------
# Build context
# ---------------------------------------------------------------------------

step "Generating build context"

# Written with cat, as the base did: a new file then gets 0666 & ~umask, where cp would give 0644 & ~umask.
cat "$SCRIPT_DIR/image/entrypoint.sh" > "$BUILD_DIR/entrypoint.sh"
sed -i -e "s|@MARKETPLACE_SOURCE@|$CLAUDE_PLUGINS_MARKETPLACE_SOURCE|" -e "s|@MARKETPLACE@|$CLAUDE_PLUGINS_MARKETPLACE|" "$BUILD_DIR/entrypoint.sh"
printf '%s\n' "${CLAUDE_PLUGINS[@]}" > "$BUILD_DIR/claude-plugins.list"

cat "$SCRIPT_DIR/image/sandbox-doctor" > "$BUILD_DIR/sandbox-doctor"

# The 'for' loop's key:path list, generated here from the same table every
# other surface reads (ai_sandbox_build_caches) rather than duplicated by hand,
# and filled into the placeholder of the file copied above, as the entrypoint's
# marketplace is. The value is escaped for sed (\, & and the | delimiter).
doctor_loop=$({
    printf 'for _bc in'
    while IFS='|' read -r _key _path; do
        [ -n "$_key" ] || continue
        printf ' "%s:%s"' "$_key" "$_path"
    done < <(ai_sandbox_build_caches)
    printf '; do'
})
sed -i "s|@BUILD_CACHE_LOOP@|$(printf '%s' "$doctor_loop" | sed -e 's/[\\&|]/\\&/g')|" "$BUILD_DIR/sandbox-doctor"
unset _key _path doctor_loop

cat "$SCRIPT_DIR/image/sandbox-desktop" > "$BUILD_DIR/sandbox-desktop"

cat "$SCRIPT_DIR/image/sandbox-idea" > "$BUILD_DIR/sandbox-idea"

cat "$SCRIPT_DIR/image/xdg-open" > "$BUILD_DIR/xdg-open"

# Interactive shell configuration, sourced from .bashrc. Written as a real file
# rather than a chain of echoes so that quoting is unambiguous.
cat "$SCRIPT_DIR/image/sandbox-bashrc.sh" > "$BUILD_DIR/sandbox-bashrc.sh"

# Environment for EVERY shell. Agents never get an interactive one: 'ai-sandbox
# <cmd>' runs 'bash -lc', which reads /etc/profile.d but stops in .bashrc at
# Ubuntu's interactivity guard, and a bare 'bash -c' reads only BASH_ENV. So
# whatever lived in .bashrc alone was invisible to them: 'java' looked "not
# installed" and got apt-installed instead of taken from SDKMAN. This file is
# reached from all three directions (profile.d symlink, BASH_ENV, .bashrc) and
# therefore has to be idempotent, silent and POSIX sh.
cat "$SCRIPT_DIR/image/sandbox-env.sh" > "$BUILD_DIR/sandbox-env.sh"

# 'sdk' is a shell function that only interactive shells define. Agents run
# 'bash -c' and subprocesses, where it does not exist -- so they gave up on
# SDKMAN and apt-installed a JDK. This wrapper makes the command work from
# anywhere; interactive shells still get the real function, which shadows it.
cat "$SCRIPT_DIR/image/sandbox-sdk" > "$BUILD_DIR/sandbox-sdk"

# Managed settings (root-owned in the image): Claude Code takes classifier
# (autoMode) rules only from user/flag/managed sources, and will not let a
# session write them into its own settings. Without this, auto mode blocks
# `agy -p` as exfiltration to Google.
cat "$SCRIPT_DIR/image/claude-managed-settings.json" > "$BUILD_DIR/claude-managed-settings.json"

cp "$SCRIPT_DIR/image/ai-delegate" "$BUILD_DIR/ai-delegate"
cp "$SCRIPT_DIR/image/sandbox-knowledge-sync" "$BUILD_DIR/sandbox-knowledge-sync"
cp "$SCRIPT_DIR/context-statusline" "$BUILD_DIR/context-statusline"

# --- Dockerfile ------------------------------------------------------------

cat "$SCRIPT_DIR/image/Dockerfile.head" > "$BUILD_DIR/Dockerfile"

cat "$SCRIPT_DIR/image/Dockerfile.base" >> "$BUILD_DIR/Dockerfile"

if [ "$WITH_DOCKER" = "yes" ]; then
cat "$SCRIPT_DIR/image/Dockerfile.docker" >> "$BUILD_DIR/Dockerfile"
fi

if [ -n "$IMAGE_GUI" ]; then
cat "$SCRIPT_DIR/image/Dockerfile.gui" >> "$BUILD_DIR/Dockerfile"
fi

cat "$SCRIPT_DIR/image/Dockerfile.tail" >> "$BUILD_DIR/Dockerfile"

# Fill the @NAME@ placeholders of the ARG lines above (the generated Dockerfile
# is written through quoted heredocs, so the shell cannot expand them there).
for _arg in NODE_MAJOR ANTIGRAVITY_CLI_VERSION ANTIGRAVITY_HUB_VERSION ANTIGRAVITY_IDE_VERSION \
        COMBY_VERSION EARTHLY_VERSION GITLEAKS_VERSION GITLEAKS_LINUX_X64_SHA256 \
        GOOGLE_CHROME_VERSION UV_VERSION HEADROOM_VERSION PLAYWRIGHT_VERSION PUPPETEER_CORE_VERSION; do
    sed -i "s|@${_arg}@|${!_arg}|g" "$BUILD_DIR/Dockerfile"
done
unset _arg

log "Dockerfile and helper scripts written to $BUILD_DIR"
}

image_build() {
step "Image"
BUILD_HASH=$(ai_sandbox_build_hash "$BUILD_DIR" \
             "$HOST_UID" "$HOST_GID" "$HOST_USER" "$CONTAINER_HOME" "$IMAGE_VARIANT")

need_build="no"
if [ "$FORCE_REBUILD" = "yes" ]; then
    need_build="yes"
elif ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    need_build="yes"
elif [ ! -f "$IMAGE_STAMP" ] || [ "$(cat "$IMAGE_STAMP")" != "$BUILD_HASH" ]; then
    need_build="yes"
fi

if [ "$need_build" = "yes" ]; then
    log "building $IMAGE_NAME -- one image per kind, shared by every project"
    docker_build_flags=()
    [ "$FORCE_REBUILD" = "yes" ] && docker_build_flags+=(--no-cache)
    DOCKER_BUILDKIT=1 docker build "${docker_build_flags[@]+"${docker_build_flags[@]}"}" \
        --build-arg "USER_ID=$HOST_UID" \
        --build-arg "GROUP_ID=$HOST_GID" \
        --build-arg "USER_NAME=$HOST_USER" \
        --build-arg "USER_HOME=$CONTAINER_HOME" \
        -t "$IMAGE_NAME" "$BUILD_DIR"
    # Only stamped after a successful build, so a failure retries next run.
    printf '%s\n' "$BUILD_HASH" > "$IMAGE_STAMP"
else
    log "$IMAGE_NAME is up to date"
fi
}
