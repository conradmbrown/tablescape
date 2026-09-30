#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
checks="$SCAPE_BUILD_ROOT/VolumeChecks"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Temporary"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Temporary"
export TABLESCAPE_VOLUME_PIXEL_ARTIFACTS="$checks/Artifacts"
export TMPDIR="$checks/Temporary/"
xcrun swiftc -O -parse-as-library -module-cache-path "$checks/ModuleCache" \
  "$repo_root/Native/TableScape/Rendering/VolumeMaterial.swift" \
  "$repo_root/Native/Tests/NativeVolumeMaterialChecks.swift" -o "$checks/material-check"
"$checks/material-check" | tee "$checks/Artifacts/material.log"
xcrun swiftc -O -parse-as-library -module-cache-path "$checks/ModuleCache" \
  "$repo_root/Native/TableScape/Assets/NativeGeometry.swift" \
  "$repo_root/Native/TableScape/Rendering/SceneMath.swift" \
  "$repo_root/Native/TableScape/Rendering/VolumeMaterial.swift" \
  "$repo_root/Native/TableScape/Rendering/VolumetricTableRenderer.swift" \
  "$repo_root/Native/Tests/NativeVolumeRendererChecks.swift" -o "$checks/renderer-check"
"$checks/renderer-check" | tee "$checks/Artifacts/renderer.log"

xcrun swiftc -O -parse-as-library -module-cache-path "$checks/ModuleCache" \
  "$repo_root/Native/TableScape/Assets/NativeGeometry.swift" \
  "$repo_root/Native/TableScape/Rendering/VolumeMaterial.swift" \
  "$repo_root/Native/Tests/NativeVolumePixelChecks.swift" -o "$checks/pixel-check"
"$checks/pixel-check" | tee "$checks/Artifacts/pixels.log"
