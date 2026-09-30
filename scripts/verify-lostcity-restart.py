import json,time,urllib.request,subprocess
url='http://127.0.0.1:8768'
def get(path):
 with urllib.request.urlopen(url+path,timeout=5) as r:return json.load(r)
old=get('/v1/scene')['session']
subprocess.run(['systemctl','--user','restart','scape-lostcity-engine','scape-lostcity-export','scape-lostcity-api'],check=True)
end=time.monotonic()+75
while time.monotonic()<end:
 try:
  health=get('/health')
  if health['status']=='ok':
   scene=get('/v1/scene')
   if scene['session']!=old:
    print(json.dumps({'restart':'passed','new_session':scene['session'],'sequence':scene['sequence'],'meshes':len(scene['meshes']),'health':health}),flush=True);break
 except Exception:pass
 time.sleep(1)
else:raise SystemExit('No fresh post-restart Lost City scene')
