do
local E=require('re2ivr.equip')
local oldsdk=sdk;sdk={game_namespace=function(n)return n end}
local equipped,changes,drawn=0,{},0
local inv,eq,arm={},{},{}
local currentType=1
local typeName='EquipmentDefine.WeaponParts'
local partsGetter={get_name=function()return 'get_WeaponParts'end,get_param_types=function()return {}end,
 get_return_type=function()return {get_full_name=function()return typeName end}end,call=function()return 7 end}
local slot={get_type_definition=function()return {get_methods=function()return {partsGetter}end,get_fields=function()return {}end}end}
local api={subCategory=9,mainCategory=4,
 equipSlot={call=function(_,owner,index)assert(owner==inv and index==3);equipped=equipped+1;return true end},
 change={call=function(_,owner,category,weapon,parts)assert(owner==eq and parts==7);changes[#changes+1]={category,weapon}end},
 draw={call=function(_,weapon,visible)assert(weapon==arm and visible);drawn=drawn+1 end}}
eq.call=function(_,name,id)
 if name=='get_EquipType'then return currentType end
 assert(name=='getWeapon');return arm
end
-- Subweapon: request change, never draw a cached unequipped mesh.
assert(E.apply(slot,3,inv,eq,api,200,true,false))
assert(equipped==1 and #changes==1 and changes[1][1]==9 and drawn==0)
currentType=200;assert(E.apply(slot,3,inv,eq,api,200,true,true))
assert(#changes==1 and drawn==1,'Already equipped item must redraw without another change')
-- Main shotgun uses its own reflected category, not the subweapon category.
currentType=1;assert(E.apply(slot,3,inv,eq,api,12,false,false))
assert(#changes==2 and changes[2][1]==4 and changes[2][2]==12 and drawn==1)
currentType=12;assert(E.apply(slot,3,inv,eq,api,12,false,true))
assert(#changes==2 and drawn==2)
api.equipSlot.call=function()return false end;currentType=1
assert(not E.apply(slot,3,inv,eq,api,12,false,false));assert(#changes==2)
local unknown={get_type_definition=function()return {get_methods=function()return {}end,get_fields=function()return {}end}end}
assert(E.apply(unknown,3,inv,eq,api,12,false,true));assert(#changes==2,'No guessed parts')
local field={is_static=function()return false end,get_type=function()return {get_full_name=function()return typeName end}end,get_data=function()return 11 end}
local fieldSlot={get_type_definition=function()return {get_methods=function()return {}end,get_fields=function()return {field}end}end}
assert(E.parts(fieldSlot)==11,'Typed parts field supported')
local ambiguous={get_type_definition=function()return {get_methods=function()return {}end,get_fields=function()return {field,field}end}end}
assert(E.parts(ambiguous)==nil,'Ambiguous fields rejected')
local beforeChanges,beforeDraws=#changes,drawn
api.equipSlot.call=function()equipped=equipped+1;return true end
assert(E.apply(unknown,3,inv,eq,api,200,true,false,true),'Icon selects even without a parts getter')
assert(#changes==beforeChanges and drawn==beforeDraws,'Icon selection must not force a draw or weapon change')
local scalarGetter={get_name=function()return 'get_WeaponParts'end,get_param_types=function()return {}end,
get_return_type=function()return {get_full_name=function()return 'System.Int32'end}end,call=function()return 3 end}
local parent={get_methods=function()return {scalarGetter}end,get_fields=function()return {}end}
local inherited={get_type_definition=function()return {
get_methods=function()return {}end,get_fields=function()return {}end,get_parent_type=function()return parent end}end}
assert(E.parts(inherited)==3,'Inherited integer-valued parts getter must be supported')
assert(E.parts(unknown,inherited)==3,'Weapon object can supply parts absent on inventory slot')
inv.call=function(_,name)assert(name=='get_MainSlot');return slot end
api.equipSlot.call=function()return false end
currentType=12
assert(E.apply(slot,3,inv,eq,api,12,false,false),'Already selected main slot must not fail idempotent equip')
sdk=oldsdk
print('PASS main/sub native equip: reflected category/parts, asynchronous change, selected redraw, refusal and typed-field fallback')
end
