-- Live-schema-backed native RE2 adapter. No raw inventory writes.
local N={fireGateReady=false,events={},faults={},pumpPending={},finiteOnly=true,auditFrame=0,ledger={}}
local threads={}
local function context()
    local id=thread.get_id()
    if not threads[id] then threads[id]={equipment={},gunDepth=0} end
    return threads[id]
end
local function key(s) return s and (tostring(s.slot)..':'..tostring(s.wt)) end
N.key=key
local equipment_t=sdk.find_type_definition(sdk.game_namespace("survivor.Equipment"))
local slot_t=sdk.find_type_definition(sdk.game_namespace("inventory.Slot"))
local gui_t=sdk.find_type_definition(sdk.game_namespace("gui.GUIMaster"))
local condition_t=sdk.find_type_definition(sdk.game_namespace("survivor.SurvivorCondition"))
local WT=sdk.game_namespace("EquipmentDefine.WeaponType")
local function method(t,name,args,returns)
    if not t then error("Missing type for "..name) end
    for _,m in ipairs(t:get_methods()) do
        if m:get_name()==name and m:get_return_type():get_full_name()==returns then
            local p=m:get_param_types()
            local same=#p==#args
            for i,v in ipairs(args) do if not p[i] or p[i]:get_full_name()~=v then same=false end end
            if same then return m end
        end
    end
    error("Incompatible signature: "..name)
