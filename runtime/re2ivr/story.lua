-- Conservative story compatibility. Named runtime enum fields are preferred;
-- Ada's original Broom Hc is the fallback, never a guessed numeric character ID.
local S={native=false,reason='regular gameplay',characterName=nil}
local labels={}
local cachedInv,cachedCharacter,cachedBroom,lastScan=nil,nil,false,-10
local function normalized(s)return tostring(s or ''):lower():gsub('[%s%p]','')end
function S.update(inv,character,known)
    S.characterName=nil
    if known then
        if not labels[character] then
            local t=sdk.find_type_definition(sdk.game_namespace('SurvivorDefine.SurvivorType'))
            for _,f in ipairs(t and t:get_fields() or {})do
                if f:is_static() and f:get_data(nil)==character then labels[character]=f:get_name();break end
            end
        end
        S.characterName=labels[character]
    end
    local ada=normalized(S.characterName):match('^ada')~=nil
    local main=inv and inv:call('get_MainSlot')
    local ok,name=pcall(function()return main and main:call('get_WeaponName')end)
    local broom=ok and normalized(name):find('broomhc',1,true)~=nil
    local scope=known and character or nil
    if cachedInv~=inv or cachedCharacter~=scope then cachedInv=inv;cachedCharacter=scope;cachedBroom=false;lastScan=-10 end
    if broom then cachedBroom=true;lastScan=os.clock()
    elseif not ada and inv and os.clock()-lastScan>=2 then
        lastScan=os.clock();cachedBroom=false
        local scanOK,found=pcall(function()
            local slots=inv:call('get_Slots');local count=slots and slots:call('get_Count') or 0
            if type(count)~='number' or count<0 or count>256 then return false end
            for n=0,count-1 do
                local slot=slots:call('get_Item(System.Int32)',n)
                if slot and not slot:call('get_IsEmpty') and not slot:call('get_IsDeadSlot') and slot:call('get_IsWeapon')==true
                    and normalized(slot:call('get_WeaponName')):find('broomhc',1,true) then return true end
            end
            return false
        end)
        cachedBroom=scanOK and found or false
    end
    broom=broom or cachedBroom
    S.native=ada or broom
    S.reason=ada and 'Ada character' or (broom and 'Broom Hc story compatibility' or 'regular gameplay')
    if S.native and vrmod and vrmod.unhide_crosshair then
        -- Keep native target feedback visible; no forced target activation or raycast.
        pcall(function()vrmod:unhide_crosshair()end)
    end
    return S.native
end
return S
