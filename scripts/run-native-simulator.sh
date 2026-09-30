#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd -P)/storage-env.sh"
root="$(cd "$(dirname "$0")/.." && pwd -P)"
base="$SCAPE_WORKSPACE"
export TMPDIR="$SCAPE_BUILD_ROOT/Temporary/"
scape_require_storage_path "$TMPDIR" "$base/Artifacts"
mkdir -p "$TMPDIR" "$base/Artifacts"
# Keep the game gateway bound to loopback. Reuse a healthy existing tunnel.
if ! curl -fsS --max-time 3 http://127.0.0.1:18890/health >/dev/null; then
  : "${SCAPE_SSH_HOST:?Set SCAPE_SSH_HOST to your configured game-server SSH alias}"
  ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -fN -L 127.0.0.1:18890:127.0.0.1:8890 "$SCAPE_SSH_HOST"
fi
curl -fsS --max-time 5 http://127.0.0.1:18890/health | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("revision")==274,"Unexpected gateway revision"'
sim=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for key,arr in json.load(sys.stdin)["devices"].items() if "xrOS" in key for d in arr if d.get("isAvailable")]; ds.sort(key=lambda d:d["state"]!="Booted"); assert ds,"Install a visionOS simulator in Xcode first"; print(ds[0]["udid"])')
app="$SCAPE_BUILD_ROOT/DerivedData/Build/Products/Debug-xrsimulator/TableScape.app"
[[ -d "$app" ]] || "$root/scripts/build-native-visionos.sh"
state=$(xcrun simctl list devices -j | python3 -c 'import json,sys; target=sys.argv[1]; print(next(d["state"] for a in json.load(sys.stdin)["devices"].values() for d in a if d["udid"]==target))' "$sim")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$sim"; fi
xcrun simctl bootstatus "$sim" -b
xcrun simctl install "$sim" "$app"
open -a Simulator
xcrun simctl launch --terminate-running-process "$sim" com.innoiso.tablescape.native --tablescape-connect "$@"
echo "Simulator: $sim. Drag native window bars to arrange the controls."
echo 'For immersive profiling, pass --tablescape-immersive --tablescape-profile.'
