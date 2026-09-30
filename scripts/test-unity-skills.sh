#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
run="${1:?Pass the suite run directory}"
mkdir -p "$run/results"
sha256sum "$ROOT/Builds/Linux/ScapeClient" "$ROOT/Builds/Linux/ScapeClient_Data/Managed/Assembly-CSharp.dll" "$ROOT/vendor/lostcity-engine274/src/scape/UnityGateway.ts" > "$run/build-provenance.txt"
set +e
timeout 2200 xvfb-run -a -s "-screen 0 1440x900x24" "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-skills-test --scape-suite="$run/suite.json" --scape-results="$run/results" -logFile "$run/unity.log"
result=$?
rg 'SCAPE_SKILL_(BEGIN|RESULT)|SCAPE_SKILLS_COMPLETE' "$run/unity.log"
exit "$result"
