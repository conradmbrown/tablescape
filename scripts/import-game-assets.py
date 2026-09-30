#!/usr/bin/env python3
"""Import a separately supplied converted Unity/Assets tree, or verify local assets.

Only paths in the committed hash lock are copied. No downloads, upstream builds,
server restarts, or Git operations are performed. Original asset rights are not
changed by this tool. See docs/ASSETS.md.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'assets/UnityAssets.lock.json'

def checked_entries(lock):
    entries = lock['files']
    seen = set()
    for entry in entries:
        path = Path(entry['path'])
        if path.is_absolute() or '..' in path.parts or str(path) in seen:
            raise ValueError('Unsafe or duplicate asset lock path')
        if not str(path).startswith(('LostCity274/', 'Scape/Resources/Icons/', 'Scape/Resources/Feedback/', 'Scape/Resources/Overlays/')):
            raise ValueError('Unexpected asset lock path')
        seen.add(str(path))
    if not entries:
        raise ValueError('Empty asset lock')
    return entries

def verify(source, entries):
    for entry in entries:
        path = source / entry['path']
        if not path.resolve().is_relative_to(source.resolve()):
            raise ValueError('Asset symlink escapes supplied directory: ' + entry['path'])
        if not path.is_file():
            raise ValueError('Missing asset: ' + entry['path'])
        data = path.read_bytes()
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Asset hash mismatch: ' + entry['path'])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--from-unity-assets', type=Path, help='Path to separately converted Unity/Assets')
    mode.add_argument('--verify', action='store_true', help='Verify this checkout without copying')
    args = parser.parse_args()
    target = ROOT / 'Unity/Assets'
    entries = checked_entries(json.loads(LOCK.read_text()))
    source = args.from_unity_assets.resolve() if args.from_unity_assets else target
    # Verify the entire source before any writes; incomplete exports never partly install.
    verify(source, entries)
    if args.from_unity_assets:
        spec = importlib.util.spec_from_file_location('asset_storage', ROOT / 'scripts/validate-storage.py')
        storage = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(storage)
        storage.validate([str(ROOT), str(target), *[str(target/e['path']) for e in entries]])
        for entry in entries:
            src, dst = source / entry['path'], target / entry['path']
            if src.resolve() == dst.resolve():
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.exists() and hashlib.sha256(dst.read_bytes()).hexdigest() == entry['sha256']:
                continue
            # Storage validation above also follows pre-existing destination symlinks.
            pending = dst.with_name(dst.name + '.import-pending')
            storage.validate([str(pending)])
            shutil.copyfile(src, pending)
            pending.replace(dst)
        verify(target, entries)
    print(f'Verified {len(entries)} local asset files; no assets added to Git.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(f'Asset setup failed: {error}', file=sys.stderr)
        sys.exit(1)
