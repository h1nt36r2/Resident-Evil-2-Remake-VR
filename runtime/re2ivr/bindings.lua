-- Per-character belt fallback. Never edits game inventory or guesses native enum values.
local B={}
local directions={up=true,down=true,left=true,right=true}
local data
local function load()
 if data then return end
 local ok,value=pcall(function()return json.load_file('re2ivr_shortcut_bindings.json')end)
 data=ok and type(value)=='table' and value.schema==1 and type(value.characters)=='table' and value or {schema=1,characters={}}
end
local function owner(inv)
 local ok,value=pcall(function()return inv:call('get_SurvivorType')end)
 if ok and type(value)=='number' and value>=0 and value%1==0 then return tostring(value)end
end
function B.owned(inv)
 local slots=inv and inv:call('get_Slots')
 local count=slots and slots:call('get_Count') or 0
 assert(type(count)=='number' and count>=0 and count<=256,'Invalid inventory size')
 local rows={}
 for n=0,count-1 do
  local slot=slots:call('get_Item(System.Int32)',n)
  if slot and not slot:call('get_IsEmpty') and not slot:call('get_IsDeadSlot')
   and slot:call('get_IsWeapon') and not slot:call('get_IsSubWeapon')then
   local wt=slot:call('get_WeaponType')
   if type(wt)=='number' and wt>=0 and wt%1==0 then
    local ok,name=pcall(function()return slot:call('get_WeaponName')end)
    rows[#rows+1]={slot=slot,index=n,weaponType=tostring(wt),sub=false,name=ok and tostring(name) or tostring(wt)}
   end
  end
 end
 return rows
end
function B.read(inv)
 load()
 local id=owner(inv);local saved=id and data.characters[id]
 if type(saved)~='table'then return {}end
 local owned={}
 for _,row in ipairs(B.owned(inv))do owned[row.weaponType]=row end
 local out={}
 for direction,row in pairs(saved)do
  local item=type(row)=='table' and owned[row.weaponType]
  if directions[direction] and item and row.source=='mod'then
   out[direction]={weaponType=item.weaponType,sub=false,source='mod'}
  end
 end
 return out
end
function B.assign(inv,slot,direction,source)
 if not directions[direction]then return false,'Invalid shortcut direction'end
 load()
 local id=owner(inv);if not id then return false,'Character identity unavailable; binding not saved'end
 local selected
 for _,row in ipairs(B.owned(inv))do if row.slot==slot then selected=row;break end end
 if not selected then return false,'Selected weapon is no longer owned'end
 local previous=data.characters[id]
 if type(previous)~='table'then previous=nil end
 local nextRows={}
 for key,row in pairs(previous or {})do nextRows[key]=row end
 nextRows[direction]={weaponType=selected.weaponType,source=source=='native' and 'native' or 'mod'}
 data.characters[id]=nextRows
 local ok,result=pcall(function()return json.dump_file('re2ivr_shortcut_bindings.json',data)end)
 if not ok or result==false then data.characters[id]=previous;return false,'Could not save belt assignment'end
 return true,selected.name..' -> '..direction..(source=='native' and ' (game + saved status)' or ' (saved mod belt slot)')
end
function B.clear(inv)
 load();local id=owner(inv);if not id then return false end
 local previous=data.characters[id];data.characters[id]=nil
 local ok,result=pcall(function()return json.dump_file('re2ivr_shortcut_bindings.json',data)end)
 if not ok or result==false then data.characters[id]=previous;return false end
 return true
end
return B
