#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$ROOT/scripts/storage-env.sh"
export TMPDIR="$SCAPE_BUILD_ROOT/Unreal/tmp"
scape_require_storage_path "$TMPDIR"
mkdir -p "$TMPDIR"
: "${SCAPE_UNREAL_ENGINE:?Set SCAPE_UNREAL_ENGINE to the Unreal installation directory}"
"$SCAPE_UNREAL_ENGINE/Engine/Build/BatchFiles/Linux/Build.sh" ScapeTabletopEditor Linux Development "$ROOT/ScapeTabletop.uproject" -WaitMutex -MaxParallelActions=1
