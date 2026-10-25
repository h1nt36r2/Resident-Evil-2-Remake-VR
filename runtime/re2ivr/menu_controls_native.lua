-- No simulated desktop keys or binding changes. Uses the game's current menu,
-- native shortcut assignment API and the GUI triggers used upstream for D-pad floors.
local N={status='Menu controls not sampled',policy=require('re2ivr.menu_controls').new()}
local Shortcuts=require('re2ivr.shortcuts')
local inventoryState
local function context()
    local gui=sdk.get_managed_singleton(sdk.game_namespace('gui.GUIMaster'))
    if not gui then return nil end
    local busy=gui:call('isBusyGeneralDialog')
    if busy then return nil end
    local extraOK,extraBusy=pcall(function()return gui:call('isBusyGeneralDialogEx')end)
    if extraOK and extraBusy==true then return nil end
    if gui:call('get_IsOpenMap')==true then return 'map',gui end
    if inventoryState==nil then
        local t=sdk.find_type_definition(sdk.game_namespace('gui.GUIMaster.GuiState'))
        for _,f in ipairs(t and t:get_fields() or {})do
            if f:is_static() and f:get_name():lower()=='inventory' then inventoryState=f:get_data(nil) end
        end
    end
    if inventoryState~=nil and gui:call('get_IsOpenInventory')==true and gui:call('get_State_')==inventoryState then return 'inventory',gui end
end
function N.assign(direction)
    local mode=context();if mode~='inventory' then return false,'Not a regular inventory screen' end
    local manager=sdk.get_managed_singleton(sdk.game_namespace('PlayerManager'))
    local player=manager and manager:call('get_CurrentPlayer')
    local inv=player and player:call('getComponent(System.Type)',sdk.typeof(sdk.game_namespace('survivor.Inventory')))
    if not inv then return false,'Inventory unavailable' end
    local slot=inv:call('get_MainSlot')
    if not slot or slot:call('get_IsEmpty') or slot:call('get_IsDeadSlot') or not slot:call('get_IsWeapon')
        or slot:call('get_IsSubWeapon') or not inv:call('enableSetShortcut',slot) then return false,'Equip a main weapon before assigning its shortcut' end
    local value=Shortcuts.direction(direction)
    if value==nil then return false,'Shortcut direction unavailable' end
    local slots=inv:call('get_Slots');local count=slots and slots:call('get_Count') or 0
    if count<0 or count>256 then return false,'Invalid inventory size' end
    local index
    for n=0,count-1 do if slots:call('get_Item(System.Int32)',n)==slot then index=n;break end end
    if index==nil then return false,'Equipped weapon no longer in inventory' end
    local setter
    local invType=sdk.find_type_definition(sdk.game_namespace('survivor.Inventory'))
    for _,m in ipairs(invType and invType:get_methods() or {}) do
        local p=m:get_param_types()
        if m:get_name()=='setShortcutSlot' and #p==2 and p[1]:get_full_name()=='System.Int32'
            and p[2]:get_full_name()==sdk.game_namespace('EquipmentDefine.Shortcut')
            and m:get_return_type():get_full_name()=='System.Boolean' then setter=m;break end
    end
    if not setter then return false,'Shortcut assignment method unavailable' end
    local accepted=setter:call(inv,index,value)
    if accepted~=true then return false,'Game rejected shortcut assignment' end
    local after=Shortcuts.read(inv)[direction]
    if not after or after.weaponType~=tostring(slot:call('get_WeaponType')) then return false,'Shortcut verification failed; not retried' end
    return true,'Equipped weapon assigned: '..direction
end
function N.floor(direction)
    if direction~='up' and direction~='down' then return false,'Invalid map direction' end
    local mode,gui=context();if mode~='map' then return false,'Map is not open' end
    local input=gui:call('get_Input');if not input then return false,'Map input unavailable' end
    local name=direction=='up' and 'set_IsTriggerMoveUpD' or 'set_IsTriggerMoveDownD'
    local t=input:get_type_definition();local found
    for _,m in ipairs(t:get_methods()) do
        local p=m:get_param_types()
        if m:get_name()==name and #p==1 and p[1]:get_full_name()=='System.Boolean' and m:get_return_type():get_full_name()=='System.Void' then found=m;break end
    end
    if not found then return false,'Map trigger unavailable: '..name end
    found:call(input,true)
    return true,'Map floor request: '..direction
end
function N.tick()
    local i={active=false}
    if vrmod and vrmod:is_hmd_active() and vrmod:is_using_controllers() and not reframework:is_drawing_ui() then
        local action=vrmod:get_action_joystick_click()
        local axis=vrmod:get_right_stick_axis()
        if axis and type(axis.x)=='number' and type(axis.y)=='number' and axis.x==axis.x and axis.y==axis.y and math.abs(axis.x)<=1.1 and math.abs(axis.y)<=1.1 then
            i={active=true,leftStickClick=vrmod:is_action_active(action,vrmod:get_left_joystick())==true,
                rightStickClick=vrmod:is_action_active(action,vrmod:get_right_joystick())==true,rightStickAxis={x=axis.x,y=axis.y}}
        end
    end
    N.policy:step(i,context(),N.assign,N.floor)
    N.status=N.policy.status
end
return N
