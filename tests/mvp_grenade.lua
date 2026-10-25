local C=require('re2ivr.interaction').math
local G=require('re2ivr.grenade')
local s=G.new();local spawns,releases=0,0
local i={active=true,rightGrip=false,rightTrigger=false,rightVelocity=C.v(2,1,-3)}
local fail=false
local function step(id,ready)
 s:step(i,id or 'grenade',ready~=false,function(r)
  releases=releases+1;assert(r.rightVelocity.z==-3);return true
 end,function()
  spawns=spawns+1;return not fail,'uncertain'
 end)
end
step();i.rightGrip=true;step();assert(s.stage=='held')
i.leftGrip=true;step();assert(spawns==0,'Left grip is not the pin action')
i.rightTrigger=true;step();assert(s.stage=='armed' and spawns==1 and releases==0)
for n=1,20 do step()end;assert(spawns==1,'Held trigger must not create duplicates')
i.rightGrip=false;step();assert(releases==1 and spawns==1)
for n=1,20 do step()end;assert(releases==1)
i.rightTrigger=false;i.rightGrip=true;step();i.rightGrip=false;step()
assert(spawns==1,'Unprimed return must cost nothing')
i.rightGrip=true;step();fail=true;i.rightTrigger=true;step()
for n=1,20 do step()end;assert(spawns==2 and s.stage=='failed')
i.rightGrip=false;step();assert(releases==1,'Failed prime must never release a replacement')
step(nil,false);i.rightGrip=true;i.rightTrigger=true;step();assert(spawns==2,'No standby re-prime')
print('PASS trigger primes once before release; no left-pin, unprimed debit, held-trigger retry or tracking re-prime')
