TK_AUTO = TK_AUTO or {}
local K=TK_AUTO
local U={generation=0,page=1,picker_page=1,profile="recommended",actions={},action_ids={},click_locks={},panel=nil,regions={},picker=nil}
TK_AUTO_CITY_UI=U
local profiles={"agriculture","commerce","industry","other","recommended"}
local function C() return TK_AUTO_CITIES end
local element_names={metal="金",wood="木",water="水",fire="火",earth="土"}
local element_order={"metal","wood","water","fire","earth"}
local function current_template()
    if U.mode=="gate" then
        return C().state.profiles.gate
    end
    if U.mode=="county" then
        C().state.county_templates=C().state.county_templates or {}
        local e=U.element or "metal"
        C().state.county_templates[e]=C().state.county_templates[e] or {[1]=false,[2]=false}
        return C().state.county_templates[e]
    end
    return C().state.profiles[U.profile]
end
local function update_county()
    if U.mode=="county" then
        local t=current_template()
        C().set_county_targets(U.element or "metal",t[1],t[2])
    end
end

local function record(key)
    return "PlayersFaction.CapitalSettlementContext.PrimaryRegionSlotContext.BuildingContext.BuildingLevelRecordContext.RecordList.FirstContext(Key == "..K.quote(key)..")"
end
local title_cache={}
local effects_cache={}
local faction_permissions,matching_variant
local permissions_cache
local function building_title(key)
    if not key then return K.L("pick_building") end
    local permission=faction_permissions()
    local cache_key=permission.faction..":"..permission.subculture..":"..tostring(key)
    if title_cache[cache_key] then return title_cache[cache_key] end
    local data=TK_AUTO_BUILDINGS[key]
    local value=K.read(record(key)..".PlayerVariantRecordContext.Name")
    local variant=matching_variant(key,permission)
    if not value or value=="" or tostring(value):match("^3k_") or tostring(value):match("^ep_") then
        value=variant and variant.name
        if not value or value=="" then value=data and data.name end
    end
    if not value or value=="" or tostring(value):match("^3k_") or tostring(value):match("^ep_") then
        value=data and data.chain_name
        if not value or value=="" or tostring(value):match("^3k_") or tostring(value):match("^ep_") then value=K.L("unnamed_building") end
    end
    title_cache[cache_key]=tostring(value)
    return title_cache[cache_key]
end
U.building_title=building_title

local function button(parent,id,label,x,y,w,h,action)
    local result=K.button(parent,id,label,x,y,w,h,650)
    U.actions[id]=action
    U.actions[id.."_text"]=action
    U.action_ids[id]=id
    U.action_ids[id.."_text"]=id
    return result
end

local function event_id(context,method)
    if not context then return nil end
    local ok,id=pcall(function() return context[method](context) end)
    if ok and type(id)=="string" and id~="" then return id end
end

local function valid_component(component)
    if not component then return false end
    local ok,valid=pcall(function() return component:IsValid() end)
    if not ok or not valid then return false end
    local good,id=pcall(function() return component:Id() end)
    return good and type(id)=="string" and id~=""
end

-- Reacquire from the live tree every time: a created component's handle goes
-- stale when the UI is rebuilt, and IsValid() keeps lying about it, so drawing
-- into the old handle throws for every child.
local function live_panel()
    local root=K.ui_root()
    if not root then return nil end
    local found=K.find(root,"tk_auto_city_settings")
    if not found then return nil end
    U.panel=found
    return found
end

local function panel_visible()
    local panel=live_panel()
    if not panel then U.panel=nil;return false end
    local ok,visible=pcall(function() return panel:Visible() end)
    return ok and visible==true
end

-- Native text/button children have shared ids. Resolve the nearest registered
-- ancestor instead of treating those ids as independent buttons.
function U.resolve_action(context)
    local function lookup(id)
        if id=="tk_auto_city_open" then return U.open,id end
        if id=="tk_auto_close" then return U.close,id end
        if id and U.actions[id] then return U.actions[id],U.action_ids[id] or id end
    end
    -- Native clicks supply their id in context.string; component_id() can be
    -- absent. Resolve known ids before inspecting a transient native address.
    local action,canonical=lookup(context and context.string)
    if action then return action,canonical end
    action,canonical=lookup(event_id(context,"component_id"))
    if action then return action,canonical end
    action,canonical=lookup(event_id(context,"component_parent_id"))
    if action then return action,canonical end
    if context and context.component then
        local ok,component=pcall(function() return UIComponent(context.component) end)
        if ok and valid_component(component) then
            for _=1,16 do
                local good,id=pcall(function() return component:Id() end)
                if not good or type(id)~="string" then break end
                local action,canonical=lookup(id)
                if action then return action,canonical end
                -- The UI root has no parent. Do not construct handles from
                -- its null parent address or from destroyed native widgets.
                if id=="root" then break end
                local valid,parent=pcall(function() return component:Parent() end)
                if not valid or not parent then break end
                local made,next_component=pcall(function() return UIComponent(parent) end)
                if not made or not valid_component(next_component) or next_component==component then break end
                component=next_component
            end
        end
    end
end

function U.dispatch_action(context)
    local action,id=U.resolve_action(context)
    if not action or not id then return end
    -- One mouse release can be reported by the native child and its parent.
    -- Guard state-changing city buttons until that release has finished.
    -- Creating/redrawing native widgets inside ComponentLClickUp can leave
    -- the clicked handle/root unavailable to subsequent event listeners.
    -- Queue the Lua action, without retaining the native event or address.
    -- Include the settings toggle: a child/parent release must not open and
    -- then immediately close the same panel.
    local generation=U.generation
    local function run()
        if generation~=U.generation then return end
        local ok,err=pcall(action)
        if not ok then K.log("City button failed: id="..id.." error="..tostring(err)) end
    end
    -- Opening/closing the shell needs no campaign model. Content/actions use
    -- model jobs; short duplicate suppression does not depend on their completion.
    K.ui_action(id,function()
        if id=="tk_auto_city_open" or id=="tk_auto_close" then run()
        else K.defer(run,0.05,"tk_auto_action_"..id) end
    end)
