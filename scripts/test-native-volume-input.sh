#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
checks="$SCAPE_BUILD_ROOT/VolumeInputChecks"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Temporary"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Temporary"
export TMPDIR="$checks/Temporary/"
xcrun swiftc -O -parse-as-library -module-cache-path "$checks/ModuleCache" \
  "$repo_root/Native/TableScape/Core/JSON.swift" \
  "$repo_root/Native/TableScape/Assets/NativeGeometry.swift" \
  "$repo_root/Native/TableScape/Rendering/SceneMath.swift" \
  "$repo_root/Native/TableScape/Spatial/TableGeometry.swift" \
  "$repo_root/Native/TableScape/Rendering/VolumeInputController.swift" \
  "$repo_root/Native/Tests/NativeVolumeInputChecks.swift" -o "$checks/input-check"
"$checks/input-check" 2>&1 | tee "$checks/Artifacts/input.log"
if rg -q 'invalid parameter|FAIL volume input' "$checks/Artifacts/input.log"; then
  echo 'RealityKit reported an invalid collision configuration.' >&2
  exit 1
fi
