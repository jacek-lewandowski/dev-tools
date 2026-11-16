#!/usr/bin/env bash
# I3c, the no-follow function (O7): a host write below a directory a sandbox can write never
# follows a link a sandbox placed there. Every case plants a link into a trap, a directory
# outside the root, and compares the trap before and after.
set -uo pipefail
here=${BASH_SOURCE[0]%/*}
. "$here/harness.sh"
fake_home >/dev/null; w="$FAKE_HOME_DIR/w"; mkdir -p "$w"
. "$REPO_ROOT/bin/ai/ai-sandbox-lib.sh"

nf() { ai_sandbox_nofollow "$@"; }
root="$w/root"; trap_="$w/trap"; src="$w/src"
reset() {   # a fresh root, a trap holding a file, a directory with a file and a stale entry, and a source
    rm -rf "$root" "$trap_" "$src"
    mkdir -p "$root/a/b" "$trap_/b" "$trap_/sub" "$src"
    printf 'secret' > "$trap_/secret"; printf 'inner' > "$trap_/b/inner"; printf 'x' > "$trap_/sub/file"
    printf 'from-src' > "$src/file"
}
# listing with types, modes and link targets, then every file's hash: equal text, equal trap
snap() {   # <dir>
    (cd "$1" && find . -printf '%p|%y|%m|%l\n' | LC_ALL=C sort; find . -type f -exec sha256sum {} + | LC_ALL=C sort)
}
rcof() { "$@" >"$w/out" 2>"$w/err" </dev/null; echo $?; }   # status, output kept in $w/out and $w/err
nlines() { grep -c . "$1"; }

# --- normal cases create what they say
reset
assert_eq "mkdir makes every missing component" "$(rcof nf mkdir "$root" x/y/z)" 0
assert_eq "and they are directories" "$([ -d "$root/x/y/z" ] && echo yes)" yes
assert_eq "mkdir on an existing directory is fine" "$(rcof nf mkdir "$root" x/y/z)" 0
printf 'hello\n' | nf write "$root" a/b/f; assert_eq "write holds standard input" "$(cat "$root/a/b/f")" hello
printf 'again' | nf write "$root" a/b/f; assert_eq "write replaces the file" "$(cat "$root/a/b/f")" again
printf 'sec' | nf write "$root" a/b/m 600; assert_eq "write with a mode" "$(stat -c %a "$root/a/b/m")" 600
assert_eq "link makes a symbolic link" "$(nf link "$root" a/l ../T; readlink "$root/a/l")" ../T
nf link "$root" a/l ../U; assert_eq "link replaces it" "$(readlink "$root/a/l")" ../U
assert_eq "hardlink makes a second name of the file" "$(nf hardlink "$root" a/h "$src/file"; stat -c %i "$root/a/h")" "$(stat -c %i "$src/file")"
assert_eq "hardlink again over its own name still succeeds" "$(rcof nf hardlink "$root" a/h "$src/file")" 0
assert_eq "and leaves no temporary name" "$(ls -A "$root/a" | grep -c 'ai-sandbox-nofollow')" 0
ln -s nowhere "$src/dangling"
nf hardlink "$root" a/hd "$src/dangling"; assert_eq "hardlink of a link is a link, never followed" "$([ -L "$root/a/hd" ] && readlink "$root/a/hd")" nowhere
assert_eq "remove removes a file" "$(nf remove "$root" a/h; [ -e "$root/a/h" ] && echo there || echo gone)" gone
assert_eq "remove of an absent name exits 0" "$(rcof nf remove "$root" a/nothing)" 0
assert_eq "remove below an absent directory exits 0" "$(rcof nf remove "$root" nodir/nothing)" 0
assert_eq "write below an absent directory exits 1" "$(rcof nf write "$root" nodir/f)" 1

# --- O7 a: a link into the trap at the last and at each intermediate component, for every op
trapsnap=""
plant() {   # <position>: a | ab | c
    reset
    case $1 in
        a)  rm -rf "$root/a"; ln -s "$trap_" "$root/a" ;;
        ab) rm -rf "$root/a/b"; ln -s "$trap_" "$root/a/b" ;;
        c)  ln -s "$trap_" "$root/a/b/c" ;;
    esac
    trapsnap=$(snap "$trap_")
}
runop() {   # <op>: runs it on a/b/c
    case $1 in
        mkdir)    nf mkdir "$root" a/b/c ;;
        write)    printf 'data' | nf write "$root" a/b/c ;;
        link)     nf link "$root" a/b/c TARGET ;;
        hardlink) nf hardlink "$root" a/b/c "$src/file" ;;
        remove)   nf remove "$root" a/b/c ;;
        copy)     nf copy "$root" a/b/c "$src" ;;
    esac
}
for op in mkdir write link hardlink remove copy; do
    for pos in a ab; do
        plant "$pos"
        runop "$op" >"$w/out" 2>"$w/err" </dev/null; rc=$?
        assert_eq "O7 a: $op through a link at $pos: exit 1" "$rc" 1
        assert_eq "O7 a: $op through a link at $pos: the trap is unchanged" "$(snap "$trap_")" "$trapsnap"
        assert_eq "O7 a: $op through a link at $pos: one line on stderr" "$(nlines "$w/err")" 1
        assert_contains "O7 a: $op through a link at $pos: it names root and path" "$(cat "$w/err")" "$root"
        linked=a; [ "$pos" = ab ] && linked=a/b
        assert_contains "O7 a: $op through a link at $pos: it names the path" "$(cat "$w/err")" "$root $linked"
    done
    plant c
    runop "$op" >"$w/out" 2>"$w/err" </dev/null; rc=$?
    assert_eq "O7 a: $op with a link at the last component: the trap is unchanged" "$(snap "$trap_")" "$trapsnap"
    case $op in
        mkdir)    assert_eq "O7 a: mkdir at a link: exit 1" "$rc" 1
                  assert_eq "O7 a: and the link stays" "$([ -L "$root/a/b/c" ] && echo yes)" yes ;;
        write)    assert_eq "O7 a: write replaces the link: exit 0" "$rc" 0
                  assert_eq "O7 a: with a regular file holding the input" "$([ -f "$root/a/b/c" ] && [ ! -L "$root/a/b/c" ] && cat "$root/a/b/c")" data ;;
        link)     assert_eq "O7 a: link replaces the link: exit 0" "$rc" 0
                  assert_eq "O7 a: with a link to the target" "$(readlink "$root/a/b/c")" TARGET ;;
        hardlink) assert_eq "O7 a: hardlink replaces the link: exit 0" "$rc" 0
                  assert_eq "O7 a: with the given file's inode" "$(stat -c %i "$root/a/b/c")" "$(stat -c %i "$src/file")" ;;
        remove)   assert_eq "O7 a: remove removes the link: exit 0" "$rc" 0
                  assert_eq "O7 a: it is gone" "$([ -e "$root/a/b/c" ] || [ -L "$root/a/b/c" ] || echo gone)" gone ;;
        copy)     assert_eq "O7 a: copy replaces the link: exit 0" "$rc" 0
                  assert_eq "O7 a: with a directory holding the source's file" "$([ ! -L "$root/a/b/c" ] && cat "$root/a/b/c/file")" from-src ;;
    esac
done

# --- O7 b: a real directory with a file at the last component is refused and untouched
reset; mkdir -p "$root/a/b/c"; printf 'keep' > "$root/a/b/c/f"; before=$(snap "$root/a/b/c")
for op in write link hardlink remove; do
    runop "$op" >"$w/out" 2>"$w/err" </dev/null; rc=$?
    assert_eq "O7 b: $op over a real directory: exit 1" "$rc" 1
    assert_eq "O7 b: $op over a real directory: directory and file byte-identical" "$(snap "$root/a/b/c")" "$before"
done

# --- the contract: a real directory inside a copy where the source holds a file is replaced only by --delete
reset; mkdir -p "$root/dst/f"; printf 'keep' > "$root/dst/f/x"; printf 'top' > "$src/f"; before=$(snap "$root/dst/f")
assert_eq "copy over a real directory at a file name: exit 1" "$(rcof nf copy "$root" dst "$src")" 1
assert_eq "copy over a real directory at a file name: directory and file byte-identical" "$(snap "$root/dst/f")" "$before"
assert_eq "copy --ignore-existing leaves it: exit 0" "$(rcof nf copy "$root" dst "$src" --ignore-existing)" 0
assert_eq "copy --ignore-existing leaves it: byte-identical" "$(snap "$root/dst/f")" "$before"
assert_eq "copy --delete replaces it: exit 0" "$(rcof nf copy "$root" dst "$src" --delete)" 0
assert_eq "copy --delete replaces it: by the file" "$([ -f "$root/dst/f" ] && cat "$root/dst/f")" top

# --- O7 c: copy with a link into the trap inside the destination tree
cplant() {
    reset; mkdir -p "$src/d" "$root/dst"
    printf 'sd' > "$src/d/f"; printf 'top' > "$src/f"
    ln -s "$trap_" "$root/dst/d"; ln -s "$trap_" "$root/dst/f"
    trapsnap=$(snap "$trap_")
}
for opt in "" --delete --ignore-existing; do
    cplant
    nf copy "$root" dst "$src" $opt >"$w/out" 2>"$w/err"; rc=$?
    assert_eq "O7 c [$opt]: exit 0" "$rc" 0
    assert_eq "O7 c [$opt]: the trap is unchanged" "$(snap "$trap_")" "$trapsnap"
    if [ "$opt" = --ignore-existing ]; then
        assert_eq "O7 c [$opt]: the directory-named link is left" "$([ -L "$root/dst/d" ] && echo yes)" yes
        assert_eq "O7 c [$opt]: the file-named link is left" "$([ -L "$root/dst/f" ] && echo yes)" yes
    else
        assert_eq "O7 c [$opt]: the link at a directory name is replaced by the directory" "$([ ! -L "$root/dst/d" ] && cat "$root/dst/d/f")" sd
        assert_eq "O7 c [$opt]: the link at a file name is replaced by the file" "$([ ! -L "$root/dst/f" ] && [ -f "$root/dst/f" ] && cat "$root/dst/f")" top
    fi
done

# --- O7 d: the mount points survive a refresh-shaped copy
reset; mkdir -p "$src/keepdir" "$root/dst/projects/k" "$root/dst/stale-dir/deep" "$root/dst/Safe Browsing" "$root/dst/Code Cache"
printf 'new' > "$src/keepdir/n"; printf 'mine' > "$root/dst/projects/k/f"; printf 'old' > "$root/dst/stale-file"
printf 'old' > "$root/dst/stale-dir/deep/x"; printf 'sb' > "$root/dst/Safe Browsing/s"; printf 'cc' > "$root/dst/Code Cache/c"
proj_before=$(snap "$root/dst/projects")
assert_eq "O7 d: the copy succeeds" "$(rcof nf copy "$root" dst "$src" --delete --exclude=projects '--exclude=*Cache*' '--exclude=Safe Browsing')" 0
assert_eq "O7 d: projects/ and its file are byte-identical" "$(snap "$root/dst/projects")" "$proj_before"
assert_eq "O7 d: the stale file is gone" "$([ -e "$root/dst/stale-file" ] || echo gone)" gone
assert_eq "O7 d: the stale directory is gone" "$([ -e "$root/dst/stale-dir" ] || echo gone)" gone
assert_eq "O7 d: excluded names stay: Safe Browsing" "$(cat "$root/dst/Safe Browsing/s")" sb
assert_eq "O7 d: excluded names stay: Code Cache" "$(cat "$root/dst/Code Cache/c")" cc
assert_eq "O7 d: the source's entries arrive" "$(cat "$root/dst/keepdir/n")" new

# --- O7 d (L1): an excluded entry inside a stale directory survives, the directory stays holding only it
reset; mkdir -p "$root/dst/stale/Cache" "$root/dst/stale/gone" "$src/keep"; printf c > "$root/dst/stale/Cache/c"; printf g > "$root/dst/stale/gone/g"; printf s > "$root/dst/stale/f"
assert_eq "O7 d L1: the copy succeeds" "$(rcof nf copy "$root" dst "$src" --delete '--exclude=*Cache*')" 0
assert_eq "O7 d L1: the excluded entry inside the stale directory stays" "$(cat "$root/dst/stale/Cache/c")" c
assert_eq "O7 d L1: the rest of the stale directory is gone" "$(ls "$root/dst/stale")" Cache

# --- O7 e: the matching is on the entry's own name, at any depth, case-sensitive, split nowhere
reset; mkdir -p "$src/GPUCache" "$src/x/y/GPUCache" "$src/Code Cache" "$src/Safe Browsing" "$src/gpucache" "$src/x/ok"
for d in GPUCache x/y/GPUCache "Code Cache" "Safe Browsing" gpucache x/ok; do printf 'v' > "$src/$d/f"; done
nf copy "$root" dst "$src" --delete '--exclude=*Cache*' '--exclude=Safe Browsing' >/dev/null 2>&1
for d in GPUCache x/y/GPUCache "Code Cache" "Safe Browsing"; do
    assert_eq "O7 e: '$d' is not copied" "$([ -e "$root/dst/$d" ] || echo absent)" absent
done
assert_eq "O7 e: gpucache (another case) is copied" "$(cat "$root/dst/gpucache/f")" v
assert_eq "O7 e: a sibling of a matched name at depth is copied" "$(cat "$root/dst/x/ok/f")" v

# --- O7 f: what is kept
reset; mkdir -p "$src/dir"; printf 'e' > "$src/exec"; chmod 755 "$src/exec"; printf 's' > "$src/priv"; chmod 600 "$src/priv"
ln -s ../x "$src/l"; touch -d '2020-01-02 03:04:05' "$src/exec" "$src/priv"; printf 'i' > "$src/dir/i"; touch -d '2019-05-06 07:08:09' "$src/dir/i"
touch -d '2018-01-01 00:00:00' "$src/dir"; chmod 750 "$src/dir"
nf copy "$root" dst "$src" >/dev/null 2>&1
assert_eq "O7 f: 0755 and its time" "$(stat -c '%a %Y' "$root/dst/exec")" "$(stat -c '%a %Y' "$src/exec")"
assert_eq "O7 f: 0600 and its time" "$(stat -c '%a %Y' "$root/dst/priv")" "$(stat -c '%a %Y' "$src/priv")"
assert_eq "O7 f: a nested file's time" "$(stat -c '%Y' "$root/dst/dir/i")" "$(stat -c '%Y' "$src/dir/i")"
assert_eq "O7 f: a directory's mode and time" "$(stat -c '%a %Y' "$root/dst/dir")" "$(stat -c '%a %Y' "$src/dir")"
assert_eq "O7 f: the dangling link arrives as a link with the same text" "$([ -L "$root/dst/l" ] && readlink "$root/dst/l")" ../x
mkfifo "$src/fifo"; nf copy "$root" dst2 "$src" >/dev/null 2>&1
assert_eq "O7 f: any other kind of entry is skipped" "$([ -e "$root/dst2/fifo" ] || echo skipped)" skipped

# --- O7 g: --ignore-existing, and the default
reset; mkdir -p "$src/d" "$root/dst/d"; printf 'new' > "$src/file"; printf 'new' > "$src/missing"; printf 'newd' > "$src/d/arrives"; printf 'old' > "$root/dst/file"; printf 'keep' > "$root/dst/d/there"
printf 'newd' > "$src/d/there"
nf copy "$root" dst "$src" --ignore-existing >/dev/null 2>&1
assert_eq "O7 g: an existing file keeps its content" "$(cat "$root/dst/file")" old
assert_eq "O7 g: a missing file arrives" "$(cat "$root/dst/missing")" new
assert_eq "O7 g: an existing directory is entered, its missing file arrives" "$(cat "$root/dst/d/arrives")" newd
assert_eq "O7 g: and its existing file keeps its content" "$(cat "$root/dst/d/there")" keep
printf 'extra' > "$root/dst/extra"
nf copy "$root" dst "$src" >/dev/null 2>&1
assert_eq "O7 g (no option): an existing file is replaced" "$(cat "$root/dst/file")" new
assert_eq "O7 g (no option): a destination file the source lacks is kept" "$(cat "$root/dst/extra")" extra
assert_eq "O7 g (no option): a nested existing file is replaced" "$(cat "$root/dst/d/there")" newd

# --- O7 h: mkdir with a mode
reset; mkdir -m 755 "$root/m"
nf mkdir "$root" m 700; assert_eq "O7 h: an existing 0755 directory becomes 0700" "$(stat -c %a "$root/m")" 700
nf mkdir "$root" n/o 700; assert_eq "O7 h: a missing one is made 0700" "$(stat -c %a "$root/n/o")" 700

# --- O7 i: the root and the arguments
reset; ln -s "$root" "$w/rootlink"
assert_eq "O7 i: a root that is a link: exit 1" "$(rcof nf mkdir "$w/rootlink" x)" 1
assert_eq "O7 i: a root that is not a directory: exit 1" "$(rcof nf mkdir "$root/a/nothing" x)" 1
assert_eq "O7 i: an absolute path: exit 2" "$(rcof nf mkdir "$root" /x)" 2
assert_eq "O7 i: an empty path: exit 2" "$(rcof nf mkdir "$root" '')" 2
assert_eq "O7 i: an empty component: exit 2" "$(rcof nf mkdir "$root" a//b)" 2
assert_eq "O7 i: a . component: exit 2" "$(rcof nf mkdir "$root" a/./b)" 2
assert_eq "O7 i: a .. component: exit 2" "$(rcof nf mkdir "$root" a/../b)" 2
assert_eq "O7 i: a relative root: exit 2" "$(rcof nf mkdir rel x)" 2
assert_eq "O7 i: copy with both options: exit 2" "$(rcof nf copy "$root" x "$src" --delete --ignore-existing)" 2
assert_eq "O7 i: an --exclude holding a slash: exit 2" "$(rcof nf copy "$root" x "$src" --delete --exclude=a/b)" 2
assert_eq "O7 i: another option of copy: exit 2" "$(rcof nf copy "$root" x "$src" --force)" 2
assert_eq "O7 i: an unknown op: exit 2" "$(rcof nf chmod "$root" x)" 2
assert_eq "O7 i: a missing argument: exit 2" "$(rcof nf link "$root" x)" 2
assert_eq "O7 i: nothing was made by the refused calls" "$(ls "$root")" a

finish
