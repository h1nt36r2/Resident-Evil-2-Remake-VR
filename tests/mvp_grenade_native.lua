-- Boundary fixture for the native grenade adapter, not proof of live RE2 semantics.
do
local oldsdk,oldthread,oldvr,oldvector=sdk,thread,vrmod,Vector3f
local hooks,storage={},{}
local function method(name,args,ret)
 local m={}
 function m:get_name()return name end
 function m:get_param_types()local p={};for _,x in ipairs(args)do local y=x;p[#p+1]={get_full_name=function()return y end}end;return p end
 function m:get_return_type()return {get_full_name=function()return ret end}end
 function m:call(obj,...)return self.execute(obj,...)end
 return m
end
local prefix='app.ropeway.'
local genMethod=method('generateShellProcess',{'via.mat4'},'System.Void')
local rigid=method('onRigidInstantiate',{'via.GameObject'},'System.Void')
local use=method('use',{prefix..'EquipmentDefine.WeaponType','System.Int32'},prefix..'inventory.ReduceResult')
local fire=method('executeFire',{prefix..'EquipmentDefine.WeaponType','System.Int32'},'System.Boolean')
local request=method('requestFire',{},'System.Void')
local gt={get_methods=function()return {genMethod,rigid}end}
local et={get_methods=function()return {use,fire,request}end}
local gen={get_type_definition=function()return {is_a=function(_,t)return t==gt end}end}
sdk={game_namespace=function(n)return prefix..n end,typeof=function(n)return n end,
 find_type_definition=function(n)if n:find('ThrowGrenadeGenerator',1,true)then return gt elseif n:find('survivor.Equipment',1,true)then return et end end,
 hook=function(m,pre,post)hooks[m]={pre=pre,post=post}end,to_managed_object=function(x)return x end,
 to_int64=function(x)return x end,to_ptr=function(x)return x end,PreHookResult={SKIP_ORIGINAL='skip'}}
thread={get_hook_storage=function()return storage end}
local q={};function q:inverse()return self end;function q:normalized()return self end
setmetatable(q,{__mul=function(_,b)return b==q and q or b end})
local matrix={to_quat=function()return q end}
local transform={call=function(_,name)assert(name=='get_WorldMatrix');return matrix end}
local go={call=function(_,name)assert(name=='get_Transform');return transform end}
sdk.get_primary_camera=function()return transform end
vrmod={get_transform=function()return matrix end}
Vector3f={new=function(x,y,z)return {x=x,y=y,z=z}end}
local count,spawns,debits,linear=3,0,0,nil
local body={call=function(_,name,index,value)if name=='setLinearVelocity'then linear=value end end}
local shellgo={call=function(_,name,t)assert(name=='getComponent(System.Type)');if t=='via.dynamics.RigidBodySet'then return body end end}
local w={get_field=function(_,name)assert(name=='<ShellGenerator>k__BackingField');return gen end,
 call=function(_,name)assert(name=='get_GameObject');return go end}
local slot={call=function(_,name)if name=='get_IsSubWeapon'then return true elseif name=='get_Number'then return count end end}
local raw={safe=true,ranged=false,weapon=w,slot=slot,equipment={},wt=50,infinity=false}
function genMethod.execute()
 spawns=spawns+1;hooks[rigid].pre({[2]=gen,[3]=shellgo});hooks[rigid].post(nil)
end
function use.execute(_,wt,n)assert(wt==50 and n==1);debits=debits+1;count=count-1 end
local G=require('re2ivr.grenade_native');G.init();assert(G.ready,G.status)
local v=require('re2ivr.interaction').math.v
local i={active=true,rightGrip=false,leftGrip=false,right=v(0,1,0),left=v(0,1,0),rightVelocity=v(2,1,-3),rightAngular=v(0,0,1)}
local function step()G.step(i,raw,true)end
step();i.rightGrip=true;step()
assert(hooks[request].pre({[2]=raw.equipment})=='skip')
assert(hooks[fire].pre({[2]=raw.equipment,[3]=50})=='skip')
assert(hooks[fire].post(1)==0)
i.leftGrip=true;step();i.left=v(.08,1,0);step();i.rightGrip=false;step()
assert(spawns==1 and debits==1 and count==2 and linear.x==2 and linear.z==-3,G.status)
for n=1,20 do step()end;assert(spawns==1 and debits==1)
-- Menu/tracking loss disables interception; it never throws from a stale pose.
i.active=false;step();assert(hooks[request].pre({[2]=raw.equipment})==nil)
assert(spawns==1)
sdk,thread,vrmod,Vector3f=oldsdk,oldthread,oldvr,oldvector
print('PASS actual grenade adapter with boundary doubles: attack suppression, one shell/debit, release velocity, standby')
end
