#!/usr/bin/env bash
# pin-artefacts.sh <tree> <out>
#
# Runs <tree>'s create-ai-sandbox.sh with <tree>'s own test stubs for each case K1..K32 of
# the phase 3 pin matrix and writes <out>/manifest: per case and run, the exit status, the
# output streams, the stub docker log, and every path the run left under the root.
# PIN_CASES="K5 K15" limits a run to those cases (method checks).
# Two manifests are comparable only when taken at the same fixed work path (the project id
# hashes the absolute path), so the work path is fixed here; run under the suite lock.
#
# Per case, run 1 records stdout and stderr separately plus the footprint; run 2 records
# the one combined stream (2>&1), which pins their interleaving.
# Named non-deterministic values, replaced by placeholders:
#   N1 the content of <sandbox dir>/.seeded
#   N2 the first field (the time) of line 1 of <sandbox dir>/status/knowledge
#   N3 the time in the stdout line "already seeded on <time>"
#   N4 the timestamp in the name of ai-knowledge's backup GEMINI.md.pre-ai-knowledge.<ts> (found by T01, K9)
set -uo pipefail

[ $# -eq 2 ] || { echo "usage: $0 <tree> <out>" >&2; exit 2; }
TREE=$(cd "$1" && pwd -P) || exit 2
mkdir -p "$2" && OUT=$(cd "$2" && pwd -P) || exit 2

WORK=/tmp/claude-1000/pin-work          # fixed: the same for every tree compared
R=$WORK/x                               # the root of one case
H=$R/home
PROJ=$R/work/p
NT=$WORK/tree-notools
ST=$TREE/tests/ai-sandbox/stub
TD=$WORK/bin-td                         # a failing timedatectl
XS=$WORK/xstub                          # display stubs
NR=$WORK/bin-norsync                    # the stub directory without rsync
BC=$WORK/bin-badcompose                 # a docker that fails 'compose version'
BASEPATH=$TD:$ST:/usr/bin:/bin
DISPPATH=$TD:$ST:$XS:/usr/bin:/bin
UIDN=$(id -u)
IMG_BASE=ai-sandbox:base-u$UIDN
IMG_DOCKER=ai-sandbox:docker-u$UIDN
MANIFEST=$OUT/manifest

# ---------------------------------------------------------------- fixtures outside the root
rm -rf "$WORK"; mkdir -p "$WORK" "$TD" "$XS" "$NR" "$BC" "$WORK/etc"
printf '#!/bin/sh\nexit 1\n' > "$TD/timedatectl"
for t in xpra Xvfb Xephyr xauth; do printf '#!/bin/sh\nexit 0\n' > "$XS/$t"; done
printf '#!/bin/sh\necho 0123456789abcdef0123456789abcdef\n' > "$XS/mcookie"
printf 'Etc/UTC\n' > "$WORK/etc/timezone"
for f in "$ST"/*; do ln -sf "$f" "$NR/"; done; rm -f "$NR/rsync"; ln -sf "$TD/timedatectl" "$NR/timedatectl"
printf '#!/bin/bash\n[ "$1 $2" = "compose version" ] && exit 1\nexec %s/docker "$@"\n' "$ST" > "$BC/docker"
chmod +x "$TD/timedatectl" "$XS"/* "$BC/docker"
mkdir -p "$NT" && (cd "$TREE" && tar --exclude=./.git --exclude=./tools -cf - .) | (cd "$NT" && tar -xf -)

# ---------------------------------------------------------------- helpers
norm() {   # path placeholders, then N3 and N4
    sed -e "s|$NT|<NT>|g" -e "s|$TREE|<TREE>|g" -e "s|$WORK|<WORK>|g" \
        -e 's/\(already seeded on \).*/\1<N3>/' -e 's/\.pre-ai-knowledge\.[0-9]\{14\}/.pre-ai-knowledge.<N4>/g'
}

absent() {   # <PATH> <program>...: the case's input is a PATH, so the program must not be found
    local p=$1 prog; shift
    for prog in "$@"; do
        if PATH=$p command -v "$prog" >/dev/null 2>&1; then
            echo "pin-artefacts: '$prog' is found under the PATH of this case: $p" >&2; exit 3
        fi
    done
}

sock() { python3 -I - "$1" <<'PY'
import os, socket, sys
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.close()
PY
}

