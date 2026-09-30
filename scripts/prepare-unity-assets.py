#!/usr/bin/env python3
"""Copy real revision-274 assets into Unity with their numeric cache identities.
No original client is executed. Source files are read without modification.
"""
import argparse, hashlib, json, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--content',type=Path,required=True)
p.add_argument('--project',type=Path,required=True)
a=p.parse_args()
root=a.project/'Assets'/'LostCity274'
root.mkdir(parents=True,exist_ok=True)
if (a.content/'LICENSE').exists(): shutil.copyfile(a.content/'LICENSE',root/'LICENSE.txt')
manifest={'revision':274,'source':'LostCityRS/Content','assets':[],'unavailable':[]}
try:
    manifest['commit']=subprocess.check_output(['git','-c',f'safe.directory={a.content.resolve()}','-C',str(a.content),'rev-parse','HEAD'],text=True).strip()
except subprocess.CalledProcessError:
    raise SystemExit('Content source must have a verifiable git revision')
for kind,folder,extension in [('model','models','.ob2'),('texture','textures','.png')]:
    candidates={}
    for f in (a.content/folder).rglob('*'+extension):
        if f.stem in candidates: raise SystemExit(f'Duplicate source name: {f.stem}')
        candidates[f.stem]=f
    target=root/folder
    target.mkdir(exist_ok=True)
    for line in (a.content/'pack'/f'{kind}.pack').read_text().splitlines():
        if not line.strip() or line.lstrip().startswith('//'):continue
        identity,name=line.split('=',1)
        if not identity.isdecimal():raise SystemExit(f'Invalid cache ID: {identity}')
        if name not in candidates or candidates[name].stat().st_size == 0:
            manifest['unavailable'].append({'kind':kind,'id':int(identity),'name':name})
            continue
        source=candidates[name]
        destination=target/(identity+extension)
        shutil.copyfile(source,destination)
        manifest['assets'].append({'kind':kind,'id':int(identity),'name':name,'path':str(destination.relative_to(root)),'sha256':hashlib.sha256(destination.read_bytes()).hexdigest()})
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'revision':274,'models':sum(x['kind']=='model' for x in manifest['assets']),'textures':sum(x['kind']=='texture' for x in manifest['assets']),'commit':manifest['commit'],'unavailable_ids':len(manifest['unavailable'])}))
