#!/usr/bin/env python3
"""Loopback-only fault injection for the native session regression; never used by the desktop client."""
import http.server,json,time,urllib.request,urllib.error,threading
fault={'mode':'ok','until':0,'remaining':0};lock=threading.Lock();stats={'session_posts':0,'state_requests':0,'actions':0,'session_deletes':0}
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def reply(self,status,data):
  self.send_response(status);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(data)
 def do_GET(self):self.handle_request()
 def do_POST(self):self.handle_request()
 def do_DELETE(self):self.handle_request()
 def handle_request(self):
  data=self.rfile.read(int(self.headers.get('Content-Length',0)))
  if self.path=='/__test/fault':
   f=json.loads(data);fault.update(mode=f['mode'],until=time.monotonic()+f.get('seconds',60),remaining=f.get('remaining',10000));self.reply(200,b'{}');return
  if self.path=='/__test/stats':self.reply(200,json.dumps(stats).encode());return
  with lock:
   if self.path=='/v1/session' and self.command=='POST':stats['session_posts']+=1
   if self.path=='/v1/state':stats['state_requests']+=1
   if self.path=='/v1/action':stats['actions']+=1
   if self.path=='/v1/session' and self.command=='DELETE':stats['session_deletes']+=1
   active=time.monotonic()<fault['until'] and fault['remaining']>0
   mode=fault['mode'] if active else 'ok'
   if self.path=='/v1/state' and mode=='malformed':fault['remaining']-=1
  if self.path=='/v1/session' and self.command=='POST' and mode=='slow_login':time.sleep(3)
  if self.command!='DELETE' and mode=='offline':self.reply(503,b'{"error":"Injected temporary outage"}');return
  if self.path=='/v1/state' and mode=='malformed':self.reply(200,b'not-json');return
  headers={'Content-Type':'application/json'}
  if self.headers.get('Authorization'):headers['Authorization']=self.headers['Authorization']
  try:
   request=urllib.request.Request('http://127.0.0.1:8890'+self.path,data=data if self.command=='POST' else None,headers=headers,method=self.command)
   with urllib.request.urlopen(request,timeout=12) as response:self.reply(response.status,response.read())
  except urllib.error.HTTPError as e:self.reply(e.code,e.read())
  except (OSError,TimeoutError):self.reply(503,b'{"error":"Backend unavailable"}')
http.server.ThreadingHTTPServer(('127.0.0.1',18990),Handler).serve_forever()