snapshot() {   # every directory, file and link under the root; git repositories by ref names
    python3 -I - "$R" "$TREE" "$WORK" "$NT" <<'PY'
import hashlib, os, stat, subprocess, sys
root, tree, work, nt = sys.argv[1:5]
subs = [(nt.encode(), b'<NT>'), (tree.encode(), b'<TREE>'), (work.encode(), b'<WORK>')]
def norm(b):
    for a, c in subs:
        b = b.replace(a, c)
    return b
out = []
def walk(d):
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name); rel = os.path.relpath(p, root)
        st = os.lstat(p); m = stat.S_IMODE(st.st_mode)
        if stat.S_ISLNK(st.st_mode):
            out.append('l %o %s -> %s' % (m, rel, norm(os.readlink(p).encode()).decode('utf-8', 'replace')))
        elif stat.S_ISDIR(st.st_mode):
            if name == '.git' or name.endswith('.git'):
                r = subprocess.run(['git', '--git-dir', p, 'for-each-ref', '--format=%(refname)'],
                                   capture_output=True, text=True).stdout.split()
                out.append('repo %s refs=%s' % (rel, ','.join(sorted(r))))
                continue
            out.append('d %o %s' % (m, rel)); walk(p)
        elif stat.S_ISREG(st.st_mode):
            b = open(p, 'rb').read()
            if rel.endswith('/.seeded'):
                h = '<N1>'
            else:
                if rel.endswith('/status/knowledge'):
                    ls = b.split(b'\n', 1)
                    f = ls[0].split(b' ', 1)
                    ls[0] = b' '.join([b'<N2>'] + f[1:])
                    b = b'\n'.join(ls)
                h = hashlib.sha256(norm(b)).hexdigest()
            out.append('f %o %s %s' % (m, rel, h))
        else:
            out.append('%s %o %s' % ('s' if stat.S_ISSOCK(st.st_mode) else 'x', m, rel))
walk(root)
print('\n'.join(out))
PY
}

# ---------------------------------------------------------------- the environment of every call
RUNENV=()
base_env() {   # the fixed environment; per-case additions come after
    RUNENV=(HOME="$H" USER=u LANG=C.UTF-8 PATH="$BASEPATH" DOCKER_STUB_LOG="$WORK/docker.log"
        HOST_ETC_DIR="$WORK/etc" IDEA_HOST_DIR="$WORK/noidea" HOST_SND_DIR="$WORK/nosnd"
        XDG_RUNTIME_DIR="$R/xdg" GIT_AUTHOR_DATE=2026-01-01T00:00:00+0000
        GIT_COMMITTER_DATE=2026-01-01T00:00:00+0000 GIT_CONFIG_NOSYSTEM=1)
}
setenv() { local k=$1 i; for i in "${!RUNENV[@]}"; do case ${RUNENV[$i]} in "$k="*) RUNENV[$i]="$k=$2"; return ;; esac; done; RUNENV+=("$k=$2"); }
senv() { ( umask 022; env -i "${RUNENV[@]}" "$@" ); }   # a setup command in the case's environment

CASE_TREE=$TREE
reset_root() {   # a fresh root at the fixed path with the default budget
    rm -rf "$R"; mkdir -p "$H/.ai-sandbox" "$PROJ" "$R/xdg"
    printf 'AI_SANDBOX_MEMORY_BUDGET_GB=18\n' > "$H/.ai-sandbox/config"
    rm -f "$WORK"/docker.log*; : > "$WORK/docker.log"
    CASE_TREE=$TREE; base_env
}

sandbox_dir() { senv bash -c '. "$1/bin/ai/ai-sandbox-lib.sh"; ai_sandbox_dir_for "$2"' _ "$TREE" "$PROJ"; }

CASE=; RUN=; INV=0
x11_before() { ls -a /tmp/.X11-unix 2>/dev/null | LC_ALL=C sort > "$WORK/xb"; }
x11_after() {
    ls -a /tmp/.X11-unix 2>/dev/null | LC_ALL=C sort | comm -13 "$WORK/xb" - > "$WORK/xa"
    sed 's/^/x11: /' "$WORK/xa" | norm
    while IFS= read -r d; do [ -n "$d" ] && rm -rf "/tmp/.X11-unix/$d"; done < "$WORK/xa"
}

