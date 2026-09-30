#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export PATH="$ROOT/runtime/node-v24.21.0-linux-x64/bin:$PATH"
cd "$ROOT/vendor/lostcity-engine2007"
exec node --import tsx src/index.ts
