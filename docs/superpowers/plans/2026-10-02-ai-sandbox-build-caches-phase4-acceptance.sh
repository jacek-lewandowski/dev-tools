#!/usr/bin/env bash
# Phase 4 host acceptance for the build-cache overlays (spec:
# docs/superpowers/specs/2026-10-02-ai-sandbox-build-caches-design.md).
# Run ON THE HOST from inside a Gradle project that has a committed ./gradlew
# and was built on this host before:
#     cd ~/dev/<project> && bash ~/dev/public/dev-tools/docs/superpowers/plans/2026-10-02-ai-sandbox-build-caches-phase4-acceptance.sh [task]
# Then paste back ~/build-caches-acceptance.log.
set -u
P="$(git rev-parse --show-toplevel)" || { echo "run it from inside a Gradle project"; exit 1; }
T="${1:-assemble}"
CREATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/bin/ai/create-ai-sandbox.sh"
LOG="$HOME/build-caches-acceptance.log"
MARK="$HOME/.build-caches-mark"
{
touch "$MARK"; sleep 1
echo "project=$P task=$T"
echo "== 1 create-ai-sandbox.sh refuses while the sandbox runs"
( cd "$P" && ai-sandbox true ) || true
"$CREATE" "$P" 2>&1 | tail -5; echo "exit=${PIPESTATUS[0]} (expect non-zero, naming ai-sandbox-stop)"
echo "== 2 stop, then accepted (rebuilds the shared image once)"
( cd "$P" && ai-sandbox-stop )
"$CREATE" "$P" 2>&1 | tail -15; echo "exit=${PIPESTATUS[0]} (expect 0)"
echo "== 3 sandbox-doctor: three overlay rows, UTF-8 locale"
( cd "$P" && ai-sandbox sandbox-doctor ) | grep -i -E 'gradle-caches|gradle-wrapper-dists|m2-repository'
( cd "$P" && ai-sandbox 'echo "LANG=$LANG"; java -XshowSettings:properties -version 2>&1 | grep sun.jnu.encoding' )
echo "== 4 offline build (writes build outputs into the project, as any build does)"
( cd "$P" && ai-sandbox "cd '$P' && ./gradlew --offline --no-daemon $T 2>&1 | tail -15; exit \${PIPESTATUS[0]}" ); echo "gradle exit=$?"
echo "== 5 probe: survives entering a running sandbox, gone after restart and after stop+start"
( cd "$P" && ai-sandbox 'echo probe > $HOME/.gradle/caches/sandbox-probe-check' )
( cd "$P" && ai-sandbox 'test -f $HOME/.gradle/caches/sandbox-probe-check && echo PROBE_SURVIVES_ENTRY' )
( cd "$P" && ai-sandbox-restart ) >/dev/null
( cd "$P" && ai-sandbox 'test -f $HOME/.gradle/caches/sandbox-probe-check || echo PROBE_GONE_AFTER_RESTART' )
( cd "$P" && ai-sandbox 'echo probe > $HOME/.gradle/caches/sandbox-probe-check' )
( cd "$P" && ai-sandbox-stop ) >/dev/null
( cd "$P" && ai-sandbox 'test -f $HOME/.gradle/caches/sandbox-probe-check || echo PROBE_GONE_AFTER_STOP_START' )
echo "== 6 host cache directories unchanged since the start (expect nothing listed)"
find "$HOME/.gradle/caches" "$HOME/.gradle/wrapper/dists" "$HOME/.m2/repository" -cnewer "$MARK" | head -20
echo "== 7 ai-sandbox-rm on a throwaway project leaves nothing behind"
TP="$HOME/dev/build-caches-throwaway-$$"; mkdir -p "$TP" && git -C "$TP" init -q
( cd "$P" && ai-sandbox-stop ) >/dev/null   # frees a slot under the three-running cap
"$CREATE" --display=none "$TP" 2>&1 | tail -3
( cd "$TP" && yes y | ai-sandbox-rm ); echo "rm exit=$? (expect 0)"
ls -d "$HOME/.ai-sandbox/build-caches-throwaway-"*-agent 2>/dev/null && echo "LEFTOVER DIRECTORY REMAINS" || echo "throwaway sandbox directory gone: ok"
docker volume ls -q | grep build-caches-throwaway && echo "LEFTOVER VOLUMES" || echo "throwaway volumes gone: ok"
rm -rf "$TP"
rm -f "$MARK"
} 2>&1 | tee "$LOG"
