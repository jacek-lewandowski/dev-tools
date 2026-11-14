# create.d/seed.sh -- tool-state seed, IntelliJ and the SDKMAN farm.
# Sourced by create-ai-sandbox.sh, never run: definitions only; the entry calls the
# stage functions in order and they set the script's globals.

seed_tool_state() {
# ---------------------------------------------------------------------------
# Copy tool state into the sandbox
# ---------------------------------------------------------------------------

step "Copying tool state into the sandbox"

# The exclude list lives in ai-sandbox-lib.sh so that 'ai-sandbox-account
# refresh' copies exactly what the seed copies.
seed_rsync() {  # <path under $HOME> <path under $SANDBOX_DIR> [rsync flags...]
    local host_rel=$1 sb_rel=$2 ex
    shift 2
    mapfile -t ex < <(ai_sandbox_seed_excludes "$host_rel")
    safe_rsync -a "$@" "${ex[@]}" "$HOME/$host_rel/" "$SANDBOX_DIR/$sb_rel/"
}

if [ -f "$SANDBOX_DIR/.seeded" ]; then
    log "already seeded on $(cat "$SANDBOX_DIR/.seeded")"
    log "this project's logins are left alone; 'ai-sandbox-account refresh' re-pulls the host's"
    if [ ! -f "$SANDBOX_DIR/.antigravity-ide/argv.json" ] && [ -f "$SANDBOX_DIR/.antigravity/argv.json" ]; then
        cp -a "$SANDBOX_DIR/.antigravity/argv.json" "$SANDBOX_DIR/.antigravity-ide/argv.json"
    fi
else
    log "seeding from the host, once. Later runs will not overwrite this, so a"
    log "login made inside the sandbox survives."

    if [ -d "$HOME/.gemini" ]; then
        seed_rsync .gemini .gemini --delete-excluded
        log ".gemini"
    fi
    if [ -d "$HOME/.antigravity" ]; then
        seed_rsync .antigravity .antigravity
        log ".antigravity"
    fi
    if [ -d "$HOME/.antigravity-ide" ]; then
        seed_rsync .antigravity-ide .antigravity-ide
        log ".antigravity-ide"
    elif [ -d "$HOME/.antigravity" ]; then
        seed_rsync .antigravity .antigravity-ide
        log ".antigravity-ide (from .antigravity)"
    fi
    if [ -d "$HOME/.config/Antigravity" ]; then
        seed_rsync .config/Antigravity antigravity-data
        log "Antigravity"
    fi
    if [ -d "$HOME/.config/Antigravity IDE" ]; then
        seed_rsync '.config/Antigravity IDE' antigravity-ide-data
        log "Antigravity IDE"
    fi
    if [ -d "$HOME/.config/Claude" ]; then
        seed_rsync .config/Claude claude-data
        log "Claude Desktop"
    fi
    if [ -d "$HOME/.claude" ]; then
        # CLAUDE.md and this project's projects/ entry are bind-mounted live
        # further down, not copied; other projects' history stays on the host.
        seed_rsync .claude .claude
        log ".claude"
    fi

    # ~/.claude.json is the Claude Code CLI's account/session state and lives
    # beside ~/.claude rather than inside it.
    if [ -f "$HOME/.claude.json" ]; then
        cp -f "$HOME/.claude.json" "$SANDBOX_DIR/.claude.json"
    else
        echo '{}' > "$SANDBOX_DIR/.claude.json"
    fi

    if [ -d "$HOME/.codex" ]; then
        seed_rsync .codex .codex
        log ".codex"
    fi

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
#   ~/.config/JetBrains       settings, and the licence or JetBrains Account
#                             token -- per sandbox, seeded from the host once so
#                             the IDE comes up already activated.
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

    # Existence is the marker: seeded once, then this sandbox's own. Deliberately
    # not in ai_sandbox_seed_paths -- 'ai-sandbox-account reset' rm -rf's those,
    # and an IDE licence is not an AI account.
    if [ ! -e "$SANDBOX_DIR/jetbrains-config" ]; then
        mkdir -p "$SANDBOX_DIR/jetbrains-config"
        if [ -d "$HOME/.config/JetBrains" ]; then
            seed_rsync .config/JetBrains jetbrains-config
            log "settings and licence seeded from the host, once"
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
    local part cdir vdir name version cur target seeded=0

    mkdir -p "$SDKMAN_FARM/candidates" "$SDKMAN_FARM/etc" \
             "$SDKMAN_FARM/var" "$SDKMAN_FARM/ext" "$SDKMAN_FARM/tmp"

    # Linked, not copied, so a 'sdk selfupdate' on the host reaches every
    # sandbox at once and none of them carries a second copy of libexec.
    for part in bin libexec contrib; do
        [ -d "$HOST_SDKMAN/$part" ] && ln -sfn "$CONTAINER_SDKMAN_HOST/$part" "$SDKMAN_FARM/$part"
    done
    # src is the exception: sdkman-init.sh loads its functions with
    # 'find "$SDKMAN_DIR/src" -type f', and find does not descend into a
    # symlinked starting point (nor match symlinked files). Behind a link, no
    # function was ever defined -- 'sdk' did not exist and the candidates never
    # reached PATH. It is 100 kB, so a real copy, refreshed on every run.
    if [ -d "$HOST_SDKMAN/src" ]; then
        [ -L "$SDKMAN_FARM/src" ] && rm -f "$SDKMAN_FARM/src"
        mkdir -p "$SDKMAN_FARM/src"
        safe_rsync -a --delete "$HOST_SDKMAN/src/" "$SDKMAN_FARM/src/"
    fi

    # Knobs a sandbox may legitimately change: seeded from the host, then its own.
    # '||' rather than 'if' would make a host without etc/config fatal under set -e.
    if [ ! -f "$SDKMAN_FARM/etc/config" ] && [ -f "$HOST_SDKMAN/etc/config" ]; then
        cp -f "$HOST_SDKMAN/etc/config" "$SDKMAN_FARM/etc/config"
    fi
    [ -d "$HOST_SDKMAN/var" ] && safe_rsync -a --ignore-existing \
        "$HOST_SDKMAN/var/" "$SDKMAN_FARM/var/"

    for cdir in "$HOST_SDKMAN/candidates"/*; do
        [ -d "$cdir" ] || continue
        name=${cdir##*/}
        mkdir -p "$SDKMAN_FARM/candidates/$name"

        # One link per version the host has installed.
        for vdir in "$cdir"/*; do
            version=${vdir##*/}
            [ "$version" = current ] && continue        # the default pointer, not a version
            [ -d "$vdir" ] || continue
            ln -sfn "$CONTAINER_SDKMAN_HOST/candidates/$name/$version" \
                    "$SDKMAN_FARM/candidates/$name/$version"
        done

        # Retire links to versions the host has since removed. Symlinks only: a
        # real directory here was installed inside the sandbox and is not ours.
        for vdir in "$SDKMAN_FARM/candidates/$name"/*; do
            version=${vdir##*/}
            [ "$version" = current ] && continue
            [ -L "$vdir" ] || continue
            [ -d "$HOST_SDKMAN/candidates/$name/$version" ] || rm -f "$vdir"
        done

        cur="$SDKMAN_FARM/candidates/$name/current"
        if [ ! -L "$cur" ]; then
            # First sight of this candidate: start from the host's default.
            target=$(readlink "$cdir/current" 2>/dev/null || true)
            if [ -n "$target" ]; then
                ln -sfn "${target##*/}" "$cur"
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
                ln -sfn "${target##*/}" "$cur"
                log "  repointed $name -> ${target##*/} (the host's default)"
            else
                rm -f "$cur"
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
