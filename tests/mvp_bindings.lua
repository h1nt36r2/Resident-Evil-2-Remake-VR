do
local oldsdk,oldjson=sdk,json
local previous=package.loaded['re2ivr.bindings']
local id=1
local items={}
local function item(wt,name)
 return {call=function(_,n)
  if n=='get_WeaponType'then return wt end
  if n=='get_WeaponName'then return name end
  if n=='get_IsWeapon'then return true end
  if n=='get_IsEmpty' or n=='get_IsDeadSlot' or n=='get_IsSubWeapon'then return false end
 end}
end
local pistol,shotgun=item(10,'Pistol'),item(12,'W-870')
items={pistol,shotgun}
local list={call=function(_,n,index)if n=='get_Count'then return #items end;return items[index+1]end}
local inv={call=function(_,n)
 if n=='get_SurvivorType'then return id end
 if n=='get_Slots'then return list end
 error('No usable native shortcut API')
end}
local saved,writes,fail=nil,0,false
local function copy(value)
 if type(value)~='table'then return value end
 local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out
end
json={load_file=function()return copy(saved)end,dump_file=function(_,value)
 if fail then return false end
 saved=copy(value);writes=writes+1;return true
end}
sdk={game_namespace=function(n)return n end,find_type_definition=function()return nil end}
local B=assert(loadfile('runtime/re2ivr/bindings.lua'))()
assert(B.assign(inv,shotgun,'down','mod'))
assert(writes==1 and B.read(inv).down.weaponType=='12')
B=assert(loadfile('runtime/re2ivr/bindings.lua'))()
assert(B.read(inv).down.weaponType=='12','Assignment must survive module/game reload')
package.loaded['re2ivr.bindings']=B
local oldShortcuts=package.loaded['re2ivr.shortcuts']
local S=assert(loadfile('runtime/re2ivr/shortcuts.lua'))()
local shortcuts=S.read(inv)
assert(shortcuts.down.weaponType=='12' and shortcuts.down.source=='mod','Saved shoulder binding works with unavailable native enum/API')
items={pistol};assert(B.read(inv).down==nil,'Removed weapon cannot be issued')
items={pistol,shotgun};id=2;assert(B.read(inv).down==nil,'Bindings belong to character')
id=1;fail=true;assert(not B.assign(inv,pistol,'down','mod'))
assert(B.read(inv).down.weaponType=='12','Failed save must not replace current binding')
fail=false;assert(B.assign(inv,pistol,'down','native'))
assert(B.read(inv).down==nil,'Verified native assignment removes prior belt override')
assert(B.assign(inv,shotgun,'down','mod'));assert(B.clear(inv));assert(B.read(inv).down==nil)
sdk, json=oldsdk,oldjson
package.loaded['re2ivr.bindings']=previous;package.loaded['re2ivr.shortcuts']=oldShortcuts
print('PASS saved shoulder slots: native API fallback, persistence, ownership/character checks, failed-save rollback and return to native assignments')
end
