"""Send real X11 input only to the isolated Xvfb display created for this test."""
import ctypes,json,os,sys,time
request,pid=sys.argv[1],int(sys.argv[2]);x=ctypes.CDLL('libX11.so.6');t=ctypes.CDLL('libXtst.so.6')
x.XOpenDisplay.argtypes=[ctypes.c_char_p];x.XOpenDisplay.restype=ctypes.c_void_p
x.XFlush.argtypes=[ctypes.c_void_p];x.XCloseDisplay.argtypes=[ctypes.c_void_p]
x.XStringToKeysym.argtypes=[ctypes.c_char_p];x.XStringToKeysym.restype=ctypes.c_ulong
x.XKeysymToKeycode.argtypes=[ctypes.c_void_p,ctypes.c_ulong];x.XKeysymToKeycode.restype=ctypes.c_uint
for name,args in [('XTestFakeMotionEvent',[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ulong]),('XTestFakeButtonEvent',[ctypes.c_void_p,ctypes.c_uint,ctypes.c_int,ctypes.c_ulong]),('XTestFakeKeyEvent',[ctypes.c_void_p,ctypes.c_uint,ctypes.c_int,ctypes.c_ulong])]:getattr(t,name).argtypes=args
if not os.environ.get('DISPLAY'):raise RuntimeError('Isolated test display required')
d=x.XOpenDisplay(None)
if not d:raise RuntimeError('Cannot open test display')
last=None;until=time.time()+290
try:
 while time.time()<until:
  try:os.kill(pid,0)
  except ProcessLookupError:break
  try:
   with open(request) as f:a=json.load(f)
  except (FileNotFoundError,json.JSONDecodeError):time.sleep(.05);continue
  if a['step']==last:time.sleep(.05);continue
  last=a['step'];print(json.dumps({'input':a}),flush=True)
  if a['kind']=='key':
   code=x.XKeysymToKeycode(d,x.XStringToKeysym(a['key'].encode()));t.XTestFakeKeyEvent(d,code,1,0);x.XFlush(d);time.sleep(.35);t.XTestFakeKeyEvent(d,code,0,0)
  else:
   t.XTestFakeMotionEvent(d,-1,a['x'],a['y'],0);x.XFlush(d);time.sleep(.04)
   if a['kind']=='move':continue
   button=3 if a['kind']=='right' else 1;t.XTestFakeButtonEvent(d,button,1,0);x.XFlush(d);time.sleep(.1);t.XTestFakeButtonEvent(d,button,0,0)
  x.XFlush(d)
finally:x.XCloseDisplay(d)
