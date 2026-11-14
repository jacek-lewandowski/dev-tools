#!/usr/bin/env bash
# ai-sandbox-install (C-INSTALL): fetch from the hosting remote or, with --from, from a
# tree a sandbox can write through the confined git; show, ask, export the commit's bytes
# read-only as installed/rev/<commit>, switch installed/current by a rename.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

INSTALL="$REPO_ROOT/bin/ai/ai-sandbox-install"
ROOTS=(bin/ai tools tests/ai-sandbox verify-ai-sandbox-on-host.sh)
REAL_GIT=$(command -v git)
T=$(mktemp -d)

new_home() {   # a fresh HOME with the stub docker, the host's git identity, no prompt
    fake_home >/dev/null
    # no revision installed yet: fake_home's install root is for the tests that need one
    rm -rf "$AI_SANDBOX_ROOT/installed" "$AI_SANDBOX_ROOT/bin"
    git config --global user.email t@example.com; git config --global user.name t
    git config --global init.defaultBranch main
}

# A work tree with the four roots and files outside them; commit() adds one commit.
mkwork() {   # <dir>
    git init -q "$1"
    mkdir -p "$1/bin/ai" "$1/tools/pkg" "$1/tests/ai-sandbox" "$1/docs"
    printf 'lib one\n' > "$1/bin/ai/ai-sandbox-lib.sh"
    printf '#!/bin/sh\necho one\n' > "$1/bin/ai/tool"; chmod 0755 "$1/bin/ai/tool"
    printf 'pkg\n' > "$1/tools/pkg/m.py"
    printf '#!/bin/sh\n' > "$1/tests/ai-sandbox/run-tests.sh"; chmod 0755 "$1/tests/ai-sandbox/run-tests.sh"
    printf '#!/bin/sh\n' > "$1/verify-ai-sandbox-on-host.sh"; chmod 0755 "$1/verify-ai-sandbox-on-host.sh"
    printf 'readme\n' > "$1/README.md"; printf 'doc\n' > "$1/docs/d.md"
}
commit() {   # <dir> <message>
    git -C "$1" add -A && git -C "$1" commit -q --allow-empty -m "$2" && git -C "$1" rev-parse HEAD
}

