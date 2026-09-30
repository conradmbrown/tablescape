import copy,json,unittest,threading,urllib.request,urllib.error
from pathlib import Path
from http.server import ThreadingHTTPServer
from server import validate,handler
SCENE=Path(__file__).resolve().parents[1]/'data/scene.json'
class ProtocolTests(unittest.TestCase):
 def setUp(self):self.scene=json.loads(SCENE.read_text())
 def test_fixture(self):validate(self.scene)
 def test_bad_geometry(self):
  for field,value in [('vertices',[float('nan')]*9),('vertices',[1,2]),('triangles',[0,1,100000]),('triangles',[0,1,1.5]),('color',[1,0,float('inf')])]:
   with self.subTest(field=field,value=value):
    s=copy.deepcopy(self.scene);s['meshes'][0][field]=value
    with self.assertRaises(ValueError):validate(s)
 def test_bad_sequence(self):
  for seq in [-1,1.5,True,2**54]:
   s=copy.deepcopy(self.scene);s['sequence']=seq
   with self.assertRaises(ValueError):validate(s)
 def test_http_routes(self):
  server=ThreadingHTTPServer(('127.0.0.1',0),handler(SCENE));thread=threading.Thread(target=server.serve_forever);thread.start()
  try:
   base=f'http://127.0.0.1:{server.server_port}'
   with urllib.request.urlopen(base+'/v1/scene') as r:self.assertEqual(json.load(r)['session'],'fixture-v1')
   with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(base+'/../../etc/passwd')
   self.assertEqual(e.exception.code,404)
  finally:server.shutdown();server.server_close();thread.join()
if __name__=='__main__':unittest.main()