end
local api={}
local current,permit_reload=nil,nil
local enabled=false
local policy=function() return false end
local waiting={}
local function account(raw,baseline,accepted)
    if raw.player~=N.sessionPlayer then return end -- discard callbacks from a previous player scene
    local k=key(raw)
    local ok,n=pcall(function() return api.loaded:call(raw.equipment,raw.wt) end)
    if ok and n<baseline then
        N.events[#N.events+1]={key=k,spent=baseline-n,loaded=n,profile=raw.profile}
        N.ledger[k]=n;waiting[k]=nil
        if raw.profile=='pump' then N.pumpPending[k]=true end
    elseif accepted then
        waiting[k]=waiting[k] or {slot=raw.slot,loaded=baseline,untilFrame=N.auditFrame+12}
    elseif raw.profile=='pump' then N.pumpPending[k]=nil end
end
local function blocked()
    if not current then return true end
    local k=key(current)
    return (N.finiteOnly and current.infinity) or N.faults[k] or waiting[k] or N.pumpPending[k] or policy('fire')
end
local function component(player,name)
    local t=sdk.typeof(sdk.game_namespace(name))
    return t and player:call("getComponent(System.Type)",t) or nil
end
local function read()
    local manager=sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
    local player=manager and manager:call("get_CurrentPlayer")
    N.observedPlayer=player
    if not player then return nil,"No player" end
    local eq=component(player,"survivor.Equipment")
    local condition=component(player,"survivor.SurvivorCondition")
    local gui=sdk.get_managed_singleton(sdk.game_namespace("gui.GUIMaster"))
    if not eq or not condition or not gui then return nil,"Incomplete scene" end
    local weapon=eq:call("get_EquipWeapon")
    local slot=eq:call("get_EquipSlot")
    if not weapon or not slot then return nil,"No equipped weapon" end
    local wt=eq:call("get_EquipType")
    local gun_ok,gun=pcall(function() return N.gunType and weapon:get_type_definition():is_a(N.gunType) end)
    local ranged=gun_ok and gun==true
    local reasons={}
    for name,value in pairs({gui=gui:call("get_IsGuiOpen"),dead=condition:call("get_IsDead"),
        event=condition:call("get_IsEvent"),grabbed=condition:call("get_IsJack"),
        changingWeapon=condition:call("get_IsChangeWeapon"),vanillaReload=condition:call("get_IsReload")}) do
        if value then reasons[#reasons+1]=name end
    end
    local inventory=component(player,"survivor.Inventory")
    local reserve=nil; if not ranged then reserve=0 end
    if ranged and inventory then
        local bullet=slot:call("get_BulletID")
        local slots=inventory:call("get_Slots")
        if slots then
            reserve=0
            local count=slots:call("get_Count")
            if count<0 or count>256 then error("Invalid inventory list size") end
            for i=0,count-1 do
                local item=slots:call("get_Item(System.Int32)",i)
                if item and item:call("get_IsItem") and item:call("get_ItemID")==bullet then
                    local amount=item:call("get_Number")
                    if amount<0 then error("Invalid ammunition stack") end
                    reserve=reserve+amount
                end
            end
        end
    end
    local name_ok,name=pcall(function() return slot:call('get_WeaponName') end)
    return {player=player,equipment=eq,weapon=weapon,slot=slot,wt=wt,name=name_ok and tostring(name) or '',ranged=ranged,safe=#reasons==0,reasons=reasons,reserve=reserve,
        loaded=ranged and api.loaded:call(eq,wt) or 0,capacity=ranged and api.capacity:call(slot) or 0,
        reloadable=ranged and api.reloadable:call(eq,wt) or 0,infinity=slot:call("get_Infinity")}
end
local function same(a,b)
    return a and b and a.player==b.player and a.weapon==b.weapon and a.equipment==b.equipment and a.slot==b.slot
        and a.wt==b.wt and a.loaded==b.loaded and a.capacity==b.capacity and a.reloadable==b.reloadable and a.reserve==b.reserve
end

local hidden=nil
local function reload_scene_safe()
    if not current then return false end
    if current.safe then return true end
    if not current.reasons or #current.reasons==0 then return false end
    for _,reason in ipairs(current.reasons) do if reason~='vanillaReload' then return false end end
    return true
end
local function block(m,kind,getter)
    sdk.hook(m,function(args)
        local affected=enabled and current and (current.safe or (kind=='reload' and reload_scene_safe())) and sdk.to_managed_object(args[2])==current.equipment
            and not (kind=="reload" and permit_reload==thread.get_id()) and ((kind=='fire' and blocked()) or (kind~='fire' and policy(kind)))
        thread.get_hook_storage().re2ivr_mvp_block=affected
        if affected and not getter then return sdk.PreHookResult.SKIP_ORIGINAL end
    end,function(retval)
        if thread.get_hook_storage().re2ivr_mvp_block and m:get_return_type():get_full_name()=="System.Boolean" then return sdk.to_ptr(0) end
        return retval
    end)
end
function N.init(predicate)
    policy=predicate
    if not thread or not thread.get_hook_storage or not thread.get_id then error("Thread-safe hooks unavailable") end
    api.loaded=method(equipment_t,"getBulletNumber",{WT},"System.Int32")
    api.reloadable=method(equipment_t,"getReloadableBulletNumber",{WT},"System.Int32")
    api.reload=method(equipment_t,"executeReload",{WT,"System.Int32"},"System.Boolean")
    api.capacity=method(slot_t,"get_MaxNumber",{},"System.Int32")
    api.change=method(equipment_t,'changeWeapon',{sdk.game_namespace('EquipmentDefine.EquipCategory'),WT,sdk.game_namespace('EquipmentDefine.WeaponParts')},'System.Void')
    local category=sdk.find_type_definition(sdk.game_namespace('EquipmentDefine.EquipCategory'))
    for _,field in ipairs(category and category:get_fields() or {}) do
        local name=field:get_name():lower():gsub('_','')
        if (name=='sub' or name=='subweapon') and field:is_static() then api.subCategory=field:get_data(nil) end
        if (name=='main' or name=='mainweapon') and field:is_static() then api.mainCategory=field:get_data(nil) end
    end
    method(slot_t,"get_Infinity",{},"System.Boolean")
    method(slot_t,"get_BulletID",{},sdk.game_namespace("gamemastering.Item.ID"))
    method(slot_t,"get_ItemID",{},sdk.game_namespace("gamemastering.Item.ID"))
    method(slot_t,"get_IsItem",{},"System.Boolean")
    method(slot_t,"get_Number",{},"System.Int32")
    method(gui_t,"get_IsGuiOpen",{},"System.Boolean")
    for _,name in ipairs({"get_IsDead","get_IsEvent","get_IsJack","get_IsChangeWeapon","get_IsReload"}) do
        method(condition_t,name,{},"System.Boolean")
    end
    -- The draw method was exported from the live Implement schema.
    api.draw=method(sdk.find_type_definition(sdk.game_namespace("implement.Implement")),"requestSetDraw",{"System.Boolean"},"System.Void")
    block(method(equipment_t,"get_EnableFire",{},"System.Boolean"),"fire",true)
    block(method(equipment_t,"get_EnableAutoReload",{},"System.Boolean"),"reload",true)
    -- NEVER SKIP Equipment.executeFire: it may own the native ammunition debit.
    -- Observe it without changing its return value; gate requestFire and Gun.executeFire instead.
    local fire=method(equipment_t,'executeFire',{WT,'System.Int32'},'System.Boolean')
    sdk.hook(fire,function(args)
        local st=thread.get_hook_storage()
        st.eqctx=nil
        if enabled and current and current.safe and sdk.to_managed_object(args[2])==current.equipment
            and sdk.to_int64(args[3])==current.wt then
            local c=context();local before=current
            local ok,n=pcall(function() return api.loaded:call(before.equipment,before.wt) end)
            local entry={raw=before,key=key(before),loaded=math.max(ok and n or before.loaded,N.ledger[key(before)] or before.loaded),allowed=not blocked(),gunSeen=false}
            c.equipment[#c.equipment+1]=entry;st.eqctx=entry
        end
    end,function(retval)
        local e=thread.get_hook_storage().eqctx
        if e then
            local c=context();if c.equipment[#c.equipment]==e then table.remove(c.equipment) end
            account(e.raw,e.loaded,e.gunExecuted==true)
        end
        return retval
    end)
    block(method(equipment_t,'requestFire',{},'System.Void'),'fire')
    local gun_t=sdk.find_type_definition(sdk.game_namespace('implement.Gun'))
    N.gunType=gun_t
    local signatures={}
    for _,m in ipairs(gun_t and gun_t:get_methods() or {}) do
        local ret=m:get_return_type():get_full_name()
        if m:get_name()=='executeFire' and not m:is_static() and (ret=='System.Void' or ret=='System.Boolean') then
            local args={};for _,t in ipairs(m:get_param_types()) do args[#args+1]=t:get_full_name() end
            signatures[#signatures+1]={name='executeFire',args=args,returns=ret}
            sdk.hook(m,function(a)
                local st=thread.get_hook_storage();st.gunBlocked=false;st.gunTracked=false;st.outside=nil;st.entry=nil
                if enabled and current and current.safe and sdk.to_managed_object(a[2])==current.weapon then
                    local c=context();local entry=c.equipment[#c.equipment]
                    st.entry=entry
                    local allowed=(entry and entry.allowed) or (not entry and not blocked())
                    if c.gunDepth>0 then allowed=true end -- preserve nested native overloads of the same shot
                    st.gunBlocked=not allowed
                    if not allowed then return sdk.PreHookResult.SKIP_ORIGINAL end
                    if not entry and c.gunDepth==0 then
                        local ok,n=pcall(function() return api.loaded:call(current.equipment,current.wt) end)
                        st.outside={raw=current,loaded=math.max(ok and n or current.loaded,N.ledger[key(current)] or current.loaded)}
                    end
                    c.gunDepth=c.gunDepth+1;st.gunTracked=true
                    if entry then entry.gunSeen=true end
                    if current.profile=='pump' then N.pumpPending[key(current)]=true end
                end
            end,function(retval)
                local st=thread.get_hook_storage()
                if st.gunTracked then local c=context();c.gunDepth=math.max(0,c.gunDepth-1) end
                if st.gunTracked and st.entry and (ret=='System.Void' or sdk.to_int64(retval)~=0) then st.entry.gunExecuted=true end
                if st.outside then account(st.outside.raw,st.outside.loaded,ret=='System.Void' or sdk.to_int64(retval)~=0) end
                if st.gunBlocked and ret=='System.Boolean' then return sdk.to_ptr(0) end
                return retval
            end)
        end
    end
    N.fireGateReady=#signatures>0
    json.dump_file('re2ivr_fire_contract.json',{schema=1,gunGateReady=N.fireGateReady,gunMethods=signatures,
        equipmentFire='observer only: original and return preserved',finiteOnly=true})
    block(api.reload,"reload")
    -- RE2 also exposes the category overload, used by the normal button/automatic path.
    block(method(equipment_t,'executeReload',{sdk.game_namespace('EquipmentDefine.EquipCategory'),'System.Int32'},'System.Boolean'),'reload')
    block(method(equipment_t,"requestReload",{},"System.Void"),"reload")
end
function N.refresh()
    local ok,nextCurrent=pcall(read)
    if not ok then
        -- Scene construction can briefly invalidate a component. Retry next sample;
        -- do not persistently disable the mod or dereference the previous scene.
        N.readError=tostring(nextCurrent);current=nil;enabled=false;hidden=nil
        return nil
    end
    N.readError=nil
    if N.sessionPlayer~=N.observedPlayer then
        -- Fresh player/new game owns a fresh ammo ledger. Never touch the old scene's weapon.
        N.sessionPlayer=N.observedPlayer;N.sceneEpoch=(N.sceneEpoch or 0)+1
        enabled=false;hidden=nil;waiting={};N.events={};N.faults={};N.pumpPending={};N.ledger={};N.auditFrame=0
    end
    current=nextCurrent;if current and current.safe then N.auditFrame=N.auditFrame+1 end
    if current then
        local k=key(current);local a=waiting[k]
        if a then
            if current.loaded<a.loaded then
                N.events[#N.events+1]={key=k,spent=a.loaded-current.loaded,loaded=current.loaded,profile=current.profile}
                waiting[k]=nil
            elseif N.auditFrame>=a.untilFrame then
                N.faults[k]='Native shot did not debit ammunition';waiting[k]=nil
                json.dump_file('re2ivr_ammo_fault.json',{schema=1,weaponType=current.wt,name=current.name,loaded=current.loaded,
                    reserve=current.reserve,infinity=current.infinity,reason=N.faults[k]})
            end
        end
        N.ledger[k]=current.loaded
    end
    return current
end
function N.drain_events() local out=N.events;N.events={};return out end
function N.is_gun(raw)
    if not raw or not N.gunType then return false end
    local ok,yes=pcall(function() return raw.weapon:get_type_definition():is_a(N.gunType) end)
    return ok and yes==true
end
function N.ack_pump(k) N.pumpPending[k]=nil end
function N.model_source(wt)
    if not current then return nil end
    local arm=current.wt==wt and current.weapon or current.equipment:call('getWeapon',wt)
    if not arm then return nil end
    return arm:call('get_Mesh'),arm:call('get_GameObject')
end
local function select_owned(wt,sub)
    if not N.scene_safe() or not current then return false,'Unsafe scene' end
    local category=api.mainCategory;if sub then category=api.subCategory end
    if category==nil then return false,'Native equip category unavailable' end
    local manager=sdk.get_managed_singleton(sdk.game_namespace('PlayerManager'))
    local player=manager and manager:call('get_CurrentPlayer')
    local inv=player and component(player,'survivor.Inventory')
    local slots=inv and inv:call('get_Slots');if not slots then return false,'Inventory unavailable' end
    local count=slots:call('get_Count');if count<0 or count>256 then return false,'Invalid inventory size' end
    for n=0,count-1 do
        local slot=slots:call('get_Item(System.Int32)',n)
        if slot and not slot:call('get_IsEmpty') and not slot:call('get_IsDeadSlot')
            and (sub or slot:call('get_IsWeapon')==true)
            and (slot:call('get_IsSubWeapon')==true)==sub and slot:call('get_WeaponType')==wt then
            -- Native equip only: no item creation, no ammo spending, no speculative parts flags.
            api.change:call(current.equipment,category,wt,slot:call('get_WeaponParts'))
            return true,'Native belt equip requested'
        end
    end
    return false,'Belt item no longer owned'
end
function N.select_subweapon(wt)return select_owned(wt,true)end
function N.select_mainweapon(wt)return select_owned(wt,false)end
function N.scene_safe()
    if N.readError then return false end
    if current then return current.safe end
    local manager=sdk.get_managed_singleton(sdk.game_namespace('PlayerManager'))
    local player=manager and manager:call('get_CurrentPlayer')
    if not player then return false end
    local condition=component(player,'survivor.SurvivorCondition')
    local gui=sdk.get_managed_singleton(sdk.game_namespace('gui.GUIMaster'))
    if not condition or not gui or gui:call('get_IsGuiOpen') then return false end
    for _,name in ipairs({'get_IsDead','get_IsEvent','get_IsJack','get_IsChangeWeapon','get_IsReload'}) do
        if condition:call(name) then return false end
    end
    return true
end
function N.control(value) enabled=value end
function N.visible(value)
    -- Never dereference a weapon retained from a different scene/identity.
    if not current then hidden=nil;return end
    if not value then api.draw:call(current.weapon,false);hidden=current.weapon
    elseif hidden==current.weapon then api.draw:call(current.weapon,true);hidden=nil end
end
function N.stop() enabled=false;N.visible(true) end
function N.commit(expected,n)
    local before=read()
    assert(enabled and before and before.safe and same(before,expected),"Native snapshot changed")
    assert(not before.infinity and n>=1 and n%1==0 and n<=before.reloadable and n<=before.reserve
        and before.loaded+n<=before.capacity,"Invalid ammo request")
    permit_reload=thread.get_id()
    local ok,accepted=pcall(function() return api.reload:call(before.equipment,before.wt,n) end)
    permit_reload=nil
    local after=read();current=after
    local verified=ok and accepted==true and after and before.weapon==after.weapon and before.slot==after.slot
        and after.loaded==before.loaded+n and after.reserve==before.reserve-n and after.capacity==before.capacity
    json.dump_file("re2ivr_mvp_transaction.json",{schema=1,requested=n,called=ok,accepted=accepted==true,
        verified=not not verified,before={loaded=before.loaded,reserve=before.reserve},
        after=after and {loaded=after.loaded,reserve=after.reserve} or nil})
    assert(verified,"Native ammunition postcondition failed; no automatic retry")
    N.ledger[key(after)]=after.loaded
    return after
end
return N

