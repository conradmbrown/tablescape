#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
export ROOT
xvfb-run -a -s "-screen 0 1440x900x24" /bin/bash -c '
request="$ROOT/Saved/playtest-input-$$.json"
timeout 290 "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-context-test --scape-input-file="$request" --scape-capture="$ROOT/Saved/unity-context" -logFile "$ROOT/Saved/unity-context.log" &
player=$!
python3 "$ROOT/scripts/input-playtest-driver.py" "$request" "$player" > "$ROOT/Saved/unity-context-input.log" &
driver=$!
wait "$player"; result=$?
wait "$driver"
exit "$result"
'
rg 'SCAPE_CONTEXT_PASSED' "$ROOT/Saved/unity-context.log"
