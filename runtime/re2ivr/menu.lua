-- Title-only opt-in workaround: retain a selected background as a screen-space view.
-- Never change stereo projections, game resolution or all GUI layers at once.
local M={seen={},status='Open title screen, then inspect background layers below',count=0}
local settings
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
            if pm and pm:call('get_CurrentPlayer') then return end -- never affect gameplay inventory/HUD
            local go=element:call('get_GameObject')
            local name=go and go:call('get_Name')
            if type(name)~='string' then return end
            local view=element:call('get_View')
            if not view then return end
            if not M.seen[name] and M.count<128 then
                M.seen[name]={name=name,viewType=tostring(view:call('get_ViewType'))};M.count=M.count+1
            end
            if settings.titleBackground==name and screen~=nil then
                -- REFramework restores the GUI's screen type after drawing. No persistent transform is retained here.
                view:call('set_ViewType',screen)
                M.status='Title background screen-space workaround: '..name
            end
        end)
        if not ok then M.status='Title GUI diagnostic: '..tostring(why) end
        return true
    end)
end
function M.ui()
    imgui.text(M.status)
    imgui.text('Title city tiny? Select ONLY its background layer. This is an unverified rendering workaround.')
    if imgui.button('Reset title background workaround') then settings.titleBackground=nil;json.dump_file('re2ivr_mvp_settings.json',settings) end
    local names={};for name in pairs(M.seen) do names[#names+1]=name end;table.sort(names)
    for _,name in ipairs(names) do
        if imgui.button('Use title background: '..name) then settings.titleBackground=name;json.dump_file('re2ivr_mvp_settings.json',settings) end
    end
    if imgui.button('Save title layer report') then json.dump_file('re2ivr_title_layers.json',{layers=M.seen,status=M.status,selected=settings.titleBackground}) end
end
return M
