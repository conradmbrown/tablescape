#!/usr/bin/env python3
"""Read-only scene service. Expose via SSH tunnel; never accepts game commands."""
import argparse,json,math,time
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
MAX_BYTES=16_000_000

def validate(s):
    def number(x,lo,hi):
        return type(x) in (int,float) and math.isfinite(x) and lo<=x<=hi
    if not isinstance(s,dict) or s.get('schema')!=1: raise ValueError('schema')
    if type(s.get('sequence')) is not int or not 0<=s['sequence']<=2**53-1: raise ValueError('sequence')
    if not isinstance(s.get('session'),str) or not 1<=len(s['session'])<=128: raise ValueError('session')
    if not isinstance(s.get('source'),str) or not 1<=len(s['source'])<=256: raise ValueError('source')
    if not isinstance(s.get('meshes'),list) or not 1<=len(s['meshes'])<=4096: raise ValueError('meshes')
    total=0
    for m in s['meshes']:
        if not isinstance(m,dict):raise ValueError('mesh')
        v=m.get('vertices');t=m.get('triangles');c=m.get('color')
        if not isinstance(v,list) or len(v)<9 or len(v)%3 or not all(number(x,-512,512) for x in v):raise ValueError('vertices')
        total+=len(v)
        if total>1_500_000:raise ValueError('vertex budget')
        if not isinstance(t,list) or len(t)<3 or len(t)%3 or not all(type(x) is int and 0<=x<len(v)//3 for x in t):raise ValueError('triangles')
        if not isinstance(c,list) or len(c)!=3 or not all(number(x,0,1) for x in c):raise ValueError('color')
    return s

def read_scene(path):
    with path.open('rb') as f:raw=f.read(MAX_BYTES+1)
    if len(raw)>MAX_BYTES:raise ValueError('size')
    validate(json.loads(raw));return raw

def handler(scene):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in ('/health','/v1/scene'):
                self.send_error(404);return
            try:
                raw=read_scene(scene)
                if self.path=='/health':
                    age=max(0,time.time()-scene.stat().st_mtime)
                    raw=json.dumps({'status':'ok' if age<5 else 'stale','age_seconds':round(age,2),'source':json.loads(raw)['source']}).encode()
            except (OSError,ValueError,TypeError):self.send_error(503,'No valid scene');return
            self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.send_header('Cache-Control','no-store');self.end_headers();self.wfile.write(raw)
    return Handler
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--scene',type=Path,required=True);p.add_argument('--port',type=int,default=8768);a=p.parse_args()
    read_scene(a.scene)
    ThreadingHTTPServer(('127.0.0.1',a.port),handler(a.scene)).serve_forever()
