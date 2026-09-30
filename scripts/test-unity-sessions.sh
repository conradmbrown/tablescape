#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
mkdir -p "$ROOT/Saved/sessions"
python3 "$ROOT/tests/session_fault_proxy.py" > "$ROOT/Saved/sessions/proxy.log" 2>&1 &
proxy=$!
trap 'kill "$proxy" 2>/dev/null || true' EXIT
for attempt in {1..20}; do if curl --silent --fail http://127.0.0.1:18990/__test/stats >/dev/null; then break; fi; sleep .2; done
set +e
timeout 240 xvfb-run -a -s "-screen 0 1440x900x24" "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-session-test --scape-endpoint=http://127.0.0.1:18990 --scape-capture="$ROOT/Saved/sessions/client" -logFile "$ROOT/Saved/sessions/unity.log"
result=$?
curl --silent --fail http://127.0.0.1:18990/__test/stats > "$ROOT/Saved/sessions/request-counts.json"
rg 'SCAPE_(PARITY|SESSION|CONNECTION)' "$ROOT/Saved/sessions/unity.log"
exit "$result"
