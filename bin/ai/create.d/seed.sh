# create.d/seed.sh -- tool-state seed, IntelliJ and the SDKMAN farm.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

# What the seed copies is one table in ai-sandbox-lib.sh (ai_sandbox_seed_table): the settings
# rows always, the login rows only for a sandbox in the host mode (--host-logins). Each login
# row copied is appended to host-logins.log, which only the host reads ('ai-sandbox-account
# reset' lists it).
seed_tool_state() {
# ---------------------------------------------------------------------------
# Copy tool state into the sandbox
# ---------------------------------------------------------------------------

step "Copying tool state into the sandbox"

if [ -f "$SANDBOX_DIR/.seeded" ]; then
    log "already seeded on $(cat "$SANDBOX_DIR/.seeded")"
    log "this project's logins are left alone; 'ai-sandbox-account refresh' re-pulls the host's"
    # W4: written without following a link the sandbox may have put at the target (D9: a refusal
    # is one stderr line and create goes on); a link at the source is not read.
    if [ ! -f "$SANDBOX_DIR/.antigravity-ide/argv.json" ] && [ -f "$SANDBOX_DIR/.antigravity/argv.json" ] \
       && [ ! -L "$SANDBOX_DIR/.antigravity/argv.json" ]; then
        ai_sandbox_nofollow write "$(readlink -f "$SANDBOX_DIR")/.antigravity-ide" argv.json < "$SANDBOX_DIR/.antigravity/argv.json" || true
    fi
else
    log "seeding from the host, once. Later runs will not overwrite this, so a"
    log "login made inside the sandbox survives."

    ai_sandbox_seed_copy "$SANDBOX_DIR" settings tools >/dev/null
    log "settings"
    # Codex's permission mode and trust of this project, and agy's trust of it: written, not copied
    ai_sandbox_seed_codex_default "$SANDBOX_DIR" "$PROJECT_ABS_DIR" || true
    ai_sandbox_seed_agy_trust "$SANDBOX_DIR" "$PROJECT_ABS_DIR" || true
    log "Codex default (approve for me, this project trusted) and agy's trust of this project"
    if [ "$LOGINS_SEED" = "yes" ]; then
        ai_sandbox_seed_copy "$SANDBOX_DIR" login tools | ai_sandbox_seed_log_logins "$SANDBOX_DIR"
        log "the host's logins (--host-logins)"
    else
        log "no logins: log in inside the sandbox"
    fi

    # The mode is recorded before .seeded exists, so a create that stops after this point does not
    # leave a sandbox that reads as an unrecorded legacy one (.seeded present, no key).
    compose_env_skeleton
    ai_sandbox_env_set "$SANDBOX_DIR" SANDBOX_HOST_LOGINS "$LOGINS_MODE"
    # The size too: a .env without it reads as a sandbox from before the key (6 GB), not a new one.
    ai_sandbox_env_set "$SANDBOX_DIR" SANDBOX_MEMORY_GB "$MEMORY_GB"
    date -Iseconds > "$SANDBOX_DIR/.seeded"
fi

# Enforced on every run, seeded or not.
[ -f "$SANDBOX_DIR/.claude.json" ] || echo '{}' > "$SANDBOX_DIR/.claude.json"
chmod 600 "$SANDBOX_DIR/.claude.json"

# gcloud: no host credentials are copied and no login is performed. The isolated
# config directory is mounted empty; run 'gcloud auth login' inside the sandbox
# if and when a project needs it.
log "gcloud: isolated empty config at $SANDBOX_DIR/gcloud (log in inside the sandbox if needed)"
}

