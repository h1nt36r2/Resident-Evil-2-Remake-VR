-- Deliberately simple MVP proxies, rendered using REFramework draw primitives.
-- They are interaction targets, not cloned weapon meshes or colliding rigid bodies.
local G=require("re2ivr.interaction").math
local R={}
local Models=require('re2ivr.models')
-- Recognisable silhouettes replace the former identical capsule placeholders.
function R.geometry(kind)
    if kind=='shotgun' or kind=='launcher' then return {
        {-.025,0,.24},{.025,0,.24},{-.025,.06,.02},{.025,.06,.02},
        {-.025,.06,-.57},{.025,.06,-.57},{-.025,.10,-.57},{.025,.10,-.57},
        {-.035,-.015,-.18},{.035,-.015,-.18},{-.035,-.015,-.33},{.035,-.015,-.33},
        {-.025,-.05,.09},{.025,-.05,.09}
    },{{1,2},{1,3},{2,4},{3,4},{3,5},{4,6},{5,6},{5,7},{6,8},{7,8},{7,3},{8,4},{9,10},{10,12},{12,11},{11,9},{1,13},{2,14},{13,14},{13,3},{14,4}} end
    if kind=='knife' then return {
        {-.018,0,0},{.018,0,0},{.018,.10,0},{.03,.11,0},{.014,.28,0},{0,.32,0},{-.014,.12,0},{-.03,.11,0}
    },{{1,2},{2,3},{3,4},{4,5},{5,6},{6,7},{7,8},{8,1},{3,7}} end
    if kind=='grenade' then return {
        {-.04,-.04,0},{.04,-.04,0},{.05,.04,0},{.025,.08,0},{-.025,.08,0},{-.05,.04,0},
        {-.015,.08,0},{-.015,.115,0},{.025,.115,0},{.04,.09,0},{.04,.035,0},
        {-.04,0,.035},{.04,0,.035},{-.04,.04,-.025},{.04,.04,-.025}
    },{{1,2},{2,3},{3,4},{4,5},{5,6},{6,1},{7,8},{8,9},{9,10},{10,11},{1,12},{12,13},{13,2},{6,14},{14,15},{15,3},{12,14},{13,15}} end
    if kind=='flash' then return {
        {-.025,-.05,0},{.025,-.05,0},{.025,.09,0},{-.025,.09,0},
        {-.015,.09,0},{-.015,.12,0},{.02,.12,0},{.035,.08,0},{.035,.02,0},
        {-.025,-.05,.035},{.025,-.05,.035},{.025,.09,.035},{-.025,.09,.035}
    },{{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,9},{1,10},{2,11},{3,12},{4,13},{10,11},{11,12},{12,13},{13,10}} end
    if kind=='magazine' then return {
        {-.018,-.06,-.012},{.018,-.06,-.012},{.018,.06,-.012},{-.018,.06,-.012},
        {-.018,-.06,.012},{.018,-.06,.012},{.018,.06,.012},{-.018,.06,.012}
    },{{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}} end
    return {
        {-.025,0,.03},{.025,0,.03},{.025,.045,-.16},{-.025,.045,-.16},
        {-.025,.08,-.16},{.025,.08,-.16},{.025,.08,.045},{-.025,.08,.045},
        {-.022,-.095,.065},{.022,-.095,.065},{-.022,-.095,.015},{.022,-.095,.015},
        {-.022,0,-.015},{.022,0,-.015}
    },{{1,2},{2,3},{3,4},{4,1},{4,5},{5,6},{6,3},{5,8},{8,7},{7,6},{1,8},{2,7},
        {1,9},{2,10},{9,10},{9,11},{11,12},{12,10},{11,13},{12,14},{13,14},{13,1},{14,2}}
