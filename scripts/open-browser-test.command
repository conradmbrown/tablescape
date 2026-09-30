#!/bin/bash
# Double-click on the Mac, or run from Terminal. No Tailscale account is needed.
set -euo pipefail
: "${SCAPE_SSH_HOST:?Set SCAPE_SSH_HOST to your configured game-server SSH alias}"
SCAPE_HOST="$SCAPE_SSH_HOST"
SCAPE_PORT="${SCAPE_PORT:-8891}"
SCAPE_SOCKET="${TMPDIR:-/tmp}/scape-browser-${UID}.sock"
[[ "$SCAPE_PORT" =~ ^[0-9]+$ ]] || { echo 'SCAPE_PORT must be numeric.' >&2; exit 1; }
SSH_ARGS=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ServerAliveInterval=20 -o ServerAliveCountMax=3)
ssh "${SSH_ARGS[@]}" "$SCAPE_HOST" 'systemctl --user stop scape-unity-client 2>/dev/null || true; systemctl --user start scape-browser-stream; for attempt in $(seq 1 100); do if curl -fsS http://127.0.0.1:8891/ >/dev/null 2>&1; then exit 0; fi; sleep 1; done; systemctl --user status scape-browser-stream --no-pager; exit 1'
if ! ssh "${SSH_ARGS[@]}" -S "$SCAPE_SOCKET" -O check "$SCAPE_HOST" >/dev/null 2>&1; then
  ssh "${SSH_ARGS[@]}" -fNT -M -S "$SCAPE_SOCKET" -o ExitOnForwardFailure=yes \
    -L "127.0.0.1:$SCAPE_PORT:127.0.0.1:8891" "$SCAPE_HOST"
fi
curl --fail --silent --show-error "http://127.0.0.1:$SCAPE_PORT/" >/dev/null
printf 'Unity browser test ready: http://127.0.0.1:%s/\n' "$SCAPE_PORT"
if [[ "${SCAPE_NO_OPEN:-0}" != 1 ]]; then open "http://127.0.0.1:$SCAPE_PORT/"; fi
