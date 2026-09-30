import urllib.request,json,time
B='http://127.0.0.1:8890';tokens=[]
def call(path,token=None,body=None,method=None):
 h={'Content-Type':'application/json'}
 if token:h['Authorization']='Bearer '+token
 with urllib.request.urlopen(urllib.request.Request(B+path,headers=h,data=None if body is None else json.dumps(body).encode(),method=method or ('POST' if body is not None else 'GET')),timeout=10) as r:return json.load(r)
try:
 for name in ['unitymulta','unitymultb']:tokens.append(call('/v1/session',body={'startLumbridge':False,'username':name})['token'])
 for _ in range(5):
  time.sleep(.7);states=[call('/v1/state',t) for t in tokens]
 assert all(len(s['players'])>=1 for s in states),[(s['player']['id'],s['players']) for s in states]
 assert states[0]['player']['id']!=states[1]['player']['id']
 print(json.dumps({'result':'passed','sessions':2,'mutual_visibility':True}))
finally:
 for t in tokens:call('/v1/session',t,method='DELETE')