inv() {   # <create args...>: one call of the case's tree's create, recorded
    INV=$((INV + 1))
    local rc
    x11_before
    if [ "$RUN" = 1 ]; then
        ( cd "$PROJ" && umask 022 && env -i "${RUNENV[@]}" /bin/bash "$CASE_TREE/bin/ai/create-ai-sandbox.sh" "$@" \
            > "$WORK/out" 2> "$WORK/err" ); rc=$?
        { echo "== $CASE run1 inv$INV args: $*"; echo "rc=$rc"
          echo "-- stdout"; norm < "$WORK/out"
          echo "-- stderr"; norm < "$WORK/err"
          echo "-- docker"; norm < "$WORK/docker.log"
          echo "-- footprint"; snapshot | norm
          echo "-- x11"; x11_after
        } >> "$MANIFEST"
    else
        ( cd "$PROJ" && umask 022 && env -i "${RUNENV[@]}" /bin/bash "$CASE_TREE/bin/ai/create-ai-sandbox.sh" "$@" \
            > "$WORK/comb" 2>&1 ); rc=$?
        { echo "== $CASE run2 inv$INV args: $*"; echo "rc=$rc"
          echo "-- combined"; norm < "$WORK/comb"
          echo "-- x11"; x11_after
        } >> "$MANIFEST"
    fi
}

# ---------------------------------------------------------------- the cases
want() { setenv PATH "$1"; }
display_case() { reset_root; want "$DISPPATH"; }

K1()  { reset_root; inv --display=none --no-start; }
K2()  { display_case; inv --display=xpra --no-start; }
K3()  { display_case; inv --display=nested --no-start; }
K4()  { display_case; sock "$R/xdg/wayland-pin"; setenv WAYLAND_DISPLAY wayland-pin; inv --display=wayland --no-start; }
K5()  { display_case; setenv DISPLAY :0; inv --display=host --no-start; }
K6()  { display_case; inv --display=auto --no-start; }
K7()  { reset_root; inv --display=none --with-docker --no-start; }
k8_setup() { display_case; mkdir -p "$R/snd"; sock "$R/xdg/pulse/native"; setenv HOST_SND_DIR "$R/snd"; }
K8()  { k8_setup; inv --display=xpra --audio --no-start; }
K9() {
    reset_root
    senv git config --global user.email t@example.com; senv git config --global user.name t
    senv git config --global init.defaultBranch main
    mkdir -p "$H/.gemini" "$H/.claude" "$R/work/dev-tools"
    printf '# Rules\n\n- be brief\n\n<!-- BEGIN dev-tools:ai-sandbox-environment -->\nsandbox block\n<!-- END dev-tools:ai-sandbox-environment -->\n' > "$H/.gemini/GEMINI.md"
    senv git init -q --bare "$R/remote.git"; senv git -C "$R/work/dev-tools" init -q
    senv env AI_KNOWLEDGE_GIT_TIMEOUT=20 DOCKER_STUB_IMAGES="$IMG_BASE $IMG_DOCKER" \
        bash "$TREE/bin/ai/ai-knowledge" init "file://$R/remote.git" --integrator "$R/work/dev-tools" >/dev/null 2>&1
    inv --display=none --no-start
}
K10() {
    reset_root
    local idea=$R/idea-IU sd=$H/.sdkman
    mkdir -p "$idea/bin" "$H/.config/JetBrains/IntelliJIdea2025.1/options" "$H/.local/share/JetBrains/IntelliJIdea2025.1/some-plugin/lib"
    printf '#!/bin/sh\nexit 0\n' > "$idea/bin/idea"; chmod +x "$idea/bin/idea"
    echo '{"name":"IntelliJ IDEA","version":"2025.1"}' > "$idea/product-info.json"
    echo LICENCE > "$H/.config/JetBrains/IntelliJIdea2025.1/idea.key"
    echo jar > "$H/.local/share/JetBrains/IntelliJIdea2025.1/some-plugin/lib/p.jar"
    mkdir -p "$sd/bin" "$sd/libexec" "$sd/src" "$sd/contrib" "$sd/etc" "$sd/var" \
        "$sd/candidates/java/21.0.8-tem/bin" "$sd/candidates/java/17.0.16-tem/bin" "$sd/candidates/gradle/9.6.1/bin"
    echo init > "$sd/bin/sdkman-init.sh"; echo fn > "$sd/src/sdkman-default.sh"
    echo 'sdkman_auto_answer=false' > "$sd/etc/config"; echo 5.20.0 > "$sd/var/version"
    ln -s 21.0.8-tem "$sd/candidates/java/current"
    setenv IDEA_HOST_DIR "$idea"
    inv --display=none --no-start
}
# K11 passes --no-start on its two later calls: "no option" means no option that changes a
# remembered value, and a start would run the display launcher of K8's remembered xpra mode.
K11() { k8_setup; inv --display=xpra --audio --no-start; inv --no-start; inv --memory=8 --no-docker --no-audio --no-start; }
K12() {
    reset_root; local d; d=$(sandbox_dir); mkdir -p "$d"; printf 'SANDBOX_WITH_AUDIO=1\n' > "$d/.env"
    inv --display=none --no-start
}
K13() { reset_root; inv --display=none; }
K14() {
    reset_root
    inv --help; inv --with-docker --no-docker; inv --audio --no-audio
    inv --display=bogus; inv --memory=x; inv --bogus
}
K15() { reset_root; rm -f "$H/.ai-sandbox/config"; inv --display=none --no-start; }
K16() { reset_root; printf 'AI_SANDBOX_MEMORY_BUDGET_GB=x\n' > "$H/.ai-sandbox/config"; inv --display=none --no-start; }
K17() { reset_root; absent "$NR:/usr/bin:/bin" rsync; want "$NR:/usr/bin:/bin"; inv --display=none --no-start; }
K18() { reset_root; want "$BC:$BASEPATH"; inv --display=none --no-start; }
K19() { reset_root; setenv DOCKER_STUB_RUNNING true; inv --display=none --no-start; }
K20() { reset_root; setenv DOCKER_STUB_RUNNING true; inv --display=none; }
K21() { reset_root; local h2=$R/ho,me; mkdir -p "$h2/.ai-sandbox"; cp "$H/.ai-sandbox/config" "$h2/.ai-sandbox/config"; setenv HOME "$h2"; inv --display=none --no-start; }
K22() { reset_root; CASE_TREE=$NT; inv --display=none --no-start; }
K23() { reset_root; absent "$TD:$ST:/usr/bin:/bin" xpra Xvfb Xephyr; inv --display=auto --no-start; }
K24() { reset_root; absent "$BASEPATH" xpra; inv --display=xpra --no-start; }
K25() { display_case; inv --display=wayland --no-start; }
K26() { display_case; inv --display=host --no-start; }
K27() {
    reset_root; printf 'AI_SANDBOX_MEMORY_BUDGET_GB=8\n' > "$H/.ai-sandbox/config"; mkdir -p "$H/.ai-sandbox/other-agent"
    setenv DOCKER_STUB_PS other-agent; setenv DOCKER_STUB_MEMORY other-agent=4294967296
    inv --display=none --memory=6
}
K28() { reset_root; inv --display=none; setenv DOCKER_STUB_IMAGES "$IMG_BASE"; inv --display=none; }
K29() { reset_root; inv --display=none --rebuild; }
K30() { display_case; inv --display=xpra; }
K31() { reset_root; setenv DOCKER_STUB_NO_BUILDX 1; inv --display=none --no-start; }
K32() { reset_root; inv --no-start; }

