#!/usr/bin/env bash
# Host verification for the ai-sandbox rework. Run this ON THE HOST, not in a
# sandbox. Phases A-B are read-only. Phase C onward MUTATES ~/.ai-sandbox.
set -uo pipefail
R="$HOME/.ai-sandbox"
S="$(cd "$(dirname "$0")" && pwd)/bin/create-ai-sandbox.sh"
hr() { printf '\n===== %s =====\n' "$*"; }

hr "A. state before anything"
{ . /etc/os-release; echo "host: $PRETTY_NAME  python3: $(python3 -V 2>&1)"; }
echo "-- sandbox dirs --";      ls -1 "$R" 2>/dev/null
echo "-- sizes --";             du -sh "$R"/* 2>/dev/null | sort -h
echo "-- images --";            docker images --format '{{.ID}}  {{.Size}}  {{.Repository}}:{{.Tag}}' | grep -i ai-sandbox
echo "-- distinct image IDs --"; docker images --format '{{.ID}} {{.Repository}}' | grep -i ai-sandbox | awk '{print $1}' | sort -u | wc -l
echo "-- running containers --"; docker ps --format '{{.Names}}' | grep -- -agent || echo "(none running)"

hr "B. cheap safety net (hardlinks: near-instant, ~no extra space)"
if [ -e "$R.pre-migration" ]; then
    echo "backup already exists at $R.pre-migration -- leaving it alone"
else
    cp -al "$R" "$R.pre-migration" && echo "backed up -> $R.pre-migration" \
        || echo "BACKUP FAILED - stop here and investigate"
fi

hr "C. MUTATES: migrate + regenerate for THIS project"
echo "Stop any running sandbox first; migration refuses to touch a live one."
"$S" --no-start
echo "-- dirs after --"; ls -1 "$R"
echo "-- project-path files --"
for d in "$R"/*-agent; do printf '%s -> %s\n' "$(basename "$d")" "$(cat "$d/project-path" 2>/dev/null || echo MISSING)"; done

hr "D. credentials and history survived the rename"
for d in "$R"/*-agent; do
  printf '%s: claude-creds=%s claude.json=%s antigravity-history=%s seeded=%s\n' \
    "$(basename "$d")" \
    "$( [ -s "$d/.claude/.credentials.json" ] && echo yes || echo NO )" \
    "$( [ -s "$d/.claude.json" ] && echo yes || echo NO )" \
    "$( [ -d "$d/antigravity-data/User/History" ] && echo yes || echo none )" \
    "$( [ -f "$d/.seeded" ] && cat "$d/.seeded" || echo NO )"
done
echo "-- host-side Antigravity history (must be untouched; lives outside ~/.ai-sandbox) --"
du -sh ~/.gemini/antigravity/conversations ~/.gemini/antigravity-ide/conversations 2>/dev/null

hr "E. one image shared by every project"
echo "-- compose image tags --"
grep -h 'image: ' "$R"/*-agent/docker-compose.yml | sort | uniq -c
echo "-- any leftover build: blocks (want none) --"
grep -l 'build:' "$R"/*-agent/docker-compose.yml 2>/dev/null || echo "none"

hr "F. sticky --with-docker"
"$S" --no-start --with-docker >/dev/null 2>&1
grep -h SANDBOX_WITH_DOCKER "$R"/*-agent/.env | head -1
"$S" --no-start           >/dev/null 2>&1
echo "after a bare re-run (must still be 1):"; grep -h SANDBOX_WITH_DOCKER "$R"/*-agent/.env | head -1
"$S" --no-start --no-docker >/dev/null 2>&1
echo "after --no-docker (must be 0):";        grep -h SANDBOX_WITH_DOCKER "$R"/*-agent/.env | head -1
"$S" --with-docker --no-docker >/dev/null 2>&1; echo "both flags exit code (want 2): $?"

hr "G. disk after"
du -sh "$R"/* 2>/dev/null | sort -h
echo "-- shared/ --"; du -sh "$R"/shared/* 2>/dev/null | sort -h

hr "H. what gc would reclaim (lists only, removes nothing)"
"$R/bin/ai-sandbox-gc" </dev/null

hr "DONE. Not yet tested: the real image build and container start."
echo "Next, when you are ready:  $S      # builds ~10GB once, then starts"
