-- Pure gesture policy. A release is consumed before invoking any native operation.
local C=require('re2ivr.interaction').math
local G={}
function G.new()
    local s={stage='idle',message='Grip grenade, then pull pin with left hand',throws=0}
    function s:reset()
        self.stage='idle';self.lastGrip=true;self.lastLeft=true;self.pinStart=nil;self.identity=nil
    end
    function s:step(i,id,ready,emit)
        if not ready or not i or not i.active or not id then self:reset();return end
        if self.identity~=id then self:reset();self.identity=id end
        local grip=i.rightGrip==true
        local left=i.leftGrip==true
        local press=grip and not self.lastGrip
        local pin=left and not self.lastLeft
        if self.stage=='idle' and press then self.stage='held';self.message='Pull pin: left grip near right hand, then separate hands' end
        if self.stage=='held' and grip then
            if pin and C.dist(i.left,i.right)<.14 then self.pinStart=C.sub(i.left,i.right) end
            if not left then self.pinStart=nil end
            if self.pinStart and C.len(C.sub(C.sub(i.left,i.right),self.pinStart))>=.06 then
                self.stage='armed';self.pinStart=nil;self.message='Pin removed: release right grip to throw'
            end
        end
        local release=self.lastGrip and not grip
        self.lastGrip=grip;self.lastLeft=left
        if release then
            local armed=self.stage=='armed'
            self.stage='idle';self.pinStart=nil -- consume first: errors must never retry a throw
            if armed then
                self.throws=self.throws+1
                local ok,why=emit(i)
                self.message=ok and 'Grenade thrown' or ('Throw stopped: '..tostring(why))
            else self.message='Unarmed grenade returned; no item consumed' end
        end
    end
    s:reset();return s
end
return G
