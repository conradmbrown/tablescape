import http.server, json, threading, time, socket, sys, pathlib

lock = threading.Lock()
state = {'mode':'normal','sessions':{},'logins':[],'deletes':[],'actions':0,'tick':100,'lastBody':{},'redirectHits':0,'failedStates':0,'characters':{}}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def reply(self,status,obj):
        body = obj if isinstance(obj,bytes) else json.dumps(obj).encode()
        self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers()
        try:self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError):pass
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or b'{}')
        if self.path=='/__mode':
            with lock:
                state['mode']=body['mode']
                if body['mode']=='expire_all':state['sessions'].clear();state['mode']='normal'
            self.reply(200,{'ok':True});return
        if self.path=='/v1/session':
            with lock:
                token='token'+str(len(state['logins'])+1);state['logins'].append(body);username=body.get('username','QA');state['sessions'][token]=username;mode=state['mode']
                if body.get('startLumbridge',True) or username not in state['characters']:state['characters'][username]={'x':3222,'z':3218,'level':0}
            if mode=='delayed_login':time.sleep(1.5)
            self.reply(200,{'token':token,'revision':274});return
        if self.path=='/v1/action':
            with lock:
                state['actions']+=1;state['lastBody']=body;mode=state['mode']
                token=self.headers.get('Authorization','').removeprefix('Bearer ');username=state['sessions'].get(token)
                if username and body.get('kind')=='move':state['characters'][username].update(x=body['x'],z=body['z'])
                if mode=='action_lost':state['mode']='normal'
            if mode=='action_lost':
                self.close_connection=True
                try:self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:pass
                self.connection.close();return
            self.reply(202,{'queued':True,'tick':state['tick']});return
        self.reply(404,{})
    def do_DELETE(self):
        token=self.headers.get('Authorization','').removeprefix('Bearer ')
        with lock:state['sessions'].pop(token,None);state['deletes'].append(token)
        self.reply(200,{'closed':True})
    def do_GET(self):
        if self.path=='/redirect-sink':
            with lock:state['redirectHits']+=1
            self.reply(200,{});return
        if self.path=='/__stats':
            with lock:obj=json.loads(json.dumps(state))
            self.reply(200,obj);return
        if self.path=='/v1/state':
            token=self.headers.get('Authorization','').removeprefix('Bearer ')
            with lock:
                mode=state['mode'];valid=token in state['sessions']
                if mode=='expired_once':state['sessions'].pop(token,None);state['mode']='normal';valid=False
                if mode!='stale':state['tick']+=1
                tick=state['tick']-10 if mode=='stale' else state['tick']
                username=state['sessions'].get(token,'QA');position=dict(state['characters'].get(username,{'x':3222,'z':3218,'level':0}))
            if not valid:self.reply(401,{'error':'Session ended'});return
            if mode=='unavailable':
                with lock:state['failedStates']+=1
                self.reply(503,{'error':'Fixture temporarily unavailable'});return
            if mode=='redirect':
                self.send_response(302);self.send_header('Location','http://127.0.0.1:'+str(self.server.server_port)+'/redirect-sink');self.send_header('Content-Length','0');self.end_headers();return
            if mode=='malformed':self.reply(200,b'{');return
            self.reply(200,{'revision':274,'tick':tick,'level':position['level'],'player':{'id':1,'name':username,'x':position['x'],'z':position['z'],'hp':10,'maxHp':10},'inventory':[],'ui':[],'tabs':[-1,-1,-1,3213],'activeTab':3,'chatRoot':-1,'mainRoot':-1,'sideRoot':-1,'audio':[],'music':{},'npcs':[],'locs':[],'objects':[],'players':[]});return
        self.reply(404,{})

server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
pathlib.Path(sys.argv[1]).write_text('http://127.0.0.1:'+str(server.server_port))
try:server.serve_forever()
except KeyboardInterrupt:pass
finally:server.server_close()
