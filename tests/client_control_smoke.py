#!/usr/bin/env python3
"""Drive the actual Unity client over its local command interface, never the gateway."""
import importlib.util,json,pathlib,sys,time
root=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('control',root/'scripts/client-control.py');control=importlib.util.module_from_spec(spec);spec.loader.exec_module(control)
directory=pathlib.Path(sys.argv[1]);output=pathlib.Path(sys.argv[2]);output.mkdir(parents=True,exist_ok=True)
def call(command):return control.request(command,directory)
def snapshot():return call({'command':'state'})
def wait(label,predicate,seconds=40):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        try:s=snapshot()
        except (RuntimeError,FileNotFoundError):time.sleep(.2);continue
        if predicate(s):print('PASS',label,flush=True);return s
        time.sleep(.1)
    raise AssertionError(label)
s=wait('native client ready',lambda s:s['canAct'] and not s['state']['busy'] and len(s['nearby'])>20,120)
call({'command':'camera','yaw':0,'pitch':55,'distance':9})
if len(sys.argv)>3 and sys.argv[3]=='player-death':
    victim=next(t for t in s['nearby'] if t['kind']=='npc' and t['actor']['name']=='Man' and 'Attack' in t['actor']['ops'])
    call({'command':'act','key':victim['key'],'operation':'Attack'})
    frames=set();seen=False;captured=False;end=time.monotonic()+80;next_attempt=time.monotonic()+3
    while time.monotonic()<end:
        s=snapshot();player=next(t for t in s['nearby'] if t['key']=='player')
        if not seen and s['state']['player']['faceId']<0 and not s['state']['busy'] and time.monotonic()>next_attempt:
            victim=next(t for t in s['nearby'] if t['kind']=='npc' and t['actor']['name']=='Man' and 'Attack' in t['actor']['ops'])
            call({'command':'act','key':victim['key'],'operation':'Attack'});next_attempt=time.monotonic()+3
        if player['dying'] and player['sequence']==s['state']['player']['deathAnim']:
            seen=True;frames.add(player['frame'])
            if not captured and player['frame']>=5:
                (output/'player-death-capture.json').write_text(json.dumps(call({'command':'capture'})));captured=True
        if seen and s['state']['player']['hp']>0 and abs(s['state']['player']['x']-3222)<5 and abs(s['state']['player']['z']-3218)<5:break
        time.sleep(.05)
    assert seen and len(frames)>=3 and not player['dying'] and s['state']['player']['hp']>0,(seen,frames,player['dying'])
    (output/'PLAYER-DEATH.json').write_text(json.dumps({'pass':True,'observedFrames':sorted(frames),'respawn':s['state']['player']},indent=2))
    print('SCAPE_PLAYER_DEATH_PASSED frames='+str(sorted(frames)),flush=True)
    call({'command':'logout'});wait('native logout',lambda s:not s['connected'],20)
    sys.exit(0)
# Reject invalid/stale targets rather than report an action as gameplay success.
for command in [{'command':'act','key':'npc-not-present','operation':'Attack'}, {'command':'act','key':'player','operation':'Attack'}]:
    try:call(command);raise AssertionError('invalid action accepted')
    except RuntimeError:pass
print('PASS invalid targets rejected',flush=True)
weapon=next(i for i in s['state']['inventory'] if i['name']=='Rune scimitar')
call({'command':'action','action':{'kind':'inventory','id':weapon['id'],'slot':weapon['slot'],'component':weapon['component'],'op':next(i+1 for i,op in enumerate(weapon['ops']) if op=='Wield')}})
s=wait('native weapon equip',lambda s:any(i['id']==weapon['id'] and i['component']==1688 for i in s['state']['inventory']))
victim=next(t for t in s['nearby'] if t['kind']=='npc' and t['actor']['name']=='Man' and 'Attack' in t['actor']['ops'])
call({'command':'act','key':victim['key'],'operation':'Attack'})
trace=[];frames=set();sequence=-1;seen_death=False;captured=False;end=time.monotonic()+100
while time.monotonic()<end:
    s=snapshot()
    trace.append({'tick':s['state']['tick'],'player':{k:s['state']['player'].get(k) for k in ['x','z','hp','anim','animDeath']},'target':[{'sequence':t['sequence'],'frame':t['frame'],**{k:t['actor'].get(k) for k in ['id','name','x','z','hp','anim','animDeath','animEvent']}} for t in s['nearby'] if t['actor']['id']==victim['actor']['id'] and t['kind'] in ('npc','visual')]})
    for t in s['nearby']:
        if t['actor']['id']==victim['actor']['id'] and t['kind'] in ('npc','visual') and t['dying']:
            seen_death=True;sequence=t['sequence'];frames.add(t['frame'])
            if not captured and t['frame']>=3:
                capture=call({'command':'capture'});(output/'death-capture.json').write_text(json.dumps(capture));captured=True
    if s['completedDeaths']>0 and any(o['id']==526 for o in s['state']['objects']):break
    time.sleep(.05)
(output/'death-trace.json').write_text(json.dumps(trace,indent=2))
(output/'last-state.json').write_text(json.dumps(s,indent=2))
assert seen_death and len(frames)>=3 and s['completedDeaths']>0 and s['deathFramesRendered']>=3,(seen_death,frames,s['completedDeaths'])
print('PASS original death sequence',sequence,'observed frames',sorted(frames),'rendered frames',s['deathFramesRendered'],flush=True)
(output/'death-state.json').write_text(json.dumps(s,indent=2))
bones=next(t for t in s['nearby'] if t['kind']=='obj' and t['actor']['id']==526)
call({'command':'act','key':bones['key'],'operation':'Take'})
s=wait('bones picked up',lambda s:any(i['id']==526 for i in s['state']['inventory']))
# Exact nearby tree, real native target action, real server inventory/XP outcome.
tree=next(t for t in s['nearby'] if t['kind']=='loc' and t['actor']['name']=='Tree' and any('chop' in op.lower() for op in (t['actor'].get('ops') or []) if op))
op=next(op for op in tree['actor']['ops'] if op and 'chop' in op.lower());xp=s['state']['experience'][8]
call({'command':'act','key':tree['key'],'operation':'Chop-down'})
s=wait('tree chopped: logs and Woodcutting XP',lambda s:s['state']['experience'][8]>xp and any(i['id']==1511 for i in s['state']['inventory']),90)
(output/'chop-state.json').write_text(json.dumps(s,indent=2))
call({'command':'action','action':{'kind':'move','x':int(s['state']['player']['x']),'z':int(s['state']['player']['z'])}})
call({'command':'logout'});wait('native logout',lambda s:not s['connected'],20)
(output/'RESULTS.json').write_text(json.dumps({'pass':True,'deathSequence':sequence,'observedDeathFrames':sorted(frames),'completedDeaths':s['completedDeaths'],'renderedDeathFrames':s['deathFramesRendered'],'tree':tree['key'],'operation':op,'woodcuttingXpBefore':xp,'woodcuttingXpAfter':s['state']['experience'][8]},indent=2))
print('SCAPE_CLIENT_CONTROL_PASSED',flush=True)
