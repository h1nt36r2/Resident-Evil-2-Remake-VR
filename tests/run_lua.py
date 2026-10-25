"""Run pure Lua and native boundary fixtures. Requires LUA_DLL pointing to Lua 5.3."""
from pathlib import Path
import ctypes
import os

root=Path(__file__).resolve().parents[1]
lua=ctypes.CDLL(os.environ['LUA_DLL'])
ptr=ctypes.c_void_p
lua.luaL_newstate.restype=ptr
lua.luaL_openlibs.argtypes=[ptr]
lua.luaL_loadbufferx.argtypes=[ptr,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_char_p,ctypes.c_char_p]
lua.lua_pcallk.argtypes=[ptr,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_ssize_t,ptr]
lua.lua_tolstring.argtypes=[ptr,ctypes.c_int,ptr];lua.lua_tolstring.restype=ctypes.c_char_p
lua.lua_settop.argtypes=[ptr,ctypes.c_int];lua.lua_close.argtypes=[ptr]
s=lua.luaL_newstate();assert s;lua.luaL_openlibs(s)
def run(code,name,execute=True):
    data=code.encode('utf-8')
    result=lua.luaL_loadbufferx(s,data,len(data),name.encode(),None)
    if result==0 and execute:result=lua.lua_pcallk(s,0,0,0,0,None)
    if result:raise AssertionError(lua.lua_tolstring(s,-1,None).decode('utf-8','replace'))
    lua.lua_settop(s,0)
try:
    os.chdir(root)
    for p in (root/'runtime').rglob('*.lua'):run(p.read_text(encoding='utf-8'),p.name,False)
    run("package.path='runtime/?.lua;'..package.path",'path')
    for name in ('mvp_interaction.lua','mvp_weapon_families.lua','mvp_grenade.lua','mvp_grenade_native.lua','mvp_menu.lua','mvp_quickslots.lua','mvp_belt.lua','mvp_shortcuts.lua','mvp_menu_controls.lua','mvp_menu_controls_native.lua','mvp_story.lua','mvp_story_crosshair.lua','mvp_equip.lua'):
        run((root/'tests'/name).read_text(encoding='utf-8'),name)
    print('PASS fixtures; no RE2 or headset runtime used')
finally:
    lua.lua_close(s)
