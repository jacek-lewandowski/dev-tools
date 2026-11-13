# P11 probe: create's refusal and start paths through their real inputs.
# Usage: bash probe11.sh <tree> <fixed dir> refusals|start ; appends to <fixed dir>/result
T=$1; P=$2/run; O=$2; mkdir -p "$P/bin-norsync" "$P/bin-badcompose" "$P/xstub"
ST=$T/tests/ai-sandbox/stub
for t in xpra Xvfb Xephyr; do printf '#!/bin/sh\nexit 0\n' > "$P/xstub/$t"; done; chmod +x "$P/xstub/"*
for f in "$ST"/*; do ln -sf "$f" "$P/bin-norsync/"; done; rm -f "$P/bin-norsync/rsync"
printf '#!/bin/bash\n[ "$1 $2" = "compose version" ] && exit 1\nexec %s/docker "$@"\n' "$ST" > "$P/bin-badcompose/docker"; chmod +x "$P/bin-badcompose/docker"
rm -rf "$P/tree-notools"; cp -a "$T" "$P/tree-notools"; rm -rf "$P/tree-notools/tools"
run() {  # <case> <home> <tree> <PATH> [VAR=value...] -- <create args...>; KEEP=1 keeps the previous root
  local c=$1 h=$2 tr=$3 pa=$4; shift 4; local env=(); while [ "$1" != -- ]; do env+=("$1"); shift; done; shift
  [ -n "${KEEP:-}" ] || rm -rf "$P/x"; mkdir -p "$P/x/work/p" "$h/.ai-sandbox"; : > "$P/x/docker.log"
  case $c in
    R1) rm -f "$h/.ai-sandbox/config" ;;
    R2) echo 'AI_SANDBOX_MEMORY_BUDGET_GB=x' > "$h/.ai-sandbox/config" ;;
    R13) echo 'AI_SANDBOX_MEMORY_BUDGET_GB=8' > "$h/.ai-sandbox/config"; mkdir -p "$h/.ai-sandbox/other-agent" ;;
    *) echo 'AI_SANDBOX_MEMORY_BUDGET_GB=18' > "$h/.ai-sandbox/config" ;;
  esac
  find "$P/x" -printf '%P\n' | LC_ALL=C sort > "$P/before"; ls -a /tmp/.X11-unix 2>/dev/null | LC_ALL=C sort > "$P/xb"
  ( cd "$P/x/work/p" && env -i HOME="$h" USER=u LANG=C.UTF-8 PATH="$pa" DOCKER_STUB_LOG="$P/x/docker.log" "${env[@]}" \
      /bin/bash "$tr/bin/ai/create-ai-sandbox.sh" "$@" > "$P/out" 2> "$P/err"; echo $? > "$P/rc" )
  { echo "== $c rc=$(cat "$P/rc") args: $*"; sed 's/^/  out: /' "$P/out"; sed 's/^/  err: /' "$P/err"
    sed 's/^/  docker: /' "$P/x/docker.log"
    find "$P/x" -printf '%P\n' | LC_ALL=C sort | comm -13 "$P/before" - | command grep -v '^docker\.log' | sed 's/^/  new: /'
    ls -a /tmp/.X11-unix 2>/dev/null | LC_ALL=C sort | comm -13 "$P/xb" - | sed 's/^/  x11: /'
  } | sed "s|$P/tree-notools|<NT>|g; s|$P|<P>|g; s|$T|<T>|g" >> "$O/result"
  ls -a /tmp/.X11-unix 2>/dev/null | LC_ALL=C sort | comm -13 "$P/xb" - | while read -r d; do rmdir "/tmp/.X11-unix/$d"; done
}
H=$P/x/home; SP="$ST:$P/xstub:/usr/bin"
case $3 in
refusals)
  run R1  "$H" "$T" "$SP" -- --display=none --no-start
  run R2  "$H" "$T" "$SP" -- --display=none --no-start
  run R3  "$H" "$T" "$P/bin-norsync:/usr/bin" -- --display=none --no-start
  run R4  "$H" "$T" "$P/bin-badcompose:$SP" -- --display=none --no-start
  run R5  "$H" "$T" "$SP" DOCKER_STUB_RUNNING=true -- --display=none --no-start
  run R6  "$H" "$T" "$SP" DOCKER_STUB_RUNNING=true -- --display=none
  run R7  "$P/x/ho,me" "$T" "$SP" -- --display=none --no-start
  run R8  "$H" "$P/tree-notools" "$SP" -- --display=none --no-start
  run R9  "$H" "$T" "$ST:/usr/bin" -- --no-start
  run R10 "$H" "$T" "$ST:/usr/bin" -- --display=xpra --no-start
  run R11 "$H" "$T" "$SP" -- --display=wayland --no-start
  run R12 "$H" "$T" "$SP" -- --display=host --no-start
  run R13 "$H" "$T" "$SP" DOCKER_STUB_PS=other-agent DOCKER_STUB_MEMORY=other-agent=4294967296 -- --display=none ;;
start)
  run S1 "$H" "$T" "$SP" -- --display=none
  KEEP=1 run S2 "$H" "$T" "$SP" DOCKER_STUB_IMAGES=ai-sandbox:base-u$(id -u) -- --display=none
  run S3 "$H" "$T" "$SP" -- --display=none --rebuild
  run S4 "$H" "$T" "$SP" -- --display=xpra ;;
esac
