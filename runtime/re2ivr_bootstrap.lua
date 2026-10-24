-- Complete gameplay candidate: physical input -> state machine -> checked native transaction.
if reframework:get_game_name()~="re2" then return end
if _G.RE2IVR_MVP_LOADED then return end
_G.RE2IVR_MVP_LOADED=true
local VERSION="0.6.0-belt"
local Interaction=require("re2ivr.interaction")
local VR=require("re2ivr.vr")
local Native=require("re2ivr.native")
local Visuals=require("re2ivr.visuals")
local Presentation=require("re2ivr.presentation")
local Inventory=require("re2ivr.inventory")
local Controls=require("re2ivr.controls")
local Stereo=require("re2ivr.stereo")
local Profiles=require("re2ivr.profiles")
local Models=require('re2ivr.models')
local Quickslots=require('re2ivr.quickslots')
local Belt=require('re2ivr.belt')
local settings={enabled=true,visuals=true,nativeHolsterModels=true,nativeGrenadeModels=true,cleanStereo=false,visualBindings={},profiles={["1"]="magazine"},hipX=.23,hipY=-.70,hipZ=.04,pouchX=-.23,pouchY=-.62,pouchZ=-.03,
    quickDraw=true,nativeControls=false,physicalReload=false,beltVisible=true,beltForward=.03,heightOffset=0,recenterMode='both',recenterBind='right_stick',recenterHold=1}
local settings_ok,loaded=pcall(json.load_file,"re2ivr_mvp_settings.json")
if not settings_ok then loaded=nil end
if type(loaded)=="table" then
    for _,k in ipairs({"enabled","visuals","cleanStereo","nativeHolsterModels","nativeGrenadeModels","quickDraw","nativeControls","physicalReload","beltVisible"}) do if type(loaded[k])=="boolean" then settings[k]=loaded[k] end end
    if loaded.recenterMode=='both' or loaded.recenterMode=='yaw' or loaded.recenterMode=='height' then settings.recenterMode=loaded.recenterMode end
    if loaded.recenterBind=='right_stick' or loaded.recenterBind=='left_grip_r3' or loaded.recenterBind=='off' then settings.recenterBind=loaded.recenterBind end
    if type(loaded.heightOffset)=='number' and loaded.heightOffset==loaded.heightOffset and math.abs(loaded.heightOffset)<=.30 then settings.heightOffset=loaded.heightOffset end
    if type(loaded.recenterHold)=='number' and loaded.recenterHold>=.5 and loaded.recenterHold<=3 then settings.recenterHold=loaded.recenterHold end
    if type(loaded.profiles)=="table" then
        for k,v in pairs(loaded.profiles) do if Profiles.valid[v] then settings.profiles[tostring(k)]=v end end
    end
    if type(loaded.visualBindings)=="table" then
        for k,v in pairs(loaded.visualBindings) do
            if v=="knife" or v=="grenade" or v=="flash" or v=="pistol" then settings.visualBindings[tostring(k)]=v end
        end
    end
    for _,k in ipairs({"hipX","hipY","hipZ","pouchX","pouchY","pouchZ","beltForward"}) do
        local n=loaded[k];if type(n)=="number" and n==n and math.abs(n)<=1.5 then settings[k]=n end
    end
end
-- Legacy projected lines are mono UI, not stereo meshes. Migrate them off once.
if type(loaded)~='table' or loaded.stereoVisualRevision~=1 then settings.cleanStereo=true end
settings.stereoVisualRevision=1
-- User requested physical reloads; clear a previously persisted recovery mode once.
if type(loaded)~='table' or loaded.reloadRevision~=2 then
    settings.nativeControls=false
    for wt,profile in pairs(settings.profiles) do if profile=='native' then settings.profiles[wt]=nil end end
    settings.profiles['1']=settings.profiles['1'] or 'magazine'
