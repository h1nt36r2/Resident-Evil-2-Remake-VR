do
local M=require('re2ivr.menu_controls');local s=M.new()
local assignments,floors={},{}
local i={active=true,leftStickClick=false,rightStickClick=false,rightStickAxis={x=0,y=0}}
local function tick(mode)
 s:step(i,mode,function(d)assignments[#assignments+1]=d;return true end,function(d)floors[#floors+1]=d;return true end)
end
tick('inventory');i.leftStickClick=true;i.rightStickAxis={x=0,y=1};tick('inventory')
for n=1,20 do tick('inventory')end;assert(#assignments==1 and assignments[1]=='up')
i.rightStickAxis={x=0,y=-1};tick('inventory');assert(#assignments==1)
i.leftStickClick=false;tick('inventory');i.leftStickClick=true;tick('inventory');assert(assignments[2]=='down')
tick('map');assert(#floors==0,'Held press entering map must not change floor')
i.leftStickClick=false;tick('map');i.leftStickClick=true;tick('map');assert(floors[1]=='down')
for n=1,20 do tick('map')end;assert(#floors==1)
i.leftStickClick=false;tick('map');i.rightStickClick=true;tick('map');assert(floors[2]=='up')
tick(nil);tick('inventory');assert(#assignments==2)
i.active=false;tick('map');assert(#floors==2)
-- Diagonal, simultaneous stick presses and unrelated menu contexts are ignored.
i.active=true;i.leftStickClick=false;i.rightStickClick=false;tick('inventory')
i.leftStickClick=true;i.rightStickAxis={x=1,y=1};tick('inventory');assert(#assignments==2)
i.rightStickClick=true;tick('map');tick('map');assert(#floors==2)
print('PASS contextual menu controls: four-direction chord, click floor changes, no repeats or held-menu-entry activation')
end
