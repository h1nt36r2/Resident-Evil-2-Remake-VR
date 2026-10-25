local C=require('re2ivr.interaction');local v=C.math.v
local P=require('re2ivr.profiles')
assert(P.detect('W-870')=='pump' and P.detect('SLS 60')=='revolver' and P.detect('MQ 11')=='magazine' and P.detect('GM 79')=='breech')
assert(P.detect('unrecognised custom gun')==nil)
for _,name in ipairs({'Minigun','Chemical Flamethrower','Spark Shot','ATM-4','Anti-tank Rocket'}) do
 assert(P.detect(name)=='native')
 assert(P.resolve({wt=99,name=name},{})==nil)
end
assert(P.detect('Broom Hc')=='magazine')
local b={v(1,0,0),v(0,1,0),v(0,0,1)}
local function setup(profile,loaded,capacity)
 local s={identity='gun',key='slot:gun',loaded=loaded,reserve=8,capacity=capacity,reloadable=capacity-loaded,safe=true,profile=profile}
 local calls=0
 local e=C.new(function(n)
  calls=calls+1;s.loaded=s.loaded+n;s.reserve=s.reserve-n;s.reloadable=math.min(s.capacity-s.loaded,s.reserve)
  local out={};for k,x in pairs(s) do out[k]=x end;return out
 end)
 local i={active=true,head=v(0,1.7,0),headBasis=b,right=v(0,1,0),left=v(0,1,0),rightBasis=b,leftBasis=b,rightAngular=v(0,0,0),floor=0}
 local function step()local out={};for k,x in pairs(s) do out[k]=x end;e:step(i,out,.016) end
 step();i.right=e.holster;i.rightGrip=true;step();return e,i,s,step,function() return calls end
end
local e,i,s,step,calls=setup('pump',3,5)
assert(e.longGun and e:can_fire())
s.loaded=2;s.reloadable=3;step();assert(e.stage=='needs_pump' and not e:can_fire())
i.left=e.foreEnd;i.leftGrip=true;step()
i.left=C.math.add(e.foreEnd,v(0,0,.13));step();assert(not e:can_fire())
i.left=e.foreEnd;step();assert(e:can_fire() and not e:needs_cycle())
-- Dropping, recentering and switching away/back never bypass the per-weapon cycle latch.
e:spent(s.key,'pump');step();i.rightGrip=false;step();i.rightGrip=true;step();assert(not e:can_fire())
e:reset();i.rightGrip=false;step();i.rightGrip=true;step();assert(not e:can_fire())
-- Load one shell per fresh pouch pickup, close partially full, still needs its pump stroke.
i.eject=true;step();assert(e.stage=='loading_shells');i.eject=false;i.leftGrip=false;step()
i.left=e.pouch;i.leftGrip=true;step();assert(e.round)
i.left=e.loadingPort;step();assert(s.loaded==3 and s.reserve==7 and calls()==1)
for _=1,8 do step() end;assert(calls()==1)
i.eject=true;step();assert(not e:can_fire());i.eject=false;step()
i.leftGrip=false;step();i.left=e.foreEnd;i.leftGrip=true;step()
i.left=C.math.add(e.foreEnd,v(0,0,.13));step();i.left=e.foreEnd;step();assert(e:can_fire())
-- Empty tube after shell insertion needs a pump even without previous shot evidence.
do
 local a,j,x,t,n=setup('pump',0,5);assert(not a:can_fire())
 j.eject=true;t();j.eject=false;j.left=a.pouch;j.leftGrip=true;t();j.left=a.loadingPort;t()
 assert(x.loaded==1 and n()==1 and a:needs_cycle());j.eject=true;t();assert(not a:can_fire())
end
-- Break-action/launcher reload: one real round, action must be closed before firing.
do
 local a,j,x,t,n=setup('breech',0,1);assert(not a:can_fire())
 j.eject=true;t();j.eject=false;j.left=a.pouch;j.leftGrip=true;t();j.left=a.breech;t()
 assert(x.loaded==1 and x.reserve==7 and n()==1 and not a:can_fire())
 j.eject=true;t();assert(a:can_fire())
end
print('PASS named weapon profiles, shoulder holster, pump back-forward stroke, cycle latch survives drop/reset, per-shell paid loading, empty-tube cycle, breech open-insert-close')
