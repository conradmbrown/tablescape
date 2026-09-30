#!/usr/bin/env bash
# Exact animation parity/timing and actual-GPU buffer retirement checks; no network or SDK downloads.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
suite="${1:-all}"
case "$suite" in all|animation|pool) ;; *) echo 'Usage: test-native-performance.sh [all|animation|pool]' >&2; exit 2;; esac
# Resolve symlinks before creating anything so an override cannot redirect writes to the system SSD.
checks="$build_root/PerformanceChecks"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp" "$checks/Pool"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp" "$checks/Pool"
export TMPDIR="$checks/Tmp/"
python3 - "$repo_root" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);fixtures=root/'Native/Tests/Fixtures'
for name,expected in json.loads((fixtures/'asset-fixture-manifest.json').read_bytes())['sha256'].items():
    if hashlib.sha256((fixtures/name).read_bytes()).hexdigest()!=expected:raise SystemExit('Fixture hash mismatch: '+name)
pack=root/'Native/TableScape/Resources/AssetPack'
manifest={entry['path']:entry for entry in json.loads((pack/'manifest.json').read_bytes())['assets']}
for model in [292,151,254,230,176,181,249,3081,3082,3091]:
    path=f'models/{model}.ob2';data=(pack/path).read_bytes();entry=manifest[path]
    if len(data)!=entry['bytes'] or hashlib.sha256(data).hexdigest()!=entry['sha256']:raise SystemExit('Model hash mismatch: '+path)
print('Original animation fixture and model hashes verified')
PY
if [[ "$suite" == all || "$suite" == animation ]]; then
  xcrun swiftc -O -swift-version 6 -module-cache-path "$checks/ModuleCache" \
    "$repo_root/Native/TableScape/Assets/NativeGeometry.swift" \
    "$repo_root/Native/TableScape/Assets/NativeAnimation.swift" \
    "$repo_root/Native/TableScape/Assets/NativeDefinitionLighting.swift" \
    "$repo_root/Native/TableScape/Assets/NativeAssetStore.swift" \
    "$repo_root/Native/Tests/Reference/NativeAnimatorBeforeOptimization.swift" \
    "$repo_root/Native/Tests/NativeAnimationPerformanceChecks.swift" -o "$checks/animation"
  "$checks/animation" "$repo_root" | tee "$checks/Artifacts/animation.log"
fi
if [[ "$suite" == all || "$suite" == pool ]]; then
  python3 - "$repo_root" "$checks/Pool" <<'PY'
import hashlib,pathlib,sys
root=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2])
renderer=(root/'Native/TableScape/Rendering/MetalRenderer.swift').read_text()
marker='@MainActor final class PreviewDelegate'
if renderer.count(marker)!=1:raise SystemExit('Renderer extraction marker changed; review the pool harness')
extracted=renderer[:renderer.index(marker)].replace('import CompositorServices\n','').replace('import ARKit\n','')
scene=(root/'Native/TableScape/Rendering/GameScene.swift').read_text()
start='final class RenderGeometry:';end='final class SceneExchange:'
if scene.count(start)!=1 or scene.count(end)!=1:raise SystemExit('Scene type extraction markers changed; review the pool harness')
types=scene[scene.index(start):scene.index(end)]
scaffold=(root/'Native/Tests/NativeMetalPoolChecks.swift').read_text()
(out/'ExactMetalPool.generated.swift').write_text(extracted+'\n'+types+'\n'+scaffold)
(out/'TableScapeShaders.txt').write_bytes((root/'Native/TableScape/Rendering/TableScape.metal').read_bytes())
print('Testing production renderer SHA256 '+hashlib.sha256(renderer.encode()).hexdigest())
PY
  xcrun swiftc -O -swift-version 6 -module-cache-path "$checks/ModuleCache" \
    "$repo_root/Native/TableScape/Assets/NativeGeometry.swift" \
    "$repo_root/Native/TableScape/Rendering/SceneMath.swift" \
    "$repo_root/Native/TableScape/Rendering/RenderMetrics.swift" \
    "$checks/Pool/ExactMetalPool.generated.swift" -o "$checks/Pool/check"
  "$checks/Pool/check" | tee "$checks/Artifacts/pool.log"
fi
echo "Native performance evidence: $checks/Artifacts"