# run the install; stdin is the answer (default y); out/err in $T
inst() {
    printf '%s' "${ANS-y}" | bash "$INSTALL" "$@" >"$T/out" 2>"$T/err"; echo $?
}
SRC() { printf '%s/installed/src.git' "$AI_SANDBOX_ROOT"; }
tree_sum() {   # <dir>: names, modes and bytes
    (cd "$1" && find . -printf '%m %p\n' | LC_ALL=C sort; find . -type f -exec sha256sum {} + | LC_ALL=C sort)
}
# <gitdir> <commit> <installed dir>: the dir holds exactly the commit's files under the four
# roots, with its bytes and executable bits (0 problems printed).
compare_rev() {
    local gd=$1 c=$2 d=$3 mode type oid path
    diff <(git --git-dir="$gd" ls-tree -r --name-only "$c" -- "${ROOTS[@]}" | LC_ALL=C sort) \
         <(cd "$d" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
    while IFS=$'\t' read -r meta path; do
        read -r mode type oid <<<"$meta"
        cmp -s <(git --git-dir="$gd" cat-file blob "$oid") "$d/$path" || echo "bytes differ: $path"
        if [ "$mode" = 100755 ]; then [ -x "$d/$path" ] || echo "not executable: $path"; else [ ! -x "$d/$path" ] || echo "executable: $path"; fi
    done < <(git --git-dir="$gd" ls-tree -r "$c" -- "${ROOTS[@]}")
}

# ===========================================================================
# O4: the hosting remote
# ===========================================================================
new_home
W="$T/w"; mkwork "$W"
c1=$(commit "$W" "first revision")
printf 'lib two\n' > "$W/bin/ai/ai-sandbox-lib.sh"; printf 'new\n' > "$W/tools/pkg/new.py"
printf 'readme two\n' > "$W/README.md"; printf 'doc two\n' > "$W/docs/d.md"
c2=$(commit "$W" "second revision")
ORIGIN="$T/origin.git"; git clone -q --bare "$W" "$ORIGIN"
INST="$AI_SANDBOX_ROOT/installed"

# no src.git and no --from
rc=$(inst); err=$(cat "$T/err")$(cat "$T/out")
assert_eq "no hosting remote: exit 1" "$rc" 1
assert_eq "src.git was made as a bare repository" "$(git --git-dir="$INST/src.git" rev-parse --is-bare-repository)" true
assert_eq "with no remote" "$(git --git-dir="$INST/src.git" remote)" ""
assert_contains "the whole command that adds the remote is printed, <root> expanded" "$err" \
    "git --git-dir=$INST/src.git remote add origin <url>"
assert_no_file "nothing was switched" "$INST/current"
git --git-dir="$INST/src.git" remote add origin "$ORIGIN"

# first install, by object id
rc=$(inst "$c1")
assert_eq "first install: exit 0" "$rc" 0
assert_eq "installed/rev/<c1> holds exactly the commit's files, bytes and modes" \
    "$(compare_rev "$INST/src.git" "$c1" "$INST/rev/$c1")" ""
assert_eq "nothing in it is writable" "$(find "$INST/rev/$c1" -perm /222 | wc -l | tr -d ' ')" 0
assert_eq "current names the revision" "$(readlink "$INST/current")" "rev/$c1"
assert_eq "~/.ai-sandbox/bin is the link into the install root" "$(readlink "$AI_SANDBOX_ROOT/bin")" "installed/current/bin/ai"
assert_contains "stdout names the commit" "$(cat "$T/out")" "$c1"
assert_eq "and asks once" "$(grep -c 'Install it?' "$T/out")" 1
sum1=$(tree_sum "$INST/rev/$c1")

# declined
rc=$(ANS=n inst "$c2")
assert_eq "declined: exit 1" "$rc" 1
assert_eq "current still names c1" "$(readlink "$INST/current")" "rev/$c1"
assert_no_file "no rev/<c2>" "$INST/rev/$c2"

# an unknown branch
rc=$(inst nope)
assert_eq "an unknown branch name: exit 1" "$rc" 1
assert_contains "names the full ref" "$(cat "$T/err")" "refs/remotes/origin/nope"
assert_eq "current unchanged" "$(readlink "$INST/current")" "rev/$c1"

# no revision: main (c2)
rc=$(inst)
assert_eq "no revision given: exit 0" "$rc" 0
assert_eq "main is installed" "$(readlink "$INST/current")" "rev/$c2"
out=$(cat "$T/out")
assert_contains "the summary lists c2's subject" "$out" "second revision"
assert_contains "and the changed paths under the roots" "$out" "bin/ai/ai-sandbox-lib.sh"
assert_contains "including a new one" "$out" "tools/pkg/new.py"
assert_eq "and no path outside them" "$(printf '%s\n' "$out" | grep -cE 'README.md|docs/d.md')" 0
assert_eq "rev/<c2> holds exactly c2's files" "$(compare_rev "$INST/src.git" "$c2" "$INST/rev/$c2")" ""
assert_eq "rev/<c1> is unchanged" "$(tree_sum "$INST/rev/$c1")" "$sum1"

# the same revision again
rc=$(ANS= inst "$c2")
assert_eq "the same revision again: exit 0" "$rc" 0
assert_contains "says it is installed" "$(cat "$T/out")" "already installed"
assert_eq "and asks nothing" "$(grep -c 'Install it?' "$T/out")" 0

# an origin that cannot be reached
git --git-dir="$INST/src.git" remote set-url origin "$T/nowhere.git"
rc=$(inst "$c1")
assert_eq "an unreachable origin: exit 1" "$rc" 1
assert_eq "current unchanged" "$(readlink "$INST/current")" "rev/$c2"
git --git-dir="$INST/src.git" remote set-url origin "$ORIGIN"

# ===========================================================================
# O7: a partial export left by an interrupted run
# ===========================================================================
new_home; INST="$AI_SANDBOX_ROOT/installed"
git init -q --bare "$INST/src.git"; git --git-dir="$INST/src.git" remote add origin "$ORIGIN"
mkdir -p "$INST/rev/.partial-$c2/bin/ai"; echo junk > "$INST/rev/.partial-$c2/bin/ai/junk"; chmod -R a-w "$INST/rev/.partial-$c2"
rc=$(inst "$c2")
assert_eq "a partial export of the commit is replaced: exit 0" "$rc" 0
assert_eq "and the result is the commit's files" "$(compare_rev "$INST/src.git" "$c2" "$INST/rev/$c2")" ""
assert_no_file "no partial directory is left" "$INST/rev/.partial-$c2"
body=$(sed -n '/^switch_link "rev/,/^$/p;/^switch_link()/,/^}/p' "$INSTALL")
assert_contains "the switch writes a new link beside current and renames it over" "$body" 'mv -T -- "$2.new" "$2"'
assert_eq "no step of the export writes into an existing rev/ directory" \
    "$(grep -c 'rm_tree "\$FINAL"\|> "\$FINAL' "$INSTALL")" 0

# ===========================================================================
# O6: the first install over today's layout
# ===========================================================================
new_home; INST="$AI_SANDBOX_ROOT/installed"
git init -q --bare "$INST/src.git"; git --git-dir="$INST/src.git" remote add origin "$ORIGIN"
mkdir -p "$AI_SANDBOX_ROOT/bin/knowledge-seed"
printf 'old lib\n' > "$AI_SANDBOX_ROOT/bin/ai-sandbox-lib.sh"; printf 'old\n' > "$AI_SANDBOX_ROOT/bin/ai-sandbox"
printf 'seed\n' > "$AI_SANDBOX_ROOT/bin/knowledge-seed/README.md"
old_sum=$(tree_sum "$AI_SANDBOX_ROOT/bin")
BLOCK='# >>> dev-tools ai-sandbox helpers >>>
# Helpers for dev-tools/bin/ai/create-ai-sandbox.sh live in ~/.ai-sandbox/bin.
case ":$PATH:" in
    *":$HOME/.ai-sandbox/bin:"*) ;;
    *) PATH="$HOME/.ai-sandbox/bin:$PATH" ;;
