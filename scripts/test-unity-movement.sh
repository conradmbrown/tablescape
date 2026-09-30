#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
xvfb-run -a -s "-screen 0 1440x900x24" timeout 240 "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-movement-test --scape-capture="$ROOT/Saved/unity-movement" -logFile "$ROOT/Saved/unity-movement.log"
rg 'SCAPE_MOVEMENT_PASSED' "$ROOT/Saved/unity-movement.log"
python3 "$ROOT/scripts/check-movement-trace.py" "$ROOT/Saved/unity-movement-motion.csv"
