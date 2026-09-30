#!/usr/bin/env python3
"""Fail before writing if configured source/output escapes the mounted development disk."""
import os
import pathlib
import sys


def validate(extra=()):
    raw = os.environ.get("SCAPE_STORAGE_ROOT", "")
    storage = pathlib.Path(raw).resolve()
    if not raw or not pathlib.Path(raw).is_absolute() or storage == pathlib.Path(storage.anchor) or not storage.is_mount():
        raise ValueError("SCAPE_STORAGE_ROOT must name an existing mounted development disk, not the system root")
    workspace = os.environ.get("SCAPE_WORKSPACE", str(storage / "TableScape"))
    build = os.environ.get("SCAPE_BUILD_ROOT", str(pathlib.Path(workspace) / "Build"))
    source = os.environ.get("SCAPE_SOURCE_ROOT", str(pathlib.Path(__file__).resolve().parent.parent))
    for raw_path in [workspace, build, source, *extra]:
        path = pathlib.Path(raw_path)
        if not path.is_absolute() or not path.resolve().is_relative_to(storage):
            raise ValueError("Configured source/output must resolve inside SCAPE_STORAGE_ROOT")
    return pathlib.Path(build).resolve()


if __name__ == "__main__":
    try:
        validate(sys.argv[1:])
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
