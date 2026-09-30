#!/usr/bin/env bash
set -euo pipefail
: "${SCAPE_SSH_HOST:?Set SCAPE_SSH_HOST to your configured game-server SSH alias}"
: "${SCAPE_REMOTE_SOURCE:?Set SCAPE_REMOTE_SOURCE to the absolute server checkout path}"
remote=(python3 "$SCAPE_REMOTE_SOURCE/scripts/client-control.py" "$@")
printf -v command '%q ' "${remote[@]}"
exec ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$SCAPE_SSH_HOST" "$command"
