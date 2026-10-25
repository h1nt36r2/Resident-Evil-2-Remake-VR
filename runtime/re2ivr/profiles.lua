-- Match real inventory weapon names, not guessed numeric IDs. Unknown weapons keep native controls.
local P={valid={magazine=true,revolver=true,pump=true,breech=true,native=true}}
local aliases={
    {'w870','pump',true},{'sls60','revolver',false},{'quickdraw','revolver',false},
    {'matilda','magazine',false},{'jmbhp3','magazine',false},{'samuraiedge','magazine',false},
    {'m19','magazine',false},{'mup','magazine',false},{'lightninghawk','magazine',false},
    {'mq11','magazine',true},{'le5','magazine',true},{'gm79','breech',true},
    -- Native families keep spin-up, fuel burn, electrical charge and scripted rocket logic.
    {'minigun','native',true},{'chemicalflamethrower','native',true},{'flamethrower','native',true},
    {'sparkshot','native',true},{'atm4','native',true},{'antitank','native',true},
    {'rocketlauncher','native',true},{'broomhc','magazine',false},
}
function P.detect(name)
    local n=(name or ''):lower():gsub('[%s%p]','')
    for _,a in ipairs(aliases) do if n:find(a[1],1,true) then return a[2],a[3] end end
end
function P.resolve(raw,overrides)
    if overrides[tostring(raw.wt)]=='native' then return nil,false end
    local automatic,long=P.detect(raw.name)
    local resolved=overrides[tostring(raw.wt)] or automatic
    if resolved=='native' then return nil,long end
    return resolved,long or automatic=='pump' or automatic=='breech'
end
return P
