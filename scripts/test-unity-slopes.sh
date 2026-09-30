#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
mkdir -p "$ROOT/Saved/slopes"
sha256sum "$ROOT/Builds/Linux/ScapeClient_Data/Managed/Assembly-CSharp.dll" "$ROOT/vendor/lostcity-engine274/src/scape/UnityScenery.ts" > "$ROOT/Saved/slopes/build-provenance.txt"
timeout 230 xvfb-run -a -s "-screen 0 1440x900x24" "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-slope-test --scape-capture="$ROOT/Saved/slopes/fence" -logFile "$ROOT/Saved/slopes/unity.log"
rg 'SCAPE_SLOPE_PASSED' "$ROOT/Saved/slopes/unity.log"
