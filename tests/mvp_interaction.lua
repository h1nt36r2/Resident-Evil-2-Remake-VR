local C=require("re2ivr.interaction")
local v=C.math.v
local basis={v(1,0,0),v(0,1,0),v(0,0,1)}
local function setup(profile)
    local calls=0
    local s={identity="Matilda",loaded=6,reserve=18,capacity=12,reloadable=6,safe=true,profile=profile or "magazine"}
    local e=C.new(function(n,before)
        assert(before.loaded==s.loaded and before.reserve==s.reserve)
        calls=calls+1;s.loaded=s.loaded+n;s.reserve=s.reserve-n;s.reloadable=math.min(s.capacity-s.loaded,s.reserve)
        local a={};for k,x in pairs(s) do a[k]=x end;return a
    end)
    local i={active=true,head=v(0,1.7,0),headBasis=basis,right=v(.23,1,.04),left=v(-.23,1.08,-.03),
        rightBasis=basis,leftBasis=basis,rightVelocity=v(0,0,0),rightAngular=v(0,0,0),floor=0}
    local function step() local a={};for k,x in pairs(s) do a[k]=x end;e:step(i,a,.016) end
    step();i.right=e.holster;i.rightGrip=true;step();assert(e.place=="held" and e:can_fire())
    return e,i,s,step,function() return calls end
end
local e,i,s,step,calls=setup()
s.safe=false;s.raw={reasons={'vanillaReload'}};step();assert(e.place=='held')
s.safe=true;s.raw=nil;step();assert(e.place=='held' and e:can_fire())
i.eject=true;step();assert(e.stage=="empty_well" and not e:can_fire())
i.eject=false;i.leftGrip=true;step();assert(e.stage=="magazine_held")
assert(s.loaded==6 and s.reserve==18 and calls()==0)
i.left=C.math.add(e.well,v(0,-.09,0));step()
i.left=C.math.add(e.well,v(0,0,0));step();assert(e.stage=="inserted")
i.leftGrip=false;step();i.left=e.slide;i.leftGrip=true;step();assert(e.stage=="slide_held")
i.left=C.math.add(e.slide,v(0,0,.08));step();i.leftGrip=false;step()
assert(e.stage=="ready" and e:can_fire() and s.loaded==12 and s.reserve==12 and calls()==1)
for _=1,10 do step() end;assert(calls()==1)
-- Release => immediate holster, cosmetic drop; regrab removes duplicate visual.
i.rightGrip=false;step();assert(e.place=="holstered" and e.drop and not e:can_fire())
i.rightGrip=true;step();assert(e.place=="held" and not e.drop)
-- Cancelling at any precommit stage spends no ammo.
for _,stage in ipairs({"empty_well","magazine_held","inserted","slide_held"}) do
 local a,b,c,t,n=setup();a.stage=stage;a.amount=6;a.expected=c
 b.rightGrip=false;t();assert(c.loaded==6 and c.reserve==18 and n()==0 and a.stage=="ready")
end
-- Scene/input/weapon identity interruption demands a fresh release and re-grab.
for _,kind in ipairs({"input","scene","identity"}) do
 local a,b,c,t,n=setup();a.stage="empty_well";a.expected=c
 if kind=="input" then b.active=false elseif kind=="scene" then c.safe=false else c.identity="different" end
 t();assert(a.place=="holstered" and n()==0 and not a:can_fire())
 b.active=true;c.safe=true;t();assert(a.place=="holstered")
 b.rightGrip=false;t();b.rightGrip=true;t();assert(a.place=="held")
end
-- Ammo conflict cancels, no guessed retry.
do local a,b,c,t,n=setup();b.eject=true;t();c.reserve=17;t();assert(a.stage=="ready" and n()==0) end
-- Insertion requires approach and correct alignment; proximity alone is insufficient.
do
 local a,b,c,t,n=setup();b.eject=true;t();b.eject=false;b.leftGrip=true;t()
 b.left=a.well;t();assert(a.stage=="magazine_held")
 b.left=C.math.add(a.well,v(0,-.09,0));t()
 b.left=a.well;b.leftBasis={v(1,0,0),v(0,-1,0),v(0,0,-1)};t();assert(a.stage=="magazine_held")
end
-- Revolver: one native round per fresh pouch grip, hold cannot duplicate, partial close.
do
 local a,b,c,t,n=setup("revolver");c.loaded=2;c.capacity=5;c.reloadable=3
 b.eject=true;t();assert(a.stage=="cylinder_open");b.eject=false;b.leftGrip=true;t();assert(a.round)
 b.left=a.cylinder;t();assert(c.loaded==3 and c.reserve==17 and n()==1 and not a.round)
 for _=1,10 do t() end;assert(n()==1)
 b.leftGrip=false;t();b.left=a.pouch;b.leftGrip=true;t();b.left=a.cylinder;t();assert(n()==2 and c.loaded==4)
 b.eject=true;t();assert(a.stage=="ready" and a:can_fire() and c.loaded==4)
end
-- Wrist close uses signed local angular speed, guarded against immediately closing on open.
do
 local a,b,c,t=setup("revolver");b.eject=true;t();b.eject=false;b.rightAngular=v(0,0,10)
 for _=1,30 do t() end;assert(a.stage=="cylinder_open")
 b.rightAngular=v(0,0,0);t();b.rightAngular=v(0,0,6);t();assert(a.stage=="ready")
end
-- An uncertain native write locks the engine and cannot be repeated automatically.
do
 local a,b,c,t,n=setup("revolver");a.commit=function() error("uncertain write") end
 b.eject=true;t();b.eject=false;b.leftGrip=true;t();b.left=a.cylinder;t();assert(a.locked)
 for _=1,10 do t() end;assert(not a:can_fire())
end
do
 local e=C.new(function()error('Must not reload during scene reset')end)
 e.cycles.old=true;e.failedKeys.old=true;e.lastAmmo.old=99;e.locked=true;e.identity='old'
 e:reset_session()
 assert(not e.locked and not next(e.cycles) and not next(e.failedKeys) and not next(e.lastAmmo) and e.identity==nil and e.place=='holstered')
end
print("PASS magazine geometry/slide, revolver, ammo conservation, grip, scene conflict and full new-player session reset")

-- Fast insertion crosses the seating plane between sampled frames.
do
 local a,b,c,t,n=setup();b.eject=true;t();b.eject=false;b.leftGrip=true;t()
 b.left=C.math.add(a.well,v(0,-.09,0));t()
 b.left=C.math.add(a.well,v(0,.11,0));t()
 assert(a.stage=='inserted' and n()==0)
 b.leftGrip=false;t();b.left=a.slide;b.leftGrip=true;t()
 b.left=C.math.add(a.slide,v(.25,0,.09));t()
 assert(a.stage=='inserted' and n()==0,'Lateral hand motion must lose slide grip')
end
