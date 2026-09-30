#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")/../../.." && pwd -P)/scripts/storage-env.sh"
scape_spatial="$(cd "$(dirname "$0")" && pwd -P)"
scape_build="$SCAPE_BUILD_ROOT"
scape_require_storage_path "$scape_build/SpatialMacModuleCache" "$scape_build/SpatialChecks/Artifacts" "$scape_build/SpatialChecks/Temporary"
mkdir -p "$scape_build/SpatialMacModuleCache" "$scape_build/SpatialChecks/Artifacts" "$scape_build/SpatialChecks/Temporary"
export TMPDIR="$scape_build/SpatialChecks/Temporary/"
xcrun --sdk macosx swiftc -D TABLE_GEOMETRY_CHECKS \
    -module-cache-path "$scape_build/SpatialMacModuleCache" \
    "$scape_spatial/TableGeometry.swift" "$scape_spatial/GeometryChecks.swift" \
    -o "$scape_build/table-geometry-checks"
"$scape_build/table-geometry-checks" | tee "$scape_build/SpatialChecks/Artifacts/table-geometry.log"
xcrun --sdk macosx swiftc -parse-as-library -D MINIMAP_GEOMETRY_CHECKS \
    -module-cache-path "$scape_build/SpatialMacModuleCache" \
    "$scape_spatial/../UI/NativeMinimap.swift" \
    -o "$scape_build/minimap-geometry-checks"
"$scape_build/minimap-geometry-checks" | tee "$scape_build/SpatialChecks/Artifacts/minimap-geometry.log"
