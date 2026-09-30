#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
export ROOT
mkdir -p "$ROOT/Saved/sidebar/results" "$ROOT/Saved/skill-fixtures"
export SCAPE_SIDEBAR_USER="$(python3 - "$ROOT" <<'PY'
import sys,json,secrets
from pathlib import Path
root=Path(sys.argv[1]);name='unityqa'+secrets.token_hex(3)[:5]
f={'spawn':[3222,3218,0],'levels':{'6':50,'5':45,'3':80,'1':60},'items':[{'name':n,'count':c} for n,c in [('bronze_sword',1),('bucket_empty',1),('airrune',100),('mindrune',100),('coins',10000)]]}
(root/'Saved/skill-fixtures'/f'{name}.json').write_text(json.dumps(f));print(name)
PY
)"
sha256sum "$ROOT/Builds/Linux/ScapeClient_Data/Managed/Assembly-CSharp.dll" "$ROOT/vendor/lostcity-engine274/src/scape/UnitySidebar.ts" > "$ROOT/Saved/sidebar/build-provenance.txt"
xvfb-run -a -s "-screen 0 1440x900x24" /bin/bash -c '
request="$ROOT/Saved/sidebar/input.json"
timeout 280 "$ROOT/Builds/Linux/ScapeClient" -screen-width 1440 -screen-height 900 --scape-sidebar-test --scape-test-user="$SCAPE_SIDEBAR_USER" --scape-capture="$ROOT/Saved/sidebar/results/native" --scape-input-file="$request" -logFile "$ROOT/Saved/sidebar/unity.log" &
player=$!
python3 "$ROOT/scripts/input-playtest-driver.py" "$request" "$player" > "$ROOT/Saved/sidebar/input.log" &
driver=$!
wait "$player"; result=$?
wait "$driver"
exit "$result"
'
rg 'SCAPE_(PARITY|SIDEBAR|MENU_ICON)' "$ROOT/Saved/sidebar/unity.log"
