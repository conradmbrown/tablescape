#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
CLI="${SCAPE_UNITY_CLI:?Set SCAPE_UNITY_CLI to the Unity CLI executable}"
EDITOR="${SCAPE_UNITY_EDITOR:?Set SCAPE_UNITY_EDITOR to the activated Unity editor executable}"
"$CLI" build "$ROOT/Unity" --editor-path "$EDITOR" --target StandaloneLinux64 --execute-method ScapeBuild.Build --output-path "$ROOT/Builds/Linux/ScapeClient" --log-file "$ROOT/Saved/unity-build.log" --no-tail