esac
# <<< dev-tools ai-sandbox helpers <<<'
printf 'export A=1\n\n%s\nexport B=2\n' "$BLOCK" > "$HOME/.bashrc"
cp "$HOME/.bashrc" "$T/bashrc.before"
rc=$(inst "$c1")
assert_eq "first install over a directory of copies: exit 0" "$rc" 0
assert_eq "bin.pre-install holds the old files unchanged" "$(tree_sum "$AI_SANDBOX_ROOT/bin.pre-install")" "$old_sum"
assert_eq "~/.ai-sandbox/bin is the link" "$(readlink "$AI_SANDBOX_ROOT/bin")" "installed/current/bin/ai"
assert_contains "stdout names the old directory" "$(cat "$T/out")" "$AI_SANDBOX_ROOT/bin"
assert_contains "and where it went" "$(cat "$T/out")" "$AI_SANDBOX_ROOT/bin.pre-install"
assert_eq "~/.bashrc is byte-identical to before" "$(cmp "$HOME/.bashrc" "$T/bashrc.before" && echo same)" same
rc=$(inst "$c2")
assert_eq "a second install: exit 0" "$rc" 0
assert_eq "leaves bin.pre-install alone" "$(tree_sum "$AI_SANDBOX_ROOT/bin.pre-install")" "$old_sum"
# a HOME with no block gets exactly one, with the base's markers and text
new_home; INST="$AI_SANDBOX_ROOT/installed"
git init -q --bare "$INST/src.git"; git --git-dir="$INST/src.git" remote add origin "$ORIGIN"
printf 'export A=1\n' > "$HOME/.bashrc"
rc=$(inst "$c1")
assert_eq "no block yet: exit 0" "$rc" 0
assert_eq "exactly one block" "$(grep -c '^# >>> dev-tools ai-sandbox helpers >>>$' "$HOME/.bashrc")" 1
assert_eq "with the base's text" "$(sed -n '/^# >>> dev-tools/,/^# <<< dev-tools/p' "$HOME/.bashrc")" "$BLOCK"
assert_contains "and the user's own line kept" "$(cat "$HOME/.bashrc")" "export A=1"

# ===========================================================================
# O13: who still runs another revision
# ===========================================================================
new_home; INST="$AI_SANDBOX_ROOT/installed"
git init -q --bare "$INST/src.git"; git --git-dir="$INST/src.git" remote add origin "$ORIGIN"
mk_sandbox() {   # <name> <tools mount source> <project>
    mkdir -p "$AI_SANDBOX_ROOT/$1"; printf '%s\n' "$3" > "$AI_SANDBOX_ROOT/$1/project-path"
    printf 'services:\n  s:\n    volumes:\n      - "%s:/home/dev/tools:ro"\n' "$2" > "$AI_SANDBOX_ROOT/$1/docker-compose.yml"
}
mk_sandbox up-agent "$AI_SANDBOX_ROOT/installed/current/tools" /work/up
mk_sandbox old-agent "/somewhere/tools" /work/old
mk_sandbox cur-agent "$AI_SANDBOX_ROOT/installed/current/tools" /work/cur
rc=$(DOCKER_STUB_PS=up-agent inst "$c1")
out=$(cat "$T/out")
assert_eq "the install with sandboxes about: exit 0" "$rc" 0
assert_contains "the running sandbox is named" "$out" "up-agent"
assert_contains "with stop and start advice" "$(grep 'up-agent' "$T/out")" "stop and start"
assert_contains "the stopped sandbox of another tools directory is named with its re-create command" "$out" \
    "create-ai-sandbox.sh /work/old"
assert_eq "a stopped current sandbox is not named" "$(grep -c 'cur-agent' "$T/out")" 0

