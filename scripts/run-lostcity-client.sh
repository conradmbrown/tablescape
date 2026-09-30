#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
mkdir -p "$ROOT/data/client-home"
cd "$ROOT/vendor/lostcity-os1"
# Wait for the cache-loaded game listener, not merely the server process.
python3 - <<'READY'
import socket,time
until=time.monotonic()+90
while True:
    try:
        with socket.create_connection(('127.0.0.1',40001),timeout=1):break
    except OSError:
        if time.monotonic()>until:raise SystemExit('Lost City game listener did not become ready')
        time.sleep(.5)
READY
exec "$ROOT/runtime/jdk8u504-b01/bin/java" -Duser.home="$ROOT/data/client-home" -Dscape.output="$ROOT/data/lostcity-scene.json" "$@" -cp build/classes jagex3.client.Client
