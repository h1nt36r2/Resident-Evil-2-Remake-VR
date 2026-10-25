-- Boundary fixture for the native grenade adapter, not proof of live RE2 semantics.
do
local oldsdk,oldthread,oldvr,oldvector,oldvector4=sdk,thread,vrmod,Vector3f,Vector4f
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
local draw=method('requestSetDraw',{'System.Boolean'},'System.Void')
local destroy=method('onDestroy',{},'System.Void')
local it={get_methods=function()return {draw}end}
local st={get_methods=function()return {destroy}end}
local gt={get_methods=function()return {genMethod,rigid}end}
local et={get_methods=function()return {use,fire,request}end}
local gen={get_type_definition=function()return {is_a=function(_,t)return t==gt end}end}
sdk={game_namespace=function(n)return prefix..n end,typeof=function(n)return n end,
 find_type_definition=function(n)if n:find('ThrowGrenadeGenerator',1,true)then return gt elseif n:find('survivor.Equipment',1,true)then return et elseif n:find('implement.Implement',1,true)then return it elseif n:find('weapon.shell.ThrowGrenade',1,true)then return st end end,
 hook=function(m,pre,post)hooks[m]={pre=pre,post=post}end,to_managed_object=function(x)return x end,
 to_int64=function(x)return x end,to_ptr=function(x)return x end,PreHookResult={SKIP_ORIGINAL='skip'}}
thread={get_hook_storage=function()return storage end}
local q={};function q:inverse()return self end;function q:normalized()return self end
setmetatable(q,{__mul=function(_,b)return b==q and q or b end})
local matrix={[3]={x=0,y=1,z=0},to_quat=function()return q end}
local transform={call=function(_,name)assert(name=='get_WorldMatrix');return matrix end}
local go={call=function(_,name)assert(name=='get_Transform');return transform end}
sdk.get_primary_camera=function()return transform end
vrmod={get_transform=function()return matrix end}
Vector3f={new=function(x,y,z)return {x=x,y=y,z=z}end}
Vector4f={new=function(x,y,z,w)return {x=x,y=y,z=z,w=w}end}
local count,spawns,debits,linear=3,0,0,nil
local body={call=function(_,name,index,value)if name=='setLinearVelocity'then linear=value end end}
local attached
local shellTransform={set_position=function(_,p)attached=p end}
local shellgo={call=function(_,name,t)
 if name=='get_Transform'then return shellTransform end
 assert(name=='getComponent(System.Type)')
 if t=='via.dynamics.RigidBodySet'then return body end
end}
local shell={call=function()return shellgo end}
local w={get_field=function(_,name)assert(name=='<ShellGenerator>k__BackingField');return gen end,
 call=function(_,name)assert(name=='get_GameObject');return go end}
local slot={call=function(_,name)if name=='get_IsSubWeapon'then return true elseif name=='get_Number'then return count end end}
local raw={safe=true,ranged=false,weapon=w,slot=slot,equipment={},wt=50,infinity=false}
function genMethod.execute()
 spawns=spawns+1;hooks[rigid].pre({[2]=gen,[3]=shellgo});hooks[rigid].post(nil)
end
function use.execute(_,wt,n)assert(wt==50 and n==1);debits=debits+1;count=count-1 end
local hidden=false
function draw.execute(_,value)hidden=not value end
local G=require('re2ivr.grenade_native');G.init();assert(G.ready,G.status)
local v=require('re2ivr.interaction').math.v
local i={active=true,head=v(0,1,0),rightTrigger=false,rightGrip=true,leftGrip=false,right=v(0,1,0),left=v(0,1,0),rightVelocity=v(2,1,-3),rightAngular=v(0,0,1)}
local function step()G.step(i,raw,true)end
G.begin_pickup(50);step();assert(G.gesture.stage=='held','Belt grip must transfer into held grenade without re-gripping')
assert(hooks[request].pre({[2]=raw.equipment})=='skip')
assert(hooks[fire].pre({[2]=raw.equipment,[3]=50})=='skip')
assert(hooks[fire].post(1)==0)
i.rightTrigger=true;step()
assert(spawns==1 and debits==1 and count==2 and G.live and hidden,'Prime must spawn and debit before release')
assert(linear.x==0 and linear.z==0,'Live shell must stay in hand')
for n=1,10 do step()end;assert(spawns==1 and debits==1)
i.right=v(1,1,0);step();assert(attached.x==1,'Live shell follows hand')
i.rightGrip=false;step()
assert(spawns==1 and debits==1 and not G.live and not hidden and linear.x==2 and linear.z==-3,G.status)
for n=1,20 do step()end;assert(spawns==1 and debits==1)
-- Native detonation in hand clears tether; it never generates a second shell.
i.rightGrip=true;i.rightTrigger=false;step();i.rightTrigger=true;step()
assert(spawns==2 and G.live)
hooks[destroy].pre({[2]=shell});hooks[destroy].post(nil);assert(not G.live)
i.rightGrip=false;step();assert(spawns==2 and debits==2)
-- Tracking loss detaches an already primed shell; it never refunds/restarts fuse.
i.rightGrip=true;i.rightTrigger=false;step();i.rightTrigger=true;step()
assert(spawns==3 and G.live)
i.active=false;step();assert(not G.live and hooks[request].pre({[2]=raw.equipment})==nil)
assert(spawns==3 and debits==3)
sdk,thread,vrmod,Vector3f,Vector4f=oldsdk,oldthread,oldvr,oldvector,oldvector4
print('PASS live native grenade: trigger spawn/debit, held shell follows hand, same-shell velocity release, lifecycle/standby without duplicate')
end