seed_idea() {
# ---------------------------------------------------------------------------
# IntelliJ IDEA
#
# The installation itself is the host's and is mounted read-only: the sandbox
# runs the IDE but cannot modify or auto-update it. Everything IDEA writes is
# under $HOME, split three ways because the three have different lifetimes:
#
#   ~/.config/JetBrains       settings -- per sandbox, seeded from the host once;
#                             the licence or JetBrains Account token only with
#                             --host-logins, otherwise activate the IDE inside.
#   ~/.local/share/JetBrains  downloaded plugins -- bulk and identical for every
#                             project, so it lives in the shared store, read-only.
#   ~/.cache/JetBrains        indexes, logs, the system directory -- per sandbox,
#                             never seeded, and a mount of its own: two IDEs
#                             indexing through one directory corrupt it.
#
# All three are mounts, so they survive the container being recreated, which
# happens on every run of this script.
# ---------------------------------------------------------------------------

if [ -d "$IDEA_HOST_DIR" ]; then
    step "IntelliJ IDEA"
    log "installation $IDEA_HOST_DIR (read-only)"

    # Existence is the marker: seeded once, then this sandbox's own. The IDE's settings are
    # settings rows of the seed table; its licence is a login row (copied only in the host mode).
    if [ ! -e "$SANDBOX_DIR/jetbrains-config" ]; then
        mkdir -p "$SANDBOX_DIR/jetbrains-config"
        if [ -d "$HOME/.config/JetBrains" ]; then
            ai_sandbox_seed_copy "$SANDBOX_DIR" settings idea >/dev/null
            log "settings seeded from the host, once"
            if [ "${LOGINS_MODE:-}" != "0" ]; then
                ai_sandbox_seed_copy "$SANDBOX_DIR" login idea | ai_sandbox_seed_log_logins "$SANDBOX_DIR"
                log "licence seeded from the host (--host-logins)"
            fi
        fi
    else
        log "settings are this sandbox's own; delete jetbrains-config to re-seed"
    fi

    # Plugins come from the shared store, synced from the host above and
    # read-only in the sandbox, so they are installed on the host.
    log "plugins from the shared store, read-only ($(du -sh "$SHARED_DIR/jetbrains-plugins" 2>/dev/null | cut -f1))"

    # Created here, not by Docker: a missing bind source becomes a root-owned
    # directory the IDE then cannot write to.
    mkdir -p "$SANDBOX_DIR/jetbrains-cache"
    log "run it with: ai-sandbox   then  idea &"
fi
}

