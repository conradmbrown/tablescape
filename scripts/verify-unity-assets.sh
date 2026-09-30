#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
EDITOR="${SCAPE_UNITY_EDITOR:?Set SCAPE_UNITY_EDITOR to the activated Unity editor executable}"
mkdir -p "$ROOT/Saved"
CLI="${SCAPE_UNITY_CLI:?Set SCAPE_UNITY_CLI to the Unity CLI executable}"
"$CLI" run "$ROOT/Unity" --editor-path "$EDITOR" --no-tail --timeout 1200 --log-file "$ROOT/Saved/unity-asset-import.log" -- -nographics -executeMethod ScapeAssetVerification.Run
grep -F 'SCAPE_ASSET_IMPORT_PASSED' "$ROOT/Saved/unity-asset-import.log"
