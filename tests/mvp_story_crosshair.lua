do
local saved={sdk=sdk,vrmod=vrmod,re=re,json=json,reframework=reframework,Vector4f=Vector4f}
local statics,utility=package.loaded['utility/Statics'],package.loaded['utility/RE2']
local Vec={};Vec.__index=Vec
local function v(x,y,z,w)return setmetatable({x=x,y=y,z=z,w=w or 0},Vec)end
function Vec.__add(a,b)return v(a.x+b.x,a.y+b.y,a.z+b.z)end
function Vec.__mul(a,b)return v(a.x*b,a.y*b,a.z*b)end
function Vec:normalized()
 local n=math.sqrt(self.x*self.x+self.y*self.y+self.z*self.z)
 if n==0 then return v(0,0,0)end
 return v(self.x/n,self.y/n,self.z/n)
end
function Vec:to_quat()return {to_mat4=function()return {[0]=v(1,0,0),[1]=v(0,1,0),[2]=v(0,0,1)}end}end
Vector4f={new=v}
local writes={}
local display={write_float=function(_,offset,value)writes[offset]=value end}
local source={origin=v(1,2,3),axis=v(0,0,1),joint=true,missing=false}
local joint={get_field=function()return nil end,call=function(_,n)assert(n=='get_AxisZ');return source.axis end}
local transform={call=function(_,n)
 assert(n=='get_WorldMatrix')
 return {[3]=source.origin,[2]=source.axis}
end}
local go={}
local weapon={
 get_field=function(_,n)
  if n=='<MuzzleJoint>k__BackingField' and source.joint then return {get_field=function()return joint end}end
  error('EMF must not need bullet parameters')
 end,
 call=function(_,n)assert(n=='get_GameObject');return go end}
-- Missing muzzle is a normal supported device case, not an SDK exception.
weapon.get_field=function(_,n)
 assert(n=='<MuzzleJoint>k__BackingField')
 if source.joint then return {get_field=function()return joint end}end
end
local state={weapon=weapon}
package.loaded['utility/Statics']={generate=function()return {}end}
package.loaded['utility/RE2']=state
local function method(fn)
 return setmetatable({call=function(_,self,...)return fn(self,...)end},{__call=function(_,...)return fn(...)end})
end
sdk={game_namespace=function(n)return n end,get_tdb_version=function()return 70 end,
 get_primary_camera=function()error('Head/camera aim forbidden')end,
 get_native_singleton=function()error('EMF bullet physics forbidden')end,
 create_instance=function()error('EMF bullet physics forbidden')end,
 find_type_definition=function(t)return {get_method=function(_,name)
  return method(function(obj,...)
   if name=='calc32' then return 0 end
   if name=='get_Transform' then if source.missing then return nil end; return transform end
   if name=='getJointByHash' then return nil end
   if name=='get_Position' then return source.origin end
   error('Unexpected method '..name)
  end)
 end}end}
local callbacks={}
reframework={get_game_name=function()return 're2'end}
json={load_file=function()return {default_crosshair_behavior=true}end,dump_file=function()end}
re={on_config_save=function()end,on_draw_ui=function()end,
 on_application_entry=function(n,fn)callbacks[n]=fn end,on_pre_gui_draw_element=function(fn)callbacks.gui=fn end}
local tracked=true
vrmod={is_hmd_active=function()return true end,is_using_controllers=function()return tracked end,
 unhide_crosshair=function()end}
local reticle={call=function(_,n)
 if n=='get_Name' then return 'GUI_Reticle' end
 if n=='get_Transform' then return display end
end}
local element={call=function()return reticle end}
local Story=require('re2ivr.story');Story.native=true
assert(loadfile('runtime/re2_vr_crosshair.lua'))()
local function check(x,y,z)
 writes={};callbacks.LockScene();assert(callbacks.gui(element)==true)
 assert(writes[0xB0]==x and writes[0xB4]==y and writes[0xB8]==z,'Reticle must follow weapon world pose')
end
check(1,2,5)
source.axis=v(1,0,0);check(3,2,3)
source.origin=v(4,5,6);check(6,5,6)
source.joint=false;check(6,5,6)
state.weapon=nil;callbacks.LockScene();assert(callbacks.gui(element)==false,'No stale gun marker')
state.weapon=weapon;source.missing=true;callbacks.LockScene();assert(callbacks.gui(element)==false)
source.missing=false;tracked=false;callbacks.LockScene();assert(callbacks.gui(element)==false)
tracked=true;source.axis=v(0,0,0);callbacks.LockScene();assert(callbacks.gui(element)==false)
Story.native=false
for k,value in pairs(saved)do _G[k]=value end
package.loaded['utility/Statics'],package.loaded['utility/RE2']=statics,utility
print('PASS Ada visual aim follows muzzle/device world pose; no HMD fallback, physics, target activation or stale reticle')
end
