#!/usr/bin/env python3
"""Copy separately supplied revision-274 feedback sheets into ignored local resources."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--content', type=Path, required=True)
a = p.parse_args()
target = root / 'Unity/Assets/Scape/Resources/Feedback'
entries = {e['path']: e for e in json.loads((root/'assets/UnityAssets.lock.json').read_text())['files']}
spec = importlib.util.spec_from_file_location('feedback_storage', root/'scripts/validate-storage.py')
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)
copies = []
for name in ('cross', 'hitmarks'):
    source = a.content / 'sprites' / (name + '.png')
    data = source.read_bytes()
    for filename in (name+'.png', name+'-source.bytes'):
        entry = entries['Scape/Resources/Feedback/'+filename]
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise SystemExit('Wrong upstream feedback sheet: ' + name)
        copies.append((source, target/filename))
storage.validate([str(root), *[str(dst) for _, dst in copies]])
target.mkdir(parents=True, exist_ok=True)
for source, destination in copies:
    if source.resolve() != destination.resolve():
        shutil.copyfile(source, destination)
print('Verified and copied original feedback sheets into ignored resources.')
