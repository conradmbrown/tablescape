#!/usr/bin/env bash
# Source from launchers after ROOT is set; fail if configured storage is unavailable.
source "$ROOT/scripts/storage-env.sh"
export TMPDIR="$SCAPE_BUILD_ROOT/Unity/tmp"
export XDG_CACHE_HOME="$SCAPE_BUILD_ROOT/Unity/cache"
export UPM_CACHE_ROOT="$SCAPE_BUILD_ROOT/Unity/packages"
scape_require_storage_path "$TMPDIR" "$XDG_CACHE_HOME" "$UPM_CACHE_ROOT" "$ROOT/Saved"
mkdir -p "$TMPDIR" "$XDG_CACHE_HOME" "$UPM_CACHE_ROOT" "$ROOT/Saved"
