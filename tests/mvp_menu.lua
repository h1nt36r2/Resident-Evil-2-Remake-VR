do
local oldsdk,oldre,oldvr=sdk,re,vrmod
local pre,player,changes=nil,nil,0
local view={call=function(_,name,value)if name=='get_ViewType'then return 1 elseif name=='set_ViewType'then assert(value==0);changes=changes+1 end end}
local name='TEST_TitleCity'
local go={call=function()return name end}
local element={call=function(_,name)if name=='get_GameObject'then return go elseif name=='get_View'then return view end end}
sdk={game_namespace=function(n)return n end,
 find_type_definition=function()return {get_fields=function()return {{get_name=function()return 'Screen' end,is_static=function()return true end,get_data=function()return 0 end}}end}end,
 get_managed_singleton=function()return {call=function()return player end}end}
re={on_pre_gui_draw_element=function(fn)pre=fn end};vrmod={is_hmd_active=function()return true end}
local settings={enabled=true};local M=require('re2ivr.menu');M.init(settings)
pre(element);assert(M.seen.TEST_TitleCity and changes==0)
M.started=-1;pre(element);assert(changes==1,'Recognized title background must be recovered automatically')
name='Other_TitleBG';pre(element);assert(changes==1,'Ambiguous title layers must not be modified')
player={};pre(element);assert(changes==1,'Title workaround must never affect gameplay HUD')
assert(M.count==0 and M.selected==nil,'New player clears title layer cache')
sdk,re,vrmod=oldsdk,oldre,oldvr
print('PASS automatic title layer detection, ambiguous-layer exclusion, new-player reset and gameplay exclusion')
end
