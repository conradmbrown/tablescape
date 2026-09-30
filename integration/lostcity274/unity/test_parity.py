import urllib.request,json,time
T=None;B='http://127.0.0.1:8890';checks=[]
def call(path,body=None,method=None):
 h={'Content-Type':'application/json'}
 if T:h['Authorization']='Bearer '+T
 try:
  with urllib.request.urlopen(urllib.request.Request(B+path,data=None if body is None else json.dumps(body).encode(),headers=h,method=method or ('POST' if body is not None else 'GET')),timeout=15) as r:return json.load(r)
 except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode())
def state():
 time.sleep(.65);return call('/v1/state')
def act(**kw):return call('/v1/action',kw)
def until(fn,seconds=20):
 end=time.time()+seconds
 while time.time()<end:
  s=state()
  if fn(s):return s
 raise AssertionError({'timeout':seconds,'pos':s['player'],'messages':s['messages'][-4:]})
def item(s,id):return next((i for i in s['inventory'] if i['id']==id and i['component']==3214),None)
def held(i,op):act(kind='inventory',id=i['id'],slot=i['slot'],component=i['component'],op=op)
def passed(name):checks.append(name);print(json.dumps({'passed':name}),flush=True)
try:
 for attempt in range(80):
  try:T=call('/v1/session',{'startLumbridge':False,'username':'unity'+format(time.time_ns()%0xffffff,'06x')})['token'];break
  except RuntimeError as e:
   if 'already logged in' not in str(e):raise
   time.sleep(1)
 s=until(lambda s:not s.get('pending'))
 for w in s['ui']:
  if w['clientCode']==326:act(kind='appearance',id=w['id'])
 s=state();s=state()
 guide=next(n for n in s['npcs'] if n['name']=='RuneScape Guide');act(kind='npc',id=guide['id'],op=1)
 for _ in range(35):
  s=state()
  if s['player']['x']>3200:break
  resume=next((w for w in s['ui'] if w['button']==6),None);yes=next((w for w in s['ui'] if w['button']==1 and w['text'].startswith('Yes')),None)
  if resume:act(kind='resume',id=resume['id']);time.sleep(.7)
  elif yes:act(kind='button',id=yes['id']);time.sleep(.7)
 assert s['player']['x']>3200
 passed('tutorial_dialogue_to_lumbridge')
 seq=call('/v1/sequence/'+str(s['player']['ready']));assert seq['frames'] and any(f['transforms'] for f in seq['frames']);passed('original_animation_frames')
 i=item(s,1351) or item(s,1277);assert i;before=json.dumps(s['player']['parts']);held(i,2)
 s=until(lambda s:json.dumps(s['player']['parts'])!=before);passed('equip_changes_real_models')
 i=item(s,1925);held(i,5);s=until(lambda s:item(s,1925) is None and any(o['id']==1925 for o in s['objects']));o=next(o for o in s['objects'] if o['id']==1925)
 act(kind='obj',id=o['id'],x=o['x'],z=o['z'],op=3);s=until(lambda s:item(s,1925) is not None);passed('drop_and_ground_pickup')
 trees=[o for o in s['locs'] if o['name']=='Tree' and 'Chop down' in o['ops']]
 tree=min(trees,key=lambda o:abs(o['x']-s['player']['x'])+abs(o['z']-s['player']['z']))
 before=s['experience'][8];act(kind='loc',id=tree['id'],x=tree['x'],z=tree['z'],op=tree['ops'].index('Chop down')+1)
 s=until(lambda s:item(s,1511) is not None and s['experience'][8]>before,60);passed('woodcutting_logs_and_xp')
 logs=item(s,1511);tinder=item(s,590);before=s['experience'][11]
 act(kind='use',target='inventory',id=logs['id'],slot=logs['slot'],component=logs['component'],useId=tinder['id'],useSlot=tinder['slot'],useComponent=tinder['component'])
 s=until(lambda s:s['experience'][11]>before,45);passed('item_on_item_firemaking_xp')
 print(json.dumps({'result':'passed','checks':checks,'position':[s['player']['x'],s['player']['z']],'inventory':[i['name'] for i in s['inventory']]}),flush=True)
finally:
 if T:call('/v1/session',method='DELETE')
