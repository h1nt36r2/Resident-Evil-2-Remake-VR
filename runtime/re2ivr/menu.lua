-- Automatic title-only recovery for an unambiguous, semantically named background.
-- Never change stereo projections, game resolution or all GUI layers at once.
local M={seen={},status='Automatic title background detection',count=0,started=os.clock(),lastDump=-10}
local settings
function M.is_background(name)
    local n=name:lower():gsub('[%s%p_]','')
    return n:find('title',1,true)~=nil and (n:find('background',1,true)~=nil or n:find('city',1,true)~=nil or n:match('bg$')~=nil)
end
local function report()
    if M.dirty and os.clock()-M.lastDump>2 then
        json.dump_file('re2ivr_title_layers.json',{layers=M.seen,status=M.status,selected=M.selected,automatic=true})
        M.dirty=false;M.lastDump=os.clock()
    end
end
function M.init(options)
    settings=options
    if not re.on_pre_gui_draw_element then M.status='GUI callback unavailable';return end
    local enum=sdk.find_type_definition('via.gui.ViewType')
    local screen
    for _,f in ipairs(enum and enum:get_fields() or {}) do
        if f:get_name()=='Screen' and f:is_static() then screen=f:get_data(nil) end
    end
    re.on_pre_gui_draw_element(function(element)
        if not settings.enabled or not vrmod or not vrmod:is_hmd_active() then return true end
        local ok,why=pcall(function()
            local pm=sdk.get_managed_singleton(sdk.game_namespace('PlayerManager'))
            local player=pm and pm:call('get_CurrentPlayer') or nil
            if M.player~=player then
                M.player=player;M.seen={};M.count=0;M.selected=nil;M.started=os.clock();M.dirty=true
            end
            if player then return end -- never affect gameplay inventory/HUD
            local go=element:call('get_GameObject')
            local name=go and go:call('get_Name')
            if type(name)~='string' then return end
            local view=element:call('get_View')
            if not view then return end
            if not M.seen[name] and M.count<128 then
                M.seen[name]={name=name,viewType=tostring(view:call('get_ViewType'))};M.count=M.count+1
                M.dirty=true
            end
            local selected,total=nil,0
            for candidate in pairs(M.seen) do if M.is_background(candidate) then selected=candidate;total=total+1 end end
            M.selected=total==1 and selected or nil
            if total>1 then M.status='Ambiguous title backgrounds: report saved automatically'
            elseif not M.selected then M.status='Title background not identified: report saved automatically' end
            if M.selected==name and screen~=nil and os.clock()-M.started>=.5 then
                -- REFramework restores the GUI's screen type after drawing. No persistent transform is retained here.
                view:call('set_ViewType',screen)
                M.status='Automatic title background recovery: '..name
            end
            report()
        end)
        if not ok then M.status='Title GUI diagnostic: '..tostring(why) end
        return true
    end)
end
function M.ui()
    imgui.text(M.status)
    imgui.text('Automatic recovery; no layer selection required. Unknown/ambiguous layers are only reported.')
end
return M
