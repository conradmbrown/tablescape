#!/usr/bin/env bash
# Source from build/test launchers. All paths are explicitly configured by the operator.
: "${SCAPE_STORAGE_ROOT:?Set SCAPE_STORAGE_ROOT to the mounted development disk}"
export SCAPE_STORAGE_ROOT
export SCAPE_WORKSPACE="${SCAPE_WORKSPACE:-$SCAPE_STORAGE_ROOT/TableScape}"
export SCAPE_BUILD_ROOT="${SCAPE_BUILD_ROOT:-$SCAPE_WORKSPACE/Build}"
export SCAPE_SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 "$(dirname "${BASH_SOURCE[0]}")/validate-storage.py" || return 1
scape_require_storage_path() {
  python3 "$(dirname "${BASH_SOURCE[0]}")/validate-storage.py" "$@"
}
