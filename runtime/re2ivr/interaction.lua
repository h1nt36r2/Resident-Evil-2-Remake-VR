-- Pure interaction engine. All positions in tracking-space metres; no SDK calls.
local M={}
local function v(x,y,z) return {x=x,y=y,z=z} end
local function add(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
local function sub(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end
local function mul(a,s) return v(a.x*s,a.y*s,a.z*s) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function len(a) return math.sqrt(dot(a,a)) end
local function unit(a) local n=len(a);return n>.0001 and mul(a,1/n) or nil end
local function dist(a,b) return len(sub(a,b)) end
local function localpoint(p,b,x,y,z) return add(p,add(mul(b[1],x),add(mul(b[2],y),mul(b[3],z)))) end
M.math={v=v,add=add,sub=sub,mul=mul,dot=dot,len=len,dist=dist,point=localpoint}
function M.anchors(i,o)
    o=o or {}
    local right=unit(v(i.headBasis[1].x,0,i.headBasis[1].z)) or v(1,0,0)
    local body={right,v(0,1,0),v(-right.z,0,right.x)}
    return localpoint(i.head,body,o.hipX or .23,o.hipY or -.70,(o.hipZ or .04)-(o.beltForward or 0)),
        localpoint(i.head,body,o.pouchX or -.23,o.pouchY or -.62,(o.pouchZ or -.03)-(o.beltForward or 0)),body
end
local function equal(a,b)
    return a and b and a.identity==b.identity and a.loaded==b.loaded and a.reserve==b.reserve
        and a.capacity==b.capacity and a.reloadable==b.reloadable and a.profile==b.profile
end
function M.new(commit,options)
    local self={place="holstered",stage="ready",message="Reach right hip and grip",drop=nil,
        last={},armed=false,commit=assert(commit),o=options or {},locked=false,commits=0,cycles={},failedKeys={},lastAmmo={}}
    function self:spent(k,profile) if profile=='pump' then self.cycles[k]=true end end
    function self:needs_cycle(k) return self.cycles[k or self.currentKey]==true end
    function self:cancel(message)
        self.stage="ready";self.expected=nil;self.amount=nil;self.slideStart=nil;self.round=false;self.insertArmed=false;self.slideReleased=false;self.pumpStart=nil;self.pumpPulled=false
        self.message=message or "Reload cancelled"
    end
    function self:reset(message)
        self:cancel(message);self.place="holstered";self.armed=false;self.drop=nil;self.last={}
    end
    function self:can_fire() return self.place=="held" and self.stage=="ready" and not self.locked and (self.availableAmmo or 0)>0 and not self:needs_cycle() end
    function self:reset_session()
        self:reset('New player scene: release grip and re-grab')
        self.identity=nil;self.currentKey=nil;self.availableAmmo=nil
        self.cycles={};self.failedKeys={};self.lastAmmo={};self.locked=false
    end
    function self:reload_blocked() return self.place=="held" or self.stage~="ready" end
    function self:transact(n,s)
        -- Consume the interaction BEFORE calling native code. Never retry an uncertain write.
        self.stage="committing";self.amount=nil;self.round=false
        local ok,after=pcall(self.commit,n,s)
        if not ok or not after or after.identity~=s.identity or after.loaded~=s.loaded+n
            or after.reserve~=s.reserve-n or after.capacity~=s.capacity then
            self.locked=true;self.failedKeys[self.currentKey or s.key or s.identity]=true;self:cancel("Ammo verification failed: disable mod and inspect diagnostics");return nil
        end
        self.commits=self.commits+1;self.expected=after;return after
    end
    function self:step(i,s,dt)
        dt=math.min(math.max(dt or .016,0),.1)
        if s then
            self.currentKey=s.key or s.identity
            self.locked=self.failedKeys[self.currentKey] or s.ammoFault~=nil
            self.availableAmmo=s.loaded
            local previous=self.lastAmmo[self.currentKey]
            if s.profile=='pump' and previous and s.loaded<previous then self.cycles[self.currentKey]=true end
            self.lastAmmo[self.currentKey]=s.loaded
        end
        if not i or not i.active or not s or not s.safe or not s.profile or self.locked then
            -- Native executeReload starts an animation after our verified transaction.
            -- That animation suspends interaction; it does not release the user's grip.
            local reloadPause=s and s.raw and s.raw.reasons and #s.raw.reasons>0
            for _,reason in ipairs(s and s.raw and s.raw.reasons or {}) do if reason~='vanillaReload' then reloadPause=false end end
            if reloadPause and i and i.active and i.rightGrip and self.place=='held' and self.identity==s.identity and not self.locked then
                self.last={rightGrip=i.rightGrip,leftGrip=i.leftGrip,eject=i.eject}
                self.message='Reload animation: keep holding grip';return
            end
            self:reset(self.locked and "Ammo verification failed; mod locked" or "Paused: scene/input unsupported")
            return
        end
        local changed=self.identity and self.identity~=s.identity
        if changed then self:reset("Weapon changed: re-grab from holster") end
        self.identity=s.identity
        if self.expected and not equal(self.expected,s) then self:cancel("Reload cancelled: ammo/weapon changed") end
        -- Body yaw follows head yaw, never head pitch; origin follows physical crouch.
        self.holster,self.pouch,self.bodyBasis=M.anchors(i,self.o)
        self.longGun=s.longGun or s.profile=='pump' or s.profile=='breech'
        if self.longGun then self.holster=localpoint(i.head,self.bodyBasis,.20,-.18,.25) end
        self.well=localpoint(i.right,i.rightBasis,0,-.09,.015)
        self.slide=localpoint(i.right,i.rightBasis,0,.055,-.04)
        self.cylinder=localpoint(i.right,i.rightBasis,-.10,.03,-.07)
        self.foreEnd=localpoint(i.right,i.rightBasis,0,-.015,-.24)
        self.loadingPort=localpoint(i.right,i.rightBasis,0,-.07,-.12)
        self.breech=localpoint(i.right,i.rightBasis,-.07,.01,-.16)
        local rg=i.rightGrip and not self.last.rightGrip
        local lg=i.leftGrip and not self.last.leftGrip
        local eject=i.eject and not self.last.eject
        if not i.rightGrip then self.armed=true end
        if self.place=="held" and not i.rightGrip then
            self:cancel("Weapon returned to hip");self.place="holstered"
            self.drop={position=v(i.right.x,i.right.y,i.right.z),velocity=mul(i.rightVelocity or v(0,0,0),1),age=0}
        elseif self.place=="holstered" and i.rightGrip and ((self.armed and rg and (self.o.quickDraw or dist(i.right,self.holster)<(self.o.holsterRadius or .20))) or i.drawFromBelt) then
            self.place="held";self.drop=nil;self.message="Weapon held"
        end
        if self.drop then
            local d=self.drop;d.age=d.age+dt
            local speed=len(d.velocity);if speed>5 then d.velocity=mul(d.velocity,5/speed) end
            d.velocity.y=d.velocity.y-9.81*dt;d.position=add(d.position,mul(d.velocity,dt))
            -- Cosmetic floor is standing-origin floor supplied by VR host, no game collision.
            if d.position.y<(i.floor or 0) then d.position.y=i.floor or 0;d.velocity=v(0,0,0) end
            if d.age>2 then self.drop=nil end
        end
        if self.place=="held" then
            if s.profile=='pump' and self.stage=='ready' and self:needs_cycle() then self.stage='needs_pump';self.message='Pull fore-end back then push fully forward' end
            if (self.stage=="ready" or self.stage=='needs_pump') and eject then
                self.expected=s
                self.stage=s.profile=='pump' and 'loading_shells' or (s.profile=='breech' and 'breech_open' or (s.profile=="revolver" and "cylinder_open" or "empty_well"))
                self.message=self.stage=="empty_well" and "Take magazine from left pouch" or "Take one round from left pouch"
                self.openAge=0;self.wristArmed=false
            elseif self.stage=='needs_pump' then
                if i.leftGrip then
                    local pos=dot(sub(i.left,i.right),i.rightBasis[3])
                    if not self.pumpStart and dist(i.left,self.foreEnd)<.12 then self.pumpStart=pos;self.pumpPulled=false end
                    if self.pumpStart then
                        local relative=sub(i.left,self.foreEnd)
                        local radial=len(sub(relative,mul(i.rightBasis[3],dot(relative,i.rightBasis[3]))))
                        if radial>.14 then self.pumpStart=nil;self.pumpPulled=false
                        else
                            local travel=pos-self.pumpStart
                            if travel>.10 then self.pumpPulled=true end
                            if self.pumpPulled and travel<.025 then
                                self.cycles[self.currentKey]=nil;self:cancel('Pump cycled: ready')
                            end
                        end
                    end
                else self.pumpStart=nil;self.pumpPulled=false end
            elseif self.stage=='loading_shells' or self.stage=='breech_open' then
                local stage=self.stage
                if eject then self:cancel('Loading closed')
                elseif not self.round and lg and dist(i.left,self.pouch)<.18 and s.reserve>0 and s.loaded<s.capacity and s.reloadable>0 then
                    self.round=true;self.message='Bring one round to the loading port'
                elseif self.round then
                    if not i.leftGrip then self.round=false;self.message='Round returned to pouch'
                    elseif dist(i.left,stage=='loading_shells' and self.loadingPort or self.breech)<.10 then
                        local after=self:transact(1,s)
                        if after then
                            if s.profile=='pump' and s.loaded==0 then self.cycles[self.currentKey]=true end
                            self.stage=stage;self.round=false;self.message='Round inserted; take next round or press B to close'
                        end
                    end
                end
            elseif self.stage=="empty_well" and lg and dist(i.left,self.pouch)<.18 then
                self.amount=math.min(s.capacity-s.loaded,s.reserve,s.reloadable)
                if self.amount>0 or s.loaded>0 then self.stage="magazine_held";self.message="Insert magazine into grip" end
            elseif self.stage=="magazine_held" then
                if not i.leftGrip then self.stage="empty_well";self.amount=nil;self.message="Magazine returned to pouch"
                else
                    local p=sub(i.left,self.well);local depth=dot(p,i.rightBasis[2])
                    local radial=len(sub(p,mul(i.rightBasis[2],depth)))
                    -- Enter from below, aligned within a forgiving cone, then cross seating plane.
                    if depth<-.05 then self.insertArmed=true end
                    if self.insertArmed and depth>=-.015 and depth<.08 and radial<.075
                        and dot(i.leftBasis[2],i.rightBasis[2])>.35 then
                        self.stage="inserted";self.insertArmed=false;self.message="Release left grip; grasp and pull slide"
                        self.slideReleased=false
                    end
                end
            elseif self.stage=="inserted" then
                if not i.leftGrip then self.slideReleased=true end
                if self.slideReleased and lg and dist(i.left,self.slide)<.10 then
                    self.stage="slide_held";self.slideStart=dot(sub(i.left,i.right),i.rightBasis[3]);self.pulled=false
                end
            elseif self.stage=="slide_held" then
                local pull=dot(sub(i.left,i.right),i.rightBasis[3])-self.slideStart
                if pull>.065 then self.pulled=true end
                if not i.leftGrip then
                    if self.pulled then
                        local n=self.amount or 0
                        if n==0 or self:transact(n,s) then self:cancel("Reload ready") end
                    else self.stage="inserted";self.message="Pull slide farther then release" end
                end
            elseif self.stage=="cylinder_open" then
                self.openAge=self.openAge+dt
                local omega=dot(i.rightAngular or v(0,0,0),i.rightBasis[3])
                if math.abs(omega)<1 then self.wristArmed=true end
                local close=eject or (self.wristArmed and self.openAge>.3 and omega>5 and not self.round)
                if close then self:cancel("Cylinder closed")
                elseif not self.round and lg and dist(i.left,self.pouch)<.18 and s.reserve>0 and s.loaded<s.capacity and s.reloadable>0 then
                    self.round=true;self.message="Bring round to cylinder"
                elseif self.round then
                    if not i.leftGrip then self.round=false;self.message="Round returned to pouch"
                    elseif dist(i.left,self.cylinder)<.10 then
                        local after=self:transact(1,s)
                        if after then self.stage="cylinder_open";self.round=false;self.message="Round inserted: return to pouch" end
                    end
                end
            end
        end
        self.last={rightGrip=i.rightGrip,leftGrip=i.leftGrip,eject=i.eject}
    end
    return self
end
return M
