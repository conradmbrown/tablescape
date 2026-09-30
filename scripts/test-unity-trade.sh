#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
run="${1:?Pass a generated trade suite directory}"
python3 "$ROOT/tests/native_trade_peer.py" peer "$run" > "$run/peer.log" 2>&1 &
peer=$!
trap 'kill "$peer" 2>/dev/null || true' EXIT
for ((i=0;i<40;i++)); do
  test ! -e "$run/peer-ready" || break
  kill -0 "$peer" 2>/dev/null || { cat "$run/peer.log"; exit 1; }
  sleep .5
done
set +e
bash "$ROOT/scripts/test-unity-skills.sh" "$run"
client_status=$?
wait "$peer"
peer_status=$?
cat "$run/peer.log"
test "$client_status" -eq 0 && test "$peer_status" -eq 0
