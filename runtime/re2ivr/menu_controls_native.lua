-- No simulated desktop keys or binding changes. Uses the game's current menu,
-- native shortcut assignment API and the GUI triggers used upstream for D-pad floors.
local N={status='Menu controls not sampled',policy=require('re2ivr.menu_controls').new()}
local Shortcuts=require('re2ivr.shortcuts')
local function context()
    local gui=sdk.get_managed_singleton(sdk.game_namespace('gui.GUIMaster'))
    if not gui then return nil end
    local busy=gui:call('isBusyGeneralDialog')
    if busy then return nil end
    local extraOK,extraBusy=pcall(function()return gui:call('isBusyGeneralDialogEx')end)
    if extraOK and extraBusy==true then return nil end
    if gui:call('get_IsOpenMap')==true then return 'map',gui end
    -- IsOpenInventory is the native semantic guard. Exact GuiState enum labels
    -- vary between builds/subscreens and must not reject an otherwise open inventory.
    if gui:call('get_IsOpenInventory')==true then return 'inventory',gui end
end
local Bindings=require('re2ivr.bindings')
local function inventory()
    local manager=sdk.get_managed_singleton(sdk.game_namespace('PlayerManager'))
    local player=manager and manager:call('get_CurrentPlayer')
    return player and player:call('getComponent(System.Type)',sdk.typeof(sdk.game_namespace('survivor.Inventory')))
end
function N.assign(direction,index)
    local mode=context();if mode~='inventory' then return false,'Open the regular inventory first' end
    local inv=inventory();if not inv then return false,'Inventory unavailable'end
    local owned=Bindings.owned(inv)
    local slot
    if index~=nil then
        for _,row in ipairs(owned)do if row.index==index then slot=row.slot;break end end
    else
        local main=inv:call('get_MainSlot')
        for _,row in ipairs(owned)do if row.slot==main then slot=row.slot;index=row.index;break end end
    end
    if not slot then return false,'Choose an owned main weapon from the assignment list'end
    local native=false
    local nativeOK,nativeReason=pcall(function()
        local value=Shortcuts.direction(direction)
        if value==nil then return 'Native direction enum unavailable'end
        local setter,reverse
        local t=sdk.find_type_definition(sdk.game_namespace('survivor.Inventory'))
        for _,m in ipairs(t and t:get_methods() or {})do
            local p=m:get_param_types()
            local ret=m:get_return_type():get_full_name()
            if m:get_name()=='setShortcutSlot' and #p==2 and (ret=='System.Boolean' or ret=='System.Void')then
                local a,b=p[1]:get_full_name(),p[2]:get_full_name()
                if a=='System.Int32' and b==sdk.game_namespace('EquipmentDefine.Shortcut')then setter=m;reverse=false;break end
                if b=='System.Int32' and a==sdk.game_namespace('EquipmentDefine.Shortcut')then setter=m;reverse=true;break end
            end
        end
        if not setter then return 'Native assignment method unavailable'end
        if reverse then setter:call(inv,value,index)else setter:call(inv,index,value)end
        local row=Shortcuts.native_read(inv)[direction]
        native=row~=nil and row.weaponType==tostring(slot:call('get_WeaponType'))
        return native and 'Native assignment verified' or 'Native assignment not verified'
    end)
    local ok,why=Bindings.assign(inv,slot,direction,native and 'native' or 'mod')
    N.status=why;N.policy.status=why
    if ok then pcall(function()vrmod:apply_haptic_vibration(0,.08,80,.4,vrmod:get_left_joystick())end)end
    pcall(function()
        json.dump_file('re2ivr_shortcut_status.json',{schema=1,direction=direction,index=index,
            saved=ok,nativeVerified=native,nativeReason=tostring(nativeReason),nativeCallOK=nativeOK,status=why})
    end)
    return ok,why
end
function N.ui()
    if not imgui.tree_node('Assign weapons to quick slots')then return end
    local mode=context()
    if mode~='inventory'then
        imgui.text('Open the game inventory, then open this panel.')
    else
        local inv=inventory()
        local ok,rows=pcall(Bindings.owned,inv)
        imgui.text('Select a weapon below. Down = behind RIGHT shoulder; Up = RIGHT hip.')
        imgui.text('Native slots are verified; if rejected, the belt assignment is saved separately.')
        if ok then
            for _,row in ipairs(rows)do
                imgui.text(row.name)
                for _,direction in ipairs({'up','down','left','right'})do
                    if imgui.button(direction..'##assign'..row.index..direction)then N.assign(direction,row.index)end
                end
            end
            if imgui.button('Use game assignments again##clearBeltOverrides')then
                N.status=Bindings.clear(inv) and 'Saved belt overrides cleared' or 'Could not clear belt overrides'
            end
        else imgui.text('Inventory list unavailable: '..tostring(rows))end
    end
    imgui.text(N.status);imgui.tree_pop()
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
