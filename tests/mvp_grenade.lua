local C=require('re2ivr.interaction').math
local G=require('re2ivr.grenade')
local s=G.new();local calls=0
local i={active=true,rightGrip=false,leftGrip=false,right=C.v(0,1,0),left=C.v(0,1,0),rightVelocity=C.v(2,1,-3)}
local function step(id,ready,fail)
 s:step(i,id or 'grenade',ready~=false,function(release)calls=calls+1;assert(release.rightVelocity.z==-3);return not fail,'uncertain' end)
end
step();i.rightGrip=true;step();assert(s.stage=='held')
-- Trigger never arms or throws; held left grip before acquisition does not remove pin.
i.rightTrigger=true;step();assert(calls==0)
i.leftGrip=true;step();i.left=C.v(.08,1,0);step();assert(s.stage=='armed')
i.rightGrip=false;step();assert(calls==1)
for n=1,20 do step() end;assert(calls==1)
-- Unarmed release, pause/resume and weapon replacement consume no item.
i.leftGrip=false;i.rightGrip=true;step();i.rightGrip=false;step();assert(calls==1)
i.rightGrip=true;step();i.left=C.v(0,1,0);i.leftGrip=true;step();i.left=C.v(.08,1,0);step()
step(nil,false);i.rightGrip=false;step();assert(calls==1)
i.leftGrip=false;i.rightGrip=true;step();i.left=C.v(0,1,0);i.leftGrip=true;step();i.left=C.v(.08,1,0);step()
step('different');i.rightGrip=false;step('different');assert(calls==1)
-- Failed emission is not retried, even with grip remaining released.
i.leftGrip=false;step('different');i.rightGrip=true;step('different')
i.left=C.v(0,1,0);i.leftGrip=true;step('different');i.left=C.v(.08,1,0);step('different')
i.rightGrip=false;step('different',true,true);for n=1,20 do step('different') end;assert(calls==2)
print('PASS grenade pin/release policy, one-shot consumption, no retries or tracking-resume throws')
