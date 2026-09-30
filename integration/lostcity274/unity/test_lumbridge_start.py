"""Verify the requested default start and preservation of a returning test character."""
import json,time,urllib.request
BASE='http://127.0.0.1:8890';token=None
name='unity'+format(time.time_ns()%0xffffff,'06x')
def call(path,body=None,method=None):
 headers={'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 with urllib.request.urlopen(urllib.request.Request(BASE+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method),timeout=15) as r:return json.load(r)
def ready():
 for _ in range(30):
  time.sleep(.4);s=call('/v1/state')
  if not s.get('pending') and s['inventory']:return s
 raise AssertionError('No populated native session')
def inv(s):return sorted((i['component'],i['slot'],i['id'],i['count']) for i in s['inventory'])
try:
 token=call('/v1/session',{'username':name})['token'];first=ready();assert(first['player']['x'],first['player']['z'],first['level'])==(3222,3218,0)
 time.sleep(3);first=call('/v1/state');assert first['tutorialProgress']==1000, 'Queued tutorial callback reset progress'
 call('/v1/action',{'kind':'move','x':3225,'z':3218});time.sleep(3);moved=call('/v1/state');assert moved['player']['x']!=3222
 call('/v1/session',method='DELETE');token=None;time.sleep(3)
 token=call('/v1/session',{'username':name})['token'];again=ready();assert(again['player']['x'],again['player']['z'],again['level'])==(3222,3218,0)
 assert again['tutorialProgress']==1000;assert inv(first)==inv(again);assert first['experience']==again['experience'];assert first['baseLevels']==again['baseLevels']
 print(json.dumps({'result':'passed','default_lumbridge':True,'returning_lumbridge':True,'inventory_preserved':True,'experience_preserved':True,'base_levels_preserved':True}),flush=True)
finally:
 if token:call('/v1/session',method='DELETE')
