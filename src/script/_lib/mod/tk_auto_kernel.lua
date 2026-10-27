-- Shared support for three independently loadable THREE KINGDOMS mods.
-- Lua 5.1; uses the game's CCO commands, never creates free skills/buildings.
TK_AUTO = TK_AUTO or {version = "0.1.35", warnings = {}, jobs = {}}
local K = TK_AUTO
K.version = "0.1.35"
K.warnings = K.warnings or {}
K.jobs = K.jobs or {}

function K.log(text)
    local line = "[TK_AUTO] " .. tostring(text)
    if ModLog then ModLog(line) elseif out then out(line) end
end

function K.warn(key, text)
    if K.warnings[key] then return end
    K.warnings[key] = true
    K.log(text)
end

function K.quote(value)
    return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

function K.L(key) return tostring(key) end

function K.read(expr)
    -- Per-pass circuit breaker: failed native CCO reads must never cascade.
    if K.city_bridge_fault then return nil end
    -- CampaignRoot is a global UI symbol, not a CCO creatable from a string id.
    local aliases = {IsPlayersTurn="CampaignRoot.IsPlayersTurn", IsMultiplayer="CampaignRoot.IsMultiplayer",
        CampaignKey="CampaignRoot.CurrentCampaignKey"}
    local expression=aliases[expr] or expr
    K.read_count=(K.read_count or 0)+1
    local traced=K.read_count<=3
    if traced then K.runtime_probe("read_before_"..K.read_count) end
    local ok, value = pcall(function() return effect.get_context_value(expression) end)
    if traced then K.runtime_probe("read_after_"..K.read_count) end
    if ok then return value end
    if K.city_pass_active then
        K.city_bridge_fault=true
        K.log("BRIDGE_CIRCUIT trip: "..tostring(expr).." error="..tostring(value))
    else
        K.warn("read:" .. expr, "Cannot read " .. expr .. ": " .. tostring(value))
    end
    return nil
end

function K.number(expr, fallback)
    local value=K.read(expr)
    return tonumber(value) or fallback or 0
end

function K.bool(expr)
    local value = K.read(expr)
    return value == true or value == 1 or value == "true"
end

function K.command(expr)
    if K.city_bridge_fault then return false end
    local ok, result = pcall(function() return effect.call_context_command(expr) end)
    if not ok then K.warn("command:" .. expr, "Command failed: " .. tostring(result)) end
    return ok and result ~= false
end

function K.context_command(kind,id,expr)
    if K.city_bridge_fault then return false end
    -- Pin a cached native context, rather than repeatedly constructing objects
    -- while following a global expression. Used for transient skill choices.
    local ok,result=pcall(function() return effect.call_context_command(kind,tostring(id),expr) end)
    if not ok then K.warn("context_command:"..kind..":"..tostring(id),"Context command failed: "..tostring(result)) end
    return ok and result~=false
end

function K.ready()
    if not effect or not effect.get_context_value or not effect.call_context_command then return false end
    if cm and cm.is_multiplayer and cm:is_multiplayer() then return false end
    if cm and cm.is_processing_battle and cm:is_processing_battle() then return false end
    -- The query model is available to UI events; use the actual active faction.
    local ok, faction = pcall(function() return cm:query_model():world():whose_turn_is_it():name() end)
    if ok then return faction==cm:get_local_faction(true) end
    return K.bool("IsPlayersTurn")
end

-- The native bridge short-circuits on have_modify_interface. A nested first-tick
-- event can leave that flag set with no actual model, so check the model itself.
local function model_available()
    local checked,can_modify=pcall(function() return cm:can_modify(true) end)
    if not checked or can_modify~=true then return false end
    local ok,model=pcall(function() return cm:modify_model() end)
    return ok and model~=nil and model~=false
end

function K.runtime_probe(stage)
    local ok,value=pcall(string.sub,"tk_auto",1,2)
    local healthy=ok and value=="tk"
    K.log("Runtime "..stage..": string_sub="..tostring(value).." native_model="..tostring(model_available()))
    return healthy
end

local request_model,flush_jobs
local function schedule_job(name,job)
    if not model_available() then return false end
    local ok,err=pcall(function()
        cm:callback(function()
            if K.jobs[name]~=job then return end
            K.jobs[name]=nil
            local ran,problem=pcall(job.fn)
            if not ran then K.warn("job:"..name,"Job stopped ("..name.."): "..tostring(problem)) end
        end,job.delay,name)
    end)
    if ok then job.scheduled=true;return true end
    K.warn("schedule:"..name,"Model timer unavailable for "..name..": "..tostring(err))
    return false
end

