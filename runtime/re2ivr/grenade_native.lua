-- Native calls are based on REFramework v1.5.9.1 scripts/re2_vr_grenade.lua (MIT).
-- No raw inventory writes; the original Equipment.use owns the single-item debit.
local G={status='not initialized',ready=false,locked=false}
local gesture=require('re2ivr.grenade').new()
G.gesture=gesture
local generatorType,generate,use,raw,generator,pose,rotation,velocity,angular
local active=false
local pending
local function unique(t,name,args,ret)
    local found
    for _,m in ipairs(t and t:get_methods() or {}) do
        if m:get_name()==name and (not ret or m:get_return_type():get_full_name()==ret) then
            local p=m:get_param_types();local same=#p==#args
            for i,a in ipairs(args) do if not p[i] or p[i]:get_full_name()~=a then same=false end end
            if same then assert(not found,'Ambiguous '..name);found=m end
        end
    end
    return assert(found,'Missing grenade contract: '..name)
end
local function component(go,name)
    return go:call('getComponent(System.Type)',sdk.typeof(name))
end
function G.init()
    local ok,why=pcall(function()
        generatorType=assert(sdk.find_type_definition(sdk.game_namespace('weapon.generator.ThrowGrenadeGenerator')))
        generate=unique(generatorType,'generateShellProcess',{'via.mat4'})
        local eq=sdk.find_type_definition(sdk.game_namespace('survivor.Equipment'))
        use=unique(eq,'use',{sdk.game_namespace('EquipmentDefine.WeaponType'),'System.Int32'},sdk.game_namespace('inventory.ReduceResult'))
        -- Reject the vanilla attack BEFORE it creates a shell or debits an item.
        local fire=unique(eq,'executeFire',{sdk.game_namespace('EquipmentDefine.WeaponType'),'System.Int32'},'System.Boolean')
        local request=unique(eq,'requestFire',{},'System.Void')
        sdk.hook(request,function(a)
            if active and raw and raw.safe and sdk.to_managed_object(a[2])==raw.equipment then return sdk.PreHookResult.SKIP_ORIGINAL end
        end,function(ret) return ret end)
        sdk.hook(fire,function(a)
            local block=active and raw and raw.safe and sdk.to_managed_object(a[2])==raw.equipment and sdk.to_int64(a[3])==raw.wt
            thread.get_hook_storage().re2ivrGrenadeBlocked=block
            if block then return sdk.PreHookResult.SKIP_ORIGINAL end
        end,function(ret)
            if thread.get_hook_storage().re2ivrGrenadeBlocked then return sdk.to_ptr(0) end
            return ret
        end)
        -- Only shells from our exact generator receive our release velocity.
        local rigid
        for _,m in ipairs(generatorType:get_methods()) do
            if m:get_name()=='onRigidInstantiate' and #m:get_param_types()==1 then assert(not rigid);rigid=m end
        end
        assert(rigid,'Missing onRigidInstantiate callback')
        sdk.hook(rigid,function(a)
            local p=pending
            thread.get_hook_storage().re2ivrGrenadeBody=nil
            if p and os.clock()<=p.expires and sdk.to_managed_object(a[2])==p.generator then
                pending=nil
                thread.get_hook_storage().re2ivrGrenadeBody={go=sdk.to_managed_object(a[3]),velocity=p.velocity,angular=p.angular}
            end
        end,function(ret)
            local p=thread.get_hook_storage().re2ivrGrenadeBody
            if p and p.go then
                local applied,errorText=pcall(function()
                    local body=assert(component(p.go,'via.dynamics.RigidBodySet'),'No grenade rigid body')
                    body:call('setLinearVelocity',0,p.velocity)
                    body:call('setAngularVelocity',0,p.angular)
                    local shell=component(p.go,sdk.game_namespace('weapon.shell.ThrowGrenade'))
                    local ballistic=shell and shell:get_field('_BallisticInformation')
                    if ballistic then ballistic:call('set_CurrentSpeed',p.velocity) end
                end)
                if not applied then G.locked=true;G.status='Grenade velocity failed: '..tostring(errorText) end
            end
            return ret
        end)
    end)
    G.ready=ok;G.status=ok and 'Physical grenade handler ready' or tostring(why)
end
function G.stop()
    active=false;raw=nil;generator=nil;pose=nil;pending=nil;gesture:reset()
end
function G.step(i,current,enabled)
    active=false
    if not enabled or not G.ready or G.locked or not i or not i.active or not current or not current.safe then G.stop();return end
    local ok,gen=pcall(function()
        if not current.slot:call('get_IsSubWeapon') then return nil end
        local g=current.weapon:get_field('<ShellGenerator>k__BackingField')
        return g and g:get_type_definition():is_a(generatorType) and g or nil
    end)
    if not ok or not gen then G.stop();return end
    if raw and raw.weapon~=current.weapon then G.stop() end
    raw=current;generator=gen;active=true
    -- Snapshot BEFORE release; game's hand can start returning to its holster on release.
    if i.rightGrip then
        local captured,why=pcall(function()
            pose=current.weapon:call('get_GameObject'):call('get_Transform'):call('get_WorldMatrix')
            local camera=assert(sdk.get_primary_camera(),'No camera')
            rotation=(camera:call('get_WorldMatrix'):to_quat()*vrmod:get_transform(0):to_quat():inverse()):normalized()
        end)
        if not captured then G.status=tostring(why);pose=nil end
    end
    gesture:step(i,tostring(current.weapon)..':'..tostring(current.slot),true,function(release)
        local success,errorText=pcall(function()
            assert(raw==current and current.safe and pose,'Grenade changed before release')
            local count=current.slot:call('get_Number')
            assert(count>=1 and not current.infinity,'No finite grenade available')
            local v=release.rightVelocity
            local speed=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
            assert(speed==speed and speed<=20,'Invalid release velocity')
            velocity=rotation*Vector3f.new(v.x,v.y,v.z)
            local a=release.rightAngular
            angular=rotation*Vector3f.new(a.x,a.y,a.z)
            pending={generator=gen,velocity=velocity,angular=angular,expires=os.clock()+1}
            -- Never retry either native call, even if the result is uncertain.
            generate:call(gen,pose)
            use:call(current.equipment,current.wt,1)
            local after=current.slot:call('get_Number')
            assert(after==count-1,'Grenade debit not verified')
        end)
        if not success then G.locked=true;pending=nil;G.status=tostring(errorText) end
        return success,errorText
    end)
    if not G.locked then G.status=gesture.message end
end
return G
