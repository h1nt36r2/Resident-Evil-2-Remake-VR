do
local oldsdk,oldvr=sdk,vrmod
local shown=0
sdk={game_namespace=function(n)return n end,find_type_definition=function()
 return {get_fields=function()return {{is_static=function()return true end,get_name=function()return 'ADA'end,get_data=function()return 11 end}}end}
end}
vrmod={unhide_crosshair=function()shown=shown+1 end}
local Story=require('re2ivr.story')
local name='Broom Hc'
local inv={call=function()return {call=function()return name end}end}
assert(Story.update(inv,nil,false) and shown==1)
name='Matilda';local inv2={call=inv.call};assert(not Story.update(inv2,nil,false))
local pistol={call=function(_,n)if n=='get_IsWeapon'then return true elseif n=='get_WeaponName'then return 'Broom Hc' else return false end end}
local scanner={call=function()return 'EMF Visualizer'end}
local owned={call=function(_,n)if n=='get_Count'then return 1 else return pistol end end}
local inv3={call=function(_,n)if n=='get_MainSlot'then return scanner elseif n=='get_Slots'then return owned end end}
assert(Story.update(inv3,nil,false),'Ada saved with scanner selected must be recognized from owned Broom Hc')
assert(Story.update(inv,11,true) and Story.characterName=='ADA')
assert(not Story.update(nil,nil,false))
sdk,vrmod=oldsdk,oldvr
print('PASS automatic Ada compatibility by named character or Broom Hc; no numeric character IDs hardcoded')
end
