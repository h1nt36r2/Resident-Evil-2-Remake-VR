-- UI recovery independent of equipped weapon: works in title/menu scenes too.
local P={message="",closed=0,latched=false,heldSince=nil,frames=0}
local close,busy,force,busyEx
local function find(t,name,ret)
    if not t then return nil end
    for _,m in ipairs(t:get_methods()) do
        if m:get_name()==name and #m:get_param_types()==0 and m:get_return_type():get_full_name()==ret then return m end
    end
end
function P.init()
    local t=sdk.find_type_definition(sdk.game_namespace('gui.GUIMaster'))
    close=find(t,'closeGeneralDialog','System.Void')
    busy=find(t,'isBusyGeneralDialog','System.Boolean')
    force=find(t,'forceCloseGeneralDialog','System.Void')
    busyEx=find(t,'isBusyGeneralDialogEx','System.Boolean')
    P.available=close~=nil and busy~=nil
end
function P.request(forceClose)
    P.queued=forceClose and 'force' or 'close'
end
P.inputMode='mouse'
local inputCounter=0
local inputSession=tostring({})
local function helper_ready()
    local ok,s=pcall(json.load_file,'re2ivr_input_bridge.json')
    return ok and type(s)=='table' and type(s.time)=='number' and math.abs(os.time()-s.time)<=10
end
function P.request_input(mode,explicit)
    if mode~='mouse' and mode~='enter' and mode~='space' then return end
    P.queuedInput={mode=mode,explicit=explicit==true,expires=(P.now or os.clock())+10}
    P.message='Desktop input queued: close Insert menu first'
end
function P.helper_status()
    local ok,s=pcall(json.load_file,'re2ivr_input_bridge.json')
    P.message=ok and type(s)=='table' and ('Input helper: '..tostring(s.status)) or 'Input helper not found: launch Play.cmd'
end
local function menu_open(gui)
    if not gui then return false end
    if busy and busy:call(gui) then return true end
    if busyEx and busyEx:call(gui) then return true end
    local ok,open=pcall(function()return gui:call('get_IsGuiOpen')end)
    return ok and open==true
end
local function dismiss(mode)
    local gui=sdk.get_managed_singleton(sdk.game_namespace('gui.GUIMaster'))
    local open=gui and (busy:call(gui) or (busyEx and busyEx:call(gui)))
    if not open then P.message='No general dialog detected; use game RE NET settings';return end
    if mode=='force' and force then force:call(gui) else close:call(gui) end
    P.closed=P.closed+1;P.message='Dialog close requested ('..mode..')'
    json.dump_file('re2ivr_dialog_status.json',{requests=P.closed,mode=mode,forceAvailable=force~=nil})
end
function P.tick(now)
    P.now=now
    if P.queuedInput then
        local q=P.queuedInput
        if now>q.expires then P.queuedInput=nil;P.message='Desktop input request expired'
        elseif not reframework.is_drawing_ui or not reframework:is_drawing_ui() then
            P.queuedInput=nil
            local gui=sdk.get_managed_singleton(sdk.game_namespace('gui.GUIMaster'))
            if not q.explicit and not menu_open(gui) then P.message='No game menu/dialog: click suppressed'
            elseif not helper_ready() then P.message='Input helper unavailable: start game through new Play.cmd'
            else
                inputCounter=inputCounter+1
                json.dump_file('re2ivr_desktop_request.json',{schema=1,id=inputSession..':'..inputCounter,mode=q.mode,time=os.time()})
                P.message='Real '..q.mode..' input requested; helper requires RE2 foreground'
            end
        end
    end
    -- UI requests work without a headset, controller bindings or a weapon snapshot.
    if P.queued then local mode=P.queued;P.queued=nil;if P.available then dismiss(mode) end end
    if not P.available or not vrmod or not vrmod:is_hmd_active() or not vrmod:is_using_controllers() then
        P.heldSince=nil;P.latched=false;return
    end
    local left,right=vrmod:get_left_joystick(),vrmod:get_right_joystick()
    local combo=vrmod:is_action_active(vrmod:get_action_grip(),left)
        and vrmod:is_action_active(vrmod:get_action_b_button(),right)
    if not combo then P.heldSince=nil;P.latched=false;return end
    if P.latched then return end
    local gui=sdk.get_managed_singleton(sdk.game_namespace('gui.GUIMaster'))
    if not menu_open(gui) then P.heldSince=nil;return end
    P.heldSince=P.heldSince or now
    if now-P.heldSince>=1 then
        -- Explicit user-requested close, never automatic acceptance, never hidden every frame.
        P.latched=true
        if helper_ready() then P.request_input(P.inputMode) else dismiss(force and 'force' or 'close') end
    end
end
function P.diagnostics()
    local out={dialogCloseAvailable=P.available,dialogCloseRequests=P.closed}
    local ok,value=pcall(function()
        local function matrix(m)
            local result={}
            for c=0,3 do local v=m[c];result[#result+1]={v.x,v.y,v.z,v.w} end
            return result
        end
        return {openvr=vrmod:is_openvr_loaded(),openxr=vrmod:is_openxr_loaded(),hmd=vrmod:is_hmd_active(),
            controllers=#vrmod:get_controllers(),firstPerson=firstpersonmod and firstpersonmod:is_enabled() or false,
            firstPersonUsed=firstpersonmod and firstpersonmod:will_be_used() or false,
            projection=matrix(vrmod:get_current_projection_matrix(false)),
            otherProjection=matrix(vrmod:get_current_projection_matrix(true)),
            eye=matrix(vrmod:get_current_eye_transform(false)),otherEye=matrix(vrmod:get_current_eye_transform(true))}
    end)
    out.runtime=ok and value or nil;out.readError=not ok and tostring(value) or nil
    return out
end
return P
