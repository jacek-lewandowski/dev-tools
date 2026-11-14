#!/usr/bin/env bash
# bin/ai/MANIFEST: the list of what the host runs, sources, copies into the image's build
# context and mounts. The check below reads the toolchain's own text and reports every
# path the manifest does not cover, so a change that adds a source, a copy or an entry
# point enumerates itself: the test fails until the manifest line is in the same commit.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

# The manifest roots a copy of the tree needs for the check: everything a line can name.
copy_tree() {   # <destination>
    mkdir -p "$1/tests/ai-sandbox"
    cp -a "$REPO_ROOT/bin" "$REPO_ROOT/tools" "$REPO_ROOT/verify-ai-sandbox-on-host.sh" "$1/"
    cp -a "$REPO_ROOT/tests/ai-sandbox/run-tests.sh" "$1/tests/ai-sandbox/"
    chmod -R u+w "$1"
}

# manifest_covered <root> <kind|any> <path>: 0 when a line of the manifest covers <path>
# (equal, or a directory line, ending in '/', above it) under <kind>.
manifest_covered() {
    local root=$1 kind=$2 path=$3 k p
    while read -r k p; do
        case $k in ''|'#'*) continue ;; esac
        [ "$kind" = any ] || [ "$k" = "$kind" ] || continue
        case $p in */) case $path in "$p"*) return 0 ;; esac ;; *) [ "$p" = "$path" ] && return 0 ;; esac
    done < "$root/bin/ai/MANIFEST"
    return 1
}

# The self-location forms in use, each with the directory it names, relative to the root.
# A path expression that starts with none of them cannot be resolved here.
# $AI_SANDBOX_ROOT is host state, not the tree: not checked.
FORM_DIRNAME='$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/'

