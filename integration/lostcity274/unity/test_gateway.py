"""Exercise a disposable character through the Unity gateway, no original client."""
import json,time,urllib.request,urllib.error
BASE='http://127.0.0.1:8890'
token=None

def call(route,method='GET',body=None,auth=True):
    headers={'Content-Type':'application/json'}
    if token and auth:headers['Authorization']='Bearer '+token
    req=urllib.request.Request(BASE+route,method=method,headers=headers,data=None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(req,timeout=15) as response:return json.load(response)
def tick():
    time.sleep(.7)
    return call('/v1/state')
try:
    health=call('/health');assert health['revision']==274
    try:call('/v1/state',auth=False);raise AssertionError('Unauthenticated state permitted')
    except urllib.error.HTTPError as e:assert e.code==401
    login=call('/v1/session','POST',{'startLumbridge':False,'username':'unityqa'});token=login['token']
    s=tick();assert not s.get('pending'),s
    assert s['player']['parts'] and s['locs'] and s['npcs']
    for widget in s['ui']:
        if widget['clientCode']==326:call('/v1/action','POST',{'kind':'appearance','id':widget['id']})
    s=tick();s=tick()
    before=(s['player']['x'],s['player']['z'])
    call('/v1/action','POST',{'kind':'move','x':before[0]-1,'z':before[1]})
    for _ in range(6):
        s=tick()
        if (s['player']['x'],s['player']['z'])!=before:break
    after=(s['player']['x'],s['player']['z']);assert after!=before,(before,after,s['messages'])
    terrain=call('/v1/terrain');assert terrain['revision']==274 and terrain['meshes']
    guide=next(n for n in s['npcs'] if n['name']=='RuneScape Guide')
    call('/v1/action','POST',{'kind':'npc','id':guide['id'],'op':1})
    for _ in range(8):
        s=tick()
        if any(w['button']==6 for w in s['ui']):break
    assert any(w['button']==6 for w in s['ui']),s['ui']
    print(json.dumps({'result':'passed','revision':274,'movement_before':before,'movement_after':after,'npc_dialogue':True,'terrain_batches':len(terrain['meshes']),'terrain_vertices':sum(len(m['vertices'])//3 for m in terrain['meshes']),'original_client_running':False}))
finally:
    if token:call('/v1/session','DELETE')
