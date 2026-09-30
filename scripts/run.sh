#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
exec /usr/local/bin/unreal-editor "$ROOT/ScapeTabletop.uproject" /Engine/Maps/Entry -game -windowed -ResX=1280 -ResY=800 -log "$@"
