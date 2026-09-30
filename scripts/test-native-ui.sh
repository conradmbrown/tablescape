#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
root="$(cd "$(dirname "$0")/.." && pwd -P)"
base="$SCAPE_WORKSPACE"
export TMPDIR="$SCAPE_BUILD_ROOT/Temporary/"
scape_require_storage_path "$TMPDIR" "$base/Artifacts"
mkdir -p "$TMPDIR" "$base/Artifacts"
sim=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for k,a in json.load(sys.stdin)["devices"].items() if "xrOS" in k for d in a if d.get("isAvailable")]; ds.sort(key=lambda d:d["state"]!="Booted"); assert ds,"No visionOS Simulator"; print(ds[0]["udid"])')
curl -fsS --max-time 5 http://127.0.0.1:18890/health >/dev/null || { echo 'Start the private tunnel with run-native-simulator.sh first.' >&2; exit 1; }
xcodegen generate --spec "$root/Native/project.yml"
result="$base/Artifacts/NativeUI-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project "$root/Native/TableScape.xcodeproj" -scheme TableScape \
 -destination "platform=visionOS Simulator,id=$sim" -derivedDataPath "$SCAPE_BUILD_ROOT/DerivedData" \
 -clonedSourcePackagesDirPath "$SCAPE_BUILD_ROOT/Packages" -resultBundlePath "$result" \
 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- COMPILER_INDEX_STORE_ENABLE=NO CLANG_MODULE_CACHE_PATH="$SCAPE_BUILD_ROOT/ModuleCache" \
 test "$@" > "$base/Artifacts/ui-latest.log" 2>&1 || { tail -60 "$base/Artifacts/ui-latest.log"; exit 1; }
echo "Native UI passed: $result"
