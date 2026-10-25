local C=require('re2ivr.interaction')
local Q={last=true,message='',requests=0}
local Belt=require('re2ivr.belt')
function Q.step(input,current,gear,engine,select,selectMain,selectShortcut)
    if not input or not input.active or not current or not current.safe then Q.last=true;return false end
    if current.isDevice or current.storyNative then Q.last=input.rightGrip;return false end -- story tools keep native grip
    local pressed=input.rightGrip and not Q.last;Q.last=input.rightGrip
    if not pressed or engine.place=='held' then return false end
    local _,_,body=C.anchors(input,engine.o)
    -- Choose the closest physical zone FIRST, including empty zones. An empty pouch
    -- must consume this grip instead of falling through to grip-anywhere pistol draw.
    local nearest,distance
    for _,slot in ipairs(Belt.slots(current,gear,engine,engine.o)) do
        if slot.kind~='ammo' then
            local p=C.math.point(input.head,body,slot.x,slot.y,slot.z)
            local radius=slot.kind=='back' and .23 or (slot.kind=='pistol' and .20 or .14)
            local d=C.math.dist(input.right,p)
            if d<radius and (not distance or d<distance) then nearest=slot;distance=d end
        end
    end
    if nearest then
        local ok,why,wt
        if nearest.shortcut and selectShortcut then
            ok,why,wt=selectShortcut(nearest.shortcut)
        elseif nearest.weaponType then
            wt=tonumber(nearest.weaponType)
            local action=nearest.kind=='pistol' and selectMain or select
            if action and wt then ok,why=action(wt) end
        end
        Q.message=why or (nearest.shortcut and 'Shortcut slot empty/unavailable' or 'Pouch empty/unavailable')
        if ok then
            Q.requests=Q.requests+1
            return true,nearest.shortcut and 'pistol' or nearest.kind,tostring(wt or nearest.weaponType),true
        end
        return false,nil,nil,true
    end
    return false
end
return Q
