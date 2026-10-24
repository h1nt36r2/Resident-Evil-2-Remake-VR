-- Read-only belt inventory. No item IDs guessed: bind unclassified subweapons explicitly.
local I={}
local Profiles=require('re2ivr.profiles')
local function subkind(name)
    local n=(name or ''):lower()
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
        if slot and not slot:call('get_IsEmpty') and not slot:call('get_IsDeadSlot') and slot:call('get_IsWeapon') then
            local wt=tostring(slot:call('get_WeaponType'))
            local number=slot:call('get_Number')
            local ok,name=pcall(function() return slot:call('get_WeaponName') end)
            name=ok and type(name)=='string' and name or ''
            local profile=profiles[wt] or Profiles.detect(name)
            if profile=='native' then profile=Profiles.detect(name) end
            local kind=bindings[wt] or subkind(name) or (profile=='pump' and 'shotgun') or (profile=='breech' and 'launcher') or (profile and 'pistol') or nil
            local quantity=(kind=='grenade' or kind=='flash') and math.max(1,number) or 1
            if not known[wt] then
                local row={slot=n+1,weaponType=wt,name=name,count=quantity,kind=kind or 'unknown',sub=slot:call('get_IsSubWeapon')==true}
                rows[#rows+1]=row;known[wt]=row
            else known[wt].count=known[wt].count+quantity end
        end
    end
    return rows
end
return I
