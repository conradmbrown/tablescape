#!/usr/bin/env bash
set -euo pipefail
export ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
umask 077
export SCAPE_CONTROL_SCENARIO="${SCAPE_CONTROL_SCENARIO:-npc-death}"
export SCAPE_CONTROL_USER="unityqa$(python3 -c 'import secrets; print(secrets.token_hex(3)[:5])')"
fixture_dir="$ROOT/Saved/control-fixtures"
export SCAPE_CONTROL_DIR="$ROOT/Saved/control-test/$SCAPE_CONTROL_USER"
config_dir="/run/user/$(id -u)/systemd/user/scape-playable274.service.d"
config_file="$config_dir/91-control-test.conf"
[[ ! -e "$config_file" ]] || { echo 'A client-control test is already configured.' >&2; exit 1; }
mkdir -p "$fixture_dir" "$config_dir" "$SCAPE_CONTROL_DIR"
printf '{"spawn":[3222,3218,0],"levels":{"0":70,"1":70,"2":70,"3":70},"items":[{"name":"bronze_axe","count":1},{"name":"rune_scimitar","count":1}]}\n' > "$fixture_dir/$SCAPE_CONTROL_USER.json"
if [[ "$SCAPE_CONTROL_SCENARIO" == player-death ]]; then
  printf '{"spawn":[3222,3218,0],"currentLevels":{"3":1},"items":[]}\n' > "$fixture_dir/$SCAPE_CONTROL_USER.json"
fi
cleanup(){ rm -f "$config_file" "$fixture_dir/$SCAPE_CONTROL_USER.json"; systemctl --user daemon-reload; systemctl --user restart scape-playable274; }
trap cleanup EXIT
printf '[Service]\nEnvironment=SCAPE_TEST_FIXTURE_DIR=%s\n' "$fixture_dir" > "$config_file"
systemctl --user stop scape-browser-stream
systemctl --user daemon-reload
bash "$ROOT/scripts/install-unity-gateway.sh"
for attempt in {1..60}; do if curl -fsS http://127.0.0.1:8890/health >/dev/null 2>&1; then break; fi; sleep 1; done
curl -fsS http://127.0.0.1:8890/health
printf '\nNative-control test character: %s\n' "$SCAPE_CONTROL_USER"
timeout 340 xvfb-run -a -s '-screen 0 1440x900x24' bash -c '
  "$ROOT/Builds/Linux/ScapeClient" -force-vulkan -screen-width 1440 -screen-height 900 --scape-user="$SCAPE_CONTROL_USER" --scape-control-dir="$SCAPE_CONTROL_DIR" -logFile "$SCAPE_CONTROL_DIR/unity.log" > "$SCAPE_CONTROL_DIR/stdout.log" 2>&1 &
  player_pid=$!; trap "kill $player_pid 2>/dev/null || true; wait $player_pid 2>/dev/null || true" EXIT
  python3 "$ROOT/scripts/focus-stream-window.py" || exit 1
  python3 "$ROOT/tests/client_control_smoke.py" "$SCAPE_CONTROL_DIR" "$SCAPE_CONTROL_DIR/results" "$SCAPE_CONTROL_SCENARIO"
'
