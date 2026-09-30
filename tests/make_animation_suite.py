#!/usr/bin/env python3
"""Fresh gameplay cases across all 19 revision-274 skills, with rendered-pose checks."""
import json, subprocess, sys
from pathlib import Path
run=Path(sys.argv[1])
cases='attack,strength,defence,hitpoints,ranged,magic,prayer,woodcutting,firemaking,fishing,mining,cooking,smithing,crafting,fletching,herblore,agility,thieving,runecraft,fletching_logs,smithing_anvil'
subprocess.run([sys.executable,str(Path(__file__).with_name('make_skill_suite.py')),str(run),'--only',sys.argv[2] if len(sys.argv)>2 and sys.argv[2] else cases],check=True)
p=run/'suite.json';suite=json.loads(p.read_text())
for case in suite['cases']:
    for step in case['steps']:
        # The original scripts deliberately have no animation for feathering shafts
        # or identifying a herb. Exercise fletching's animated log-cutting path too.
        step['requireAnimation']=step.get('skill',-1)>=0 and case['name']!='fletching' and step['label']!='Identify guam'
        step['requireHeld']=step['requireAnimation'] and case['name'] in ('woodcutting','fishing','mining','crafting','smithing_anvil')
p.write_text(json.dumps(suite,indent=2))
