#!/usr/bin/env python3
"""A disposable protocol peer for testing the native Unity trade client.
The peer uses normal gameplay packets; no original client runs.
"""
import argparse,json,secrets,time,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('mode',choices=['generate','peer']);p.add_argument('run',type=Path);p.add_argument('--fixtures',type=Path);a=p.parse_args();a.run.mkdir(parents=True,exist_ok=True)
def step(label,kind,**kwargs):
 s=dict(label=label,kind=kind,skill=-1,style=-1,level=-1,expectedItemCount=-1,mainRoot=-1,timeout=50);s.update(kwargs);return s
if a.mode=='generate':
 names=['unityqa'+secrets.token_hex(3)[:5] for _ in range(2)]
 for i,name in enumerate(names):
  fixture=dict(spawn=[3093+i,3245,0],items=[dict(name='coins' if i==0 else 'bronze_sword',count=10 if i==0 else 1)])
  (a.fixtures/(name+'.json')).write_text(json.dumps(fixture))
 native,peer=names
 case=dict(name='native_trade',username=native,steps=[
  step('Open trade with disposable peer','target',target='player',name=peer,operation='Trade with',mainRoot=3323,retrySeconds=3),
  step('Offer five coins','invbutton',item=995,operation='Offer 5',product=995,inventoryComponent=3322,expectedItemCount=5),
  step('See the other player sword, not our coins','wait',product=1277,inventoryComponent=3416,expectedItemCount=1),
  step('Accept first stage','button',button=3420,mainRoot=3443),
  step('Confirm and receive sword','button',button=3546,product=1277,expectedItemCount=1),
  step('Verify remaining five coins','wait',product=995,expectedItemCount=5),
 ])
 (a.run/'suite.json').write_text(json.dumps(dict(cases=[case]),indent=2));(a.run/'peer.json').write_text(json.dumps(dict(native=native,peer=peer)))
 print('Generated disposable native trade pair');raise SystemExit
config=json.loads((a.run/'peer.json').read_text());token=None;done=False;offered=False;accepted=False;confirmed=False;last_request=0
base='http://127.0.0.1:8890'
def call(path,data=None,method=None):
 h={'Content-Type':'application/json'}
 if token:h['Authorization']='Bearer '+token
 req=urllib.request.Request(base+path,data=json.dumps(data).encode() if data is not None else None,headers=h,method=method)
 with urllib.request.urlopen(req,timeout=15) as r:return json.load(r)
def action(**kwargs):return call('/v1/action',kwargs)
try:
 token=call('/v1/session',dict(username=config['peer']))['token'];deadline=time.time()+160
 while time.time()<deadline:
  time.sleep(.65);s=call('/v1/state')
  if s.get('pending'):continue
  (a.run/'peer-ready').touch()
  target=next((v for v in s['players'] if v['name'].lower()==config['native']),None)
  if s['mainRoot']==3323:
   if not offered:
    item=next((i for i in s['inventory'] if i['id']==1277 and 'Offer 1' in i['buttons']),None)
    if item:action(kind='invbutton',id=item['id'],slot=item['slot'],component=item['component'],op=item['buttons'].index('Offer 1')+1);offered=True
   if offered and not accepted and any(i['component']==3416 and i['id']==995 and i['count']==5 for i in s['inventory']):
    (a.run/'peer-offers.json').write_text(json.dumps(s,indent=2));action(kind='button',id=3420);accepted=True
  elif s['mainRoot']==3443 and not confirmed:
   action(kind='button',id=3546);confirmed=True
  elif confirmed and any(i['component']==3214 and i['id']==995 and i['count']==5 for i in s['inventory']):
   assert not any(i['component']==3214 and i['id']==1277 for i in s['inventory'])
   (a.run/'peer-after.json').write_text(json.dumps(s,indent=2));print('TRADE_PEER_PASS received_five_coins=true sword_transferred=true',flush=True);done=True;break
  elif target and s['mainRoot']<0 and time.time()-last_request>3 and not accepted:
   action(kind='player',id=target['id'],op=target['ops'].index('Trade with')+1);last_request=time.time()
 if not done:raise RuntimeError('Trade peer timed out')
finally:
 if token:call('/v1/session',method='DELETE')
