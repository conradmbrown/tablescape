#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/unity-storage-env.sh"
exec "$ROOT/Builds/Linux/ScapeClient" -logFile "$ROOT/Saved/unity-player.log" "$@"