# ===========================================================================
# O5: --from a tree a sandbox can write
# ===========================================================================
new_home; INST="$AI_SANDBOX_ROOT/installed"
S="$T/served"; mkwork "$S"
printf 'ignored\n' > "$S/bin/ai/ex-ignored"; printf 'id=$Format:%%H$\n' > "$S/bin/ai/subst.txt"; printf 'raw filtered\n' > "$S/tools/filtered.txt"
printf 'bin/ai/ex-ignored export-ignore\nbin/ai/subst.txt export-subst\ntools/filtered.txt filter=p4probe\n' > "$S/.gitattributes"
s1=$(commit "$S" "served one")
git -C "$S" tag v1
git -C "$S" branch feat
printf 'feature\n' > "$S/tools/feat.txt"; git -C "$S" checkout -q feat; s2=$(commit "$S" "served feature"); git -C "$S" checkout -q main
git -C "$S" checkout -q -b esc; printf 'e\n' > "$S/tools/e.txt"
s3=$(commit "$S" "$(printf 'escape \033[31mred\033[0m and\ttab')"); git -C "$S" checkout -q main
# a replace ref the served tree could use to change what a commit holds
git -C "$S" update-ref "refs/replace/$s1" "$s2"
sg() { GIT_NO_REPLACE_OBJECTS=1 git -C "$S" "$@"; }
mkdir -p "$AI_SANDBOX_ROOT/p-agent"; printf '%s\n' "$S" > "$AI_SANDBOX_ROOT/p-agent/project-path"
rec="$T/rec"; mkdir -p "$rec"; GITLOG="$T/git.log"; export GITLOG; : > "$GITLOG"
printf '#!/bin/sh\nprintf "%%s|%%s\\n" "$PWD" "$*" >> "$GITLOG"\nexec %s "$@"\n' "$REAL_GIT" > "$rec/git"; chmod +x "$rec/git"
git config --global filter.p4probe.smudge "touch $T/marker; cat"
img=$(ai_sandbox_image_name base)
id=$(ai_sandbox_project_id "$(readlink -f "$S")")
frominst() { PATH="$rec:$PATH" DOCKER_STUB_IMAGES="${IMAGES-$img}" inst --from "$S" "$@"; }

rc=$(frominst main)
assert_eq "--from, a branch name: exit 0" "$rc" 0
assert_eq "git never ran with its working directory in the served tree (the container's upload-pack aside)" \
    "$(grep "^$S[|/]" "$GITLOG" | grep -vc '|upload-pack ')" 0
assert_eq "src.git holds, of the served tree, only refs/from/<id>/heads/*" \
    "$(git --git-dir="$INST/src.git" for-each-ref --format='%(refname)' | grep -vc "^refs/from/$id/heads/")" 0
assert_eq "no served tag" "$(git --git-dir="$INST/src.git" for-each-ref refs/tags "refs/from/$id/tags" | wc -l | tr -d ' ')" 0
assert_eq "no served replace ref" "$(git --git-dir="$INST/src.git" for-each-ref refs/replace | wc -l | tr -d ' ')" 0
assert_eq "the branch name resolved to refs/from/<id>/heads/main" "$(git --git-dir="$INST/src.git" rev-parse "refs/from/$id/heads/main")" "$s1"
assert_eq "and installed that commit" "$(readlink "$INST/current")" "rev/$s1"
# attributes: all three files hold the commit's bytes, and the smudge filter did not run
for f in bin/ai/ex-ignored bin/ai/subst.txt tools/filtered.txt; do
    assert_eq "$f has the commit's bytes" "$(cmp "$INST/rev/$s1/$f" <(sg cat-file blob "$s1:$f") && echo same)" same
done
assert_no_file "the filter did not run" "$T/marker"
# known case for the method: git archive of the same commit applies the attributes
ar="$T/ar"; mkdir -p "$ar"; sg archive "$s1" | tar -x -C "$ar"
assert_ne "git archive expands export-subst" "$(cat "$ar/bin/ai/subst.txt")" "$(sg cat-file blob "$s1:bin/ai/subst.txt")"
assert_no_file "and omits the export-ignore file" "$ar/bin/ai/ex-ignored"
# a full object id of a served branch's commit
rc=$(frominst "$s2")
assert_eq "--from, a full object id of a served branch: exit 0" "$rc" 0
assert_eq "installs that commit" "$(readlink "$INST/current")" "rev/$s2"
# an escape character in a subject
rc=$(frominst esc)
out=$(cat "$T/out")
assert_contains "the summary shows the subject's text" "$out" "red"
assert_eq "no byte below 0x20 other than newline and tab reaches stdout" "$(printf '%s' "$out" | LC_ALL=C grep -c $'[\001-\010\013-\037]')" 0
assert_eq "the escape subject installed" "$(readlink "$INST/current")" "rev/$s3"
# no sandbox image
cur=$(readlink "$INST/current")
rc=$(IMAGES="" frominst main)
assert_eq "no sandbox image: exit 125" "$rc" 125
assert_eq "current unchanged" "$(readlink "$INST/current")" "$cur"

rm -rf "$T"
finish
