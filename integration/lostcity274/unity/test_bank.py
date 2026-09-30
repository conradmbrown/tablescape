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
 s=until(lambda s:not s.get('pending'));food=item(s,315)
 if food:held(food,1)
 for x,z in ([(3093,3244)] if s['player']['x']<3120 else [(3150,3235),(3100,3248),(3093,3244)]):
  if max(abs(s['player']['x']-x),abs(s['player']['z']-z))>100:continue
  act(kind='move',x=x,z=z,run=True);s=until(lambda s:abs(s['player']['x']-x)+abs(s['player']['z']-z)<3,85)
  print(json.dumps({'waypoint':[s['player']['x'],s['player']['z']]}),flush=True)
 booth=next(l for l in s['locs'] if l['id']==2213 and l['z']==3243);act(kind='loc',id=booth['id'],x=booth['x'],z=booth['z'],op=2)
 s=until(lambda s:any(any('Deposit' in b for b in i['buttons']) for i in s['inventory']),30);passed('open_bank_booth')
 deposit=next(i for i in s['inventory'] if any('Deposit' in b for b in i['buttons']));deposited_id=deposit['id'];act(kind='invbutton',id=deposit['id'],slot=deposit['slot'],component=deposit['component'],op=1)
 s=until(lambda s:any(i['id']==deposited_id and any('Withdraw' in b for b in i['buttons']) for i in s['inventory']));passed('bank_deposit')
 withdraw=next(i for i in s['inventory'] if i['id']==deposited_id and any('Withdraw' in b for b in i['buttons']));act(kind='invbutton',id=withdraw['id'],slot=withdraw['slot'],component=withdraw['component'],op=5)
 s=until(lambda s:s['countDialog']);passed('withdraw_x_dialog');act(kind='count',id=1)
 s=until(lambda s:item(s,deposited_id) is not None);passed('bank_withdraw')
 print(json.dumps({'result':'passed','checks':checks,'bank_buttons':withdraw['buttons']}),flush=True)
finally:
 if T:call('/v1/session',method='DELETE')
