#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
scape_require_storage_path "$build_root/SceneChecks/Artifacts" "$build_root/SceneChecks/Temporary" "$build_root/SpatialMacModuleCache"
mkdir -p "$build_root/SceneChecks/Artifacts" "$build_root/SceneChecks/Temporary" "$build_root/SpatialMacModuleCache"
export TMPDIR="$build_root/SceneChecks/Temporary/"
xcrun --sdk macosx swiftc -O -D SCENE_CACHE_CHECKS \
  -module-cache-path "$build_root/SpatialMacModuleCache" \
  "$repo_root/Native/TableScape/Core/JSON.swift" \
  "$repo_root/Native/TableScape/Rendering/GameScene.swift" \
  "$repo_root/Native/Tests/NativeSceneCacheChecks.swift" \
  -o "$build_root/SceneChecks/native-scene-cache-checks"
"$build_root/SceneChecks/native-scene-cache-checks" | tee "$build_root/SceneChecks/Artifacts/scene-cache.log"
