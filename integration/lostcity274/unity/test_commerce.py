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
 merchant=next(n for n in s['npcs'] if n['name']=='Shop keeper');act(kind='npc',id=merchant['id'],op=3)
 s=until(lambda s:any('Sell 1' in i['buttons'] for i in s['inventory']))
 sell=next(i for i in s['inventory'] if i['id'] in [841,1277,1205] and 'Sell 1' in i['buttons'])
 act(kind='invbutton',id=sell['id'],slot=sell['slot'],component=sell['component'],op=2)
 s=until(lambda s:item(s,995) is not None);passed('shop_sale_coins_received')
 buy=next(i for i in s['inventory'] if i['id']==1935 and 'Buy 1' in i['buttons']);act(kind='invbutton',id=buy['id'],slot=buy['slot'],component=buy['component'],op=2)
 s=until(lambda s:item(s,1935) is not None);passed('shop_purchase_item_received')
 act(kind='close')
 for x,z in [(3150,3235),(3100,3240),(3093,3244)]:
  act(kind='move',x=x,z=z,run=True);s=until(lambda s:abs(s['player']['x']-x)+abs(s['player']['z']-z)<3,75)
  print(json.dumps({'waypoint':[s['player']['x'],s['player']['z']]}),flush=True)
 print(json.dumps({'npcs':[(n['id'],n['name'],n['ops']) for n in s['npcs']],'locs':[(l['id'],l['name'],l['x'],l['z'],l['ops']) for l in s['locs'] if 'bank' in l['name'].lower()]}),flush=True)
 banker=next(n for n in s['npcs'] if n['name']=='Banker');act(kind='npc',id=banker['id'],op=banker['ops'].index('Bank')+1)
 s=until(lambda s:any('Deposit 1' in i['buttons'] for i in s['inventory']),30);passed('open_bank')
 deposit=next(i for i in s['inventory'] if i['id']==1935 and 'Deposit 1' in i['buttons']);act(kind='invbutton',id=deposit['id'],slot=deposit['slot'],component=deposit['component'],op=1)
 s=until(lambda s:any(i['id']==1935 and 'Withdraw 1' in i['buttons'] for i in s['inventory']));passed('bank_deposit')
 withdraw=next(i for i in s['inventory'] if i['id']==1935 and 'Withdraw 1' in i['buttons']);act(kind='invbutton',id=withdraw['id'],slot=withdraw['slot'],component=withdraw['component'],op=1)
 s=until(lambda s:item(s,1935) is not None);passed('bank_withdraw')
 print(json.dumps({'result':'passed','checks':checks}),flush=True)
finally:
 if T:call('/v1/session',method='DELETE')
