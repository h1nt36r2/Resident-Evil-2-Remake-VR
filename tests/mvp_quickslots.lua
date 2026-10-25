local Q=require('re2ivr.quickslots');Q.last=true
local C=require('re2ivr.interaction');local v=C.math.v
local b={v(1,0,0),v(0,1,0),v(0,0,1)}
local i={active=true,head=v(0,1.7,0),headBasis=b,right=v(-.07,1.06,-.19),rightGrip=false}
local raw={safe=true,wt=1};local engine={place='holstered',o={}}
local gear={{weaponType='200',kind='grenade',sub=true,count=1}}
local calls=0
local function select(wt)assert(wt==200);calls=calls+1;return true,'equipped' end
Q.step(i,raw,gear,engine,select);i.rightGrip=true;assert(Q.step(i,raw,gear,engine,select))
for _=1,10 do assert(not Q.step(i,raw,gear,engine,select)) end;assert(calls==1)
i.rightGrip=false;Q.step(i,raw,gear,engine,select);engine.place='held';i.rightGrip=true
assert(not Q.step(i,raw,gear,engine,select) and calls==1)
i.rightGrip=false;Q.step(i,raw,gear,engine,select);engine.place='holstered';i.rightGrip=true
assert(not Q.step(i,raw,{},engine,select) and calls==1)
raw.safe=false;assert(not Q.step(i,raw,gear,engine,select))
raw.safe=true;i.rightGrip=false;i.right=v(-.34,1.08,-.12)
local knife={{weaponType='300',kind='knife',sub=true,count=1}}
Q.step(i,raw,knife,engine,function()error('release must not pick')end)
i.rightGrip=true;assert(Q.step(i,raw,knife,engine,function(wt)assert(wt==300);return true end))
raw.wt=300;raw.ranged=false;i.right=v(.23,1,.04);i.rightGrip=false
local pistols={{weaponType='1',kind='pistol',sub=false,count=1}}
pistols.shortcuts={up={weaponType='1',sub=false}}
local mainCalls=0;local function main(wt)assert(wt==1);mainCalls=mainCalls+1;return true end
Q.step(i,raw,pistols,engine,select,main);i.rightGrip=true
assert(Q.step(i,raw,pistols,engine,select,main) and mainCalls==1)
do
 local assignments={up=41,down=82};local directions={}
 local function shortcut(direction)directions[#directions+1]=direction;return true,'assigned',assignments[direction]end
 engine.place='holstered';raw.safe=true;raw.wt=1
 i.right=v(.23,1,.04);i.rightGrip=false;Q.step(i,raw,{},engine,select,main,shortcut)
 i.rightGrip=true;local ok,kind,wt,consumed=Q.step(i,raw,{},engine,select,main,shortcut)
 assert(ok and kind=='pistol' and wt=='41' and consumed and directions[1]=='up')
 i.right=v(.20,1.52,.25);i.rightGrip=false;Q.step(i,raw,{},engine,select,main,shortcut)
 i.rightGrip=true;ok,kind,wt=Q.step(i,raw,{},engine,select,main,shortcut)
 assert(ok and wt=='82' and directions[2]=='down')
 -- Nearby pouch overlap chooses nearest, not whichever inventory row came first.
 local items={{kind='knife',sub=true,count=1,weaponType='300'},{kind='grenade',sub=true,count=1,weaponType='200'},{kind='flash',sub=true,count=1,weaponType='201'}}
 i.right=v(-.20,1.06,-.19);i.rightGrip=false;Q.step(i,raw,items,engine,select)
 i.rightGrip=true;assert(Q.step(i,raw,items,engine,function(id)assert(id==201);return true end))
 -- Empty/failed zone consumes input: no fallback pistol draw.
 i.right=v(-.07,1.06,-.19);i.rightGrip=false;Q.step(i,raw,{},engine,select)
 i.rightGrip=true;ok,kind,wt,consumed=Q.step(i,raw,{},engine,function()error('Ghost item')end)
 assert(not ok and consumed)
end
print('PASS belt priority: assigned up/down zones, nearest pouch, no fallback pistol on empty zones, one selection per grip')
