-- Render-only scene objects using resources from the player's existing grenade mesh.
-- No game item spawning, weapon scripts, colliders, projectiles or inventory writes.
local M={cache={},status='Waiting for native grenade resources',ready=false,context=nil}
local api={}
local function find(t,name,args,returns,inherited,static)
    while t do
        for _,m in ipairs(t:get_methods()) do
            if m:get_name()==name and (static==nil or m:is_static()==static) and (not returns or m:get_return_type():get_full_name()==returns) then
                local p=m:get_param_types();local same=#p==#args
                for n,a in ipairs(args) do if not p[n] or p[n]:get_full_name()~=a then same=false end end
                if same then return m end
            end
        end
        t=inherited and t:get_parent_type() or nil
    end
end
function M.init()
    local ok,why=pcall(function()
        local go=sdk.find_type_definition('via.GameObject')
        local mesh=sdk.find_type_definition('via.render.Mesh')
        api.create=find(go,'create',{'System.String','via.Folder'},'via.GameObject',false,true)
        api.createRoot=find(go,'create',{'System.String'},'via.GameObject',false,true)
        assert(api.create or api.createRoot,'Missing GameObject factory')
        api.component=assert(find(go,'createComponent',{'System.Type'},nil,true),'Missing component factory')
        api.destroy=find(go,'destroy',{'via.GameObject'},nil,true,true) or find(go,'destroy',{'via.Object'},nil,true,true)
        assert(api.destroy,'Missing safe object destruction API')
        api.draw=assert(find(go,'set_DrawSelf',{'System.Boolean'},nil,true),'Missing owned-object visibility API')
        api.getMesh=assert(find(mesh,'getMesh',{},'via.render.MeshResource',true),'Missing mesh resource getter')
        api.material=assert(find(mesh,'get_Material',{},'via.render.MeshMaterialResource',true),'Missing material getter')
        api.setMesh=assert(find(mesh,'setMesh',{'via.render.MeshResource'},nil,true),'Missing mesh resource setter')
        api.setMaterial=assert(find(mesh,'set_Material',{'via.render.MeshMaterialResource'},nil,true),'Missing material setter')
        api.ctor=find(mesh,'.ctor',{})
        api.meshType=sdk.typeof('via.render.Mesh')
    end)
    M.ready=ok;M.status=ok and 'Ready: equip each grenade once if its mesh is not loaded' or ('Native grenade visuals unavailable: '..tostring(why))
end
local function valid(go) return go and sdk.is_managed_object(go) end
function M.clear()
    for _,entry in pairs(M.cache) do
        if valid(entry.go) then
            pcall(function() api.draw:call(entry.go,false) end)
            pcall(function() api.destroy:call(nil,entry.go) end)
        end
    end
    M.cache={};M.context=nil;M.owner=nil
end
function M.prepare(current,input,gear,engine,source,enabled,options)
    M.context=enabled and current and input and input.active and {current=current,input=input,gear=gear,engine=engine,source=source,options=options or {}} or nil
    if M.context and not current.safe then
        for _,reason in ipairs(current.reasons or {'unsafe'}) do if reason~='vanillaReload' then M.context=nil;break end end
    end
end
local function clone(row,source)
    local wt=tonumber(row.weaponType);if not wt then return nil end
    local mesh,go=source(wt)
    if not mesh or not go then return nil end
    local resource,material=api.getMesh:call(mesh),api.material:call(mesh)
    if not resource or not material then return nil end
    local folder_ok,folder=pcall(function() return go:call('get_Folder') end)
    local name='RE2IVR_visual_grenade_'..row.weaponType
    local copy
    if folder_ok and folder and api.create then copy=api.create:call(nil,name,folder)
    elseif api.createRoot then copy=api.createRoot:call(nil,name) end
    assert(copy,'Grenade visual allocation failed')
    assert(copy~=go,'Refusing to modify source game object')
    local ok,result=pcall(function()
        api.draw:call(copy,false)
        local component=api.component:call(copy,api.meshType)
        assert(component,'Grenade Mesh component allocation failed')
        if api.ctor then api.ctor:call(component) end
        assert(api.setMesh:call(component,resource)~=false,'Game rejected grenade mesh resource')
        assert(api.setMaterial:call(component,material)~=false,'Game rejected grenade material resource')
        api.draw:call(copy,false)
        return {go=copy,transform=copy:call('get_Transform'),kind=row.kind}
    end)
    if not ok then pcall(function() api.destroy:call(nil,copy) end);error(result) end
    return result