CASES="${PIN_CASES:-K1 K2 K3 K4 K5 K6 K7 K8 K9 K10 K11 K12 K13 K14 K15 K16 K17 K18 K19 K20 K21 K22 K23 K24 K25 K26 K27 K28 K29 K30 K31 K32}"

# ---------------------------------------------------------------- the manifest
{
    echo "# pin manifest; tree=<TREE> work=<WORK> uid=$UIDN"
    echo "# env: env -i HOME USER=u LANG=C.UTF-8 PATH DOCKER_STUB_LOG HOST_ETC_DIR IDEA_HOST_DIR HOST_SND_DIR XDG_RUNTIME_DIR GIT_AUTHOR_DATE GIT_COMMITTER_DATE GIT_CONFIG_NOSYSTEM=1, umask 022"
    echo "# PATH of the cases: $BASEPATH (display cases: $DISPPATH)"
    for p in rsync xpra Xvfb Xephyr xauth mcookie timedatectl git python3; do
        printf '# command -v %s: %s\n' "$p" "$(PATH=$BASEPATH command -v "$p" || echo -)"
    done
} | norm > "$MANIFEST"
for CASE in $CASES; do
    for RUN in 1 2; do INV=0; "$CASE"; done
done
rm -rf "$R"
echo "pin-artefacts: $(grep -c '^== K' "$MANIFEST") invocations in $MANIFEST" >&2
