"""Give the Unity-only virtual display focus without a desktop manager."""
import ctypes
import os
import time

x11 = ctypes.CDLL("libX11.so.6")
Pointer, Window = ctypes.c_void_p, ctypes.c_ulong
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XOpenDisplay.restype = Pointer
x11.XDefaultRootWindow.argtypes = [Pointer]
x11.XDefaultRootWindow.restype = Window
x11.XQueryTree.argtypes = [Pointer, Window, ctypes.POINTER(Window),
                         ctypes.POINTER(Window), ctypes.POINTER(ctypes.POINTER(Window)),
                         ctypes.POINTER(ctypes.c_uint)]
x11.XFetchName.argtypes = [Pointer, Window, ctypes.POINTER(ctypes.c_char_p)]
x11.XSetInputFocus.argtypes = [Pointer, Window, ctypes.c_int, ctypes.c_ulong]
x11.XMapRaised.argtypes = [Pointer, Window]
x11.XFlush.argtypes = [Pointer]
x11.XFree.argtypes = [Pointer]
x11.XCloseDisplay.argtypes = [Pointer]

display = x11.XOpenDisplay(os.environ["DISPLAY"].encode())
if not display:
    raise SystemExit("Cannot open dedicated stream display")
try:
    root = x11.XDefaultRootWindow(display)
    for attempt in range(150):
        returned_root, parent = Window(), Window()
        children, count = ctypes.POINTER(Window)(), ctypes.c_uint()
        x11.XQueryTree(display, root, ctypes.byref(returned_root), ctypes.byref(parent),
                      ctypes.byref(children), ctypes.byref(count))
        match = None
        for index in range(count.value):
            name = ctypes.c_char_p()
            x11.XFetchName(display, children[index], ctypes.byref(name))
            if name.value and b"Lost City" in name.value:
                match = children[index]
            if name:
                x11.XFree(name)
        if children:
            x11.XFree(children)
        if match:
            x11.XMapRaised(display, match)
            x11.XSetInputFocus(display, match, 2, 0)
            x11.XFlush(display)
            print("Focused native Unity stream window", flush=True)
            break
        time.sleep(0.2)
    else:
        raise SystemExit("Native Unity window did not appear")
finally:
    x11.XCloseDisplay(display)
