do
local oldsdk=sdk
local oldEquip=package.loaded['re2ivr.equip']
local story=require('re2ivr.story');local oldUpdate,oldNative=story.update,story.native
story.update=function()return false end;story.native=false
local wt=50
local grenade,knife={},{}
local activeSlot=grenade
local slots={}
local function slot(kind,id)
 return {call=function(_,name)
  if name=='get_WeaponName'then return kind end
  if name=='get_WeaponType'then return id end
  if name=='get_IsSubWeapon' or name=='get_IsWeapon'then return true end
  if name=='get_IsEmpty' or name=='get_IsDeadSlot' or name=='get_Infinity'then return false end
  if name=='get_Number'then error('Knife selection must not read grenade stack count')end
  error(name)
 end}
end
grenade=slot('Hand Grenade',50);knife=slot('Combat Knife',55);activeSlot=grenade
local list={call=function(_,name)
 if name=='get_Count'then return 1 end
 if name=='get_Item(System.Int32)'then return knife end
 error(name)
end}
local inventory={call=function(_,name)
 if name=='get_SurvivorType'then return 0 end
 if name=='get_MainSlot'then return knife end
 if name=='get_Slots'then return list end
 error(name)
end}
local weapon={get_type_definition=function()return {get_full_name=function()return 'implement.Melee'end}end}
local eq={call=function(_,name)
 if name=='get_EquipWeapon'then return weapon end
 if name=='get_EquipSlot'then return activeSlot end
 if name=='get_EquipType'then return wt end
 error(name)
end}
local condition={call=function()return false end}
local gui={call=function()return false end}
local function player()
 return {call=function(_,name,t)
  assert(name=='getComponent(System.Type)')
  if t=='survivor.Inventory'then return inventory end
  if t=='survivor.Equipment'then return eq end
  if t=='survivor.SurvivorCondition'then return condition end
 end}
end
local currentPlayer=player()
sdk={game_namespace=function(n)return n end,typeof=function(n)return n end,find_type_definition=function()return nil end,
 get_managed_singleton=function(name)
  if name=='PlayerManager'then return {call=function()return currentPlayer end}end
  if name=='gui.GUIMaster'then return gui end
 end}
local N=assert(loadfile('runtime/re2ivr/native.lua'))()
assert(N.refresh().safe)
local selections=0
package.loaded['re2ivr.equip']={apply=function(s,index,inv,e,api,id,sub,already,selectOnly)
 assert(s==knife and index==0 and inv==inventory and e==eq and id==55 and sub and selectOnly)
 selections=selections+1;return true,'Selected'
end}
assert(N.select_subweapon(55));assert(selections==1 and N.beltSub==55)
local input={active=true,leftGrip=false,rightGrip=true}
N.update_belt_hold(input,true)
assert(N.beltSub==55 and N.beltHold==nil,'Right grip selects, but does not hold')
input.rightGrip=false;input.leftGrip=true;N.update_belt_hold(input,true)
assert(N.beltSub==55 and N.beltHold=='held','Left grip draws chosen knife')
input.leftGrip=false;N.update_belt_hold(input,true)
assert(N.beltSub==55 and N.beltHold==nil,'Release must preserve selection and stop old grenade interception')
wt=55;activeSlot=knife;N.refresh()
input.leftGrip=true;N.update_belt_hold(input,true)
assert(N.beltSub==55 and N.beltHold=='held','Knife can be drawn again after grenade')
N.update_belt_hold(input,true,true)
assert(N.reloadPriority and not N.beltHold,'Ammo hand must not draw selected knife')
N.update_belt_hold(input,true,false)
assert(not N.reloadPriority and N.beltHold=='held','Subweapon hold returns after reload priority')
currentPlayer=player();N.refresh()
assert(N.beltSub==nil and N.beltOwner==nil,'New player clears old selection ownership')
sdk=oldsdk;package.loaded['re2ivr.equip']=oldEquip;story.update=oldUpdate;story.native=oldNative
print('PASS actual native adapter: icon selects knife without stack-count requirement; LEFT hold/release retains choice; player switch clears ownership')
end
