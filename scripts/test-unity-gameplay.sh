#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
timeout 260 xvfb-run -a -s "-screen 0 1440x900x24" "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-parity --scape-capture="$ROOT/Saved/unity-parity-gameplay.png" -logFile "$ROOT/Saved/unity-parity-gameplay.log"
grep 'SCAPE_PARITY_PASSED' "$ROOT/Saved/unity-parity-gameplay.log"
