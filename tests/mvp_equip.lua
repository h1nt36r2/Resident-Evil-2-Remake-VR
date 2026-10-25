do
local E=require('re2ivr.equip')
local oldsdk=sdk;sdk={game_namespace=function(n)return n end}
local equipped,changed,drawn=0,0,0
local inv,eq,arm={},{},{}
local wt=200
local partsGetter={get_name=function()return 'get_WeaponParts'end,get_param_types=function()return {}end,
 get_return_type=function()return {get_full_name=function()return 'EquipmentDefine.WeaponParts'end}end,
 call=function()return 7 end}
local slot={get_type_definition=function()return {get_methods=function()return {partsGetter}end}end}
local api={subCategory=9,
 equipSlot={call=function(_,owner,index)assert(owner==inv and index==3);equipped=equipped+1;return true end},
 change={call=function(_,owner,category,weapon,parts)assert(owner==eq and category==9 and weapon==wt and parts==7);changed=changed+1 end},
 draw={call=function(_,weapon,visible)assert(weapon==arm and visible);drawn=drawn+1 end}}
eq.call=function(_,name,id)assert(name=='getWeapon' and id==wt);return arm end
assert(E.apply(slot,3,inv,eq,api,wt,true,false))
assert(equipped==1 and changed==1 and drawn==1)
api.equipSlot.call=function()return false end
assert(not E.apply(slot,3,inv,eq,api,wt,true,false));assert(changed==1 and drawn==1)
assert(E.apply(slot,3,inv,eq,api,wt,true,true));assert(changed==2)
local unknown={get_type_definition=function()return {get_methods=function()return {}end}end}
assert(E.apply(unknown,3,inv,eq,api,wt,true,true));assert(changed==2,'Unknown parts must not be guessed')
sdk=oldsdk
print('PASS pouch equip completes inventory selection, reflected parts/category native draw; refusal and unknown contracts do not force draw')
end
