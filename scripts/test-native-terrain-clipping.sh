#!/usr/bin/env bash
# Actual production Metal pixel regression; no simulator, network or SDK download.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
baseline_ref=""
if [[ "${1:-}" == --baseline-ref && $# == 2 ]]; then
  baseline_ref="$(git -C "$repo_root" rev-parse --verify "$2^{commit}")"
elif [[ $# != 0 ]]; then
  echo 'Usage: test-native-terrain-clipping.sh [--baseline-ref COMMIT]' >&2; exit 2
fi
checks="$build_root/TerrainClippingChecks/${baseline_ref:-current}"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
export TMPDIR="$checks/Tmp/"
python3 - "$repo_root" "$checks" "$baseline_ref" <<'PY'
import hashlib,json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);ref=sys.argv[3]
pack=root/'Native/TableScape/Resources/AssetPack'
entry=next(a for a in json.loads((pack/'manifest.json').read_bytes())['assets'] if a['path']=='textures/1.png')
water=(pack/entry['path']).read_bytes()
if len(water)!=entry['bytes'] or hashlib.sha256(water).hexdigest()!=entry['sha256']:raise SystemExit('Original river texture manifest verification failed')
print('Original river texture 1 SHA256 '+entry['sha256'])
def source(path):
    return subprocess.check_output(['git','-C',str(root),'show',ref+':'+path]) if ref else (root/path).read_bytes()
renderer=source('Native/TableScape/Rendering/MetalRenderer.swift').decode()
shader=source('Native/TableScape/Rendering/TableScape.metal')
marker='@MainActor final class PreviewDelegate'
if renderer.count(marker)!=1:raise SystemExit('Renderer extraction marker changed; review the terrain harness')
extracted=renderer[:renderer.index(marker)].replace('import CompositorServices\n','').replace('import ARKit\n','')
scene=source('Native/TableScape/Rendering/GameScene.swift').decode()
start='final class RenderGeometry:';end='final class SceneExchange:'
if scene.count(start)!=1 or scene.count(end)!=1:raise SystemExit('Scene type extraction markers changed; review the terrain harness')
types=scene[scene.index(start):scene.index(end)]
scaffold=(root/'Native/Tests/NativeTerrainClippingChecks.swift').read_text()
(out/'ExactMetalTerrain.generated.swift').write_text(extracted+'\n'+types+'\n'+scaffold)
(out/'TableScapeShaders.txt').write_bytes(shader)
print('Testing '+('baseline '+ref if ref else 'current production source'))
print('Renderer SHA256 '+hashlib.sha256(renderer.encode()).hexdigest())
print('Shader SHA256 '+hashlib.sha256(shader).hexdigest())
PY
rotation_flags=()
if rg -q '^    var tableQuarterTurns = ' "$checks/ExactMetalTerrain.generated.swift"; then
  rotation_flags=(-D TABLE_ROTATION_CHECKS)
fi
# The conditional expansion also supports macOS Bash 3.2 with nounset and an empty array.
xcrun swiftc -O -swift-version 6 -module-cache-path "$checks/ModuleCache" ${rotation_flags[@]+"${rotation_flags[@]}"} \
  "$repo_root/Native/TableScape/Assets/NativeGeometry.swift" \
  "$repo_root/Native/TableScape/Rendering/SceneMath.swift" \
  "$repo_root/Native/TableScape/Rendering/RenderMetrics.swift" \
  "$checks/ExactMetalTerrain.generated.swift" -o "$checks/check"
"$checks/check" "$repo_root/Native/TableScape/Resources/AssetPack/textures/1.png" | tee "$checks/Artifacts/terrain-clipping.log"
echo "Terrain clipping evidence: $checks/Artifacts"
