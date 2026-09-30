#!/usr/bin/env bash
# Pure popup coordinator regression. Actual SwiftUI window behavior requires simulator XCTest.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
checks="$build_root/PopupRoutingChecks"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
export TMPDIR="$checks/Tmp/"
xcrun swiftc -swift-version 6 -D POPUP_ROUTING_CHECKS -module-cache-path "$checks/ModuleCache" \
  "$repo_root/Native/TableScape/UI/GamePopups.swift" \
  "$repo_root/Native/Tests/NativePopupRoutingChecks.swift" -o "$checks/check"
"$checks/check" | tee "$checks/Artifacts/routing.log"
echo "Popup routing evidence: $checks/Artifacts"
