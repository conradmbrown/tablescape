#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
mkdir -p "$ROOT/Saved/media"
name="$(python3 "$ROOT/tests/make_media_fixture.py" "$ROOT")"
sha256sum "$ROOT/Builds/Linux/ScapeClient_Data/Managed/Assembly-CSharp.dll" "$ROOT/vendor/lostcity-engine274/src/scape/UnityEffects.ts" > "$ROOT/Saved/media/build-provenance.txt"
set +e
timeout 330 xvfb-run -a -s "-screen 0 1440x900x24" "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-media-test --scape-test-user="$name" --scape-capture="$ROOT/Saved/media/native" -logFile "$ROOT/Saved/media/unity.log"
result=$?
rg 'SCAPE_(MEDIA|PARITY|AUDIO|MUSIC|EFFECT)' "$ROOT/Saved/media/unity.log"
exit "$result"
