-- Inventory selection and native draw share reflected category/parts contracts.
local E={}
local function valid(n)return type(n)=='number' and n==n and n>=0 and n%1==0 end
local function inspect(obj)
 local ok,value=pcall(function()
  local t=obj and obj:get_type_definition()
  local enum=sdk.game_namespace('EquipmentDefine.WeaponParts')
  for depth=1,8 do
   if not t then return nil end
   local found
   for _,m in ipairs(t:get_methods())do
    local name=m:get_name();local ret=m:get_return_type():get_full_name()
    local typed=ret==enum
    local named=(name=='get_WeaponParts' or name=='get_Parts') and (ret=='System.Int32' or ret=='System.UInt32')
    if name:match('^get_') and #m:get_param_types()==0 and (typed or named)then
     assert(not found,'Ambiguous weapon parts getter');found=m
    end
   end
   if found then return found:call(obj)end
   for _,f in ipairs(t:get_fields())do
    local ret=f:get_type():get_full_name()
    local typed=ret==enum
    local named=(ret=='System.Int32' or ret=='System.UInt32') and
     (f:get_name()=='_WeaponParts' or f:get_name()=='<WeaponParts>k__BackingField')
    if not f:is_static() and (typed or named)then
     assert(not found,'Ambiguous weapon parts field');found=f
    end
   end
   if found then return found:get_data(obj)end
   t=t.get_parent_type and t:get_parent_type() or nil
  end
 end)
 if ok and valid(value)then return value end
end
function E.parts(slot,arm)
 local value=inspect(slot)
 if value~=nil then return value end
 return inspect(arm)
end
function E.apply(slot,index,inv,eq,api,wt,sub,already,selectOnly)
 local parts
 if not selectOnly then
  local ok,arm=pcall(function()return eq:call('getWeapon',wt)end)
  parts=E.parts(slot,ok and arm or nil)
 end
 local category
 if sub then category=api.subCategory else category=api.mainCategory end
 if not already and api.equipSlot:call(inv,index)~=true then
  local ok,selected=pcall(function()return inv:call(sub and 'get_SubSlot' or 'get_MainSlot')end)
  if not ok or selected~=slot then return false,'Native inventory refused belt item'end
 end
 if selectOnly then return true,'Subweapon selected: hold LEFT grip to draw' end
 if eq:call('get_EquipType')==wt then
  local arm=eq:call('getWeapon',wt)
  if arm then api.draw:call(arm,true)end
  return true,'Selected weapon draw requested'
 end
 if parts~=nil and category~=nil then
  api.change:call(eq,category,wt,parts)
  -- changeWeapon may complete asynchronously. Do not display an unequipped mesh.
  if eq:call('get_EquipType')==wt then
   local arm=eq:call('getWeapon',wt)
   if arm then api.draw:call(arm,true)end
  end
  return true,'Inventory equipped; native weapon change requested'
 end
 return true,'Inventory equipped; category/parts unavailable, awaiting native weapon change'
end
return E
