-- Read actual assigned main shortcut slots; never guess enum ordinals or rewrite bindings.
local S={status='Shortcut API not sampled'}
local directions
local function resolve()
    if directions then return directions end
    local t=sdk.find_type_definition(sdk.game_namespace('EquipmentDefine.Shortcut'))
    if not t then S.status='Shortcut enum unavailable';return {} end
    local found,names={},{}
    for _,f in ipairs(t:get_fields()) do
        local name=f:get_name():lower():gsub('_','')
        if f:is_static() then
            names[#names+1]=f:get_name()
            for _,direction in ipairs({'up','down','left','right'}) do
                if name==direction or name=='shortcut'..direction then found[direction]=f:get_data(nil) end
            end
        end
    end
    if found.up==nil or found.down==nil then S.status='Shortcut directions unavailable: '..table.concat(names,',');return {} end
    directions=found;return found
end
function S.read(inv)
    local out={}
    for name,value in pairs(resolve()) do
        local slot=inv:call('getSlot('..sdk.game_namespace('EquipmentDefine.Shortcut')..')',value)
        if slot and not slot:call('get_IsEmpty') and not slot:call('get_IsDeadSlot')
            and (slot:call('get_IsWeapon') or slot:call('get_IsSubWeapon')) then
            out[name]={weaponType=tostring(slot:call('get_WeaponType')),sub=slot:call('get_IsSubWeapon')==true}
        end
    end
    S.status='Live shortcut assignments read';return out
end
return S