end
settings.reloadRevision=2
if type(loaded)~='table' or loaded.beltRevision~=1 then settings.physicalReload=false;settings.nativeControls=false;settings.beltVisible=true end
settings.beltRevision=1
local engine,current,input,state,err,ready
local gear={}
local controls=Controls.new(settings)
local stereoStatus={status='not_sampled'}
Presentation.init()
-- Stability hotfix: no new native Mesh allocation/render hooks, even with old settings.
Models.ready=false;Models.status='Native mesh copies disabled in stability build'
settings.nativeHolsterModels=false;settings.nativeGrenadeModels=false;settings.cleanStereo=true
local function snapshot(raw)
    if not raw or not raw.ranged or raw.infinity or raw.reserve==nil then return nil end
    local p,long=Profiles.resolve(raw,settings.profiles)
    if not p then return nil end
    raw.profile=settings.physicalReload and p or 'magazine'
    if not Native.fireGateReady then return nil end
    if raw.loaded<0 or raw.reserve<0 or raw.capacity<1 or raw.loaded>raw.capacity then return nil end
    return {identity=tostring(raw.equipment)..":"..tostring(raw.weapon)..":"..tostring(raw.slot),key=Native.key(raw),
        loaded=raw.loaded,capacity=raw.capacity,reserve=raw.reserve,reloadable=raw.reloadable,
        safe=raw.safe,profile=raw.profile,longGun=long,ammoFault=Native.faults[Native.key(raw)],raw=raw}
end
engine=Interaction.new(function(n,before)
    local after=Native.commit(before.raw,n)
    return snapshot(after)
end,settings)
local initialized,failure=pcall(function()
    Native.init(function(kind)
        if kind=="fire" then return not engine:can_fire() end
        -- Manual reload owns all native reload paths for a supported weapon.
        return settings.physicalReload
    end)
end)
ready=initialized;err=initialized and "" or tostring(failure)
local function stop(message)
    Native.stop();engine:reset(message);input=nil;state=nil
    Models.prepare(nil,nil,nil,nil,nil,false)
    controls:release()
