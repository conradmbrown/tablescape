#!/usr/bin/env bash
set -euo pipefail
export ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
timeout 260 xvfb-run -a -s "-screen 0 1440x900x24" bash -c '
  "$ROOT/Builds/Linux/ScapeClient" -force-vulkan -screen-width 1440 -screen-height 900 --scape-chathead-test --scape-capture="$ROOT/Saved/unity-chathead" -logFile "$ROOT/Saved/unity-chathead.log" &
  player_pid=$!
  trap "kill $player_pid 2>/dev/null || true" EXIT
  python3 "$ROOT/scripts/focus-stream-window.py" || exit 1
  wait "$player_pid"
'
rg 'SCAPE_CHATHEAD_RENDER|SCAPE_CHATHEAD_PASSED|SCAPE_PARITY_CHECK' "$ROOT/Saved/unity-chathead.log"
