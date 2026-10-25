do
local oldsdk=sdk
local assignments={}
local function slot(wt,sub)
 return {call=function(_,name)
  if name=='get_IsEmpty' or name=='get_IsDeadSlot'then return false end
  if name=='get_IsWeapon'then return not sub end
  if name=='get_IsSubWeapon'then return sub end
  if name=='get_WeaponType'then return wt end
 end}
end
assignments[31]=slot(10,false);assignments[92]=slot(20,false)
sdk={game_namespace=function(n)return 'app.ropeway.'..n end,find_type_definition=function()
 return {get_fields=function()return {
  {get_name=function()return 'UP' end,is_static=function()return true end,get_data=function()return 31 end},
  {get_name=function()return 'DOWN' end,is_static=function()return true end,get_data=function()return 92 end}}end}
end}
local inv={call=function(_,name,value)
 assert(name=='getSlot(app.ropeway.EquipmentDefine.Shortcut)');assert(value==31 or value==92,'Ordinal guessed')
 return assignments[value]
end}
package.loaded['re2ivr.shortcuts']=nil
local S=require('re2ivr.shortcuts')
local rows=S.read(inv);assert(rows.up.weaponType=='10' and rows.down.weaponType=='20')
assignments[31]=slot(30,false);assignments[92]=nil
rows=S.read(inv);assert(rows.up.weaponType=='30' and rows.down==nil,'Assignments must be reread, not cached')
sdk=oldsdk
print('PASS live shortcut lookup: reflected direction values, remapping and empty assignments')
end