end
local frames,last,vr_session=0,os.clock(),false
local tracking=false
local pendingBeltDraw
re.on_pre_application_entry("UpdateBehavior",function()
    -- Must run before the weapon adapter, including title-screen/network dialogs.
    local dialog_ok,dialog_error=pcall(Presentation.tick,os.clock())
    if not dialog_ok then Presentation.message="Dialog helper unavailable: "..tostring(dialog_error) end
    if not ready then return end
    local ok,why=pcall(function()
        local now=os.clock()
        input=VR.sample()
        if not input.active then
            Belt.publish(nil,input,gear,engine,settings,now)
            Native.control(false)
            if tracking then
                -- Refresh once before restoring visibility; do not retain an old scene weapon.
                current=Native.refresh();Native.visible(true);engine:reset('Tracking suspended: native controls restored')
            end
            tracking=false;state=nil;last=now
            return -- No per-frame inventory, geometry, calibration or diagnostic work in standby.
        end
        if not tracking then engine:reset('Tracking resumed: release and squeeze right grip');last=now end
        tracking=true
        current=Native.refresh()
        if Inventory.learn(current,settings.visualBindings) then gear={};json.dump_file("re2ivr_mvp_settings.json",settings) end
        local dt=math.min(math.max(now-last,.001),.1);last=now
        if not settings.enabled then stop("Mod disabled");return end
        state=snapshot(current)
        if controls:step(input,Native.scene_safe(),now) then
            engine:reset('Camera recentered: re-grab weapon');VR.pulse(false)
        end
        vr_session=vr_session or input.active
        local known=current and Profiles.resolve(current,settings.profiles)
        local nativeOverride=current and settings.profiles[tostring(current.wt)]=='native'
        -- A supported name alone cannot establish a working immersive input/ammo contract.
        -- Incomplete snapshots and desktop/menu sessions keep the original game's controls.
        local immersive=not settings.nativeControls and not nativeOverride and input.active and state~=nil
        local finiteBlock=not settings.nativeControls and not nativeOverride and input.active and current and current.ranged and current.infinity
        Native.control(immersive or finiteBlock or false)
        for _,event in ipairs(Native.drain_events()) do engine:spent(event.key,event.profile or (state and state.profile)) end
        local oldStage,oldPlace=engine.stage,engine.place
        if current and frames%120==0 then
            local gear_ok,items=pcall(Inventory.read,settings.visualBindings,settings.profiles)
            if gear_ok then gear=items else gear={} end
        end
        -- Check belt pickups before grip-anywhere consumes the press as a gun draw.
        local picked,pick_error,pick_kind,pick_wt=pcall(Quickslots.step,input,current,gear,engine,Native.select_subweapon,Native.select_mainweapon)
        if picked and pick_error and pick_kind=='pistol' then pendingBeltDraw={wt=tostring(pick_wt),expires=now+3} end
        if pendingBeltDraw and (not input.rightGrip or now>pendingBeltDraw.expires)then pendingBeltDraw=nil end
        if settings.nativeControls then engine:reset('Native shooting/reloading recovery mode')
        elseif picked and pick_error then engine:reset('Belt item selected');VR.pulse(false)
        else
            local controlsInput=input
            if not settings.physicalReload then controlsInput={};for k,v in pairs(input)do controlsInput[k]=v end;controlsInput.eject=false;controlsInput.leftGrip=false end
            if pendingBeltDraw and state and current.safe and tostring(current.wt)==pendingBeltDraw.wt then
                if controlsInput==input then controlsInput={};for k,v in pairs(input)do controlsInput[k]=v end end
                controlsInput.drawFromBelt=true
            end
            engine:step(controlsInput,state,dt)
            if engine.place=='held' then pendingBeltDraw=nil end
        end
        if state and state.profile=='pump' and not engine:needs_cycle(state.key) then Native.ack_pump(state.key) end
        if not picked then Quickslots.message='Grenade slot unavailable: '..tostring(pick_error)
        elseif pick_error then engine:reset('Grenade selected');VR.pulse(false) end
        Native.visible(not immersive or not current.safe or engine.place=="held")
        Belt.publish(current,input,gear,engine,settings,now)
        if oldStage~=engine.stage then VR.pulse(true) end
        if oldPlace~=engine.place then VR.pulse(false) end
        frames=frames+1
        if frames%300==0 then
            stereoStatus=Stereo.check()
            json.dump_file("re2ivr_comfort_status.json",{schema=1,stereo=stereoStatus,heightOffset=settings.heightOffset,
                recenterMode=settings.recenterMode,recenterBind=settings.recenterBind,resets=controls.resets,
                externalHeightChanges=controls.externalHeightChanges,cleanStereo=settings.cleanStereo,
                sprintBinding='native REFramework left JoystickClick -> JOG1',
                leftStickClick=input.leftStickClick,rightStickClick=input.rightStickClick})
            json.dump_file("re2ivr_presentation_status.json",Presentation.diagnostics())
            json.dump_file('re2ivr_model_status.json',{schema=1,ready=Models.ready,status=Models.status,quickslotRequests=Quickslots.requests,quickslotStatus=Quickslots.message})
            json.dump_file("re2ivr_mvp_status.json",{schema=1,version=VERSION,ready=ready,enabled=settings.enabled,
                active=input.active,profile=state and state.profile or "unsupported",weaponType=current and current.wt or nil,
                place=engine.place,stage=engine.stage,message=engine.message,locked=engine.locked,
                loaded=state and state.loaded or nil,reserve=state and state.reserve or nil,commits=engine.commits,error=err,
                nativeInfinity=current and current.infinity or false,fireGateReady=Native.fireGateReady,
                ammoFault=current and Native.faults[Native.key(current)] or nil,quickDraw=settings.quickDraw,nativeControls=settings.nativeControls,
                safe=current and current.safe,reasons=current and current.reasons,weaponName=current and current.name,
                input={rightGrip=input.rightGrip,leftGrip=input.leftGrip},snapshotAvailable=state~=nil})
        end
    end)
    if not ok then
        err=tostring(why);settings.enabled=false
        pcall(function() stop("Runtime error; mod disabled") end)
        log.error("[RE2IVR MVP] "..err)
        json.dump_file("re2ivr_mvp_error.json",{version=VERSION,error=err})
    end
end)
re.on_frame(function()
    if not ready or not settings.enabled or not settings.visuals or settings.cleanStereo or not state or not input or not input.active or not current or not current.safe then return end
    local ok,why=pcall(Visuals.draw,engine,input,state,gear)
    if not ok then err="Visual proxies unavailable: "..tostring(why);settings.visuals=false end
end)
re.on_script_reset(function() pcall(function() stop("Scripts reset") end);pcall(Models.clear);_G.RE2IVR_MVP_LOADED=nil end)
re.on_draw_ui(function()
    imgui.text("RE2 Immersive VR "..VERSION)
    imgui.text('Default reload: normal game button. Physical reload is optional while belt is being developed.')
    if imgui.button(settings.physicalReload and 'Use native button reload' or 'Enable experimental physical reload') then
        settings.physicalReload=not settings.physicalReload;engine:reset('Reload mode changed');Native.stop();json.dump_file('re2ivr_mvp_settings.json',settings)
    end
    if imgui.button(settings.beltVisible and 'Hide SteamVR spatial belt' or 'Show SteamVR spatial belt') then settings.beltVisible=not settings.beltVisible;json.dump_file('re2ivr_mvp_settings.json',settings) end
    for _,cm in ipairs({0,3,6})do if imgui.button('Belt forward: '..cm..' cm')then settings.beltForward=cm/100;json.dump_file('re2ivr_mvp_settings.json',settings)end end
    if imgui.button('Close current error dialog') then Presentation.request(false) end
    if imgui.button('Force dismiss current error dialog') then Presentation.request(true) end
    for _,mode in ipairs({'mouse','enter','space'}) do
        if imgui.button('Controller dialog input: '..mode) then Presentation.inputMode=mode end
        if imgui.button('Send real '..mode..' after Insert closes') then Presentation.request_input(mode,true) end
    end
    imgui.text('Left grip + right B for 1 second: '..Presentation.inputMode..' input. Requires new Play.cmd helper.')
    imgui.text('Mouse clicks at current desktop cursor: place it on OK in SteamVR Desktop, then close dashboard.')
    if imgui.button('Refresh input helper status') then Presentation.helper_status() end
    imgui.text('RE NET: Main menu > Options > RE NET > Play Data Settings > Off.')
    imgui.text("State: "..engine.place.." / "..engine.stage)
    imgui.text(engine.message)
    if err~="" then imgui.text(err) end
    imgui.text("Close stuck dialog: hold LEFT grip + RIGHT B for one second, then release.")
    if Presentation.message~="" then imgui.text(Presentation.message) end
    imgui.text(Models.status)
    if Quickslots.message~='' then imgui.text(Quickslots.message) end
    imgui.text('Belt uses separate SteamVR overlays; game mesh copies remain disabled.')
    imgui.text(Belt.status)
    if imgui.button('Refresh SteamVR belt status')then
        local ok,s=pcall(json.load_file,'re2ivr_belt_status.json');Belt.status=ok and type(s)=='table' and tostring(s.status) or 'No belt helper: launch new Play.cmd'
    end
    if not ready then return end
    if imgui.button(settings.nativeControls and 'Return to physical reloads' or 'Recovery: native shooting and reloads') then
        settings.nativeControls=not settings.nativeControls;Native.stop();engine:reset('Weapon controls changed')
        json.dump_file('re2ivr_mvp_settings.json',settings)
    end
    if imgui.button(settings.quickDraw and 'Draw only at holster' or 'Quick draw: grip anywhere') then
        settings.quickDraw=not settings.quickDraw;json.dump_file('re2ivr_mvp_settings.json',settings)
    end
    imgui.text('Quick draw default: release RIGHT grip, then squeeze anywhere to hold weapon.')
    imgui.text('RT one-eye body bug: try another costume, or Steam non-RT branch. See VR-TROUBLESHOOTING.md.')
    imgui.text('Stability: SteamVR per-application RE2 resolution 100%. Do not raise supersampling during crash recovery.')
    imgui.text('Walk: left stick. Sprint: click LEFT stick (native RE2 running mode).')
    imgui.text('Recenter: '..settings.recenterBind..', hold '..settings.recenterHold..' s while sticks are neutral.')
    imgui.text(controls.message)
    imgui.text('Height correction: '..string.format('%.0f',settings.heightOffset*100)..' cm')
    for _,entry in ipairs({{'Height -2 cm',-.02},{'Height +2 cm',.02}}) do
        if imgui.button(entry[1]) then
            settings.heightOffset=math.max(-.30,math.min(.30,settings.heightOffset+entry[2]));json.dump_file('re2ivr_mvp_settings.json',settings)
        end
    end
    if imgui.button('Reset height correction to 0 cm') then settings.heightOffset=0;json.dump_file('re2ivr_mvp_settings.json',settings) end
    for _,mode in ipairs({'both','yaw','height'}) do
        if imgui.button('Recenter mode: '..mode) then settings.recenterMode=mode;json.dump_file('re2ivr_mvp_settings.json',settings) end
        if imgui.button('Apply recenter '..mode..' after menu closes') then controls:queue(mode,os.clock()) end
    end
    for _,bind in ipairs({'right_stick','left_grip_r3','off'}) do
        if imgui.button('Recenter binding: '..bind) then settings.recenterBind=bind;json.dump_file('re2ivr_mvp_settings.json',settings) end
    end
    for _,seconds in ipairs({.5,1,2}) do
        if imgui.button('Recenter hold: '..seconds..' seconds') then settings.recenterHold=seconds;json.dump_file('re2ivr_mvp_settings.json',settings) end
    end
    if imgui.button(settings.cleanStereo and 'Show equipment outlines again' or 'Stereo reference view: hide mod outlines') then
        settings.cleanStereo=not settings.cleanStereo;json.dump_file('re2ivr_mvp_settings.json',settings)
    end
    imgui.text('Stereo: '..stereoStatus.status..'. Eye geometry is provided by SteamVR.')
    if imgui.button('Refresh stereo diagnostics') then
        stereoStatus=Stereo.check();json.dump_file('re2ivr_stereo_check.json',stereoStatus)
    end
    if imgui.button(settings.enabled and "Disable immersive mode" or "Enable immersive mode") then
        settings.enabled=not settings.enabled;stop("Mode changed");json.dump_file("re2ivr_mvp_settings.json",settings)
    end
    for _,row in ipairs(gear) do
        if row.sub then
            imgui.text("Belt: inventory slot "..row.slot..", weapon type "..row.weaponType.." -> "..row.kind)
            for _,kind in ipairs({"knife","grenade","flash"}) do
                if imgui.button("Show as "..kind.."##gear"..row.weaponType..kind) then
                    settings.visualBindings[row.weaponType]=kind;gear={};json.dump_file("re2ivr_mvp_settings.json",settings)
                end
            end
        end
    end
    if imgui.button(settings.visuals and "Hide interaction proxies" or "Show interaction proxies") then
        settings.visuals=not settings.visuals;json.dump_file("re2ivr_mvp_settings.json",settings)
    end
    if current then
        local profile=Profiles.resolve(current,settings.profiles)
        imgui.text("Weapon: "..current.name.." / type "..tostring(current.wt).."; loaded "..current.loaded.." / "..current.capacity)
        imgui.text('Reload profile: '..tostring(profile or 'native game controls'))
        if not current.ranged then imgui.text('Non-Gun weapon: native game controls retained') end
        if current.infinity and Native.is_gun(current) and settings.profiles[tostring(current.wt)]~='native' then imgui.text('Infinite bonus firearm blocked in finite-ammo VR mode: equip a regular weapon') end
        if Native.faults[Native.key(current)] then imgui.text(Native.faults[Native.key(current)]..'; inspect Collect report') end
        if not Native.fireGateReady then imgui.text('Direct Gun fire gate unavailable: immersive weapon profiles disabled') end
        for _,kind in ipairs({'magazine','revolver','pump','breech','native'}) do
            if imgui.button('Reload profile '..kind..'##weapon') then
                settings.profiles[tostring(current.wt)]=kind;engine:reset();json.dump_file('re2ivr_mvp_settings.json',settings)
            end
        end
    end
    imgui.text("Right hip + right grip: draw; release grip: return. Right B: eject/open/close.")
    imgui.text("Left pouch + left grip: magazine/round. Insert physically. Grasp, pull and release slide.")
    imgui.text("Movement, aim, inventory, interact, knife/grenades: REFramework/game controls.")
    imgui.text("MVP proxies are primitives; native magazine/slide/cylinder bones are not animated.")
end)
