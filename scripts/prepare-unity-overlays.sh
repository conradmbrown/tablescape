#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
export PATH="$ROOT/runtime/node-v24.21.0-linux-x64/bin:$PATH"
mkdir -p "$ROOT/vendor/lostcity-engine274/src/scape"
cp "$ROOT/integration/lostcity274/unity/UnityOverlayExport.ts" "$ROOT/vendor/lostcity-engine274/src/scape/"
cd "$ROOT/vendor/lostcity-engine274"
node --import tsx src/scape/UnityOverlayExport.ts
node "$ROOT/tools/prepare-native-overlays.mjs" "$@"
