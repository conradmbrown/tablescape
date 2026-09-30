#!/usr/bin/env bash
# Offline original-cache render checks. Source fixtures contain definitions/IDs only, never credentials.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
checks="$build_root/RenderChecks"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
checks="$(cd "$checks" && pwd -P)"
export TMPDIR="$checks/Tmp/"
python3 - "$repo_root/Native/Tests/Fixtures" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);manifest=json.loads((root/'asset-fixture-manifest.json').read_text())
for name,expected in manifest['sha256'].items():
    actual=hashlib.sha256((root/name).read_bytes()).hexdigest()
    if actual != expected:raise SystemExit('Fixture hash mismatch: '+name)
print('Original revision-274 fixture hashes verified')
PY
common=("$repo_root"/Native/TableScape/Assets/*.swift "$repo_root/Native/TableScape/Core/JSON.swift")
xcrun swiftc -O -swift-version 6 -module-cache-path "$checks/ModuleCache" "${common[@]}" \
  "$repo_root/Native/TableScape/Rendering/SceneMath.swift" "$repo_root/Native/TableScape/Rendering/NativeEffects.swift" \
  "$repo_root/Native/Tests/NativeRenderTestTypes.swift" "$repo_root/Native/Tests/NativeEffectsChecks.swift" -o "$checks/effects"
"$checks/effects" "$repo_root" "$checks" | tee "$checks/Artifacts/effects.log"
xcrun swiftc -O -swift-version 6 -module-cache-path "$checks/ModuleCache" "${common[@]}" \
  "$repo_root/Native/TableScape/Rendering/NativeDeathRetention.swift" "$repo_root/Native/Tests/NativeDeathChecks.swift" -o "$checks/death"
"$checks/death" "$repo_root" "$checks" | tee "$checks/Artifacts/death.log"
xcrun swiftc -O -swift-version 6 -module-cache-path "$checks/ModuleCache" "${common[@]}" \
  "$repo_root/Native/Tests/NativeLightingChecks.swift" -o "$checks/lighting"
"$checks/lighting" "$repo_root" "$checks" | tee "$checks/Artifacts/lighting.log"
xcrun swiftc -O -swift-version 6 -module-cache-path "$checks/ModuleCache" "${common[@]}" \
  "$repo_root/Native/Tests/NativePortraitChecks.swift" -o "$checks/portraits"
"$checks/portraits" "$repo_root" "$checks" | tee "$checks/Artifacts/portraits.log"
echo "Native renderer evidence: $checks/Artifacts"
