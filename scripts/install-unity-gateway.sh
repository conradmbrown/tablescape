#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
ENGINE="$ROOT/vendor/lostcity-engine274"
test -f "$ENGINE/src/app.ts"
mkdir -p "$ENGINE/src/scape"
cp "$ROOT"/integration/lostcity274/unity/Unity*.ts "$ENGINE/src/scape/"
cp "$ROOT/integration/lostcity274/unity/Ground.ts" "$ENGINE/src/scape/"
cp "$ROOT/integration/lostcity274/unity/entry.ts" "$ENGINE/src/scape.ts"
python3 - "$ENGINE/data/config/world.json" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);config=json.loads(p.read_text());config.setdefault('node',{})['clientRoutefinder']=False;p.write_text(json.dumps(config,indent=2)+'\n')
PY
systemctl --user restart scape-playable274