flush_jobs=function()
    if not model_available() then return end
    K.model_request_pending=false
    local batch={}
    for name,job in pairs(K.jobs) do
        if not job.scheduled then batch[#batch+1]={name,job} end
    end
    for _,entry in ipairs(batch) do schedule_job(entry[1],entry[2]) end
end

request_model=function()
    if K.model_request_pending then return true end
    if not K.model_bridge_listeners then
        K.model_bridge_listeners=true
        core:add_listener("tk_auto_deferred_model","CampaignModelScriptCallback",
            function(context)
                if context.string=="tk_auto_deferred_model" then return true end
                local ok,id=pcall(function() return context:context():event_id() end)
                return ok and id=="tk_auto_deferred_model"
            end,
            function()
                K.model_request_pending=false
                flush_jobs()
            end,true)
        -- Queued tasks survive a failed initial request. Native model events
        -- provide another opportunity; this is event driven, not frame polling.
        -- UI events are included because a job queued while one of our own panels
        -- was open has no model timer to run on, and otherwise sat in the queue
        -- until the next turn - which is what made buttons look dead.
        for _,event in ipairs({"FactionTurnStart","BuildingCompleted","RegionOwnershipChanged",
            "ComponentLClickUp","PanelOpenedCampaign","CharacterSelected","SettlementSelected"}) do
            core:add_listener("tk_auto_deferred_"..event,event,true,flush_jobs,true)
        end
    end
    K.model_request_pending=true
    local ok,result=pcall(function() return CampaignUI.CreateModelCallbackRequest("tk_auto_deferred_model") end)
    if not ok or result==false then
        K.model_request_pending=false
        K.warn("model_request","Cannot request native model callback: "..tostring(result))
        return false
    end
    return true
end

function K.defer(fn, delay, name, unavailable)
    name=tostring(name or "tk_auto_deferred")
    local existing=K.jobs[name]
    if existing and existing.scheduled then
        -- One native timer per task name. Replacing only the payload avoids
        -- creating another timer for every click/selection/toolbar request.
        existing.fn=fn
        return true
    end
    local job={fn=fn,delay=delay or 0.1}
    K.jobs[name]=job
    if schedule_job(name,job) then return true end
    local requested=request_model()
    if not requested and unavailable then pcall(unavailable) end
    return requested
end

-- UI actions must not hold a boolean until an unreliable model timer clears it.
-- A short time window deduplicates child/parent releases without blocking retries.
K.ui_click_times=K.ui_click_times or {}
function K.ui_action(id,action)
    local now=os.clock()
    local previous=K.ui_click_times[id]
    if previous and now>=previous and now-previous<0.12 then return false end
    K.ui_click_times[id]=now
    action()
    return true
end

function K.character(cqi)
    if K.number("PlayersFaction.FactionLeaderContext.CQI",-1)==tonumber(cqi) then
        return "PlayersFaction.FactionLeaderContext"
    end
    return "PlayersFaction.CharacterList.FirstContext(CQI == " .. tostring(tonumber(cqi) or -1) .. ")"
end

function K.settlement(region)
    return "PlayersFaction.SettlementList.FirstContext(RegionRecordKey == " .. K.quote(region) .. ")"
end

function K.owns_region(region)
    local ok,owned=pcall(function()
        local query=cm:query_region(region)
        return query and not query:is_null_interface() and
            query:owning_faction():name()==cm:get_local_faction(true)
    end)
    if ok then return owned==true end
    return K.bool(K.settlement(region)..".IsPlayerOwned")
end

function K.list(expr, property, limit)
    local result = {}
    local size = math.min(K.number(expr .. ".Size"), limit or 512)
    for i = 0, size - 1 do result[#result + 1] = K.read(expr .. ".At(" .. i .. ")." .. property) end
    return result
end

function K.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = K.copy(v) end
    return result
end

function K.valid_component(component)
    if not component then return false end
    local ok,id=pcall(function() return component:Id() end)
    return ok and type(id)=="string" and id~=""
end

function K.ui_root()
    local ok,root=pcall(function() return core:get_ui_root() end)
    if ok and root then return root end
end

function K.find(parent,id)
    if not parent then return nil end
    local ok,result=pcall(find_uicomponent,parent,id)
    if ok and result then return result end
end

function K.component(parent,id,template)
    if not parent then return nil end
    local existing=K.find(parent,id)
    if existing then return existing end
    -- Keep the pre-gate wrapper contract. Native versions may also return Void;
    -- look up by id after creation before falling back to a returned address.
    local called,address=pcall(function() return parent:CreateComponent(id,template) end)
    if not called then K.warn("create:"..id,"Component creation failed: "..tostring(address));return nil end
    local component=K.find(parent,id)
    if component then return component end
    if address then
        local wrapped,result=pcall(UIComponent,address)
        if wrapped and K.valid_component(result) then return result end
    end
    K.warn("create:"..id,"Component was not created: "..id)
end

function K.text(component, value)
    if not component then return end
    local label = K.find(component, "button_txt") or component
    local old = label:CurrentState()
    for _, state in ipairs({"active", "down", "hover", "inactive", "NewState"}) do
        pcall(function() label:SetState(state); label:SetStateText(tostring(value)) end)
    end
    pcall(function() label:SetState(old); label:SetStateText(tostring(value)) end)
end

function K.resize(c, width, height)
    c:SetCanResizeWidth(true)
    c:SetCanResizeHeight(true)
    c:Resize(math.floor(width), math.floor(height))
end

function K.toolbar()
    return TK_AUTO_TOOLBAR.origin(core:get_ui_root())
end

function K.layout_toolbar()
    TK_AUTO_TOOLBAR.layout(core:get_ui_root())
end

function K.button(parent, id, text, x, y, width, height, priority)
    local c = K.component(parent, id, "ui/tk_auto/button.twui.xml")
    if not c then return nil end
    -- The eighth argument is a numeric draw priority. A caller that passes
    -- something else (a click handler, say) must not poison the widget: a
    -- non-number there produced an unusable component that also swallowed
    -- clicks meant for its neighbours.
    if type(priority)~="number" then priority=600 end
    c:SetDockingPoint(0)
    K.resize(c,width or 130,height or 30)
    local label = K.find(c, "button_txt")
    if label then K.resize(label,width or 130,height or 30) end
    c:MoveTo(x, y)
    c:PropagatePriority(priority or 600)
    c:SetVisible(true)
    c:SetState("active")
    c:SetInteractive(true)
    if label then label:SetInteractive(false) end
    K.text(c, text)
    return c
end

-- Reuse the pre-gate toolbar flow: drawing happens in a deferred model callback,
-- not halfway through other mods' first-tick initialisation.
K.toolbar_entries=K.toolbar_entries or {}
function K.restore_toolbar()
    if not core:is_ui_created() then return false end
    local drawn,failed=0,false
    for id,draw in pairs(K.toolbar_entries) do
        -- One broken entry point must not take the others down with it: each draw
        -- is isolated, and a failure is recorded rather than propagated.
        local ok,widget=pcall(draw)
        if ok and widget then drawn=drawn+1
        else
            failed=true
            K.warn("toolbar:"..id,"Toolbar entry failed: "..id.." -> "..tostring(widget))
        end
    end
    pcall(K.layout_toolbar)
    K.toolbar_restore_failed=failed
    K.log("Toolbar ready: entries="..drawn.." failed="..tostring(failed))
    return not failed
end

function K.queue_toolbar_restore()
    -- Debounced by the job name, not by a boolean flag. A flag set by a request
    -- that never ran - queued while one of our own panels had the model locked -
    -- blocked every later request for good, so the toolbar was never redrawn again
    -- and all three entry points died together. Overwriting the job debounces just
    -- as well and cannot deadlock.
    local generation=K.ui_generation or 0
    local function run()
        if generation~=(K.ui_generation or 0) then return end
        local restored=K.restore_toolbar()
        if not restored and (K.toolbar_retries or 0)<3 then
            K.toolbar_retries=(K.toolbar_retries or 0)+1
            K.queue_toolbar_restore()
        elseif restored then K.toolbar_retries=0 end
    end
    -- No synchronous fallback. register_toolbar calls this during the modules'
    -- first-tick initialisation, and drawing UI components at that moment is
    -- exactly what the deferred flow exists to avoid - making the fallback run
    -- inline broke every entry point. A request that cannot get a timer simply
    -- stays queued and is flushed on the next click, panel or selection (see
    -- request_model), so it is never lost and never drawn too early.
    K.defer(run,0.25,"tk_auto_toolbar_restore")
end

function K.register_toolbar(id,draw)
    K.toolbar_entries[id]=draw
    if not K.toolbar_listeners then
        K.toolbar_listeners=true
        core:add_listener("tk_auto_toolbar_panel_closed","PanelClosedCampaign",true,
            function() K.toolbar_retries=0;K.queue_toolbar_restore() end,true)
        core:add_listener("tk_auto_toolbar_turn","FactionTurnStart",
            function(c) return c:faction():name()==cm:get_local_faction(true) end,
            K.queue_toolbar_restore,true)
        -- Self-heal: if the last restore did not succeed, the next click anywhere
        -- rebuilds the toolbar. Without this a failed restore left every entry
        -- point dead until the next turn. A healthy toolbar is not redrawn here.
        core:add_listener("tk_auto_toolbar_retry","ComponentLClickUp",
            function() return K.toolbar_restore_failed==true end,
            function() K.queue_toolbar_restore() end,true)
        local function invalidate()
            K.ui_generation=(K.ui_generation or 0)+1
            K.toolbar_retries=0
            if TK_AUTO_CITY_UI then
                if TK_AUTO_CITY_UI.invalidate_panel then TK_AUTO_CITY_UI.invalidate_panel()
                else TK_AUTO_CITY_UI.panel=nil end
            end
            if TK_AUTO_SKILLS and TK_AUTO_SKILLS.invalidate_panel then TK_AUTO_SKILLS.invalidate_panel() end
            -- Every UI-backed panel must drop its handle here. A rebuilt UI root
            -- orphans the old component, and drawing into an orphan only produces
            -- engine errors.
            if TK_AUTO_ARMY_UI then
                if TK_AUTO_ARMY_UI.invalidate_panel then TK_AUTO_ARMY_UI.invalidate_panel()
                else TK_AUTO_ARMY_UI.panel=nil end
            end
        end
        core:add_ui_created_callback(function() invalidate();K.queue_toolbar_restore() end)
        core:add_ui_destroyed_callback(invalidate)
    end
    K.queue_toolbar_restore()
end

-- ---------------------------------------------------------- panel placement
-- A dynamically created panel is re-anchored by the layout engine, so its
-- position has to be owned by us. The engine's own "moveable" drag does not
-- persist for created components, so the panels offer explicit anchor presets
-- instead, and the anchor is re-applied whenever anything moves the panel.
K.panel_anchor = K.panel_anchor or {}
K.panel_watchers = K.panel_watchers or {}
local PANEL_ANCHORS = {"center", "top_right", "bottom_right", "bottom_left", "top_left"}

function K.screen_size()
    local root = K.ui_root()
    if root then
        local ok, w, h = pcall(function() return root:Dimensions() end)
        if ok and type(w) == "number" and type(h) == "number" and w > 200 then return w, h end
    end
    return 1920, 1080
end

function K.anchor_position(name, component)
    if not component then return nil end
    local ok, w, h = pcall(function() local cw, ch = component:Dimensions(); return cw, ch end)
    if not ok or type(w) ~= "number" or type(h) ~= "number" then return nil end
    local sw, sh = K.screen_size()
    local pad = 16
    local spots = {
        center = {(sw - w) / 2, (sh - h) / 2},
        top_right = {sw - w - pad, pad},
        bottom_right = {sw - w - pad, sh - h - pad},
        bottom_left = {pad, sh - h - pad},
        top_left = {pad, pad},
    }
    local spot = spots[name] or spots.center
    return math.max(pad, spot[1]), math.max(pad, spot[2])
end

function K.set_panel_anchor(key, component, name)
    if not component then return end
    K.panel_anchor[key] = name or "center"
    local x, y = K.anchor_position(K.panel_anchor[key], component)
    if x then pcall(function() component:MoveTo(x, y) end) end
end

function K.cycle_panel_anchor(key, component)
    local current = K.panel_anchor[key] or "center"
    local next_name = PANEL_ANCHORS[1]
    for i, name in ipairs(PANEL_ANCHORS) do
        if name == current then next_name = PANEL_ANCHORS[i % #PANEL_ANCHORS + 1] end
    end
    K.set_panel_anchor(key, component, next_name)
    return next_name
end

function K.panel_anchor_label(name)
    return K.L("anchor_" .. (name or "center"))
end

-- Cheap guard: only touch the widget when it actually drifted, and never
-- re-enter: MoveTo itself raises ComponentMoved, so an unthrottled re-anchor
-- loop freezes the whole UI.
K.panel_holding = K.panel_holding or {}
function K.hold_panel(key, component)
    if not component or K.panel_holding[key] then return end
    local name = K.panel_anchor[key]
    if not name then return end
    local ok, x, y = pcall(function() return component:Position() end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return end
    local tx, ty = K.anchor_position(name, component)
    if not tx then return end
    if math.abs(x - tx) > 3 or math.abs(y - ty) > 3 then
        K.panel_holding[key] = true
        pcall(function() component:MoveTo(tx, ty) end)
        K.panel_holding[key] = nil
    end
end

-- Debounced: many moves per second are normal, but we only need to re-anchor
-- occasionally, and this keeps a MoveTo/ComponentMoved feedback loop bounded.
function K.schedule_hold(key, component_of)
    K.defer(function()
        K.hold_panel(key, component_of())
    end, 0.4, "tk_auto_panel_hold_" .. key)
end

function K.watch_panel(key, is_open, component_of)
    if K.panel_watchers[key] then return end
    K.panel_watchers[key] = true
    core:add_listener("tk_auto_panel_moved_" .. key, "ComponentMoved",
        is_open, function() K.schedule_hold(key, component_of) end, true)
end

function K.label(parent, id, text, x, y, width, height)
    local c = K.component(parent, id, "ui/tk_auto/label.twui.xml")
    if not c then return nil end
    c:SetDockingPoint(0)
    K.resize(c,width or 400,height or 30)
    c:MoveTo(x, y)
    c:PropagatePriority(670)
    c:SetVisible(true)
    K.text(c,text)
    return c
end
