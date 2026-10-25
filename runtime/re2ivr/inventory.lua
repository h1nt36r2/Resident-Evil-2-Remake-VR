-- Read-only belt inventory. No item IDs guessed: bind unclassified subweapons explicitly.
local I={}
local Profiles=require('re2ivr.profiles')
local Shortcuts=require('re2ivr.shortcuts')
local function subkind(name)
    local n=(name or ''):lower()
    if n:find('knife',1,true) then return 'knife' end
    if n:find('launcher',1,true) or n:find('Гранатом',1,true) or n:find('гранатом',1,true) then return nil end
    if n:find('flash',1,true) or n:find('светошум',1,true) or n:find('Светошум',1,true) then return 'flash' end
    if n:find('grenade',1,true) or n:find('гранат',1,true) or n:find('Гранат',1,true) then return 'grenade' end
end
function I.learn(current,bindings)
    if not current or bindings[tostring(current.wt)] then return false end
    local named=subkind(current.name)
    if named then bindings[tostring(current.wt)]=named;return true end
    local ok,melee=pcall(function()
        local t=sdk.find_type_definition(sdk.game_namespace('implement.Melee'))
        return t and current.weapon:get_type_definition():is_a(t)
    end)
    if ok and melee then bindings[tostring(current.wt)]='knife';return true end
    return false
end
function I.read(bindings,profiles)
    local manager=sdk.get_managed_singleton(sdk.game_namespace('PlayerManager'))
    local player=manager and manager:call('get_CurrentPlayer')
    if not player then return {} end
    local inv=player:call('getComponent(System.Type)',sdk.typeof(sdk.game_namespace('survivor.Inventory')))
    local slots=inv and inv:call('get_Slots')
    if not slots then return {} end
    local count=slots:call('get_Count');assert(count>=0 and count<=256,'Invalid gear inventory count')
    local rows,known={},{}
    for n=0,count-1 do
        local slot=slots:call('get_Item(System.Int32)',n)
        if slot and not slot:call('get_IsEmpty') and not slot:call('get_IsDeadSlot') and (slot:call('get_IsWeapon') or slot:call('get_IsSubWeapon')) then
            local wt=tostring(slot:call('get_WeaponType'))
            local number=slot:call('get_Number')
            local ok,name=pcall(function() return slot:call('get_WeaponName') end)
            name=ok and type(name)=='string' and name or ''
            local profile=profiles[wt] or Profiles.detect(name)
            if profile=='native' then profile=Profiles.detect(name) end
            local sub=slot:call('get_IsSubWeapon')==true
            local named=subkind(name)
            local kind=named or bindings[wt] or (not sub and ((profile=='pump' and 'shotgun') or (profile=='breech' and 'launcher') or (profile and 'pistol'))) or nil
            if sub and kind=='pistol' then kind=named end -- retire a stale main-weapon binding
            local quantity=(kind=='grenade' or kind=='flash') and (type(number)=='number' and math.max(0,number) or 0) or 1
            if not known[wt] then
                local row={slot=n+1,weaponType=wt,name=name,count=quantity,kind=kind or 'unknown',sub=slot:call('get_IsSubWeapon')==true}
                rows[#rows+1]=row;known[wt]=row
            else known[wt].count=known[wt].count+quantity end
        end
    end
    local ok,assigned=pcall(Shortcuts.read,inv)
    rows.shortcuts=ok and assigned or {};if not ok then Shortcuts.status=tostring(assigned) end
    return rows
end
return I
