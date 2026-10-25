-- Grip holds; a fresh right-trigger press primes once; grip release throws.
local G={}
function G.new()
 local s={stage='idle',message='Select pouch icon, hold LEFT grip, press RIGHT trigger, release LEFT grip',throws=0,primes=0}
 function s:reset()
  self.stage='idle';self.lastGrip=true;self.lastTrigger=true;self.identity=nil
 end
 function s:step(i,id,ready,emit,prime)
  if not ready or not i or not i.active or not id then self:reset();return end
  if self.identity~=id then self:reset();self.identity=id end
  local grip=i.rightGrip==true
  local trigger=i.rightTrigger==true
  local press=grip and not self.lastGrip
  local pin=trigger and not self.lastTrigger
  if self.stage=='idle' and press then self.stage='held';self.message='Press right trigger to remove pin' end
  if self.stage=='held' and grip and pin then
   self.stage='failed' -- consume before native calls: never retry an uncertain spawn/debit
   self.primes=self.primes+1
   local ok,why=prime(i)
   if ok then self.stage='armed';self.message='LIVE grenade: move hand and release LEFT grip'
   else self.message='Priming stopped: '..tostring(why)end
  end
  local release=self.lastGrip and not grip
  self.lastGrip=grip;self.lastTrigger=trigger
  if release then
   local armed=self.stage=='armed';self.stage='idle'
   if armed then
    self.throws=self.throws+1
    local ok,why=emit(i)
    self.message=ok and 'Grenade released; native fuse continues' or ('Release stopped: '..tostring(why))
   elseif self.stage~='failed' then self.message='Unarmed grenade returned; no item consumed'end
  end
 end
 s:reset();return s
end
return G
