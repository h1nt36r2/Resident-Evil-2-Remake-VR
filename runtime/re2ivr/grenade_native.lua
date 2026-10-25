-- Generate ONE native live grenade on trigger; native fuse/damage remain game-owned.
-- Releasing grip releases that SAME shell; never respawn or charge it twice.
local G={status='not initialized',ready=false,locked=false}
local gesture=require('re2ivr.grenade').new();G.gesture=gesture
local generatorType,generate,use,draw,raw,generator,pose,rotation
local active=false
local pending
local function unique(t,name,args,ret)
 local found
 for _,m in ipairs(t and t:get_methods() or {})do
  if m:get_name()==name and (not ret or m:get_return_type():get_full_name()==ret)then
   local p=m:get_param_types();local same=#p==#args
   for i,a in ipairs(args)do if not p[i] or p[i]:get_full_name()~=a then same=false end end
   if same then assert(not found,'Ambiguous '..name);found=m end
  end
 end
 return assert(found,'Missing grenade contract: '..name)
end
local function component(go,name)return go:call('getComponent(System.Type)',sdk.typeof(name))end
local function zero()return Vector3f.new(0,0,0)end
local function velocity(body,v,a)
 body:call('setLinearVelocity',0,v)
 body:call('setAngularVelocity',0,a)
end
local function restore(current)
 if G.hidden and current and G.hidden==current.weapon then
  pcall(function()draw:call(current.weapon,true)end);G.hidden=nil
 end
end
local function hand(i)
 local camera=assert(sdk.get_primary_camera(),'No camera'):call('get_WorldMatrix')
 rotation=(camera:to_quat()*vrmod:get_transform(0):to_quat():inverse()):normalized()
 local delta=rotation*Vector3f.new(i.right.x-i.head.x,i.right.y-i.head.y,i.right.z-i.head.z)
 local origin=camera[3]
 return Vector4f.new(origin.x+delta.x,origin.y+delta.y,origin.z+delta.z,1)
end
local function release_vectors(i)
 local v,a=i.rightVelocity,i.rightAngular
 assert(v and a and rotation,'Release tracking unavailable')
 local speed=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
 assert(speed==speed and speed<=20,'Invalid release velocity')
 for _,n in ipairs({a.x,a.y,a.z})do assert(n==n and math.abs(n)<1000,'Invalid angular velocity')end
 return rotation*Vector3f.new(v.x,v.y,v.z),rotation*Vector3f.new(a.x,a.y,a.z)
end
function G.init()
 local ok,why=pcall(function()
  generatorType=assert(sdk.find_type_definition(sdk.game_namespace('weapon.generator.ThrowGrenadeGenerator')))
  generate=unique(generatorType,'generateShellProcess',{'via.mat4'})
  local eq=sdk.find_type_definition(sdk.game_namespace('survivor.Equipment'))
  use=unique(eq,'use',{sdk.game_namespace('EquipmentDefine.WeaponType'),'System.Int32'},sdk.game_namespace('inventory.ReduceResult'))
  draw=unique(sdk.find_type_definition(sdk.game_namespace('implement.Implement')),'requestSetDraw',{'System.Boolean'},'System.Void')
  local fire=unique(eq,'executeFire',{sdk.game_namespace('EquipmentDefine.WeaponType'),'System.Int32'},'System.Boolean')
  local request=unique(eq,'requestFire',{},'System.Void')
  sdk.hook(request,function(a)
   if active and raw and raw.safe and sdk.to_managed_object(a[2])==raw.equipment then return sdk.PreHookResult.SKIP_ORIGINAL end
  end,function(ret)return ret end)
  sdk.hook(fire,function(a)
   local block=active and raw and raw.safe and sdk.to_managed_object(a[2])==raw.equipment and (G.is_live() or sdk.to_int64(a[3])==raw.wt)
   thread.get_hook_storage().re2ivrGrenadeBlocked=block
   if block then return sdk.PreHookResult.SKIP_ORIGINAL end
  end,function(ret)
   if thread.get_hook_storage().re2ivrGrenadeBlocked then return sdk.to_ptr(0)end
   return ret
  end)
  local rigid
  for _,m in ipairs(generatorType:get_methods())do
   if m:get_name()=='onRigidInstantiate' and #m:get_param_types()==1 then assert(not rigid);rigid=m end
  end
  assert(rigid,'Missing onRigidInstantiate callback')
  sdk.hook(rigid,function(a)
   local p=pending;thread.get_hook_storage().re2ivrGrenadeBody=nil
   if p and os.clock()<=p.expires and sdk.to_managed_object(a[2])==p.generator then
    pending=nil;p.go=sdk.to_managed_object(a[3])
    thread.get_hook_storage().re2ivrGrenadeBody=p
   end
  end,function(ret)
   local p=thread.get_hook_storage().re2ivrGrenadeBody
   if p and p.go then
    local applied,errorText=pcall(function()
     p.body=assert(component(p.go,'via.dynamics.RigidBodySet'),'No grenade rigid body')
     p.transform=assert(p.go:call('get_Transform'),'No grenade transform')
     -- Validate the documented transform setter before retaining a live shell.
     assert(p.transform.set_position,'No world-position setter')
     p.transform:set_position(p.position)
     if p.release then velocity(p.body,p.release.v,p.release.a)
     else velocity(p.body,zero(),zero());G.live=p end
    end)
    if not applied then G.locked=true;G.status='Live grenade attachment failed: '..tostring(errorText)end
   end
   return ret
  end)
  -- Observe verified lifecycle methods when available; never intercept detonation.
  local shell=sdk.find_type_definition(sdk.game_namespace('weapon.shell.ThrowGrenade'))
  for _,m in ipairs(shell and shell:get_methods() or {})do
   if (m:get_name()=='onDestroy' or m:get_name()=='onDispose') and #m:get_param_types()==0 then
    sdk.hook(m,function(a)
     local obj=sdk.to_managed_object(a[2])
     if G.live then
      local ok,go=pcall(function()return obj:call('get_GameObject')end)
      if ok and go==G.live.go then G.live=nil;gesture:reset();G.status='Native grenade lifecycle ended' end
     end
    end,function(ret)return ret end)
   end
  end
 end)
 G.ready=ok;G.status=ok and 'Select pouch icon -> LEFT grip -> RIGHT trigger -> release LEFT grip' or tostring(why)
