#!/usr/bin/env python3
"""Summarize recorded native Unity runs without treating setup actions as passes."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('runs',type=Path,nargs='+');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
latest={};skill_evidence={};history=[]
names=['Attack','Defence','Strength','Hitpoints','Ranged','Prayer','Magic','Cooking','Woodcutting','Fletching','Fishing','Firemaking','Crafting','Smithing','Mining','Herblore','Agility','Thieving','','','Runecraft']
for run in a.runs:
 manifest=json.loads((run/'suite.json').read_text())
 report=json.loads((run/'results/results.json').read_text())
 for case in manifest['cases']:
  rows=[r for r in report['results'] if r['test']==case['name']]
  failures=[r for r in rows if r['status']=='FAIL']
  status='FAIL' if failures else 'PASS' if len(rows)==len(case['steps']) else 'INCOMPLETE'
  entry=dict(case=case['name'],run=run.name,status=status,assertions=sum(r['status']=='PASS' for r in rows),actions=sum(r['status']=='ACTION' for r in rows),failures=failures)
  latest[case['name']]=entry;history.append(entry)
  for r in rows:
   if r['status']=='PASS' and r['skill']>=0 and r['xpAfter']>r['xpBefore']:
    skill_evidence[names[r['skill']]]=dict(case=r['test'],step=r['step'],run=run.name,xp_delta=(r['xpAfter']-r['xpBefore'])/10)
a.output.mkdir(parents=True,exist_ok=True)
summary=dict(complete_game_parity=False,enabled_skills=19,skills_with_xp_evidence=len(skill_evidence),skill_evidence=skill_evidence,cases=list(latest.values()),history=history)
(a.output/'coverage-results.json').write_text(json.dumps(summary,indent=2)+'\n')
lines=['# Native Unity gameplay test results','',f'{len(skill_evidence)}/19 enabled skills have recorded server-confirmed XP gains. This is baseline coverage, not complete gameplay parity.','',
'Fixtures supply starting items, location, and levels to disposable accounts. Actions run in the native Unity player through normal Lost City handlers. Most actions are automated client calls; separate Lumbridge tests cover physical mouse/keyboard input.','',
'## Skills','','| Skill | Verified action | XP gained | Evidence run |','|---|---|---:|---|']
for name in names:
 if not name:continue
 e=skill_evidence.get(name);lines.append(f'| {name} | {e["step"] if e else "UNTESTED"} | {e["xp_delta"] if e else "—"} | {e["run"] if e else "—"} |')
lines+=['','## Latest result for each scenario','','| Scenario | Result | Verified assertions | Run |','|---|---|---:|---|']
for case,e in latest.items():lines.append(f'| {case} | {e["status"]} | {e["assertions"]} | {e["run"]} |')
lines+=['','Earlier failed attempts remain in the raw run artifacts and JSON history. A rerun does not erase them.','',
'## Limits','',
'Passing one action does not certify every recipe, level, quest, animation, weapon or spell. The coverage inventory in `tests/COVERAGE.md` lists outstanding work. Slayer and Farming are disabled in revision 274 and are not counted. Linux Unity results do not certify AVP/visionOS.','']
(a.output/'PLAYTEST_RESULTS.md').write_text('\n'.join(lines))
print(json.dumps(dict(skills=len(skill_evidence),scenarios=len(latest),passed=sum(e['status']=='PASS' for e in latest.values()),failed=[c for c,e in latest.items() if e['status']=='FAIL'],incomplete=[c for c,e in latest.items() if e['status']=='INCOMPLETE'])))
