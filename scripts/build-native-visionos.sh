#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
root="$(cd "$(dirname "$0")/.." && pwd -P)"
[[ -f "$root/Native/TableScape/Resources/AssetPack/manifest.json" ]] || { echo "Set up local game assets first: docs/ASSETS.md" >&2; exit 1; }
volume="$SCAPE_STORAGE_ROOT"
base="$SCAPE_WORKSPACE"
scape_require_storage_path "$SCAPE_BUILD_ROOT/DerivedData" "$SCAPE_BUILD_ROOT/ModuleCache" "$SCAPE_BUILD_ROOT/Temporary" "$SCAPE_BUILD_ROOT/Packages" "$base/Artifacts"
mkdir -p "$SCAPE_BUILD_ROOT/DerivedData" "$SCAPE_BUILD_ROOT/ModuleCache" "$SCAPE_BUILD_ROOT/Temporary" "$SCAPE_BUILD_ROOT/Packages" "$base/Artifacts"
free=$(df -Pk "$volume" | awk 'NR==2 {print $4}')
(( free > 8000000 )) || { echo 'At least 8 GB free space is required.' >&2; exit 1; }
export TMPDIR="$SCAPE_BUILD_ROOT/Temporary/"
export CLANG_MODULE_CACHE_PATH="$SCAPE_BUILD_ROOT/ModuleCache"
export SWIFT_MODULECACHE_PATH="$SCAPE_BUILD_ROOT/ModuleCache"
df -k / "$volume" > "$base/Artifacts/storage-before.txt"
[[ $(shasum -a 256 "$root/Native/TableScape/Resources/pack-manifest.json" | awk '{print $1}') == $(cat "$root/Native/AssetPack.lock") ]] || { echo 'Native asset manifest does not match AssetPack.lock.' >&2; exit 1; }
python3 "$root/scripts/native-assets.py" verify --output "$root/Native/TableScape/Resources"
cmp -s "$root/Native/TableScape/Rendering/TableScape.metal" "$root/Native/TableScape/Resources/TableScapeShaders.txt" || cp "$root/Native/TableScape/Rendering/TableScape.metal" "$root/Native/TableScape/Resources/TableScapeShaders.txt"
xcodegen generate --spec "$root/Native/project.yml"
sdk=xrsimulator
destination='generic/platform=visionOS Simulator'
signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-)
if [[ ${1:-simulator} == device ]]; then sdk=xros; destination='generic/platform=visionOS'; signing=(CODE_SIGNING_ALLOWED=NO); fi
xcodebuild -project "$root/Native/TableScape.xcodeproj" -scheme TableScape \
 -configuration Debug -sdk "$sdk" -destination "$destination" \
 -derivedDataPath "$SCAPE_BUILD_ROOT/DerivedData" -clonedSourcePackagesDirPath "$SCAPE_BUILD_ROOT/Packages" \
 "${signing[@]}" COMPILER_INDEX_STORE_ENABLE=NO \
 CLANG_MODULE_CACHE_PATH="$SCAPE_BUILD_ROOT/ModuleCache" \
 SWIFT_MODULE_CACHE_PATH="$SCAPE_BUILD_ROOT/ModuleCache" build > "$base/Artifacts/build-$sdk.log" 2>&1 || { tail -100 "$base/Artifacts/build-$sdk.log"; exit 1; }
df -k / "$volume" > "$base/Artifacts/storage-after.txt"
echo "Built TableScape ($sdk). Log: $base/Artifacts/build-$sdk.log"