# resolve_expr <file, relative to the root> <text after the command word>:
# prints the tree path of the first quoted expression, or "-" (host state, not checked),
# or "?" (unresolvable); nothing when the text holds no quoted expression.
resolve_expr() {
    local file=$1 rest=$2 base suffix
    case $rest in
        '"$SCRIPT_DIR/'*)  base=bin/ai/;                rest=${rest#'"$SCRIPT_DIR/'} ;;
        '"$HERE/'*)        base=bin/ai/;                rest=${rest#'"$HERE/'} ;;
        '"'"$FORM_DIRNAME"*) base=${file%/*}/;          rest=${rest#'"'"$FORM_DIRNAME"} ;;
        '"$self/'*)        base=${file%/*}/;            rest=${rest#'"$self/'} ;;   # context-statusline, handover-ready
        # the lib's install-root constant: a path of the installed revision, named from the tree
        '"$AI_SANDBOX_INSTALLED/current/'*)   base=;    rest=${rest#'"$AI_SANDBOX_INSTALLED/current/'} ;;
        '"${AI_SANDBOX_INSTALLED}/current/'*) base=;    rest=${rest#'"${AI_SANDBOX_INSTALLED}/current/'} ;;
        '"$AI_SANDBOX_ROOT/'*) echo -; return ;;
        '"'*) echo '?'; return ;;
        *) return ;;
    esac
    suffix=${rest%%\"*}
    case $suffix in *'$'*|*'`'*) echo '?'; return ;; esac
    printf '%s%s\n' "$base" "$suffix"
}

# manifest_report <root>: one line per problem, "<file>:<line>: <message>".
manifest_report() {
    local root=$1 file line n text cmd rest res k p
    # a manifest line names a kind and a path that exists
    n=0
    while IFS= read -r text || [ -n "$text" ]; do
        n=$((n + 1))
        case $text in ''|'#'*) continue ;; esac
        read -r k p <<<"$text"
        case $k in entry|source|image|mount) ;; *) echo "bin/ai/MANIFEST:$n: unknown kind '$k'"; continue ;; esac
        [ -n "$p" ] || { echo "bin/ai/MANIFEST:$n: no path"; continue; }
        [ -e "$root/$p" ] || echo "bin/ai/MANIFEST:$n: $p does not exist"
    done < "$root/bin/ai/MANIFEST"
    # the host programs: bin/ai outside the in-image files and the seed
    while IFS= read -r file; do
        n=0
        while IFS= read -r text || [ -n "$text" ]; do
            n=$((n + 1))
            line=${text#"${text%%[![:space:]]*}"}
            case $line in '#'*|'') continue ;; esac
            cmd=''; rest=''
            case $line in
                '. '*)       cmd=source; rest=${line#. } ;;
                'source '*)  cmd=source; rest=${line#source } ;;
                'cat '*)     cmd=copy;   rest=${line#cat } ;;
                'cp '*)      cmd=copy;   rest=${line#cp } ;;
                'install '*) cmd=install; rest=${line#install } ;;
            esac
            if [ -z "$cmd" ] && [[ $line =~ ^-[[:space:]]+(\"[^\":]*): ]]; then
                # a mount source of the compose writer: only those named from the tree are checked
                rest="${BASH_REMATCH[1]}\""
                case $rest in
                    '"$SCRIPT_DIR/'*|'"${SCRIPT_DIR}/'*|'"$HERE/'*|'"$AI_SANDBOX_INSTALLED/'*|'"${AI_SANDBOX_INSTALLED}/'*) cmd=mount ;;
                esac
                rest=${rest//'${SCRIPT_DIR}'/'$SCRIPT_DIR'}
            fi
            [ -n "$cmd" ] || continue
            if [ "$cmd" = install ]; then
                # install [-m MODE] <source> ...: the source is the first quoted word
                rest=${rest#-m * }
                case $rest in '"$SCRIPT_DIR/'*|'"$HERE/'*|'"'"$FORM_DIRNAME"*) ;; *) continue ;; esac
            fi
            if [ "$cmd" = copy ]; then
                # only a copy of a file named from the tree
                case $rest in '"$SCRIPT_DIR/'*) ;; *) continue ;; esac
            fi
            res=$(resolve_expr "$file" "$rest")
            case $res in
                '') continue ;;
                -)  continue ;;
                '?') [ "$cmd" = install ] && continue   # a list-driven install names no literal path
                     echo "$file:$n: cannot resolve the path of '$line'"; continue ;;
            esac
            case $cmd in
                mount)   manifest_covered "$root" mount "$res/" || echo "$file:$n: $res/ is mounted into the sandbox and not listed as mount" ;;
                source)  manifest_covered "$root" source "$res" || echo "$file:$n: $res is sourced and not listed as source" ;;
                copy)    manifest_covered "$root" image "$res"  || echo "$file:$n: $res is copied into the build context and not listed as image" ;;
                install) manifest_covered "$root" any "$res"    || echo "$file:$n: $res is installed and not listed" ;;
            esac
        done < "$root/$file"
    done < <(cd "$root" && find bin/ai -type f ! -path 'bin/ai/image/*' ! -path 'bin/ai/knowledge-seed/*' ! -name MANIFEST | LC_ALL=C sort)
}

# --- the manifest of the tree
assert_file "the manifest exists" "$REPO_ROOT/bin/ai/MANIFEST"
expect_entries='bin/ai/create-ai-sandbox.sh
bin/ai/ai-sandbox
bin/ai/ai-sandbox-account
bin/ai/ai-sandbox-attach
bin/ai/ai-sandbox-extensions
bin/ai/ai-sandbox-gc
bin/ai/ai-sandbox-install
bin/ai/ai-sandbox-migrate
bin/ai/ai-sandbox-restart
bin/ai/ai-sandbox-rm
bin/ai/ai-sandbox-stop
bin/ai/ai-knowledge
bin/ai/context-statusline
bin/ai/handover-ready
bin/ai/update-antigravity-ide.sh
tests/ai-sandbox/run-tests.sh
verify-ai-sandbox-on-host.sh'
got_entries=$(awk '$1 == "entry" {print $2}' "$REPO_ROOT/bin/ai/MANIFEST")
assert_eq "the entry lines are the host programs of bin/ai but ai-sync, the install among them" \
    "$(printf '%s\n' "$got_entries" | LC_ALL=C sort)" \
    "$(printf '%s\n' "$expect_entries" | LC_ALL=C sort)"
assert_eq "every entry is an executable file" \
    "$(printf '%s\n' "$got_entries" | while IFS= read -r e; do [ -f "$REPO_ROOT/$e" ] && [ -x "$REPO_ROOT/$e" ] || echo "$e"; done)" ""

# --- the unchanged tree: no report
t="$(mktemp -d)"
copy_tree "$t/tree"
assert_eq "the tree is covered by its manifest" "$(manifest_report "$t/tree")" ""

# --- known cases: each planted in a copy, each reported with file and line
plant() {   # <name> <file> <line to append>  -> prints the report of the planted copy
    rm -rf "$t/p"; copy_tree "$t/p"
    printf '%s\n' "$3" >> "$t/p/$2"
    manifest_report "$t/p"
}
r=$(plant source bin/ai/ai-sandbox-stop '. "$SCRIPT_DIR/unlisted.sh"')
assert_contains "a sourced file the manifest does not list is reported" "$r" 'bin/ai/ai-sandbox-stop:'
assert_contains "and named" "$r" 'bin/ai/unlisted.sh is sourced and not listed as source'
r=$(plant image bin/ai/create.d/image.sh 'cat "$SCRIPT_DIR/image/unlisted-file" > "$BUILD_DIR/unlisted-file"')
assert_contains "a copy of an unlisted image file into the build context is reported" "$r" \
    'bin/ai/create.d/image.sh:'
assert_contains "and named" "$r" 'bin/ai/image/unlisted-file is copied into the build context and not listed as image'
r=$(plant install bin/ai/ai-sandbox-stop 'install -m 0755 "$SCRIPT_DIR/unlisted" "$AI_SANDBOX_ROOT/bin/unlisted"')
assert_contains "an install of an unlisted file is reported" "$r" 'bin/ai/unlisted is installed and not listed'
r=$(plant unresolvable bin/ai/ai-sandbox-stop '. "$SOMEDIR/x.sh"')
assert_contains "a sourced path the check cannot resolve is reported" "$r" 'cannot resolve the path of'
rm -rf "$t/p"; copy_tree "$t/p"
printf 'source bin/ai/does-not-exist.sh\n' >> "$t/p/bin/ai/MANIFEST"
r=$(manifest_report "$t/p")
assert_contains "a manifest line naming a missing file is reported with its line" "$r" \
    "bin/ai/MANIFEST:$(wc -l < "$t/p/bin/ai/MANIFEST"): bin/ai/does-not-exist.sh does not exist"
rm -rf "$t/p"; copy_tree "$t/p"
grep -v '^mount tools/$' "$REPO_ROOT/bin/ai/MANIFEST" > "$t/p/bin/ai/MANIFEST"
r=$(manifest_report "$t/p")
assert_contains "the mount line removed: the compose writer's tools mount is reported" "$r" \
    'bin/ai/create.d/compose.sh:'
assert_contains "and named" "$r" 'tools/ is mounted into the sandbox and not listed as mount'
rm -rf "$t"

finish
