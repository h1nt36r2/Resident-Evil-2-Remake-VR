local B=require('re2ivr.belt')
local C=require('re2ivr.interaction');local v=C.math.v
local e={place='holstered',o={beltForward=.03}}
local current={ranged=true,wt=1,reserve=12,safe=true}
local rows={{kind='knife',count=1,weaponType='300',sub=true},{kind='grenade',count=2,weaponType='200',sub=true}}
rows.shortcuts={up={weaponType='1'},down={weaponType='8'}}
local slots=B.slots(current,rows,e,e.o)
assert(#slots==6 and slots[1].kind=='pistol' and slots[1].count==1 and not slots[1].held)
assert(slots[2].count==1 and slots[3].count==2 and slots[4].count==0 and slots[5].count==12)
assert(math.abs(slots[1].z-.01)<.000001)
e.place='held';assert(B.slots(current,rows,e,e.o)[1].held)
local old=json;local saved
json={dump_file=function(_,packet)saved=packet end}
B.last=-10;B.publish(current,{active=true},rows,e,{beltVisible=true,beltForward=.03},0)
assert(saved.enabled and #saved.slots==6)
B.publish(current,{active=false},rows,e,{beltVisible=true},1);assert(not saved.enabled)
json=old
print('PASS compositor belt packet: real counts, empty slots, held state, forward offset and standby hiding')
