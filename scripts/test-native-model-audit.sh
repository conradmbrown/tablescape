#!/usr/bin/env bash
# Entire bundled original-model audit; no downloads or live game sessions.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
checks="$build_root/ModelAudit"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
checks="$(cd "$checks" && pwd -P)"
export TMPDIR="$checks/Tmp/"
pack="$repo_root/Native/TableScape/Resources/AssetPack"
xcrun swiftc -O -swift-version 6 -module-cache-path "$checks/ModuleCache" \
  "$repo_root"/Native/TableScape/Assets/*.swift "$repo_root/Native/TableScape/Core/JSON.swift" \
  "$repo_root/Native/Tests/NativeModelAuditChecks.swift" -o "$checks/model-audit"
"$checks/model-audit" "$pack" "$checks/Artifacts" | tee "$checks/Artifacts/model-audit.log"
echo "Original model audit evidence: $checks/Artifacts"