seed_sdkman() {
# ---------------------------------------------------------------------------
# SDKMAN
#
# The host's ~/.sdkman carries a couple of GB of toolchains, so it stays mounted
# read-only and is never duplicated. What a sandbox does need to own is
# 'candidates/<c>/current' -- SDKMAN's notion of "the default" -- so that
# 'sdk default java 17.0.16-tem' in one project changes neither the host nor any
# other project. A read-only mount cannot give that, because 'sdk default'
# rewrites exactly that symlink.
#
# So the sandbox gets its own SDKMAN_DIR, built almost entirely out of symlinks:
#
#   <sandbox>/sdkman/
#     bin,libexec,contrib -> ~/.sdkman-host/...          host machinery, ro
#     src/                                               copied (find needs a real dir)
#     etc/, var/, ext/, tmp/                             real, writable
#     candidates/java/
#       21.0.8-tem  -> ~/.sdkman-host/candidates/java/21.0.8-tem
#       17.0.16-tem -> ...                               one per host version
#       current     -> 21.0.8-tem                        real symlink, WRITABLE
#
# The link targets are container paths, so this tree dangles when read from the
# host. That is deliberate: it is only ever resolved inside the sandbox, and it
# keeps the sandbox directory at a few hundred kB rather than gigabytes.
#
# Version links are refreshed on every run, so a JDK installed on the host turns
# up in sandboxes that already exist. 'current' is snapshotted once and then left
# alone, because it is the per-project setting this whole arrangement is for.
# 'sdk install' inside a sandbox writes a real directory here and is untouched.
# ---------------------------------------------------------------------------

SDKMAN_FARM="$SANDBOX_DIR/sdkman"
CONTAINER_SDKMAN_HOST="$CONTAINER_HOME/.sdkman-host"

sync_sdkman_farm() {
    local part cdir vdir name version cur target seeded=0 fr nf=ai_sandbox_nofollow

    # W3: everything below the farm (a bind source, mounted at ~/.sdkman) is written through
    # ai_sandbox_nofollow rooted at it, so a link a sandbox placed there is replaced or refused
    # (one stderr line, create goes on: D9), never written through.
    mkdir -p "$SDKMAN_FARM"
    fr="$(readlink -f "$SANDBOX_DIR")/sdkman"
    for part in candidates etc var ext tmp; do $nf mkdir "$fr" "$part" || true; done

    # Linked, not copied, so a 'sdk selfupdate' on the host reaches every
    # sandbox at once and none of them carries a second copy of libexec.
    for part in bin libexec contrib; do
        if [ -d "$HOST_SDKMAN/$part" ]; then $nf link "$fr" "$part" "$CONTAINER_SDKMAN_HOST/$part" || true; fi
    done
    # src is the exception: sdkman-init.sh loads its functions with
    # 'find "$SDKMAN_DIR/src" -type f', and find does not descend into a
    # symlinked starting point (nor match symlinked files). Behind a link, no
    # function was ever defined -- 'sdk' did not exist and the candidates never
    # reached PATH. It is 100 kB, so a real copy, refreshed on every run.
    if [ -d "$HOST_SDKMAN/src" ]; then
        if [ -L "$SDKMAN_FARM/src" ]; then $nf remove "$fr" src || true; fi
        $nf copy "$fr" src "$HOST_SDKMAN/src" --delete || true
    fi

    # Knobs a sandbox may legitimately change: seeded from the host, then its own.
    # '||' rather than 'if' would make a host without etc/config fatal under set -e.
    if [ ! -f "$SDKMAN_FARM/etc/config" ] && [ -f "$HOST_SDKMAN/etc/config" ]; then
        $nf write "$fr" etc/config < "$HOST_SDKMAN/etc/config" || true
    fi
    if [ -d "$HOST_SDKMAN/var" ]; then $nf copy "$fr" var "$HOST_SDKMAN/var" --ignore-existing || true; fi

    for cdir in "$HOST_SDKMAN/candidates"/*; do
        [ -d "$cdir" ] || continue
        name=${cdir##*/}
        $nf mkdir "$fr" "candidates/$name" || continue

        # One link per version the host has installed.
        for vdir in "$cdir"/*; do
            version=${vdir##*/}
            [ "$version" = current ] && continue        # the default pointer, not a version
            [ -d "$vdir" ] || continue
            # a real directory here is the sandbox's own 'sdk install' of that version: skipped (D19)
            if [ -d "$SDKMAN_FARM/candidates/$name/$version" ] && [ ! -L "$SDKMAN_FARM/candidates/$name/$version" ]; then continue; fi
            $nf link "$fr" "candidates/$name/$version" "$CONTAINER_SDKMAN_HOST/candidates/$name/$version" || true
        done

        # Retire links to versions the host has since removed. Symlinks only: a
        # real directory here was installed inside the sandbox and is not ours.
        for vdir in "$SDKMAN_FARM/candidates/$name"/*; do
            version=${vdir##*/}
            [ "$version" = current ] && continue
            [ -L "$vdir" ] || continue
            [ -d "$HOST_SDKMAN/candidates/$name/$version" ] || $nf remove "$fr" "candidates/$name/$version" || true
        done

        cur="$SDKMAN_FARM/candidates/$name/current"
        if [ ! -L "$cur" ]; then
            # First sight of this candidate: start from the host's default.
            target=$(readlink "$cdir/current" 2>/dev/null || true)
            if [ -n "$target" ]; then
                $nf link "$fr" "candidates/$name/current" "${target##*/}" || true
                seeded=$((seeded + 1))
            fi
            continue
        fi

        # This sandbox's own default. Left as it is -- unless it has gone
        # dangling, which would drop the candidate off PATH with no explanation.
        # 'sdk default' writes an absolute (container-side) link, not a bare
        # version, so judge it by its last component or every choice made
        # inside the sandbox would look dangling from the host and be undone.
        target=$(readlink "$cur"); target=${target##*/}
        if [ ! -L "$SDKMAN_FARM/candidates/$name/$target" ] \
           && [ ! -d "$SDKMAN_FARM/candidates/$name/$target" ]; then
            warn "This sandbox's default $name ($target) is no longer installed on the host."
            target=$(readlink "$cdir/current" 2>/dev/null || true)
            if [ -n "$target" ]; then
                $nf link "$fr" "candidates/$name/current" "${target##*/}" || true
                log "  repointed $name -> ${target##*/} (the host's default)"
            else
                $nf remove "$fr" "candidates/$name/current" || true
                log "  dropped the $name default; set one with 'sdk default $name <version>'"
            fi
        fi
    done

    for cdir in "$SDKMAN_FARM/candidates"/*; do
        [ -d "$cdir" ] || continue
        target=$(readlink "$cdir/current" 2>/dev/null || true)
        [ -n "$target" ] && log "  ${cdir##*/} = ${target##*/}"
    done
    [ "$seeded" -gt 0 ] && log "snapshotted $seeded default(s) from the host; yours to change now"
    return 0
}

if [ -d "$HOST_SDKMAN" ]; then
    step "SDKMAN"
    log "toolchains stay on the host, read-only; the defaults below are this sandbox's"
    sync_sdkman_farm
else
    # shellcheck disable=SC2088  # literal text for display, not a path to expand
    log "no ~/.sdkman on the host; SDKMAN will not be available in the sandbox"
fi
}
