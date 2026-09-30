#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
export ROOT
run="$ROOT/Saved/overlays"
mkdir -p "$run"
python3 "$ROOT/tests/make_skill_suite.py" "$run" --only cooks_assistant --fixtures "$ROOT/Saved/skill-fixtures"
python3 - "$run/suite.json" <<'PY'
import json,sys
p=sys.argv[1];s=json.load(open(p));s['cases'][0]['steps'][3]['expectOverlay']=True
open(p,'w').write(json.dumps(s,indent=2))
PY
mkdir -p "$run/results"
sha256sum "$ROOT/Builds/Linux/ScapeClient_Data/Managed/Assembly-CSharp.dll" "$ROOT/vendor/lostcity-engine274/src/scape/UnityOverlay.ts" > "$run/build-provenance.txt"
xvfb-run -a -s "-screen 0 1440x900x24" /bin/bash -c '
request="$ROOT/Saved/overlays/input.json"
timeout 280 "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-skills-test --scape-suite="$ROOT/Saved/overlays/suite.json" --scape-results="$ROOT/Saved/overlays/results" --scape-input-file="$request" -logFile "$ROOT/Saved/overlays/unity.log" &
player=$!
python3 "$ROOT/scripts/input-playtest-driver.py" "$request" "$player" > "$ROOT/Saved/overlays/input.log" &
driver=$!
wait "$player"; result=$?
wait "$driver"
exit "$result"
'
rg 'SCAPE_SKILL_RESULT|SCAPE_SKILLS_COMPLETE' "$run/unity.log"
