exec(open('/dev/stdin').read()) if False else None
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
  try:T=call('/v1/session',{'startLumbridge':False,'username':'unitypar'})['token'];break
  except RuntimeError as e:
   if 'already logged in' not in str(e):raise
   time.sleep(1)
 s=until(lambda s:not s.get('pending'))
 print(json.dumps({'spells':[(w['id'],w['action'],w['target']) for w in s['ui'] if w['button']==2]}),flush=True)
 spell=next(w for w in s['ui'] if w['button']==2 and 'wind strike' in w['action'].lower())
 rat=min((n for n in s['npcs'] if n['name']=='Man' and n['x']>=3225),key=lambda n:abs(n['x']-s['player']['x'])+abs(n['z']-s['player']['z']))
 xp=s['experience'][6];act(kind='cast',target='npc',id=rat['id'],spell=spell['id'])
 s=until(lambda s:s['experience'][6]>xp,30);passed('wind_strike_magic_xp')
 act(kind='move',x=3216,z=3244,run=True)
 s=until(lambda s:abs(s['player']['x']-3216)+abs(s['player']['z']-3244)<3,40)
 print(json.dumps({'npcs':[(n['id'],n['name'],n['x'],n['z'],n['ops']) for n in s['npcs']],'doors':[(l['id'],l['x'],l['z'],l['ops']) for l in s['locs'] if 'Door' in l['name']]}),flush=True)
 merchant=next(n for n in s['npcs'] if n['name']=='Shop keeper')
 act(kind='npc',id=merchant['id'],op=merchant['ops'].index('Trade')+1)
 s=until(lambda s:any(any('Buy' in b for b in i['buttons']) for i in s['inventory']),35);passed('open_general_store')
 print(json.dumps({'shop':s['inventory'],'ui':[w for w in s['ui'] if w['root'] not in s['tabs']]}),flush=True)
finally:
 if T:call('/v1/session',method='DELETE')