end
function G.stop()
 -- A primed shell is never refunded, deleted, re-created or given a fresh fuse.
 -- Detach at its last position on tracking/menu loss; native gravity/fuse continue.
 active=false;raw=nil;generator=nil;pose=nil;pending=nil;G.live=nil;gesture:reset()
end
function G.reset_session()
 G.stop();G.locked=false;G.pickup=nil;G.hidden=nil;G.lastHold=true
 if G.ready then G.status='New scene: grenade interaction reset'end
end
function G.is_live()return G.live~=nil or pending~=nil end
function G.begin_pickup(wt)G.pickup={wt=wt and tostring(wt) or nil,expires=os.clock()+3}end
local function release(i)
 local ok,why=pcall(function()
  local pos=hand(i)
  local v,a=release_vectors(i)
  if G.live then
   local p=G.live;G.live=nil
   p.transform:set_position(pos);velocity(p.body,v,a)
   local shell=component(p.go,sdk.game_namespace('weapon.shell.ThrowGrenade'))
   local ballistic=shell and shell:get_field('_BallisticInformation')
   if ballistic then ballistic:call('set_CurrentSpeed',v)end
  elseif pending then pending.release={v=v,a=a}
  else error('Native shell no longer available; no replacement spawned')end
 end)
 if not ok then G.live=nil;pending=nil;G.locked=true end
 return ok,why
end
function G.step(sample,current,enabled,scene)
 active=false
 local i=sample
 if sample and sample.active then
  -- Native RE2 holds subweapons with LEFT grip; the item stays in the RIGHT hand.
  i={};for k,value in pairs(sample)do i[k]=value end
  local hold=sample.leftGrip==true
  if hold and G.lastHold==false then G.begin_pickup(nil)end
  G.lastHold=hold
  i.rightGrip=hold
 else G.lastHold=true end
 if G.pickup and (os.clock()>G.pickup.expires or not enabled or not i or not i.active or not i.rightGrip)then G.pickup=nil end
 if not enabled or not G.ready or G.locked or not i or not i.active then restore(current);G.stop();return end
 -- A last grenade may remove its inventory slot immediately on priming.
 -- Keep its live shell through that transition; it is independent of the new gun.
 if G.live or pending then
  local scenePlayer,safe
  if scene then scenePlayer=scene.player;safe=scene.safe
  else scenePlayer=current and current.player;safe=current and current.safe end
  if not safe or (G.owner and scenePlayer~=G.owner)then restore(current);G.stop();return end
  if not i.rightGrip then
   local ok,why=release(i);restore(current);gesture:reset()
   G.status=ok and 'Released same live grenade; native fuse continues' or tostring(why)
   return
  end
  local ok,why=pcall(function()
   local pos=hand(i)
   if G.live then
    G.live.transform:set_position(pos);velocity(G.live.body,zero(),zero())
   elseif pending then
    assert(os.clock()<=pending.expires,'Native shell callback timed out; no retry')
    pending.position=pos
   end
  end)
  if not ok then G.live=nil;pending=nil;G.locked=true;G.status=tostring(why);restore(current);return end
  if raw and ((scene and scene.player==G.owner) or (current and current.equipment==raw.equipment))then active=true end
  G.status='LIVE grenade: release LEFT grip; native fuse already running'
  return
 end
 if not current or not current.safe then restore(current);G.stop();return end
 local ok,gen=pcall(function()
  if not current.slot:call('get_IsSubWeapon')then return nil end
  local g=current.weapon:get_field('<ShellGenerator>k__BackingField')
  return g and g:get_type_definition():is_a(generatorType) and g or nil
 end)
 if not ok or not gen then restore(current);G.stop();return end
 restore(current)
 if raw and raw.weapon~=current.weapon then G.stop()end
 raw=current;generator=gen;active=true
 if G.pickup and (G.pickup.wt==nil or G.pickup.wt==tostring(current.wt))then
  gesture:reset();gesture.identity=tostring(current.weapon)..':'..tostring(current.slot)
  gesture.lastGrip=false;gesture.lastTrigger=i.rightTrigger==true;G.pickup=nil
 end
 gesture:step(i,tostring(current.weapon)..':'..tostring(current.slot),true,release,function()
  local success,errorText=pcall(function()
   assert(raw==current and current.safe and not current.infinity,'Grenade changed')
   local count=current.slot:call('get_Number');assert(count>=1,'No grenade available')
   pose=current.weapon:call('get_GameObject'):call('get_Transform'):call('get_WorldMatrix')
   local pos=hand(i)
   pending={generator=gen,position=pos,expires=os.clock()+1}
   G.owner=current.player
   generate:call(gen,pose) -- starts the native shell lifecycle/fuse immediately
   use:call(current.equipment,current.wt,1)
   assert(current.slot:call('get_Number')==count-1,'Grenade debit not verified')
   draw:call(current.weapon,false);G.hidden=current.weapon
  end)
  if not success then G.locked=true;pending=nil;G.live=nil;G.status=tostring(errorText)end
  return success,errorText
 end)
 if not G.locked then G.status=gesture.message end
end
return G
