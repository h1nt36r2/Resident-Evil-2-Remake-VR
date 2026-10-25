do
local oldsdk,oldvr,oldre,oldjson,oldframework=sdk,vrmod,re,json,reframework
local oldStatics,oldRE2=package.loaded['utility/Statics'],package.loaded['utility/RE2']
package.loaded['utility/Statics']={generate=function()return {}end}
package.loaded['utility/RE2']={}
sdk={find_type_definition=function()return {get_method=function()return {call=function()return 0 end}end}end,
 get_tdb_version=function()return 70 end,game_namespace=function(n)return n end,murmur_hash=function()return 0 end}
local callbacks={}
reframework={get_game_name=function()return 're2'end}
json={load_file=function()return {}end,dump_file=function()end}
re={on_config_save=function()end,on_draw_ui=function()end,
 on_application_entry=function(name,fn)callbacks[name]=fn end,on_pre_gui_draw_element=function(fn)callbacks.gui=fn end}
vrmod={is_hmd_active=function()error('Ada guard must bypass bullet-reticle logic before native calls')end}
local Story=require('re2ivr.story');Story.native=true
assert(loadfile('runtime/re2_vr_crosshair.lua'))()
callbacks.LockScene();assert(callbacks.gui({})==true)
Story.native=false
sdk,vrmod,re,json,reframework=oldsdk,oldvr,oldre,oldjson,oldframework
package.loaded['utility/Statics'],package.loaded['utility/RE2']=oldStatics,oldRE2
print('PASS shipped upstream crosshair override: Ada skips bullet raycasts and preserves native GUI reticle')
end
