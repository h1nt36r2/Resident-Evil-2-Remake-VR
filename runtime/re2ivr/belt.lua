-- Real inventory -> compositor overlay packet. No game render objects or item writes.
local C=require('re2ivr.interaction')
local B={last=-10,status='Waiting for belt overlay',layout={
    knife={-.34,-.62,-.12},grenade={-.07,-.64,-.19},flash={-.20,-.64,-.19}}}
function B.slots(current,gear,engine,options)
    local out={};local counts={knife=0,grenade=0,flash=0};local types={}
    for _,row in ipairs(gear or {}) do
        if counts[row.kind] and row.sub then counts[row.kind]=counts[row.kind]+row.count;types[row.kind]=types[row.kind] or row.weaponType end
    end
    options=options or {}
    local pistol=current and current.ranged and tostring(current.wt) or nil
    if not pistol then for _,row in ipairs(gear or {})do if row.kind=='pistol' and not row.sub then pistol=row.weaponType;break end end end
    out[#out+1]={kind='pistol',weaponType=pistol,count=pistol and 1 or 0,held=engine.place=='held' and current and tostring(current.wt)==pistol or false,x=options.hipX or .23,y=options.hipY or -.70,z=options.hipZ or .04}
    for _,kind in ipairs({'knife','grenade','flash'}) do
        local p=B.layout[kind];out[#out+1]={kind=kind,count=counts[kind],weaponType=types[kind],x=p[1],y=p[2],z=p[3]}
    end
    out[#out+1]={kind='ammo',count=current and current.reserve or 0,x=options.pouchX or -.23,y=options.pouchY or -.62,z=options.pouchZ or -.03}
    for _,slot in ipairs(out)do slot.z=slot.z-(options.beltForward or 0) end
    return out
end
function B.publish(current,input,gear,engine,settings,now)
    if now-B.last<.25 then return end;B.last=now
    local safe=current and current.safe
    if not safe and current and current.reasons and #current.reasons>0 then
        safe=true;for _,reason in ipairs(current.reasons) do if reason~='vanillaReload' then safe=false end end
    end
    json.dump_file('re2ivr_belt.json',{schema=1,time=os.time(),enabled=settings.beltVisible and input and input.active and safe or false,
        slots=B.slots(current,gear,engine,settings)})
end
return B
