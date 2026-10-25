do
local oldsdk,oldjson=sdk,json
json={load_file=function()return nil end,dump_file=function()return true end}
local mode,modal='inventory',false
local main={call=function(_,n)
 if n=='get_IsWeapon'then return true elseif n=='get_WeaponType'then return 10 else return false end
end}
local second={call=function(_,n)
 if n=='get_IsWeapon'then return true elseif n=='get_WeaponType'then return 20 elseif n=='get_WeaponName'then return 'W-870' else return false end
end}
local items={main,second};local reject=false
local assignments={[31]=main};local writes,ups,downs=0,0,0
local function field(name,value)return {get_name=function()return name end,is_static=function()return true end,get_data=function()return value end}end
local slots={call=function(_,n,index)if n=='get_Count'then return #items end;return items[index+1] end}
local inv={call=function(_,n,a,b)
 if n=='get_SurvivorType'then return 2 elseif n=='get_MainSlot'then return main elseif n=='get_Slots'then return slots elseif n=='enableSetShortcut'then return true
 elseif n=='getSlot(app.ropeway.EquipmentDefine.Shortcut)'then return assignments[a]
 elseif n=='fixtureSetShortcut'then if reject then return false end;assignments[b]=items[a+1];writes=writes+1;return true end
 error('Unexpected inventory method: '..n)
end}
local function setter(name,record)
 return {get_name=function()return name end,get_param_types=function()return {{get_full_name=function()return 'System.Boolean' end}}end,
  get_return_type=function()return {get_full_name=function()return 'System.Void' end}end,call=function(_,obj,value)assert(value==true);record()end}
end
local input={get_type_definition=function()return {get_methods=function()return {
 setter('set_IsTriggerMoveUpD',function()ups=ups+1 end),setter('set_IsTriggerMoveDownD',function()downs=downs+1 end)}end}end}
local gui={call=function(_,n)
 if n=='isBusyGeneralDialog'then return modal elseif n=='get_IsOpenInventory'then return mode=='inventory'
 elseif n=='get_IsOpenMap'then return mode=='map' elseif n=='get_State_'then return 77 elseif n=='get_Input'then return input end
 error('Unexpected GUI method: '..n)
end}
sdk={game_namespace=function(n)return 'app.ropeway.'..n end,typeof=function(n)return n end,
 find_type_definition=function(n)
  if n:find('GuiState',1,true)then return {get_fields=function()return {field('INVENTORY',999)}end}end
  if n:find('EquipmentDefine.Shortcut',1,true)then return {get_fields=function()return {field('UP',31),field('DOWN',92),field('LEFT',12),field('RIGHT',44)}end}end
  if n=='app.ropeway.survivor.Inventory'then return {get_methods=function()return {{
   get_name=function()return 'setShortcutSlot'end,
   get_param_types=function()return {{get_full_name=function()return 'System.Int32'end},{get_full_name=function()return 'app.ropeway.EquipmentDefine.Shortcut'end}}end,
   get_return_type=function()return {get_full_name=function()return 'System.Boolean'end}end,
   call=function(_,obj,index,direction)return obj:call('fixtureSetShortcut',index,direction)end}}end}end
 end,
 get_managed_singleton=function(n)if n:find('PlayerManager',1,true)then return {call=function()return {call=function()return inv end}end}else return gui end end}
package.loaded['re2ivr.shortcuts']=nil;package.loaded['re2ivr.menu_controls_native']=nil
local N=require('re2ivr.menu_controls_native')
assert(N.assign('down'));assert(writes==1 and assignments[92]==main)
mode='map';assert(not N.assign('up') and writes==1)
assert(N.floor('up'));assert(N.floor('down'));assert(ups==1 and downs==1)
modal=true;assert(not N.floor('up'));assert(not N.assign('down'));assert(ups==1 and writes==1)
mode='inventory';modal=false;assert(not N.floor('down') and downs==1)
-- Explicit list selection is independent of MainSlot; native rejection uses persisted belt fallback.
reject=true
assert(N.assign('down',1))
assert(assignments[92]==main and writes==1,'Rejected game assignment must not be claimed as a game change')
local row=require('re2ivr.shortcuts').read(inv).down
assert(row.weaponType=='20' and row.source=='mod','Selected list weapon must reach the shoulder even with native refusal')
sdk=oldsdk;json=oldjson
print('PASS native menu boundary: guarded native shortcut assignment/verification, map-only GUI triggers and modal exclusion')
end
