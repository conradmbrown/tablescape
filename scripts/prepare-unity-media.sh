#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
export PATH="$ROOT/runtime/node-v24.21.0-linux-x64/bin:$PATH"
ENGINE="$ROOT/vendor/lostcity-engine274"
mkdir -p "$ENGINE/src/scape"
cp "$ROOT/integration/lostcity274/unity/UnityMediaExport.ts" "$ENGINE/src/scape/"
cd "$ENGINE"
node --import tsx src/scape/UnityMediaExport.ts
node "$ROOT/tools/render-native-audio.mjs" prepare
# Warm the default Lumbridge track. Other original tracks render on demand.
node "$ROOT/tools/render-native-audio.mjs" music 76
