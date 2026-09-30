#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
run="${1:-$ROOT/Saved/skill-animations-$(date +%Y%m%d-%H%M%S)}"
python3 "$ROOT/tests/make_animation_suite.py" "$run" "${2:-}"
config_dir="/run/user/$(id -u)/systemd/user/scape-playable274.service.d"
config_file="$config_dir/93-skill-animation-validation.conf"
[[ ! -e "$config_file" ]] || { echo 'Animation QA is already configured' >&2; exit 1; }
mkdir -p "$config_dir"
cleanup(){ rm -f "$config_file"; systemctl --user daemon-reload; systemctl --user restart scape-playable274; systemctl --user start scape-browser-stream; }
trap cleanup EXIT
printf '[Service]\nEnvironment=SCAPE_TEST_FIXTURE_DIR=%s\n' "$run/fixtures" > "$config_file"
systemctl --user stop scape-browser-stream
systemctl --user daemon-reload
bash "$ROOT/scripts/install-unity-gateway.sh"
for attempt in {1..60}; do if curl -fsS http://127.0.0.1:8890/health >/dev/null 2>&1; then break; fi; sleep 1; done
systemctl --user start scape-browser-stream
bash "$ROOT/scripts/test-unity-skills.sh" "$run"
