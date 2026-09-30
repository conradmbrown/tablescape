#!/usr/bin/env bash
# Original model close-ups through the shipped RealityKit graph; no asset copies/downloads.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
checks="$build_root/ModelGPULighting"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Temporary"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Temporary"
checks="$(cd "$checks" && pwd -P)"
export TMPDIR="$checks/Temporary/"
xcrun swiftc -O -swift-version 6 -parse-as-library -module-cache-path "$checks/ModuleCache" \
  "$repo_root"/Native/TableScape/Assets/*.swift \
  "$repo_root/Native/TableScape/Core/JSON.swift" \
  "$repo_root/Native/TableScape/Rendering/VolumeMaterial.swift" \
  "$repo_root/Native/Tests/NativeModelGPULightingChecks.swift" -o "$checks/model-gpu-lighting"
"$checks/model-gpu-lighting" "$repo_root" "$checks" | tee "$checks/Artifacts/model-gpu-lighting.log"
