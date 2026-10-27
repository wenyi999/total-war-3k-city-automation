-- UI-only shared geometry. Identical bytes ship in all three independent packs.
-- No model access, timers, listeners or dependency on another enabled mod.
TK_AUTO_TOOLBAR = TK_AUTO_TOOLBAR or {}
local T=TK_AUTO_TOOLBAR
T.width=180;T.height=28;T.gap=8
function T.language(code)
    if TK_AUTO_LOCALE then TK_AUTO_LOCALE.override=code end
    if TK_AUTO_CITIES then TK_AUTO_CITIES.ui_message=nil;TK_AUTO_CITIES.ui_reasons=nil end
    if TK_ARMY_V2 and TK_ARMY_V2.runtime then
        TK_ARMY_V2.runtime.state.settings.language=code
        if TK_ARMY_V2.view then TK_ARMY_V2.view.render() end
    end
end
local function find(parent,id)
    if not parent then return nil end
    local ok,address=pcall(function() return parent:Find(id,false) end)
    if not ok or not address then return nil end
    local wrapped,component=pcall(UIComponent,address)
    return wrapped and component or nil
end
function T.origin(root)
    local width=root:Dimensions()
    local total=T.width*3+T.gap*2
    local x=math.max(8,math.min(math.floor(width*0.47),width-total-8))
    local y=8
    local help=find(root,"button_help")
    if help and help:Visible() then
        local _,hy=help:Position();local _,hh=help:Dimensions()
        y=math.max(0,math.floor(hy+(hh-T.height)/2))
    end
    return x,y
end
local function place(component,x,y,width,height)
    if not component then return end
    component:SetDockingPoint(0)
    local cw,ch=component:Dimensions()
    if cw~=width or ch~=height then
        component:SetCanResizeWidth(true);component:SetCanResizeHeight(true)
        component:Resize(width,height,false)
    end
    local cx,cy=component:Position()
    if cx~=x or cy~=y then component:MoveTo(x,y) end
end
function T.layout(root)
    local x,y=T.origin(root)
    for index,id in ipairs({"tk_auto_skill_toggle","tk_auto_city_open","tk_army_v2_open"}) do
        local button=find(root,id)
        if button then
            place(button,x+(index-1)*(T.width+T.gap),y,T.width,T.height)
            local caption=find(button,index==3 and "tk_army_v2_open_caption" or "button_txt")
            if caption then
                local bx,by=button:Position()
                place(caption,bx,by,T.width,T.height)
                caption:SetInteractive(false)
            end
        end
    end
    place(find(root,"tk_army_v2_power"),x+2*(T.width+T.gap),y+T.height+4,T.width,26)
end