end
local function cycle(value,list)
    for i,item in ipairs(list) do if value==item then return list[i%#list+1] end end
    return list[1]
end

local function gate_region(key,expression)
    local gates=TK_AUTO_GATES
    if not key or not gates or type(gates.is_gate)~="function" then return false end
    -- Optional gate recognition must never break ordinary city settings.
    local ok,result=pcall(gates.is_gate,key,expression)
    return ok and result==true
end

local function regions()
    local result={}
    local size=K.number("PlayersFaction.SettlementList.Size")
    for i=0,size-1 do
        local p="PlayersFaction.SettlementList.At("..i..")"
        if K.bool(p..".IsProvinceCapital") then
            local key=K.read(p..".RegionRecordKey")
            if key and not gate_region(key,p) then
                local province=K.number(p..".ProvinceContext.CQI")
                result[#result+1]={key=key,
                    name=tostring(K.read(p..".ProvinceContext.Name") or (K.L("commandery")..province)),province=province}
            end
        end
    end
    table.sort(result,function(a,b) return a.name<b.name end)
    U.regions=result
    return result
end

local function change_profile(region,source)
    local state=C().state
    local config=state.cities[region]
    if not config then state.cities[region]={profile="agriculture",paused=false}
    else
        local next=cycle(config.profile,{"agriculture","commerce","industry","other","recommended","off"})
        if next=="off" then state.cities[region]=nil else config.profile=next end
    end
    U.refresh()
    U.attach_controls()
    K.log("City type: region="..region.." source="..tostring(source or "settings")..
        " profile="..tostring(state.cities[region] and state.cities[region].profile or "off"))
    C().request_run()
end

local function pause(region,source)
    local config=C().state.cities[region]
    if not config then return end
    config.paused=not config.paused
    K.log("City pause: region="..region.." source="..tostring(source or "settings").." paused="..tostring(config.paused))
    U.refresh();U.attach_controls()
    if config and not config.paused then C().request_run() end
end

local function save_templates()
    local ok,why=TK_AUTO_TEMPLATE_STORE.save(C().state.profiles,cm:get_local_faction(true))
    U.message=ok and K.L("templates_saved") or (K.L("save_failed")..tostring(why))
    U.refresh()
end

local function load_templates()
    local templates,removed=TK_AUTO_TEMPLATE_STORE.load(U.can_choose)
    if templates then
        C().state.profiles=templates
        U.message=removed>0 and (K.L("templates_loaded")..removed..K.L("templates_loaded2")) or K.L("templates_loaded_all")
        C().request_run("templates_loaded")
    else U.message=K.L("load_failed")..tostring(removed) end
    U.refresh()
end

function U.invalidate_panel()
    U.generation=U.generation+1
    U.panel=nil
    U.picker=nil
    U.pick_port=nil
    U.pick_port_target=nil
    U.pick_port_chain=nil
    U.inline_region=nil
    U.selected_region=nil
    U.has_selection_event=nil
    U.actions={}
    U.action_ids={}
    U.click_locks={}
    U.regions={}
    title_cache={}
    effects_cache={}
end

function U.close()
    U.open_flag=false
    if valid_component(U.panel) then pcall(function() U.panel:SetVisible(false) end) end
    U.picker=nil
end

faction_permissions=function()
    local faction=cm:get_local_faction(true)
    if permissions_cache and permissions_cache.faction==faction then return permissions_cache end
    local meta=TK_AUTO_FACTION_META[faction] or {}
    local subculture=meta.subculture or K.read("PlayersFaction.SubcultureRecordContext.Key") or ""
    local culture=meta.culture or K.read("PlayersFaction.CultureRecordContext.Key") or ""
    local campaign=cm:get_campaign_name() or ""
    local chains,known={},false
    for _,rule in ipairs(TK_AUTO_BUILDING_AVAILABILITY_RULES) do
        if (rule.faction=="" or rule.faction==faction) and
           (rule.sub_culture=="" or rule.sub_culture==subculture) and
           (rule.culture=="" or rule.culture==culture) and
           (rule.campaign=="" or rule.campaign==campaign) then
            known=true
            for chain in pairs(TK_AUTO_BUILDING_AVAILABILITY_SETS[rule.set_id] or {}) do chains[chain]=true end
        end
    end
    permissions_cache={faction=faction,subculture=subculture,culture=culture,chains=chains,known=known}
    return permissions_cache
end

matching_variant=function(key,permission)
    local best,score=nil,-1
    for _,variant in ipairs((TK_AUTO_BUILDING_VARIANTS or {})[key] or {}) do
        if (variant.faction=="" or variant.faction==permission.faction) and
           (variant.subculture=="" or variant.subculture==permission.subculture) and
           (variant.culture=="" or variant.culture==permission.culture) then
            local specificity=(variant.faction~="" and 8 or 0)+
                (variant.subculture~="" and 4 or 0)+(variant.culture~="" and 2 or 0)
            if specificity>score then best,score=variant,specificity end
        end
    end
    return best
end

local function can_choose(key,permission)
    -- Templates describe future goals. Do not hide a final branch just because
    -- it is currently locked by technology, city level, or local resources.
    local target=TK_AUTO_BUILDINGS[key]
    if not target or not target.template_slot or target.visible==false then return false end
    if permission.known and not permission.chains[target.chain] then return false end
    -- Chain permission alone is insufficient: the same chain contains an
    -- orphaned bandit-only level 6 with no Han Chinese culture variant.
    local variant=matching_variant(key,permission)
    if not variant or variant.disables then return false end
    return permission.known or K.bool(record(key)..".CanPlayerBuildThis")
end
function U.can_choose(key) return can_choose(key,faction_permissions()) end

-- Position 0 of a template holds the branch a port city should end on. Those
-- buildings are fixed, so they are deliberately not part of the district
-- catalogue and are validated on their own here.
local function can_choose_port(key,permission)
    local target=TK_AUTO_BUILDINGS[key]
    if not target or not target.fixed then return false end
    if permission.known and not permission.chains[target.chain] then return false end
    local variant=matching_variant(key,permission)
    if variant and variant.disables then return false end
    return true
end
function U.can_choose_port(key) return can_choose_port(key,faction_permissions()) end

local function port_items()
    local result={}
    local permission=faction_permissions()
    for _,entry in ipairs(TK_AUTO_PORT_TARGETS or {}) do
        if can_choose_port(entry.key,permission) then result[#result+1]=entry end
    end
    return result
end

-- Only hide duplicates inside the template currently being edited.
-- A building may still appear in another city / elemental template.
local function goal_taken_by_other_slot(candidate,selected_index)
    local data=TK_AUTO_BUILDINGS[candidate]
    if not data then return false end
    local template=current_template()
    local count=U.mode=="county" and 2 or (U.mode=="gate" and 6 or 10)
    for i=1,count do
        if i~=selected_index then
            local existing=TK_AUTO_BUILDINGS[template[i]]
            if existing and existing.superchain==data.superchain then
                return true
            end
        end
    end
    return false
end

local function picker_items()
    local result={}
    local permission=faction_permissions()
    for _,key in ipairs(TK_AUTO_BUILDING_CHOICES) do
        if can_choose(key,permission) and not goal_taken_by_other_slot(key,U.picker) then result[#result+1]=key end
    end
    return result
end

local function choose(key)
    local tpl=current_template()
    local index=U.picker
    local data=TK_AUTO_BUILDINGS[key]
    if not data or not U.can_choose(key) or goal_taken_by_other_slot(key,index) then
        U.message="该建筑系列已用于本模板的另一个位置";U.refresh();return
    end
    for i=1,(U.mode=="county" and 2 or (U.mode=="gate" and 6 or 10)) do
        local old=TK_AUTO_BUILDINGS[tpl[i]]
        if i~=index and old and old.superchain==data.superchain then
            U.message=K.L("one_branch");U.refresh();return
        end
    end
    tpl[index]=key
    update_county()
    U.picker=nil;U.pick_target=nil;U.message=nil;U.refresh();C().request_run()
end

-- Fixed-building branches (position 0). A city can host one of two port
-- families, so the choice is stored per family and the automation applies
-- whichever family the city actually has.
local function choose_port(key)
    local tpl=C().state.profiles[U.profile]
    local superchain=U.pick_port_chain
    if key then
        local info=TK_AUTO_TEMPLATE_STORE.port_info(key)
        if not info then return end
        superchain=info.superchain
    end
    if not superchain then return end
    if key and not U.can_choose_port(key) then U.message=K.L("cannot_use");U.refresh();return end
    if type(tpl.port)~="table" then tpl.port={} end
    tpl.port[superchain]=key or nil
    U.message=nil;U.refresh();C().request_run()
end

local category_order={"industry","agriculture","commerce","military","government","other"}
-- Resolve authored text only while drawing; this module loads before locale.
local function category_name(category) return K.L("category_"..category) end

local function building_effects(key)
    local permission=faction_permissions()
    local cache_key=permission.faction..":"..permission.subculture..":"..tostring(key)
    if effects_cache[cache_key] then return effects_cache[cache_key] end
    local p=record(key)
    local result={}
    local effects=p..".EffectList.Filter(Priority > 0)"
    for i=0,math.min(K.number(effects..".Size"),128)-1 do
        local value=K.read(effects..".At("..i..").LocalisedText")
        if value and value~="" then result[#result+1]=tostring(value) end
    end
    if #result==0 then
        for _,value in ipairs((TK_AUTO_BUILDINGS[key] or {}).effects or {}) do result[#result+1]=value end
    end
    if #result>0 then effects_cache[cache_key]=result end
    return result
end

-- The fixed-building row offers only port end points, grouped by port family.
-- Nothing here can be cleared like a district slot: the game pins that plot, so
-- the player picks which branch each family should end on (or leaves it alone).
-- Selecting a row only highlights it; the same detail pane as the district
-- picker then shows cost, upkeep and effects before 确认 applies it.
local function render_port_picker(panel,x,y,width,height,px,py)
    K.label(panel,"tk_auto_pick_title",K.L("port_pick_title"),x,y+196,width-300,32)
    button(panel,"tk_auto_pick_template",K.L("back_template"),px+width-150,y+196,126,28,function()
        U.picker=nil;U.pick_port=nil;U.pick_port_target=nil;U.refresh()
    end)
    local tpl=C().state.profiles[U.profile]
    local ports=TK_AUTO_TEMPLATE_STORE.port_of(tpl)
    local items=port_items()
    local top=y+238
    local fy=py+height-48
    if #items==0 then
        K.label(panel,"tk_auto_port_empty",K.L("port_none_available"),x,top,width-48,40)
        return
    end
    table.sort(items,function(a,b)
        if a.superchain~=b.superchain then return a.superchain<b.superchain end
        return a.key<b.key
    end)
    local list_width=math.floor((width-64)*0.44)
    local row,last_chain=0,nil
    for _,entry in ipairs(items) do
        if entry.superchain~=last_chain then
            last_chain=entry.superchain
            local chain_name=K.read(record(entry.key)..".BuildingChainRecordContext.Name")
            if not chain_name or tostring(chain_name)=="" or tostring(chain_name):match("^3k_") then
                chain_name=entry.chain or entry.superchain
            end
            K.label(panel,"tk_auto_port_group_"..row,tostring(chain_name),x,top+row*40,list_width,30)
            row=row+1
        end
        local mark=(ports[entry.superchain]==entry.key) and "● " or ""
        button(panel,"tk_auto_port_"..row,
            mark..building_title(entry.key).." ["..(entry.level or 0)..K.L("level_suffix").."]",
            x,top+row*40,list_width,34,function()
                U.pick_port_target=entry.key
                U.pick_port_chain=entry.superchain
                U.effect_page=1
                U.refresh()
            end)
        row=row+1
    end
    local key=U.pick_port_target
    if key and TK_AUTO_BUILDINGS[key] then
        local data=TK_AUTO_BUILDINGS[key]
        local dx,dw=x+list_width+18,width-66-list_width
        K.label(panel,"tk_auto_port_title",building_title(key).." ["..(data.display_level or 0)..K.L("level_suffix"),
            dx,top,dw,32)
        K.label(panel,"tk_auto_port_cost",K.L("base_cost")..(data.cost or 0)..K.L("upkeep")..(data.upkeep or 0),
            dx,top+34,dw,28)
        K.label(panel,"tk_auto_port_unlock",K.L("city_requirement")..(data.city_requirement or 0)..K.L("build_limits"),
            dx,top+62,dw,40)
        local effects=building_effects(key)
        local per=math.max(1,math.min(6,math.floor((fy-top-206)/32)))
        local pages=math.max(1,math.ceil(#effects/per))
        U.effect_page=math.min(U.effect_page or 1,pages)
        for i=1,per do
            local value=effects[(U.effect_page-1)*per+i]
            if value then
                local label=K.label(panel,"tk_auto_port_effect_"..i,value,dx,top+106+(i-1)*32,dw,30)
                if label then label:SetTooltipText(value,true) end
            end
        end
        if #effects==0 then K.label(panel,"tk_auto_port_effect_empty",K.L("no_effects"),dx,top+106,dw,30) end
        local ey=fy-68
        button(panel,"tk_auto_port_effect_prev",K.L("effects_prev"),dx,ey,100,28,function()
            U.effect_page=math.max(1,U.effect_page-1);U.refresh()
        end)
        K.label(panel,"tk_auto_port_effect_page",U.effect_page.." / "..pages,dx+108,ey,80,28)
        button(panel,"tk_auto_port_effect_next",K.L("effects_next"),dx+190,ey,100,28,function()
            U.effect_page=math.min(pages,U.effect_page+1);U.refresh()
        end)
        button(panel,"tk_auto_port_leave",K.L("port_leave_alone"),dx,fy-34,dw,30,function()
            U.pick_port_chain=TK_AUTO_TEMPLATE_STORE.port_info(key) and
                TK_AUTO_TEMPLATE_STORE.port_info(key).superchain or U.pick_port_chain
            choose_port(false)
        end)
        button(panel,"tk_auto_port_confirm",K.L("port_confirm"),dx,fy-2-34-34,dw,32,function() choose_port(key) end)
    end
    K.label(panel,"tk_auto_port_hint",K.L("port_hint"),x,fy,list_width,32)
end

local function render_picker(panel,x,y,width,height,px,py)
    if U.picker==0 then render_port_picker(panel,x,y,width,height,px,py);return end
    -- Rebuild the available choices for each open picker: cached choices are global,
    -- but uniqueness depends on the active template and slot.
    local available_choices=picker_items()
    local groups={}
    for _,key in ipairs(available_choices) do
        local data=TK_AUTO_BUILDINGS[key]
        local category=data.category or "other"
        groups[category]=groups[category] or {}
        groups[category][data.chain]=groups[category][data.chain] or {}
        table.insert(groups[category][data.chain],key)
    end
    local title=K.L("pick_slot_title")..U.picker..K.L("pick_slot_title2")
    title=title..(U.pick_category and category_name(U.pick_category) or K.L("choose_category"))
    if U.pick_chain then
        local key=groups[U.pick_category][U.pick_chain][1]
        title=title.." → "..tostring(K.read(record(key)..".BuildingChainRecordContext.Name") or TK_AUTO_BUILDINGS[key].chain_name)
    end
    K.label(panel,"tk_auto_pick_title",title,x,y+196,width-300,32)
    button(panel,"tk_auto_pick_back",K.L("back"),px+width-270,y+196,116,28,function()
        if U.pick_chain then U.pick_chain=nil;U.pick_target=nil
        elseif U.pick_category then U.pick_category=nil
        else U.picker=nil end
        U.picker_page=1;U.refresh()
    end)
    button(panel,"tk_auto_pick_template",K.L("back_template"),px+width-150,y+196,126,28,function() U.picker=nil;U.refresh() end)
    local top=y+238
    local fy=py+height-48
    if not U.pick_category then
        local row=0
        for _,category in ipairs(category_order) do
            local chains=groups[category]
            if chains then
                local count,branches=0,0
                for _,items in pairs(chains) do count=count+1;branches=branches+#items end
                local selected=category
                button(panel,"tk_auto_category_"..category,category_name(category).."  · "..count..K.L("sequence_count")..branches..K.L("branch_count"),
                    x,top+row*48,width-48,40,function() U.pick_category=selected;U.picker_page=1;U.refresh() end)
                row=row+1
            end
        end
        K.label(panel,"tk_auto_pick_hint",K.L("pick_hint"),x,fy,width-48,32)
        return
    end
    local items={}
    if U.pick_chain then
        items=groups[U.pick_category][U.pick_chain]
    else
        for chain,keys in pairs(groups[U.pick_category]) do items[#items+1]={chain=chain,keys=keys} end
        table.sort(items,function(a,b)
            local aa,bb=TK_AUTO_BUILDINGS[a.keys[1]],TK_AUTO_BUILDINGS[b.keys[1]]
            if aa.sort~=bb.sort then return aa.sort<bb.sort end
            return a.chain<b.chain
        end)
    end
    local per_page=math.max(2,math.min(7,math.floor((fy-top-8)/48)))
    local page_count=math.max(1,math.ceil(#items/per_page))
    U.picker_page=math.min(U.picker_page,page_count)
    local list_width=U.pick_chain and math.floor((width-64)*0.43) or width-48
    for row=1,per_page do
        local item=items[(U.picker_page-1)*per_page+row]
        if item then
            local chosen=item
            if U.pick_chain then
                local data=TK_AUTO_BUILDINGS[item]
                button(panel,"tk_auto_pick_"..row,(U.pick_target==item and "● " or "")..building_title(item).." ["..data.display_level..K.L("level_suffix"),
                    x,top+(row-1)*48,list_width,40,function() U.pick_target=chosen;U.effect_page=1;U.refresh() end)
            else
                local key=item.keys[1]
                local name=tostring(K.read(record(key)..".BuildingChainRecordContext.Name") or TK_AUTO_BUILDINGS[key].chain_name)
                button(panel,"tk_auto_pick_"..row,name.."  · "..#item.keys..K.L("branch_count"),x,top+(row-1)*48,list_width,40,function()
                    U.pick_chain=chosen.chain;U.pick_target=chosen.keys[1];U.effect_page=1;U.picker_page=1;U.refresh()
                end)
            end
        end
    end
    button(panel,"tk_auto_pick_prev",K.L("prev_page"),x,fy,90,28,function() U.picker_page=math.max(1,U.picker_page-1);U.refresh() end)
    K.label(panel,"tk_auto_pick_page",U.picker_page.." / "..page_count,x+96,fy,82,28)
    button(panel,"tk_auto_pick_next",K.L("next_page"),x+184,fy,90,28,function() U.picker_page=math.min(page_count,U.picker_page+1);U.refresh() end)
    if U.pick_chain and U.pick_target then
        local key=U.pick_target
        local data=TK_AUTO_BUILDINGS[key]
        local dx,dw=x+list_width+18,width-66-list_width
        local p=record(key)
        K.label(panel,"tk_auto_effect_title",building_title(key).." ["..data.display_level..K.L("level_suffix"),dx,top,dw,38)
        K.label(panel,"tk_auto_effect_cost",K.L("base_cost")..data.cost..K.L("upkeep")..data.upkeep,dx,top+40,dw,30)
        K.label(panel,"tk_auto_effect_unlock",K.L("city_requirement")..(data.city_requirement or 0)..
            K.L("build_limits"),dx,top+70,dw,42)
        local effects=building_effects(key)
        local per_effect=math.max(1,math.min(6,math.floor((fy-top-188)/36)))
        local pages=math.max(1,math.ceil(#effects/per_effect))
        U.effect_page=math.min(U.effect_page or 1,pages)
        for i=1,per_effect do
            local value=effects[(U.effect_page-1)*per_effect+i]
            if value then
                local label=K.label(panel,"tk_auto_effect_"..i,value,dx,top+114+(i-1)*36,dw,34)
                if label then label:SetTooltipText(value,true) end
            end
        end
        if #effects==0 then K.label(panel,"tk_auto_effect_empty",K.L("no_effects"),dx,top+114,dw,34) end
        local ey=fy-66
        button(panel,"tk_auto_effect_prev",K.L("effects_prev"),dx,ey,100,28,function() U.effect_page=math.max(1,U.effect_page-1);U.refresh() end)
        K.label(panel,"tk_auto_effect_page",U.effect_page.." / "..pages,dx+108,ey,80,28)
        button(panel,"tk_auto_effect_next",K.L("effects_next"),dx+190,ey,100,28,function() U.effect_page=math.min(pages,U.effect_page+1);U.refresh() end)
        button(panel,"tk_auto_pick_confirm",K.L("set_as_target")..U.picker..K.L("set_as_target2"),dx,fy-30,dw,30,function() choose(key) end)
    end
end

local function render_panel()
    local panel=U.panel
    -- Hide old controls without retaining their stale positions.
    for i=0,panel:ChildCount()-1 do
        local child=UIComponent(panel:Find(i))
        if valid_component(child) then
            local id=child:Id()
            if id~="tk_auto_close" and id:match("^tk_auto_") then child:SetVisible(false) end
        end
    end
    local px,py=panel:Position();local width,height=panel:Dimensions()
    -- A just-created panel reports 0x0 until the first layout pass. Laying the
    -- toolbar out against that produced negative widths, i.e. widgets that were
    -- created but invisible, and a panel that only filled in after being reopened.
    if type(width)~="number" or width<320 then width=1040 end
    if type(height)~="number" or height<260 then height=720 end
    local x,y=px+22,py+20
    K.label(panel,"tk_auto_title","["..(C().version or K.version).."] "..K.L("city_title").." · "..tostring(K.read("PlayersFaction.Name") or K.L("current_faction")),x,y,width-200,32)
    -- Manual language override, in case LocLanguage detection is wrong.
    button(panel,"tk_auto_lang",TK_AUTO_LOCALE.label(TK_AUTO_LOCALE.language()),px+width-196,y,86,30,function()
        TK_AUTO_LOCALE.next_language()
        -- A completed pass contains already formatted text in the old language.
        C().ui_message=nil;C().ui_reasons=nil;U.message=nil
        title_cache={};effects_cache={}
        U.refresh();U.attach_controls()
        if K.restore_toolbar then K.restore_toolbar() end
    end)
    button(panel,"tk_auto_close",K.L("close"),px+width-104,y,80,30,U.close)
    button(panel,"tk_auto_anchor",K.L("panel_position")..": "..K.panel_anchor_label(K.panel_anchor["cities"]),
        px+width-380,y,174,30,function() K.cycle_panel_anchor("cities",U.panel);U.refresh() end)
    local state=C().state
    -- Two rows, as asked for. Row one is the three on/off switches with the run
    -- button at its right-hand end; row two is the two building controls followed
    -- by the city control.
    --   row 1: 自动建造 | 自动升级城市 | 自动升级关隘 | .................... 现在执行
    --   row 2: 建筑排序 | 建筑优先种类 | 城市升级排序
    local row1,row2=y+44,y+80
    -- Switching any of these on should take effect now, not at the next turn, and
    -- every one of them re-runs so the panel shows what changed.
    button(panel,"tk_auto_master",state.enabled and K.L("master_on") or K.L("master_off"),x,row1,178,30,function()
        state.enabled=not state.enabled;U.refresh()
        if state.enabled then C().request_run("master_on") else C().ui_message=K.L("run_off");U.refresh() end
    end)
    button(panel,"tk_auto_growth",state.auto_growth and K.L("growth_auto") or K.L("growth_manual"),x+186,row1,196,30,function()
        state.auto_growth=not state.auto_growth;U.refresh();C().request_run("growth_toggle")
    end)
    button(panel,"tk_auto_gate",state.auto_gate and K.L("gate_auto") or K.L("gate_manual"),x+390,row1,196,30,function()
        state.auto_gate=not state.auto_gate;U.refresh();C().request_run("gate_toggle")
    end)
    local run_x=math.max(x+624,px+width-176)
    button(panel,"tk_auto_run",K.L("run_now"),run_x,row1,156,30,function() C().request_run("manual") end)
    -- Row two. The first two are linked: together they decide which of a city's
    -- own template entries is paid for first. They deliberately say nothing about
    -- the order cities are handled in - that is the third control alone.
    button(panel,"tk_auto_build_sort",K.L("build_sort_"..tostring(state.build_sort)),x,row2,206,30,function()
        state.build_sort=cycle(state.build_sort,K.BUILD_SORTS or {"income_high","income_low","food_high","food_low"})
        U.refresh();C().request_run("build_sort")
    end)
    button(panel,"tk_auto_build_focus",K.L("build_focus_"..tostring(state.build_focus)),x+214,row2,190,30,function()
        state.build_focus=cycle(state.build_focus,K.BUILD_FOCUSES or {"all","agriculture","commerce","industry","other"})
        U.refresh();C().request_run("build_focus")
    end)
    button(panel,"tk_auto_city_sort",K.L("city_sort_"..tostring(state.city_sort)),x+412,row2,206,30,function()
        state.city_sort=cycle(state.city_sort,K.CITY_SORTS or {"big","small","under8"})
        U.refresh();C().request_run("city_sort")
    end)
    K.label(panel,"tk_auto_food_label",K.L("reserve_food")..state.reserve_food,x,y+116,230,28)
    button(panel,"tk_auto_food_minus","−",x+230,y+116,34,28,function() state.reserve_food=math.max(0,state.reserve_food-1);U.refresh() end)
    button(panel,"tk_auto_food_plus","+",x+268,y+116,34,28,function() state.reserve_food=state.reserve_food+1;U.refresh() end)
    K.label(panel,"tk_auto_money_label",K.L("reserve_money")..state.reserve_money,x+326,y+116,210,28)
    button(panel,"tk_auto_money_minus","−",x+540,y+116,34,28,function() state.reserve_money=math.max(0,state.reserve_money-500);U.refresh() end)
    button(panel,"tk_auto_money_plus","+",x+578,y+116,34,28,function() state.reserve_money=state.reserve_money+500;U.refresh() end)
    U.mode=U.mode or "capital"
    U.element=U.element or "metal"
    button(panel,"tk_auto_mode_capital",U.mode=="capital" and "● 主城建筑模板" or "主城建筑模板",x,y+151,156,30,function()
        U.mode="capital";U.picker=nil;U.message=nil;U.refresh()
    end)
    button(panel,"tk_auto_mode_county",U.mode=="county" and "● 资源县五行模板" or "资源县五行模板",x+160,y+151,160,30,function()
        U.mode="county";U.picker=nil;U.message=nil;U.refresh()
    end)
    button(panel,"tk_auto_mode_gate",U.mode=="gate" and "● 关隘六建筑" or "关隘六建筑",x+324,y+151,155,30,function()
        U.mode="gate";U.picker=nil;U.message=nil;U.goal_page=1;U.refresh()
    end)
    if U.mode=="capital" then
        button(panel,"tk_auto_global_cap",state.global_capitals and "全主城自动: 开" or "全主城自动: 关",x+485,y+151,155,30,function()
            state.global_capitals=not state.global_capitals;U.refresh();C().request_run()
        end)
        button(panel,"tk_auto_cap_profile", "当前模板: "..K.L("profile_"..U.profile),x+215,y+185,220,30,function()
            U.profile=cycle(U.profile,profiles);U.picker=nil;U.refresh()
        end)
    elseif U.mode=="county" then
        for i,e in ipairs(element_order) do
            local item=e
            button(panel,"tk_auto_element_"..e,(U.element==e and "● " or "")..element_names[e],x+(i-1)*79,y+185,73,28,function()
                U.element=item;U.picker=nil;U.message=nil;U.refresh()
            end)
        end
        button(panel,"tk_auto_auto_county",state.auto_counties and "资源县自动: 开" or "资源县自动: 关",x+410,y+185,150,28,function()
            C().enable_counties(not state.auto_counties);U.refresh();C().request_run()
        end)
    end
    button(panel,"tk_auto_capture_sample","以选中地区作样板",x+570,y+185,164,28,function()
        local region=U.selected_region or U.inline_region
        if not region then U.message="请先在地图选中己方地区";U.refresh();return end
        local ok,result
        if U.mode=="county" then
            ok,result=C().capture_county_template(region)
            if ok then U.element=result end
        else
            ok,result=C().capture_capital_template(region)
            if ok then U.profile="agriculture" end
        end
        U.message=ok and "样板已读取；请核对各目标" or ("读取失败: "..tostring(result))
        U.refresh()
    end)
    if U.picker then
        render_picker(panel,x,y,width,height,px,py)
        return
    end
    -- A legacy save can have no gate profile; never abort the control row.
    local tpl=current_template()
    if type(tpl)~="table" then
        if U.mode=="gate" then
            C().state.profiles.gate={}
            tpl=C().state.profiles.gate
        else
            tpl={}
        end
    end
    if U.mode=="capital" or U.mode=="gate" then
        button(panel,"tk_auto_goal_page",(U.goal_page==2 and (U.mode=="gate" and "关隘建筑 6/6" or "建筑 6-10 / 10") or (U.mode=="gate" and "关隘建筑 1-5/6" or "建筑 1-5 / 10")).."  [切换]",x,y+187,202,28,function()
            U.goal_page=(U.goal_page==2) and 1 or 2;U.refresh()
        end)
    end
    local count=U.mode=="county" and 2 or (U.mode=="gate" and (U.goal_page==2 and 1 or 5) or 5)
    local start_index=U.mode=="county" and 1 or (U.goal_page==2 and 6 or 1)
    -- Reserve column zero only in capital mode; gate has six district goals.
    local cw=(width-48)/(count+(U.mode=="capital" and 1 or 0))
    if U.mode=="capital" then
        local ports=TK_AUTO_TEMPLATE_STORE.port_of(tpl)
        local chosen={}
        for _,key in pairs(ports) do chosen[#chosen+1]=building_title(key) end
        button(panel,"tk_auto_slot_0","0. "..K.L("slot_fixed"),x,y+222,cw-8,58,function()
            U.picker=0;U.pick_port=true;U.pick_port_target=nil;U.pick_port_chain=nil
            U.picker_page=1;U.pick_category=nil;U.pick_chain=nil;U.pick_target=nil;U.effect_page=1;U.message=nil;U.refresh()
        end)
        K.label(panel,"tk_auto_fixed_note",#chosen>0 and table.concat(chosen," / ") or K.L("port_unset"),x,y+286,cw-8,26)
    end
    for pos=1,count do
        local index=start_index+pos-1
        local key=tpl[index]
        local xx=x+(pos-1+(U.mode=="capital" and 1 or 0))*cw
        -- An unsupported DLC building name must not prevent rendering the row.
        local success,label=pcall(building_title,key)
        if not success then
            K.log("Gate/City target name failed at "..tostring(index)..": "..tostring(label))
            label=key and ("未识别: "..tostring(key)) or K.L("pick_building")
        end
        button(panel,"tk_auto_slot_"..index,index..". "..tostring(label),xx,y+222,cw-8,58,function()
            U.picker=index;U.pick_port=nil;U.picker_page=1;U.pick_category=nil;U.pick_chain=nil;U.pick_target=nil;U.effect_page=1;U.message=nil;U.refresh()
        end)
        if key then button(panel,"tk_auto_remove_"..index,K.L("clear"),xx,y+286,cw-8,26,function()
            tpl[index]=false;update_county();U.refresh();C().request_run()
        end) end
    end
    -- Two rows: what happened, and (when nothing happened) which settlements
    -- were skipped and why. Without the second line "it did nothing" is a dead end.
    local summary=(U.message or C().ui_message or K.L("panel_hint"))
    if C().ui_reasons then summary=summary.."\n"..C().ui_reasons end
    K.label(panel,"tk_auto_message",summary,x,y+320,width-48,56)
    local available=U.regions
    local per_page=math.max(3,math.min(9,math.floor((height-456)/34)))
    local page_count=math.max(1,math.ceil(#available/per_page))
    U.page=math.min(U.page,page_count)
    for i=1,per_page do
        local entry=available[(U.page-1)*per_page+i]
        if entry then
            local region=entry.key;local config=state.cities[region]
            local yy=y+384+(i-1)*34
            K.label(panel,"tk_auto_city_name_"..i,entry.name,x,yy,width-380,30)
            button(panel,"tk_auto_city_type_"..i,config and K.L("city_"..config.profile) or K.L("city_unmanaged"),px+width-336,yy,126,28,function() change_profile(region) end)
            button(panel,"tk_auto_city_pause_"..i,config and (config.paused and K.L("resume") or K.L("pause")) or "—",px+width-200,yy,74,28,function() pause(region) end)
            button(panel,"tk_auto_city_go_"..i,K.L("locate"),px+width-116,yy,90,28,function() K.command(K.settlement(region)..".SelectAndZoom") end)
        end
    end
    local fy=py+height-48
    button(panel,"tk_auto_city_prev",K.L("prev_page"),x,fy,110,28,function() U.page=math.max(1,U.page-1);U.refresh() end)
    K.label(panel,"tk_auto_city_page",U.page.." / "..page_count,x+124,fy,140,28)
    button(panel,"tk_auto_city_next",K.L("next_page"),x+276,fy,110,28,function() U.page=math.min(page_count,U.page+1);U.refresh() end)
    button(panel,"tk_auto_templates_save",K.L("save_template"),x+406,fy,126,28,save_templates)
    button(panel,"tk_auto_templates_load",K.L("load_template"),x+542,fy,126,28,load_templates)
end

-- Redraw wrapper: creating and hiding our own children makes the layout engine
-- re-anchor the panel, so put it back where the player dragged it afterwards.
function U.refresh()
    if not panel_visible() then return end
    local px,py=U.panel:Position()
    local ok,err=pcall(render_panel)
    if not ok then
        K.log("City panel redraw failed ("..tostring(U.mode).."): "..tostring(err))
        -- Visible failure report instead of an unexplained blank panel.
        pcall(function()
            K.label(U.panel,"tk_auto_render_failure", "关隘目标显示出错: "..tostring(err),px+22,py+320,790,70)
        end)
    end
    K.hold_panel("cities",U.panel)
end

function U.open()
    if panel_visible() then U.close();return end
    local created,problem=pcall(function()
        -- Acquire the live root after the click event has returned.
        local root=K.ui_root()
        assert(valid_component(root),"UI root is unavailable")
        local w,h=root:Dimensions()
        assert(type(w)=="number" and type(h)=="number" and w>80 and h>100,"UI dimensions are unavailable")
        U.panel=K.component(root,"tk_auto_city_settings","ui/tk_auto/panel.twui.xml")
        assert(valid_component(U.panel),"Settings component could not be created")
        local width,height=math.min(1040,w-40),math.min(720,h-60)
        U.panel:SetDockingPoint(0);K.resize(U.panel,width,height)
        K.set_panel_anchor("cities",U.panel,K.panel_anchor["cities"] or "center")
        U.panel:PropagatePriority(640);U.panel:SetVisible(true)
        U.open_flag=true
        -- Keep a usable close button even if model/catalog rendering fails.
        local px,py=U.panel:Position()
        button(U.panel,"tk_auto_close",K.L("close"),px+width-104,py+20,80,30,U.close)
    end)
    if not created then
        K.log("Settings could not open: "..tostring(problem))
        U.close();U.panel=nil
        return
    end
    title_cache={};effects_cache={}
    local generation=U.generation
    K.defer(function()
        if generation~=U.generation or not panel_visible() then return end
        local ok,err=pcall(function() regions();U.refresh() end)
        if not ok then
            K.log("Settings could not finish drawing: "..tostring(err))
            local px,py=U.panel:Position();local width=U.panel:Dimensions()
            K.label(U.panel,"tk_auto_settings_error",K.L("settings_error"),px+22,py+110,width-44,40)
        end
    end,0.08,"tk_auto_city_panel_content")
end

local function shown(component,boundary)
    for _=1,20 do
        if not component or not component:Visible() then return false end
        if component==boundary then return true end
        local address=component:Parent()
        if not address then return true end
        component=UIComponent(address)
    end
    return false
end

local function visible_recruit(panel)
    local first=K.find(panel,"recruit_new_army")
    if first and shown(first,panel) then return first end
    -- The native panel has separate capital/county recruit widgets. Search only
    -- visible branches when the first matching widget belongs to a hidden one.
    local visited=0
    local function visit(parent)
        visited=visited+1
        if visited>512 or not parent:Visible() then return nil end
        if parent:Id()=="recruit_new_army" then return parent end
        for i=0,parent:ChildCount()-1 do
            local child=UIComponent(parent:Find(i))
            local found=visit(child)
            if found then return found end
        end
    end
    return visit(panel)
end

function U.remember_region(region)
    U.selected_region=nil
    U.inline_region=nil
    U.has_selection_event=true
    if region and not region:is_null_interface() and region:owning_faction():name()==cm:get_local_faction(true) then
        U.selected_region=region:name()
    end
end

function U.attach_controls()
    local root=K.ui_root()
    local map={}
    for _,entry in ipairs(regions()) do map[entry.province]=entry end
    local panel=K.find(root,"province_panel")
    U.inline_region=nil
    if panel and panel:Visible() then
        -- Hide controls while the selected province is foreign or unavailable;
        -- do not leave last city's action behind after changing the selection.
        for _,id in ipairs({"tk_auto_recruit_type","tk_auto_recruit_pause","tk_auto_settlement_type","tk_auto_settlement_pause"}) do
            local old=K.find(panel,id)
            if old then old:SetVisible(false) end
        end
        -- The panel's stored province is the city actually being shown, even
        -- after native clicks clear model selection or bypass a region event.
        local province=K.number('Component("province_panel").StoredContext("CcoCampaignProvince").CQI')
        if province<=0 then
            if U.selected_region then
                province=K.number(K.settlement(U.selected_region)..".ProvinceContext.CQI")
            elseif not U.has_selection_event then
                province=K.number("PlayersFaction.ProvinceList.FirstContext(IsSelected).CQI")
            end
        end
        local entry=map[province]
        local recruit=visible_recruit(panel)
        if entry and recruit then
            U.inline_region=entry.key
            local x,y=recruit:Position();local w=recruit:Dimensions()
            local height=26;local gap=6
            local config=C().state.cities[entry.key]
            -- Keep these independent of the recruit widget's disabled native
            -- parent, while following its on-screen position.
            local type_button=button(panel,"tk_auto_settlement_type",config and K.L("city_"..config.profile) or K.L("city_unmanaged"),
                x,y-height-gap,w*0.62-3,height,function()
                    if U.inline_region==entry.key then change_profile(entry.key,"settlement_panel") end
                end)
            local pause_button=button(panel,"tk_auto_settlement_pause",config and (config.paused and K.L("resume") or K.L("pause")) or "—",
                x+w*0.62+3,y-height-gap,w*0.38-3,height,function()
                    if U.inline_region==entry.key then pause(entry.key,"settlement_panel") end
                end)
            if type_button then type_button:SetTooltipText(entry.name..": "..K.L("tip_type"),true) end
            if pause_button then pause_button:SetTooltipText(entry.name..": "..K.L("tip_pause"),true) end
        end
    end
end

function U.prepare_templates()
    local state=C().state
    local had_targets=TK_AUTO_TEMPLATE_STORE.has_targets(state.profiles)
    state.profiles=TK_AUTO_TEMPLATE_STORE.normalize(state.profiles,U.can_choose)
    if not state.template_initialized then
        state.template_initialized=true
        if not had_targets then
            local templates,removed=TK_AUTO_TEMPLATE_STORE.load(U.can_choose)
            if templates then
                state.profiles=templates
                U.message=K.L("templates_autoloaded")..(removed>0 and (removed..K.L("templates_unusable")) or "")
            end
        end
    end
end

function U.init()
    C().ui_refresh=U.refresh
    local state=C().state
    if state.auto_gate==nil then state.auto_gate=true end
    -- Register entry points before optional disk/CCO template processing.
    -- A template failure must never remove both settings entry points.
    core:add_listener("tk_auto_city_buttons","ComponentLClickUp",
        function(c) return U.resolve_action(c)~=nil end,
        U.dispatch_action,true)
    core:add_listener("tk_auto_city_escape","ShortcutTriggered",
        function(c) return panel_visible() and
            (c.string=="escape" or c.string=="ESC" or c.string=="close_panel" or c.string=="cancel") end,
        U.close,true)
    core:add_listener("tk_auto_city_other_panel","PanelOpenedCampaign",true,
        function() if panel_visible() then U.close() end end,true)
    core:add_listener("tk_auto_city_panel","PanelOpenedCampaign",
        function(c) return event_id(c,"component_id")=="province_panel" or c.string=="province_panel" end,
        function() K.defer(U.attach_controls,0.12,"tk_auto_inline_attach") end,true)
    core:add_listener("tk_auto_city_selection","ComponentLClickUp",
        function(c)
            local id=event_id(c,"component_id") or c.string
            return type(id)=="string" and
                (id:match("^CcoCampaignProvince")~=nil or id:match("^CcoCampaignSettlement")~=nil)
        end,
        function() K.defer(U.attach_controls,0.12,"tk_auto_inline_selection") end,true)
    core:add_listener("tk_auto_city_selected_model","SettlementSelected",true,
        function(c)
            local ok,region=pcall(function() return c:settlement():region() end)
            if ok then U.remember_region(region) end
            K.defer(U.attach_controls,0.12,"tk_auto_inline_selected_model")
        end,true)
    core:add_listener("tk_auto_city_region_selected","RegionSelected",true,
        function(c)
            U.remember_region(c:region())
            K.defer(U.attach_controls,0.12,"tk_auto_inline_region_selected")
        end,true)
    K.watch_panel("cities",function() return U.open_flag==true end,function() return U.panel end)
    K.register_toolbar("cities",function()
        local root=K.ui_root();local x,y=K.toolbar()
        return button(root,"tk_auto_city_open",K.L("city_settings"),x+TK_AUTO_TOOLBAR.width+TK_AUTO_TOOLBAR.gap,y,TK_AUTO_TOOLBAR.width,TK_AUTO_TOOLBAR.height,U.open)
    end)
    K.runtime_probe("cities_toolbar_registered")
    K.defer(function()
        K.runtime_probe("templates_before")
        U.prepare_templates()
        K.runtime_probe("templates_after")
    end,0.6,"tk_auto_template_start")
end
