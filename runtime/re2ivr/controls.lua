-- Recenter and height bias use only REFramework's documented origin/yaw APIs.
-- They never modify eye transforms, projections, IPD, locomotion input or avatar scale.
local M={}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<10000 end
function M.new(settings)
    local self={settings=settings,pending=nil,heldSince=nil,latched=false,expectedY=nil,appliedOffset=0,
        resets=0,externalHeightChanges=0,message="Hold right stick click while standing still to recenter"}
    local function position(p)
        assert(p and finite(p.x) and finite(p.y) and finite(p.z),'Invalid recenter position')
        return p
    end
    local function set_origin(p,y)
        vrmod:set_standing_origin(Vector4f.new(p.x,y,p.z,1))
    end
    function self:queue(mode,now)
        assert(mode=='both' or mode=='yaw' or mode=='height','Invalid recenter mode')
        self.pending={mode=mode,expires=now+10};self.message="Close menu and stop moving to apply recenter"
    end
    function self:release()
        if self.expectedY and self.appliedOffset~=0 then
            local p=position(vrmod:get_standing_origin())
            if math.abs(p.y-self.expectedY)<.0001 then set_origin(p,p.y+self.appliedOffset) end
        end
        self.expectedY=nil;self.appliedOffset=0;self.pending=nil;self.heldSince=nil;self.latched=false
    end
    function self:bias()
        local p=position(vrmod:get_standing_origin())
        local external=self.expectedY and math.abs(p.y-self.expectedY)>.0001
        local baseline=p.y
        if self.expectedY and not external then baseline=p.y+self.appliedOffset end
        local offset=self.settings.heightOffset or 0
        assert(finite(offset) and math.abs(offset)<=.30,'Height correction outside +/-30 cm')
        local wanted=baseline-offset
        local changed=math.abs(wanted-p.y)>.0001
        if changed then set_origin(p,wanted) end
        if external then self.externalHeightChanges=self.externalHeightChanges+1 end
        self.expectedY=wanted;self.appliedOffset=offset
        return changed or external or false
    end
    function self:recenter(mode)
        assert(mode=='both' or mode=='yaw' or mode=='height','Invalid recenter mode')
        -- Validate everything before invoking the first setter.
        local head=position(vrmod:get_position(0))
        local offset=self.settings.heightOffset or 0
        assert(finite(offset) and math.abs(offset)<=.30,'Invalid height correction')
        local origin=position(vrmod:get_standing_origin())
        if mode=='both' or mode=='yaw' then
            vrmod:recenter_view()
            vrmod:recenter_gui(vrmod:get_rotation(0):to_quat())
        end
        if mode=='both' or mode=='height' then
            set_origin(mode=='both' and head or origin,head.y-offset)
            self.expectedY=head.y-offset
            self.appliedOffset=offset
        end
        self.resets=self.resets+1;self.message="Recentered: "..mode
    end
    function self:step(i,safe,now)
        if self.pending and now>self.pending.expires then self.pending=nil;self.message="Recenter request expired" end
        if not i or not i.active or not safe then self.heldSince=nil;return false end
        local changed=self:bias()
        local stationary=(i.leftStickMagnitude or 0)<.20 and (i.rightStickMagnitude or 0)<.20
        local bind=self.settings.recenterBind or 'right_stick'
        local pressed=i.rightStickClick and (bind=='right_stick' or (bind=='left_grip_r3' and i.leftGrip))
        if not pressed then self.heldSince=nil;self.latched=false end
        if not stationary then self.heldSince=nil;return changed end
        local mode
        if self.pending then mode=self.pending.mode;self.pending=nil
        elseif pressed and not self.latched then
            self.heldSince=self.heldSince or now
            if now-self.heldSince>=(self.settings.recenterHold or 1) then
                mode=self.settings.recenterMode or 'both';self.latched=true
            end
        end
        if mode then self:recenter(mode);return true end
        return changed
    end
    return self
end
return M
