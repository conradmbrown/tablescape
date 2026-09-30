#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
timeout 210 xvfb-run -a -s "-screen 0 1440x900x24" "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-render-test --scape-capture="$ROOT/Saved/unity-render-fixes.png" -logFile "$ROOT/Saved/unity-render-fixes.log"
rg 'SCAPE_RENDER_PASSED' "$ROOT/Saved/unity-render-fixes.log"
