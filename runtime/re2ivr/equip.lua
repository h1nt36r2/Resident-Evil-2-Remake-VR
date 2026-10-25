-- Complete inventory -> subweapon draw without guessed parts/category values.
local E={}
function E.parts(slot)
 local ok,value=pcall(function()
  local found
  for _,m in ipairs(slot:get_type_definition():get_methods())do
   if m:get_name():match('^get_')
    and #m:get_param_types()==0
    and m:get_return_type():get_full_name()==sdk.game_namespace('EquipmentDefine.WeaponParts')then
     assert(not found,'Ambiguous weapon parts getter');found=m
   end
  end
  return found and found:call(slot)
 end)
 if ok and type(value)=='number' and value==value and value>=0 and value%1==0 then return value end
end
function E.apply(slot,index,inv,eq,api,wt,sub,already)
 local parts=sub and E.parts(slot) or nil
 if not already and api.equipSlot:call(inv,index)~=true then return false,'Native inventory refused belt item' end
 if sub and parts~=nil and api.subCategory~=nil then
  api.change:call(eq,api.subCategory,wt,parts)
  local arm=eq:call('getWeapon',wt)
  if arm then api.draw:call(arm,true)end
  return true,'Inventory equipped; native subweapon draw requested'
 end
 return true,sub and 'Inventory equipped; parts contract unavailable, native grip draw pending' or 'Native belt equip requested'
end
return E
