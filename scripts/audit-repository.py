#!/usr/bin/env python3
"""Scan publishable paths for local files, workstation paths and common credential formats.

Scans tracked working files plus nonignored new files (not history). Extra private
terms can be supplied with --forbid without recording them in this repository.
This is a bounded content check, not a proof of third-party code provenance.
"""
import argparse
import pathlib
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--forbid', action='append', default=[], help='Additional private term; report paths only')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
rules = {
    'workstation home path': re.compile(rb'/(?:Users|home)/[A-Za-z0-9_.-]+/'),
    'fixed mounted-disk path': re.compile(rb'/(?:Volumes|mnt)/[A-Za-z0-9_.-]+(?:/|\b)'),
    'private key material': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'GitHub credential': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{60,})'),
    'AWS access key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
}
local_prefixes = ('Saved/', 'Private/', 'Artifacts/', 'Build/', 'node_modules/', 'vendor/', 'runtime/', 'Unity/Assets/LostCity274/', 'Unity/Assets/Scape/Resources/Icons/', 'Unity/Assets/Scape/Resources/Feedback/', 'Unity/Assets/Scape/Resources/Overlays/')
local_suffixes = ('.pem', '.key', '.p12', '.pfx', '.mobileprovision', '.xcresult', '.app')
findings = []
scanned = 0
for name in sorted(set(filter(None, names))):
    path = root / name
    if not path.is_file():
        continue  # Tracked deletions are not published in the next commit.
    if name.startswith(local_prefixes) or path.name in ('.env', '.DS_Store', 'PrivateConnection.json') or name.endswith(local_suffixes) or (path.name.startswith('.env.') and path.name != '.env.example'):
        findings.append((name, 'local/private/generated path'))
    data = path.read_bytes()
    scanned += 1
    for label, rule in rules.items():
        if rule.search(data):
            findings.append((name, label))
    for term in args.forbid:
        if term.casefold() in name.casefold() or term.encode().lower() in data.lower() or term.encode('utf-16-le').lower() in data.lower():
            findings.append((name, 'operator-supplied private term'))
for name, label in findings:
    print(f'{name}: {label}')
print(f'Scanned {scanned} publishable files; {len(findings)} findings. Git history is not included.')
sys.exit(bool(findings))
