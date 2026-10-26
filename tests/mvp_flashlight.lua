do
local F=require('re2ivr.flashlight')
local f=F.new();local player,component={},{}
local c={player=player,safe=true};local i={active=true,rightGrip=false}
local state={light=true,mesh=true};local writes={}
local function read()return state end
local function write(k,v)writes[#writes+1]=k;state[k]=v end
f:step(i,c,true,1);f:observe(component,{light=true,mesh=true})
i.rightGrip=true;f:step(i,c,true,1);state={light=false,mesh=false}
f:restore(component,read,write)
assert(state.light and state.mesh and #writes==2)
f:restore(component,read,write);assert(#writes==2,'No repeated writes when already on')
i.rightGrip=false;f:step(i,c,true,1);state={light=false,mesh=false}
f:observe(component,{light=false,mesh=false})
i.rightGrip=true;f:step(i,c,true,1);f:restore(component,read,write)
assert(not state.light and #writes==2,'Grip cannot turn on a previously dark flashlight')
i.rightGrip=false;f:step(i,c,true,1);f:observe(component,{light=true,mesh=false})
i.rightGrip=true;f:step(i,c,true,1);f:restore(component,read,write)
assert(state.light and not state.mesh,'Do not reveal an already hidden mesh')
local count=#writes
c.player={};f:step(i,c,true,2);state.light=false;f:restore(component,read,write)
assert(#writes==count and not state.light,'No writes into a previous player/scene')
i.rightGrip=false;f:step(i,c,true,2);f:observe(component,{light=true,mesh=true})
i.rightGrip=true;f:step(i,c,true,2);c.safe=false;f:step(i,c,true,2)
f:restore(component,read,write);assert(#writes==count,'Unsafe scene cancels preservation')
c.safe=true;i.rightGrip=false;f:step(i,c,true,2);f:observe(component,{light=true,mesh=true})
i.rightGrip=true;f:step(i,c,true,2);f:step(i,c,false,2);f:restore(component,read,write)
assert(#writes==count,'Disabling mod cancels preservation')
print('PASS flashlight grip preservation, dark state, mesh independence, scene and disable isolation')
end
