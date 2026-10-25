-- REFramework v1.5.9.1: tracking metres, left/right list order verified upstream.
local V={}
local function point(p)
    assert(p,"Missing pose")
    local a={x=p.x,y=p.y,z=p.z}
    for _,n in pairs(a) do assert(type(n)=="number" and n==n and math.abs(n)<10000,"Invalid pose") end
    return a
end
local function basis(r)
    local b={point(r[0]),point(r[1]),point(r[2])}
    local function dot(a,c) return a.x*c.x+a.y*c.y+a.z*c.z end
    for _,a in ipairs(b) do local n=dot(a,a);assert(n>.8 and n<1.2,"Invalid controller rotation") end
    assert(math.abs(dot(b[1],b[2]))<.2 and math.abs(dot(b[1],b[3]))<.2 and math.abs(dot(b[2],b[3]))<.2,"Invalid controller axes")
    return b
end
local function sample()
    if not vrmod or not vrmod:is_hmd_active() or not vrmod:is_using_controllers()
        or reframework:is_drawing_ui() then return {active=false} end
    local c=vrmod:get_controllers()
    if not c or #c<2 then return {active=false} end
    local ls,rs=vrmod:get_left_joystick(),vrmod:get_right_joystick()
    local g=vrmod:get_action_grip()
    local click=vrmod:get_action_joystick_click()
    local function magnitude(axis)
        assert(axis and type(axis.x)=='number' and type(axis.y)=='number' and axis.x==axis.x and axis.y==axis.y
            and math.abs(axis.x)<=1.1 and math.abs(axis.y)<=1.1,'Invalid stick input')
        return math.sqrt(axis.x*axis.x+axis.y*axis.y)
    end
    return {active=true,head=point(vrmod:get_position(0)),headBasis=basis(vrmod:get_rotation(0)),
        left=point(vrmod:get_position(c[1])),right=point(vrmod:get_position(c[2])),
        leftBasis=basis(vrmod:get_rotation(c[1])),rightBasis=basis(vrmod:get_rotation(c[2])),
        rightVelocity=point(vrmod:get_velocity(c[2])),rightAngular=point(vrmod:get_angular_velocity(c[2])),
        leftGrip=vrmod:is_action_active(g,ls)==true,rightGrip=vrmod:is_action_active(g,rs)==true,
        leftStickClick=vrmod:is_action_active(click,ls)==true,rightStickClick=vrmod:is_action_active(click,rs)==true,
        leftStickMagnitude=magnitude(vrmod:get_left_stick_axis()),rightStickMagnitude=magnitude(vrmod:get_right_stick_axis()),
        eject=vrmod:is_action_active(vrmod:get_action_b_button(),rs)==true,
        rightTrigger=vrmod:is_action_active(vrmod:get_action_trigger(),rs)==true,
        -- Tracking-space stage floor. Standing origin is a HEAD origin, not a floor.
        floor=0}
end
function V.sample()
    -- Runtime/controller poses may briefly disappear during standby or reconnection.
    -- Reject this sample without turning a recoverable tracking loss into a fatal mod error.
    local ok,value=pcall(sample)
    if not ok then V.lastError=tostring(value);return {active=false,reason='tracking_unavailable',error=V.lastError} end
    V.lastError=nil;return value
end
function V.pulse(left)
    pcall(function() vrmod:apply_haptic_vibration(0,.045,80,.35,left and vrmod:get_left_joystick() or vrmod:get_right_joystick()) end)
end
return V
