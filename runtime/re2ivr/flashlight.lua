-- Preserve an already lit player flashlight while the right hand holds a weapon.
-- Never creates lights, edits inventory, or touches cameras. Optional API boundary.
local F={ready=false,status='Not initialized'}
function F.new()
 local self={owner=nil,epoch=nil,target=nil,gripping=false,latched=false,last=nil}
 function self:clear()
  self.target=nil;self.last=nil;self.latched=false;self.gripping=false
 end
 function self:step(input,current,enabled,epoch)
  local owner=current and current.player
  if owner~=self.owner or epoch~=self.epoch then self:clear();self.owner=owner;self.epoch=epoch end
  local active=enabled and input and input.active and current and current.safe and not current.storyNative and not current.isDevice
  if not active then self:clear();return end
  local grip=input.rightGrip==true
  if grip and not self.gripping then self.latched=self.last and self.last.light==true or false end
  if not grip then self.latched=false end
  self.gripping=grip
 end
 function self:observe(target,state)
  if not self.owner then return end
  if self.target and self.target~=target then self.last=nil;self.latched=false end
  self.target=target
  if not self.gripping then self.last=state end
 end
 function self:restore(target,read,write)
  if self.gripping and self.latched and self.target==target and self.last then
   local now=read()
   if self.last.light and now.light==false then write('light',true) end
   if self.last.mesh and now.mesh==false then write('mesh',true) end
  end
 end
 return self
end
local guard=F.new()
local target,light,mesh
local function discard()
 target=nil;light=nil;mesh=nil
end
local function owned(object)
 local go=object:call('get_GameObject')
 local transform=go and go:call('get_Transform')
 for n=1,32 do
  if not transform then return false end
  if transform:call('get_GameObject')==guard.owner then return true end
  transform=transform:call('get_Parent')
 end
 return false
end
local function read()
 return {light=light:call('get_Enabled'),mesh=mesh and mesh:call('get_Enabled') or false}
end
local function write(kind,value)
 local object=kind=='light' and light or mesh
 if object then object:call('set_Enabled',value) end
end
function F.step(input,current,enabled,epoch)
 local owner,oldEpoch=guard.owner,guard.epoch
 guard:step(input,current,enabled,epoch)
 if owner~=guard.owner or oldEpoch~=guard.epoch or not guard.target then discard() end
end
function F.apply()
 if target and guard.gripping and guard.latched then
  local ok,err=pcall(function()
   if not owned(target) then discard();return end
   guard:restore(target,read,write)
  end)
  if not ok then F.status='Flashlight preservation paused: '..tostring(err);discard();guard:clear() end
 end
end
function F.init()
 local ok,err=pcall(function()
  local t=sdk.find_type_definition(sdk.game_namespace('FlashLight'))
  local method=t and t:get_method('applyTransform')
  assert(method,'FlashLight.applyTransform unavailable')
  sdk.hook(method,function(args)
   if not guard.owner then return end
   local success,why=pcall(function()
    local object=sdk.to_managed_object(args[2])
    if not object or not owned(object) then return end
    local ies=object:get_field('<IESLight>k__BackingField')
    if not ies then return end
    local go=object:call('get_GameObject')
    local mt=sdk.typeof('via.render.Mesh')
    local model=go and mt and go:call('getComponent(System.Type)',mt)
    target=object;light=ies;mesh=model
    guard:observe(object,read())
   end)
   if not success then F.status='Flashlight observation unavailable: '..tostring(why) end
  end,function(ret)
   F.apply()
   return ret
  end)
 end)
 F.ready=ok;F.status=ok and 'Preserve lit flashlight during right grip' or tostring(err)
end
function F.stop()guard:clear();guard.owner=nil;discard()end
return F
