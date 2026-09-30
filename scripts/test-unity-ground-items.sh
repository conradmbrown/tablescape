#!/usr/bin/env bash
set -euo pipefail
export ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
export SCAPE_LOOT_USER="unityqa$(python3 -c 'import secrets; print(secrets.token_hex(3)[:5])')"
fixture_dir="$ROOT/Saved/loot-fixtures"
config_dir="/run/user/$(id -u)/systemd/user/scape-playable274.service.d"
config_file="$config_dir/90-loot-test.conf"
[[ ! -e "$config_file" ]] || { echo 'A loot test is already configured.' >&2; exit 1; }
mkdir -p "$fixture_dir" "$config_dir"
printf '{"spawn":[3222,3218,0],"levels":{"0":70,"1":70,"2":70,"3":70},"items":[]}\n' > "$fixture_dir/$SCAPE_LOOT_USER.json"
cleanup(){ rm -f "$config_file" "$fixture_dir/$SCAPE_LOOT_USER.json"; systemctl --user daemon-reload; systemctl --user restart scape-playable274; }
trap cleanup EXIT
printf '[Service]\nEnvironment=SCAPE_TEST_FIXTURE_DIR=%s\n' "$fixture_dir" > "$config_file"
systemctl --user stop scape-browser-stream
systemctl --user daemon-reload
bash "$ROOT/scripts/install-unity-gateway.sh"
for attempt in {1..60}; do if curl -fsS http://127.0.0.1:8890/health >/dev/null 2>&1; then break; fi; sleep 1; done
curl -fsS http://127.0.0.1:8890/health
printf '\nGround-item test character: %s\n' "$SCAPE_LOOT_USER"
timeout 340 xvfb-run -a -s '-screen 0 1440x900x24' bash -c '
  "$ROOT/Builds/Linux/ScapeClient" -force-vulkan -screen-width 1440 -screen-height 900 --scape-loot-test --scape-test-user="$SCAPE_LOOT_USER" --scape-capture="$ROOT/Saved/loot-test" -logFile "$ROOT/Saved/unity-loot.log" > "$ROOT/Saved/unity-loot-stdout.log" 2>&1 &
  player_pid=$!; trap "kill $player_pid 2>/dev/null || true" EXIT
  python3 "$ROOT/scripts/focus-stream-window.py" || exit 1
  wait "$player_pid"
'
rg 'SCAPE_GROUND_ITEM|SCAPE_LOOT_|SCAPE_PARITY_' "$ROOT/Saved/unity-loot.log"
