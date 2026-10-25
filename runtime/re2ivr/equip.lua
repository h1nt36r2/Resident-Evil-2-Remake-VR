-- Inventory selection and native draw share reflected category/parts contracts.
local E={}
local function valid(n)return type(n)=='number' and n==n and n>=0 and n%1==0 end
function E.parts(slot)
 local ok,value=pcall(function()
  local t=slot:get_type_definition()
  local typeName=sdk.game_namespace('EquipmentDefine.WeaponParts')
  local found
  for _,m in ipairs(t:get_methods())do
   if m:get_name():match('^get_') and #m:get_param_types()==0
    and m:get_return_type():get_full_name()==typeName then
     assert(not found,'Ambiguous weapon parts getter');found=m
   end
  end
  if found then return found:call(slot)end
  -- Some slot schemas expose the enum as a field rather than a property.
  for _,f in ipairs(t:get_fields())do
   if not f:is_static() and f:get_type():get_full_name()==typeName then
    assert(not found,'Ambiguous weapon parts field');found=f
   end
  end
  return found and found:get_data(slot)
 end)
 if ok and valid(value)then return value end
end
function E.apply(slot,index,inv,eq,api,wt,sub,already)
 local parts=E.parts(slot)
 local category
 if sub then category=api.subCategory else category=api.mainCategory end
 if not already and api.equipSlot:call(inv,index)~=true then return false,'Native inventory refused belt item'end
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