end
-- Called after game behaviour, before rendering. Object creation never runs from draw/UI hooks.
function M.update()
    if not M.ready then return end
    local c=M.context
    if not c then
        for _,entry in pairs(M.cache) do entry.visible=false;if valid(entry.go) then api.draw:call(entry.go,false) end end
        return
    end
    local owner=tostring(c.current.equipment)
    if M.owner and M.owner~=owner then M.clear();M.context=c end
    M.owner=owner
    local active={};local loaded=0;local rows={};local foundCurrent=false
    for _,row in ipairs(c.gear or {}) do rows[#rows+1]=row;if tostring(row.weaponType)==tostring(c.current.wt) then foundCurrent=true end end
    -- Equipped weapon is authoritative even when localized inventory labels cannot be read.
    if c.current.ranged and not foundCurrent then rows[#rows+1]={weaponType=tostring(c.current.wt),kind='pistol'} end
    for _,row in ipairs(rows) do
        if ((row.kind=='grenade' or row.kind=='flash') and c.options.grenades~=false) or (c.options.holster~=false and tostring(row.weaponType)==tostring(c.current.wt) and c.current.ranged) then
            active[row.weaponType]=true
            local entry=M.cache[row.weaponType]
            if entry and not valid(entry.go) then M.cache[row.weaponType]=nil;entry=nil end
            if not entry then
                local count=0;for _ in pairs(M.cache) do count=count+1 end
                if count<4 then entry=clone(row,c.source);M.cache[row.weaponType]=entry end
            end
            if entry then
                entry.kind=row.kind
                entry.weapon=c.current.ranged and tostring(row.weaponType)==tostring(c.current.wt)
                entry.visible=entry.weapon and c.engine.place=='holstered' or (not entry.weapon and row.weaponType~=tostring(c.current.wt))
                loaded=loaded+1
                api.draw:call(entry.go,entry.visible)
            end
        end
    end
    for wt,entry in pairs(M.cache) do
        if not active[wt] then
            if valid(entry.go) then api.destroy:call(nil,entry.go) end
            M.cache[wt]=nil
        end
    end
    M.status=loaded>0 and ('Native belt mesh copies: '..loaded) or 'Source mesh unavailable: equip item once; see troubleshooting guide'
end
function M.render()
    local c=M.context
    if not M.ready or not c then return end
    local math3=require('re2ivr.interaction').math
    local _,_,body=require('re2ivr.interaction').anchors(c.input,c.engine.o)
    local camera=vrmod:get_last_render_matrix();if not camera then return end
    local rotation=camera:to_quat()*vrmod:get_rotation(0):to_quat():inverse()
    local origin=camera[3]
    local bodyRotation=Matrix4x4f.new(body[1].x,body[1].y,body[1].z,0,body[2].x,body[2].y,body[2].z,0,body[3].x,body[3].y,body[3].z,0,0,0,0,1):to_quat()
    for _,entry in pairs(M.cache) do
        if entry.visible and valid(entry.go) then
            local p=entry.weapon and c.engine.holster or math3.point(c.input.head,body,entry.kind=='flash' and -.20 or -.07,-.64,-.19)
            if not p then p=math3.point(c.input.head,body,.23,-.70,.04) end
            local d=math3.sub(p,c.input.head);local offset=rotation*Vector4f.new(d.x,d.y,d.z,0)
            entry.transform:set_position(Vector4f.new(origin.x+offset.x,origin.y+offset.y,origin.z+offset.z,1),true)
            entry.transform:set_rotation(rotation*bodyRotation)
        end
    end
end
function M.has(wt) local e=M.cache[wt];return M.ready and M.context and e and e.visible and valid(e.go) end
function M.fail(why)
    M.status='Native models disabled after error: '..tostring(why)
    pcall(M.clear);M.ready=false
end
return M
