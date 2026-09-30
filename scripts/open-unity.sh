#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
EDITOR="${SCAPE_UNITY_EDITOR:?Set SCAPE_UNITY_EDITOR to the activated Unity editor executable}"
if [[ ! -x "$EDITOR" ]]; then
  echo "Unity editor is not installed at $EDITOR. Set SCAPE_UNITY_EDITOR to an activated Unity 6000.0.73f1 editor." >&2
  exit 1
fi
mkdir -p "$ROOT/Saved"
exec "$EDITOR" -projectPath "$ROOT/Unity" -logFile "$ROOT/Saved/unity-editor.log" "$@"
