#!/usr/bin/env bash
# Native Swift game checks; compiler, fixtures, reports and temporary files stay on the configured disk.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
build_root="$SCAPE_BUILD_ROOT"
mode="${1:-all}"
case "$mode" in all) modes=(fault live recipe melee magic trade commerce transition reorder persistence_seed persistence_resume persistence_expired) ;; persistence) modes=(persistence_seed persistence_resume persistence_expired) ;; fault|live|recipe|melee|magic|trade|commerce|transition|reorder) modes=("$mode") ;; *) echo 'Usage: test-native-core.sh [all|fault|live|recipe|melee|magic|trade|commerce|transition|reorder|persistence]' >&2; exit 2 ;; esac
checks="$build_root/CoreChecks"
scape_require_storage_path "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
mkdir -p "$checks/Artifacts" "$checks/ModuleCache" "$checks/Tmp"
checks="$(cd "$checks" && pwd -P)"
export TMPDIR="$checks/Tmp/"
export SCAPE_CORE_ARTIFACTS="$checks/Artifacts"
export SCAPE_GATEWAY="${SCAPE_GATEWAY:-http://127.0.0.1:18890}"
if [[ "$mode" == persistence || "$mode" == all ]]; then export SCAPE_QA_NAME="unityp$(python3 -c 'import uuid; print(uuid.uuid4().hex[:6])')"; fi
xcrun swiftc -module-cache-path "$checks/ModuleCache" "$repo_root"/Native/TableScape/Core/*.swift "$repo_root/Native/Tests/NativeCoreChecks.swift" -o "$checks/native-core-checks"
fault_pid=''
persistence_active=0
cleanup() {
  local cleanup_status=0
  if [[ "$persistence_active" == 1 ]]; then
    if ! "$checks/native-core-checks" persistence_cleanup; then cleanup_status=1; fi
    persistence_active=0
  fi
  if [[ -n "$fault_pid" ]]; then kill "$fault_pid" 2>/dev/null || true; wait "$fault_pid" 2>/dev/null || true; fi
  return "$cleanup_status"
}
trap cleanup EXIT INT TERM
for suite in "${modes[@]}"; do
  if [[ "$suite" == fault || "$suite" == persistence_seed ]]; then
    endpoint_file="$(mktemp "$checks/Artifacts/fault-endpoint-${suite}-XXXXXX")"
    python3 "$repo_root/Native/Tests/fault_server.py" "$endpoint_file" > "$checks/Artifacts/fault-server.log" 2>&1 &
    fault_pid=$!
    for attempt in {1..50}; do
      [[ -s "$endpoint_file" ]] && break
      kill -0 "$fault_pid" 2>/dev/null || { cat "$checks/Artifacts/fault-server.log" >&2; exit 1; }
      sleep 0.1
    done
    [[ -s "$endpoint_file" ]] || { echo 'The isolated fault server did not become ready.' >&2; exit 1; }
    export SCAPE_FAULT_ENDPOINT="$(cat "$endpoint_file")"
    if [[ "$suite" == persistence_seed ]]; then persistence_active=1; fi
  fi
  "$checks/native-core-checks" "$suite" 2>&1 | tee "$checks/Artifacts/$suite.log"
  if [[ "$suite" == fault || "$suite" == persistence_expired ]]; then cleanup; fault_pid=''; fi
done
echo "Native core evidence: $checks/Artifacts"
