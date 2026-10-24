local C=require('re2ivr.interaction')
local Q={last=true,message='',requests=0}
local Belt=require('re2ivr.belt')
function Q.step(input,current,gear,engine,select,selectMain)
    if not input or not input.active or not current or not current.safe then Q.last=true;return false end
    local pressed=input.rightGrip and not Q.last;Q.last=input.rightGrip
    if not pressed or engine.place=='held' then return false end
    local _,_,body=C.anchors(input,engine.o)
    if selectMain then
        local slot=Belt.slots(current,gear,engine,engine.o)[1]
        if slot.weaponType and slot.weaponType~=tostring(current.wt) then
            local p=C.math.point(input.head,body,slot.x,slot.y,slot.z)
            if C.math.dist(input.right,p)<.14 then
                local ok,why=selectMain(tonumber(slot.weaponType));Q.message=why or ''
                if ok then Q.requests=Q.requests+1;return true,'pistol',slot.weaponType end
                return false
            end
        end
    end
    for _,row in ipairs(gear or {}) do
        if row.sub and Belt.layout[row.kind] and row.weaponType~=tostring(current.wt) then
            local a=Belt.layout[row.kind];local p=C.math.point(input.head,body,a[1],a[2],a[3]-(engine.o.beltForward or 0))
            if C.math.dist(input.right,p)<.11 then
                local wt=tonumber(row.weaponType);if not wt then return false end
                local ok,why=select(wt);Q.message=why or ''
                if ok then Q.requests=Q.requests+1;return true,row.kind,row.weaponType end
                return false
            end
        end
    end
    return false
end
return Q