end
function R.draw(engine,input,state,gear)
    if not input or not input.active or not engine.holster then return end
    local camera=vrmod:get_last_render_matrix()
    if not camera then return end
    local origin=camera[3]
    local rotation=camera:to_quat()*vrmod:get_rotation(0):to_quat():inverse()
    local function world(p)
        local d=G.sub(p,input.head)
        local out=rotation*Vector4f.new(d.x,d.y,d.z,0)
        return Vector3f.new(origin.x+out.x,origin.y+out.y,origin.z+out.z)
    end
    local function sphere(p,r,color) draw.sphere(world(p),r,color,true) end
    local function capsule(p,q,r,color) draw.capsule(world(p),world(q),r,color,false) end
    local function model(kind,p,b,color)
        local vertices,edges=R.geometry(kind)
        local points={}
        for n,a in ipairs(vertices) do points[n]=draw.world_to_screen(world(G.point(p,b,a[1],a[2],a[3]))) end
        for _,edge in ipairs(edges) do
            local a,c=points[edge[1]],points[edge[2]]
            if a and c then draw.line(a.x,a.y,c.x,c.y,color) end
        end
    end
    local body=engine.bodyBasis or input.headBasis
    sphere(engine.pouch,.045,0xFF60FF90)
    model('magazine',engine.pouch,body,0xFF60FF90)
    if engine.place=="holstered" then
        model(engine.longGun and 'shotgun' or 'pistol',engine.holster,body,0xFFD0D0D0)
        draw.world_text(engine.longGun and 'Shoulder weapon' or 'Pistol',world(G.point(engine.holster,body,0,.13,0)),0xFFFFFFFF)
    end
    local order={knife=0,grenade=0,flash=0,pistol=0}
    for _,row in ipairs(gear or {}) do
        if row.kind=='pistol' and state.raw and row.weaponType~=tostring(state.raw.wt) then
            order.pistol=order.pistol+1
            local p=G.point(input.head,body,-.34,-.73,.04+order.pistol*.10)
            model('pistol',p,body,0xFFD0D0D0)
            draw.world_text('Pistol '..row.weaponType,world(G.point(p,body,0,.13,0)),0xFFFFFFFF)
        end
        if row.kind=='knife' or row.kind=='grenade' or row.kind=='flash' then
            order[row.kind]=order[row.kind]+1
            local x=row.kind=='knife' and .08 or (row.kind=='grenade' and -.07 or -.20)
            local p=G.point(input.head,body,x,-.64,-.19-(order[row.kind]-1)*.10)
            if not Models.has(row.weaponType) then model(row.kind,p,body,row.kind=='knife' and 0xFFE0E0E0 or 0xFF80C0FF) end
            draw.world_text(row.kind..' x'..row.count,world(G.point(p,body,0,.16,0)),0xFFFFFFFF)
        end
    end
    if engine.drop then
        model(engine.longGun and 'shotgun' or 'pistol',engine.drop.position,body,0xFF808080)
    end
    if engine.stage=="empty_well" or engine.stage=="magazine_held" then sphere(engine.well,.065,0xFF60D0FF) end
    if engine.stage=="magazine_held" then
        model('magazine',input.left,input.leftBasis,0xFF70D0FF)
    elseif engine.stage=="inserted" or engine.stage=="slide_held" then
        sphere(engine.slide,.065,0xFF60FF90)
    elseif engine.stage=="cylinder_open" then
        sphere(engine.cylinder,.065,0xFF60D0FF)
        if engine.round then capsule(input.left,G.point(input.left,input.leftBasis,0,.045,0),.012,0xFF30C0FF) end
    elseif engine.stage=='needs_pump' then
        sphere(engine.foreEnd,.075,0xFF60FF90)
    elseif engine.stage=='loading_shells' or engine.stage=='breech_open' then
        sphere(engine.stage=='loading_shells' and engine.loadingPort or engine.breech,.075,0xFF60D0FF)
        if engine.round then capsule(input.left,G.point(input.left,input.leftBasis,0,.065,0),.014,0xFF30C0FF) end
    end
    if engine.stage~='ready' then draw.world_text(engine.message,world(G.point(input.head,input.headBasis,0,-.30,-.80)),0xFFFFFFFF) end
end
return R
