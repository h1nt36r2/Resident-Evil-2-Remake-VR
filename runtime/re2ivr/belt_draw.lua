-- Keep one belt grip across an asynchronous equipment change.
local D={}
function D.begin(wt,now,epoch)return {wt=tostring(wt),expires=now+3,epoch=epoch}end
function D.poll(ticket,input,current,now,epoch)
 if not ticket then return nil,'idle'end
 if not input or not input.active or not input.rightGrip then return nil,'released'end
 if ticket.epoch~=epoch then return nil,'scene_changed'end
 if now>ticket.expires then return nil,'timed_out'end
 if current and current.safe and tostring(current.wt)==ticket.wt then return ticket,'ready'end
 return ticket,'waiting'
end
function D.complete(ticket,current,engine)
 return ticket~=nil and current~=nil and current.safe and tostring(current.wt)==ticket.wt and engine.place=='held'
end
return D
