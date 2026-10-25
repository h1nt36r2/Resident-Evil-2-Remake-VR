do
local D=require('re2ivr.belt_draw')
local C=require('re2ivr.interaction')
local v=C.math.v
local b={v(1,0,0),v(0,1,0),v(0,0,1)}
local input={active=true,rightGrip=true,leftGrip=false,eject=false,
 head=v(0,1.7,0),headBasis=b,right=v(.20,1.52,.25),rightBasis=b,left=v(0,1,0),leftBasis=b}
local engine=C.new(function()error('Belt draw must not change ammunition')end,{quickDraw=false})
local ticket=D.begin(12,0,7)
local raw={wt=1,safe=true}
local state
ticket,state=D.poll(ticket,input,raw,.1,7);assert(ticket and state=='waiting')
engine.place='held'
assert(not D.complete(ticket,raw,engine),'Old held pistol cannot complete shotgun request')
raw={wt=12,safe=false}
ticket,state=D.poll(ticket,input,raw,.2,7);assert(ticket and state=='waiting','Native change animation must retain grip ticket')
raw={wt=12,safe=true}
ticket,state=D.poll(ticket,input,raw,.3,7);assert(ticket and state=='ready')
local shot={identity='shotgun',key='shotgun',loaded=4,reserve=10,capacity=8,profile='pump',longGun=true,safe=true}
engine:reset('Native shotgun selected')
local held={};for k,value in pairs(input)do held[k]=value end;held.drawFromBelt=true
engine:step(held,shot,.016)
assert(engine.place=='held' and D.complete(ticket,raw,engine),'Same shoulder grip must hold arriving shotgun')
input.rightGrip=false
assert(D.poll(ticket,input,raw,.4,7)==nil,'Early release cancels')
input.rightGrip=true
assert(D.poll(ticket,input,raw,.4,8)==nil,'Scene switch cancels')
assert(D.poll(ticket,input,raw,4,7)==nil,'Timeout cancels')
print('PASS shoulder draw across old pistol, change animation and delayed shotgun arrival; no re-grip, ammo writes or cross-scene completion')
end
