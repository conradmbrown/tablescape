#!/usr/bin/env python3
"""Build/verify a deterministic revision-274 native pack; never mutates Unity sources.

Example invocation:
  python3 native-assets.py build --source /path/to/scape-tabletop \
    --output /path/to/asset-pack
The output contains AssetPack, Icons and Feedback folders suitable for Xcode folder resources.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import pathlib
import shutil
import struct
import sys

VERSION = 1
REVISION = 274

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def texture_dependencies(data: bytes) -> list[str]:
    if len(data) < 18:
        raise ValueError('truncated OB2')
    nv, nf, nt, types, priority, alpha, fl, vl, nx, ny, nz, ni = struct.unpack('>HHBBBBBBHHHH', data[-18:])
    cursor = nv + nf + (nf if priority == 255 else 0) + nf * fl
    modes = data[cursor:cursor+nf] if types else bytes(nf)
    cursor += nf * types + nv * vl + nf * alpha + ni
    colors = struct.unpack('>' + 'H' * nf, data[cursor:cursor+nf*2])
    end = cursor + nf*2 + nt*6 + nx + ny + nz
    if end != len(data)-18:
        raise ValueError('OB2 section mismatch')
    return [f'textures/{texture}.png' for texture in sorted({color for mode, color in zip(modes, colors) if mode & 2})]

def atomic_write(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == data:
        return
    temp = path.with_suffix(path.suffix + '.pending')
    temp.write_bytes(data)
    temp.replace(path)

def json_bytes(obj: object) -> bytes:
    return (json.dumps(obj, sort_keys=True, separators=(',', ':')) + '\n').encode()

def build(source: pathlib.Path, output: pathlib.Path) -> dict:
    original = source / 'Unity/Assets/LostCity274'
    if not (original/'manifest.json').is_file():
        raise ValueError('Local game assets are missing; follow docs/ASSETS.md')
    resources = source / 'Unity/Assets/Scape/Resources'
    original_manifest = json.loads((original / 'manifest.json').read_text())
    expected = {a['path']: a['sha256'] for a in original_manifest['assets']}
    entries = []
    for kind, directory, suffix in [('model', 'models', '.ob2'), ('texture', 'textures', '.png')]:
        for path in sorted((original/directory).glob('*'+suffix), key=lambda p:int(p.stem)):
            data = path.read_bytes()
            relative = f'{directory}/{path.name}'
            sha = digest(data)
            if relative in expected and expected[relative] != sha:
                raise ValueError(f'Original manifest mismatch: {relative}')
            dependencies = texture_dependencies(data) if kind == 'model' else []
            for dependency in dependencies:
                if not (original/dependency).is_file():
                    raise ValueError(f'Missing dependency: {relative} -> {dependency}')
            atomic_write(output/'AssetPack'/relative, data)
            entries.append(dict(kind=kind,id=int(path.stem),path=relative,sha256=sha,bytes=len(data),dependencies=dependencies))
    manifest = dict(version=VERSION, revision=REVISION, source='LostCityRS/Content + ScapeTabletop Unity', sourceManifestSHA256=digest((original/'manifest.json').read_bytes()), assets=entries)
    atomic_write(output/'AssetPack/manifest.json', json_bytes(manifest))
    atomic_write(output/'AssetPack/LICENSE.txt', (original/'LICENSE.txt').read_bytes())
    all_entries = []
    for folder in ('Icons','Feedback'):
        for path in sorted((resources/folder).glob('*.png')):
            data = path.read_bytes(); relative = f'{folder}/{path.name}'
            atomic_write(output/relative,data)
            all_entries.append(dict(path=relative,sha256=digest(data),bytes=len(data)))
    all_entries += [dict(path='AssetPack/'+e['path'],sha256=e['sha256'],bytes=e['bytes']) for e in entries]
    for relative in ('AssetPack/manifest.json','AssetPack/LICENSE.txt'):
        data = (output/relative).read_bytes(); all_entries.append(dict(path=relative,sha256=digest(data),bytes=len(data)))
    inventory = dict(version=VERSION,revision=REVISION,bytes=sum(e['bytes'] for e in all_entries),files=len(all_entries),assets=sorted(all_entries,key=lambda e:e['path']))
    atomic_write(output/'pack-manifest.json',json_bytes(inventory))
    return verify(output)

def verify(output: pathlib.Path) -> dict:
    inventory_bytes = (output/'pack-manifest.json').read_bytes()
    inventory = json.loads(inventory_bytes)
    for entry in inventory['assets']:
        relative = pathlib.PurePosixPath(entry['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Unsafe manifest path')
        data = (output/relative).read_bytes()
        if len(data) != entry['bytes'] or digest(data) != entry['sha256']:
            raise ValueError('Verification failed: '+entry['path'])
    return dict(version=VERSION,revision=REVISION,files=inventory['files'],bytes=inventory['bytes'],manifestSHA256=digest(inventory_bytes),verified=True)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('build','verify'))
    parser.add_argument('--source', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if args.command == 'build':
        if not args.source: parser.error('--source is required for build')
        source = args.source.resolve()
        if output == source or source in output.parents:
            parser.error('Pack must be outside original source checkout')
        result = build(source,output)
    else:
        result = verify(output)
    print(json.dumps(result,sort_keys=True))

if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(f'Asset pack failed: {error}', file=sys.stderr)
        sys.exit(1)
