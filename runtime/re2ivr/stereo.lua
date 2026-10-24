-- Inspect runtime stereo geometry. No setters: equalizing the eyes would remove stereo.
local S={}
function S.check()
    local result={status='unavailable',notes={},writesEyeGeometry=false}
    if not vrmod or not vrmod:is_hmd_active() then result.status='headset_inactive';return result end
    local function matrix(m)
        assert(m,'Missing stereo matrix')
        local a={}
        for c=0,3 do
            local p=m[c];local row={p.x,p.y,p.z,p.w}
            assert(#row==4,'Incomplete stereo matrix')
            for _,n in ipairs(row) do assert(type(n)=='number' and n==n and math.abs(n)<1e8,'Non-finite stereo matrix') end
            a[#a+1]=row
        end
        return a
    end
    local ok,error_text=pcall(function()
        local a,b,stable
        for attempt=1,2 do
            a=matrix(vrmod:get_current_eye_transform(false))
            b=matrix(vrmod:get_current_eye_transform(true))
            local again=matrix(vrmod:get_current_eye_transform(false))
            stable=true
            for n=1,3 do if math.abs(a[4][n]-again[4][n])>1e-6 then stable=false end end
            if stable then break end
        end
        if not stable then result.status='sample_unstable';result.notes[1]='Render eye phase changed during read; refresh diagnostics';return end
        local p,q=matrix(vrmod:get_current_projection_matrix(false)),matrix(vrmod:get_current_projection_matrix(true))
        local dx,dy,dz=a[4][1]-b[4][1],a[4][2]-b[4][2],a[4][3]-b[4][3]
        result.eyeSeparationMM=math.sqrt(dx*dx+dy*dy+dz*dz)*1000
        result.verticalDifferenceMM=math.abs(dy)*1000
        result.status='runtime_geometry_read'
        if result.eyeSeparationMM<1 then result.notes[#result.notes+1]='Eye origins coincide: verify native VR mode' end
        if result.eyeSeparationMM>200 then result.notes[#result.notes+1]='Unexpected runtime eye separation' end
        if math.abs(p[1][1])<1e-6 or math.abs(p[2][2])<1e-6 or math.abs(q[1][1])<1e-6 or math.abs(q[2][2])<1e-6 then
            result.notes[#result.notes+1]='Degenerate projection focal terms'
        end
        if #result.notes>0 then result.status='geometry_warning' end
        -- Different projection matrices are normal. Eye A/B order alternates with rendering.
        result.projectionA=p;result.projectionB=q;result.eyeA=a;result.eyeB=b
    end)
    if not ok then result.status='read_error';result.error=tostring(error_text) end
    return result
end
return S
