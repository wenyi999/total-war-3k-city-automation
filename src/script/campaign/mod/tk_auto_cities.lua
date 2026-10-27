local K = TK_AUTO
local C = {version="0.1.49",state={version=1,enabled=true,
    -- Two separate orderings: the building pair ranks the entries of one city's
    -- template, the city key ranks cities against each other.
    build_sort="income_high",build_focus="all",city_sort="small",reserve_money=0,
    reserve_food=0,auto_growth=true,auto_gate=true,profiles={agriculture={},commerce={},industry={},other={},recommended={},gate={}},cities={},reservations={}},
    busy=false,submitted={},demolish_order={},status={},run=nil,requests=0}
TK_AUTO_CITIES=C
local SAVE="tk_auto_cities_v1"
-- EDIT HERE: Building LEVEL IDs, not translated in-game names.
-- Empty entries are intentionally safe; automation only runs once goals are set.
-- You can also call C.capture_capital_template(region_key, overrides) or
-- C.capture_county_template(region_key, overrides) from another Lua campaign script.
local USER_CONFIG={
    enabled=false, -- set true ONLY after filling the desired goal keys below
    capital={false,false,false,false,false,false,false,false,false,false},
    metal={false,false},wood={false,false},water={false,false},
    fire={false,false},earth={false,false},
    -- Optional: region keys of fully upgraded SAMPLE cities. These are captured
    -- at startup if enabled=true. Capture failure leaves that template untouched.
    sample_capital=false,
    sample_counties={metal=false,wood=false,water=false,fire=false,earth=false},
}
local FOOD="3k_main_pooled_resource_food"
local fixed_chains={}
for _,data in pairs(TK_AUTO_BUILDINGS) do
    if data.fixed then fixed_chains[data.chain]=true end
end
local food_effects='EffectKey == "3k_main_effect_province_food_consumption_distribution" || EffectKey == "3k_main_effect_province_food_abs_sold_markets" || EffectKey == "3k_main_effect_province_food_abs_farming" || EffectKey == "3k_main_effect_province_food_abs_fishing" || EffectKey == "3k_main_effect_province_food_abs_foraging" || EffectKey == "3k_dlc05_effect_province_food_abs_banditry"'

-- The recommended preset is independent of agriculture/commerce/industry/other.
-- IDs reflect the included 1.7.2 building catalogue. Users can edit these in
-- the existing ten-target editor. A few requested Chinese names differ from
-- the catalogue and should be verified in-game before enabling automation.
local RECOMMENDED_DEFAULT={
    "3k_district_artisan_mines_5", -- industrial mining workers (closest catalogue match)
    "3k_district_artisan_workshop_state_5", -- state workshop
    "3k_district_artisan_workshop_lacquer_5", -- lacquer workshop
    "3k_district_residential_government_tools_5", -- fan cart / agricultural tools line; modern catalog: 簸谷机器作坊
    "3k_district_residential_landlords_5", -- landlords
    "3k_district_market_tea_5", -- tea house
    "3k_district_market_trade_5", -- trade guild
    "3k_district_military_security_province_northern_horses_5", -- White Horse Garrison
    false, -- faction-specific structure / training camp: select in the UI
    "3k_district_government_administration_5", -- palace: last priority; omitted in hybrid resource cities
}
local function ensure_recommended_profile()
    C.state.profiles=C.state.profiles or {}
    if C.state.profiles.recommended and next(C.state.profiles.recommended) then return end
    local profile={port={}}
    for i=1,10 do
        local key=RECOMMENDED_DEFAULT[i]
        local data=key and TK_AUTO_BUILDINGS[key]
        profile[i]=(data and data.template_slot) and key or false
    end
    C.state.profiles.recommended=profile
end
ensure_recommended_profile()

-- Gate: its own six-goal district profile, independent of capital templates.
-- Unverified named branches are deliberately left editable rather than guessed.
local GATE_DEFAULT_NAMES={
    "派系特色建筑（无特色时：大型郡国学）", "扇车工坊", "豪强田产", "大型邸阁",
    "白马义从团部", "讲武营（征募三级）"
}
-- Name resolution uses BUILDING CHAIN, not an unverified exact Chinese label.
-- Original game labels differ from the bundled 1.7.2 catalog.
-- Candidate preview for in-game label verification ONLY:
-- slot 1 uses 孙坚江东兵府 as an UNVERIFIED stand-in for 孙策佣兵大帐;
-- slot 4 uses 南蛮国廪 as an UNVERIFIED stand-in for 大型邸阁.
-- The game may deny construction for faction or culture restrictions.
-- Other four goals are catalog matches; the conscription level 3 is
-- named 训练营 in catalog but shown 讲武营 in supplied screenshot.
local GATE_DEFAULT={
    "3k_district_market_school_5",                    -- fallback school until actual mercenary DLC key is supplied
    "3k_district_residential_government_tools_5",    -- 簸谷机器作坊 / fan cart branch
    "3k_district_residential_landlords_5",           -- 豪右农庄 / landowners branch
    "3k_district_residential_logistics_5",           -- verified 大型谷仓 / 大型邸阁
    "3k_district_military_security_province_northern_horses_5", -- 白马义从团部
    "3k_district_military_conscription_3",           -- screenshot: 讲武营, 征募三级; catalog: 训练营
}
local function ensure_gate_profile()
    C.state.profiles=C.state.profiles or {}
    local p=C.state.profiles.gate
    if type(p)~="table" then p={} end
    -- Upgrade only the original almost-empty Gate Beta preset. Never overwrite
    -- an edited profile (including deliberately cleared goals).
    local old_fifth="3k_district_military_security_province_5"
    local previous=not p._verified_defaults_v1 and
      (p[1]==nil or p[1]==false) and (p[2]==nil or p[2]==false) and
      (p[3]==nil or p[3]==false) and (p[4]==nil or p[4]==false) and
      (p[5]==nil or p[5]==false or p[5]==old_fifth) and
      (p[6]==nil or p[6]==false)
    -- Preview preset migration: replace ONLY unchanged original screenshot-beta
    -- defaults or the prior blank gate profile. Never overwrite edited goals.
    local prior_v1={
        "3k_district_market_school_5",
        "3k_district_residential_government_tools_5",
        "3k_district_residential_landlords_5",
        "3k_district_residential_logistics_5",
        "3k_district_military_security_province_northern_horses_5",
        "3k_district_military_conscription_3",
    }
    local prior_unchanged = p._verified_defaults_v1 and not p._candidate_preview_v2
    if prior_unchanged then
        for i=1,6 do
            if p[i]~=prior_v1[i] then prior_unchanged=false;break end
        end
    end
    if previous or prior_unchanged then
        for i=1,6 do
            local k=GATE_DEFAULT[i]
            p[i]=(TK_AUTO_BUILDINGS[k] and TK_AUTO_BUILDINGS[k].template_slot) and k or false
        end
        p._verified_defaults_v1=true
        p._candidate_preview_v2=true
    end
    -- Old candidate preview can refer to a foreign faction building which
    -- fails the player's permissions and appears blank in the picker.
    -- Replace it only if the template still carries that exact placeholder.
    if p[1]=="3k_district_artisan_sun_jian_fealty_5" then
        p[1]="3k_district_market_school_5"
    end
    -- User verified the true logistics target; migrate the wrong Guolin key,
    -- leaving all other individually edited gate slots untouched.
    if p[4]=="3k_dlc06_district_residential_logistics_5" then
        p[4]="3k_district_residential_logistics_5"
        K.log("GATE_PRESET_MIGRATE logistics: Guolin -> Large Granary")
    end
    p.port=p.port or {};p._initialized=true
    C.state.profiles.gate=p
end
ensure_gate_profile()
local function migrate_templates()
    for name,template in pairs(C.state.profiles) do
        -- Preserve a player's existing ninth/tenth picks while moving the
        -- palace to the lowest priority in the recommended set.
        if name=="recommended" and template[9]=="3k_district_government_administration_5" and
           template[10]~="3k_district_government_administration_5" then
            template[9],template[10]=template[10],template[9]
            K.log("HYBRID_TEMPLATE_MIGRATE moved palace to goal 10")
        end
        local clean={}
        -- The fixed-building branch lives in the string field "port" and
        -- survives the migration; only the six district slots are checked
        -- against the template catalogue.
        -- The fixed-building branches live in the string field "port" as a
        -- superchain -> end point map, and survive the migration; only the six
        -- district slots are checked against the template catalogue.
        local ports={}
        local source=type(template.port)=="table" and template.port or {}
        local store=TK_AUTO_TEMPLATE_STORE
        for _,key in pairs(source) do
            local info=store and type(store.port_info)=="function" and store.port_info(key) or nil
            if info then ports[info.superchain]=key
            else K.log("Removed unknown fixed-building branch from "..name.." template: "..tostring(key)) end
        end
        clean.port=ports
        if port and not clean.port then
            K.log("Removed unknown fixed-building branch from "..name.." template: "..tostring(port))
        end
        for i=1,10 do
            local key=template[i]
            local data=TK_AUTO_BUILDINGS[key]
            if data and data.template_slot then clean[i]=key
            else
                clean[i]=false
                if key then K.log("Removed fixed/missing building from "..name.." template position "..i..": "..tostring(key)) end
            end
        end
        if name=="gate" then clean._initialized=true; clean._verified_defaults_v1=template._verified_defaults_v1; clean._candidate_preview_v2=template._candidate_preview_v2 end
        C.state.profiles[name]=clean
    end
end
C.normalize_templates=migrate_templates

-- County add-on, initially DISABLED; never touches fixed resource plots.
-- Targets are actual district building LEVEL keys from TK_AUTO_BUILDINGS.
local ELEMENTS={"metal","wood","water","fire","earth"}
local function county_settings()
    if type(C.state.county_templates)~="table" then C.state.county_templates={} end
    return C.state.county_templates
end
-- Default resource-county templates. Only seed a category when it was never
-- configured. An intentionally cleared or edited category stays untouched.
local COUNTY_DEFAULTS={
    metal={"3k_district_artisan_workshop_state_5","3k_district_artisan_workshop_lacquer_5"},
    fire={"3k_district_artisan_workshop_state_5","3k_district_artisan_workshop_lacquer_5"},
    earth={"3k_district_artisan_workshop_state_5","3k_district_artisan_workshop_lacquer_5"},
    wood={"3k_district_residential_government_tools_5","3k_district_residential_landlords_5"},
    water={"3k_district_market_tea_5","3k_district_market_trade_5"},
}
local function ensure_county_defaults()
    local t=county_settings()
    for element,pair in pairs(COUNTY_DEFAULTS) do
        if type(t[element])~="table" then
            t[element]={}
            for i=1,2 do
                local key=pair[i]
                local data=TK_AUTO_BUILDINGS[key]
                t[element][i]=(data and data.template_slot) and key or false
            end
        end
    end
end
ensure_county_defaults()
local function get_element(key)
    if type(key)~="string" then return nil end
    -- Economic-preset routing, NOT necessarily the game's Wu Xing colour.
    -- Tea plantations and trade ports are commerce; lumber, farms and
    -- livestock are agricultural. All other resources default to industry.
    if not key:find("3k_resource_",1,true) and not key:find("_resource_",1,true) then return nil end
    local lower=key:lower()
    if lower:find("tea",1,true) or lower:find("trading_port",1,true) or
       lower:find("silk",1,true) or lower:find("spice",1,true) or
       lower:find("water_fish",1,true) or lower:find("wood_fish",1,true) then return "water" end
    if lower:find("farms",1,true) or lower:find("lumber",1,true) or
       lower:find("livestock",1,true) or lower:find("wood_bamboo",1,true) then return "wood" end
    return "metal"
end
-- Persistent setting API for eventual UI. This does NOT issue any game action.
function C.set_county_targets(element,first,second)
    local found=false
    for _,name in ipairs(ELEMENTS) do if name==element then found=true;break end end
    if not found then return false,"unknown_element" end
    if first==second and first~=nil then return false,"duplicate_targets" end
    for _,key in ipairs({first or false,second or false}) do
        if key then
            local data=TK_AUTO_BUILDINGS[key]
            if not data or not data.template_slot or data.fixed then return false,"invalid_district_target:"..tostring(key) end
        end
    end
    local t=county_settings()
    -- Use sequential indexes to remain compatible with next_city_action.
    t[element]={[1]=first or false,[2]=second or false}
    return true
end
function C.enable_counties(value)
    C.state.auto_counties=(value==true)
end
C.county_element=get_element
local function capture_goals(region,limit,overrides,county)
    if not region or not K.owns_region(region) then return nil,"not_owned" end
    local p=K.settlement(region)
    if K.bool(p..".IsProvinceCapital")==county then return nil,"wrong_region_type" end
    local records,seen={},{}
    local size=K.number(p..".RegionSlotList.Size")
    for i=0,size-1 do
        local slot=p..".RegionSlotList.At("..i..")"
        if K.bool(slot..".IsVisible") and not K.bool(slot..".IsPrimary") and not K.bool(slot..".IsEmpty") then
            local record=slot..".BuildingContext.BuildingLevelRecordContext"
            local key=K.read(record..".Key")
            local data=TK_AUTO_BUILDINGS[key]
            if data and data.template_slot and not data.fixed and not seen[data.superchain] then
                records[#records+1]=key
                seen[data.superchain]=true
            end
        end
    end
    if #records>limit then return nil,"too_many_districts" end
    local goals={}
    for i,key in ipairs(records) do
        local replacement=overrides and overrides[i] or key
        local original,goal=TK_AUTO_BUILDINGS[key],TK_AUTO_BUILDINGS[replacement]
        if not goal or not goal.template_slot or goal.fixed or original.superchain~=goal.superchain or
          (key~=replacement and not goal.ancestors[key]) then
            return nil,"invalid_target_at_"..i
        end
        -- Reject ambiguous unfinished branches. A captured building is usable as
        -- the final goal only if no further visible descendant in that superchain.
        local descendants=0
        for candidate,entry in pairs(TK_AUTO_BUILDINGS) do
            if entry.template_slot and entry.superchain==goal.superchain and entry.ancestors[replacement] then
                descendants=descendants+1
            end
        end
        if descendants>0 and (not overrides or not overrides[i]) then
            return nil,"target_not_final_at_"..i..":"..key
        end
        goals[i]=replacement
    end
    if #goals==0 then return nil,"no_ordinary_buildings" end
    return goals
end
function C.capture_capital_template(region,overrides)
    local goals,err=capture_goals(region,10,overrides,false)
    if not goals then return false,err end
    local previous=C.state.profiles.agriculture or {}
    goals.port=previous.port or {}
    C.state.profiles.agriculture=goals
    C.state.global_capitals=true
    return true,goals
end
function C.capture_county_template(region,overrides)
    local p=K.settlement(region)
    if not K.owns_region(region) or K.bool(p..".IsProvinceCapital") then return false,"not_a_county" end
    local element=nil
    for i=0,K.number(p..".RegionSlotList.Size")-1 do
        local slot=p..".RegionSlotList.At("..i..")"
        if not K.bool(slot..".IsEmpty") then
            local key=K.read(slot..".BuildingContext.BuildingLevelRecordContext.Key")
            local info=TK_AUTO_BUILDINGS[key]
            if info and info.fixed then element=get_element(info.superchain or info.chain or key) or element end
        end
    end
    if not element then return false,"resource_element_unknown" end
    local goals,err=capture_goals(region,2,overrides,true)
    if not goals then return false,err end
    local success,msg=C.set_county_targets(element,goals[1],goals[2])
    return success,success and element or msg
end



-- Experimental global assignment: applies the agriculture profile to every
-- owned capital unless it has an explicit per-city override. Disabled by
-- default so existing saves retain their original opt-in behaviour.
local function region_config(region)
    local config=C.state.cities[region]
    if config then return config end
    if C.state.global_capitals then
        return {profile=C.state.global_default_profile or "agriculture",paused=false}
    end
    return nil
end
C.region_config=region_config
-- One-click setup: use the recommended profile for every owned capital,
-- preserve the separate gate profile, and enable five-element county defaults.
-- Explicitly assigned city profiles are updated too, avoiding repeated cycling.
function C.apply_recommended_everywhere()
    ensure_recommended_profile()
    ensure_county_defaults()
    C.state.global_default_profile="recommended"
    C.state.global_capitals=true
    C.state.auto_counties=true
    C.state.auto_gate=true
    C.state.cities=C.state.cities or {}
    local changed=0
    for _,config in pairs(C.state.cities) do
        if type(config)=="table" then
            config.profile="recommended"
            config.paused=false
            changed=changed+1
        end
    end
    K.log("Recommended global default applied; existing city overrides updated="..changed)
    return changed
end
-- Read-only ID inspector for currently selected region. Lists actual built
-- building level keys (including DLC), not predictions from the static catalog.
function C.inspect_region_buildings(region)
    if not region or not K.owns_region(region) then return false,"not_an_owned_region" end
    local p=K.settlement(region)
    local n=K.number(p..".RegionSlotList.Size")
    local found={}
    K.log("INSPECT_BEGIN region="..tostring(region).." total_slots="..tostring(n))
    for i=0,n-1 do
        local slot=p..".RegionSlotList.At("..i..")"
        if not K.bool(slot..".IsEmpty") then
            local key=K.read(slot..".BuildingContext.BuildingLevelRecordContext.Key")
            if key and key~="" then
                local d=TK_AUTO_BUILDINGS[key]
                local item=tostring(i)..": "..tostring(key).." | "..tostring(d and d.name or "not in static catalog")
                found[#found+1]=item
                K.log("INSPECT "..tostring(region).." "..item)
            end
        end
    end
    if C.diagnose_county_slots then C.diagnose_county_slots(region,"inspector") end
    K.log("INSPECT_END region="..tostring(region).." built="..#found)
    return true,found
end

-- Bandit-only buildings are useless (and actively harmful) to every other
-- culture, so they are demolished rather than repaired. A bandit lord keeps
-- them, which is the only case where they should stay.
local bandit_subculture="3k_dlc05_subculture_bandits"
local function can_clear_bandits()
    if C.bandit_owner==nil then
        -- The generated faction table carries the subculture, so no CCO read is
        -- needed in the common case; the native read is only a fallback.
        local meta=TK_AUTO_FACTION_META and TK_AUTO_FACTION_META[cm:get_local_faction(true)] or nil
        local subculture=meta and meta.subculture or K.read("PlayersFaction.SubcultureRecordContext.Key")
        C.bandit_owner=(subculture==bandit_subculture)
        K.log("Bandit building sweep "..(C.bandit_owner and "disabled (player is a bandit faction)" or "enabled")..
            "; subculture="..tostring(subculture))
    end
    return not C.bandit_owner
end

local function has_targets(template)
    for i=1,10 do if TK_AUTO_BUILDINGS[(template or {})[i]] then return true end end
    return false
end

cm:add_saving_game_callback(function(context) cm:save_named_value(SAVE,C.state,context) end)
cm:add_loading_game_callback(function(context)
    local saved=cm:load_named_value(SAVE,C.state,context)
    if type(saved)=="table" and saved.version==1 then C.state=saved end
    ensure_recommended_profile()
    ensure_gate_profile()
    C.state.reservations=C.state.reservations or {}
    ensure_county_defaults()
    if C.state.auto_counties==nil then C.state.auto_counties=false end
    C.demolish_order=C.demolish_order or {}
    if C.state.auto_gate==nil then C.state.auto_gate=true end
    -- The single "sort" and "focus" fields were split into a building pair and a
    -- city key. Carry an existing save across instead of resetting the player's
    -- choices: "growth" was the smallest-city-first order, which is now city_sort,
    -- and focus was a template category, which is now build_focus.
    if C.state.city_sort==nil then
        C.state.city_sort=(C.state.sort=="income" or C.state.sort=="food") and "big" or "small"
    end
    if C.state.build_focus==nil then C.state.build_focus=C.state.focus or "all" end
    if C.state.build_sort==nil then
        C.state.build_sort=(C.state.sort=="food") and "food_high" or "income_high"
    end
    C.state.sort=nil
    C.state.focus=nil
    migrate_templates()
end)

local function food_balance(record)
    -- Signed base food effects; future farm output never becomes available cash/food credit.
    return K.number(record..".EffectList.Filter("..food_effects..").Sum(Value)")
end

-- *InCurrentSlot needs a native component's stored slot/province scope. Read
-- native CCO lists through scalar probes, without relying on hidden ContextList
-- widgets being cloned/refreshed. Read-only probes cannot issue orders.
local bridge
local slot_busy
local native_ticket=0
local function arm_commit(name,value)
    return K.command("Component("..K.quote(name)..").SetProperty(\"tk_auto_armed\", "..K.quote(value)..")")
end
local function text_value(component,id)
    local label=K.find(component,id)
    if not label then return nil end
    local ok,value=pcall(function() return label:GetStateText() end)
    return ok and value or nil
end

-- Silent context read for the fallback paths. The normal K.read records every
-- distinct failing expression, which would flood the log while probing a whole
-- list, so the fallback reads quietly and simply degrades to nil.
local function try(expr)
    if not effect or not effect.get_context_value then return nil end
    local ok,value=pcall(effect.get_context_value,expr)
    if ok then return value end
    return nil
end

local function bind_slot(slot)
    local root=core:get_ui_root()
    bridge=K.find(root,"tk_auto_construction_context") or
        K.component(root,"tk_auto_construction_context","ui/tk_auto/construction_context.twui.xml")
    local scope=bridge and (K.find(bridge,"tk_auto_slot_scope") or bridge)
    if not scope then K.warn("city_bridge_missing","Native construction context could not be created");return nil end
    local id=K.read("GetContextObjectId("..slot..")")
    if id==nil or tostring(id)=="" then
        K.warn("city_slot_id:"..slot,"Native region-slot cache id is unavailable: "..slot)
        return nil
    end
    -- Keep the probes alive without displaying a panel or intercepting clicks.
    bridge:MoveTo(-20000,-20000);bridge:SetOpacity(0)
    arm_commit("tk_auto_native_commit_build",0)
    arm_commit("tk_auto_native_commit_downgrade",0)
    if not K.command('Component("tk_auto_construction_context").SetProperty("tk_auto_index", "0")') then return nil end
    -- Store all three actual graph objects explicitly. A chain/level probe can
    -- then evaluate CanBuildInCurrentSlot in this scope.
    -- No automatic propagator replaces the slot with a settlement/province.
    local component="Component("..K.quote(scope:Id())..")"
    if not K.command(component..'.ClearContext("CcoCampaignRegionSlot", true)') or
        not K.command(component..".PropagateContext("..slot..".SettlementContext.ProvinceContext)") or
        not K.command(component..".PropagateContext("..slot..".SettlementContext)") or
        not K.command(component..".PropagateContext("..slot..")") then
        K.warn("city_bridge_bind","Could not propagate the region slot to native construction children")
        return nil
    end
    local pinned=text_value(scope,"native_slot_id")
    if tostring(pinned or "")~=tostring(id) then
        local stored=K.read("GetContextObjectId("..component..'.StoredContext("CcoCampaignRegionSlot"))')
        K.warn("city_bridge_context:"..slot,"Native construction slot propagation failed: expected="..tostring(id)..
            " stored="..tostring(stored).." child="..tostring(pinned))
        return nil
    end
    for _,entry in ipairs({{"CcoCampaignSettlement","native_settlement_id",slot..".SettlementContext"},
                           {"CcoCampaignProvince","native_province_id",slot..".SettlementContext.ProvinceContext"}}) do
        local expected=K.read("GetContextObjectId("..entry[3]..")")
        if not expected or tostring(text_value(scope,entry[2]) or "")~=tostring(expected) then
            K.warn("city_scope:"..entry[1]..":"..slot,"Native construction scope is missing "..entry[1].." for "..slot)
            return nil
        end
    end
    return scope
end

local function building_record(key)
    -- Empty plots have no BuildingContext. Use any owned settlement's primary
    -- building to reach the native level RecordList, rather than manufacturing a
    -- building-level object with an unverified script factory.
    local records="PlayersFaction.SettlementList.At(0).PrimaryRegionSlotContext.BuildingContext.BuildingLevelRecordContext.RecordList"
    local record=records..".FirstContext(Key == "..K.quote(key)..")"
    if K.read(record..".Key")==key then return record end
    return nil
end

-- Returns the readable entries plus the native list count. The count alone
-- proves the slot context reached the widget, so one unreadable entry degrades
-- to "no candidate" instead of discarding the whole slot.
local function native_list(scope,name)
    local count=tonumber(text_value(scope,name.."_count"))
    if count==nil or count<0 or count>128 then return nil,nil end
    local item=K.find(scope,name.."_item")
    if not item then return nil,count end
    local result={}
    for i=0,count-1 do
        if not K.command('Component("tk_auto_construction_context").SetProperty("tk_auto_index", '..K.quote(i)..')') or
            not K.command("Component("..K.quote(item:Id())..").ForceUpdateContextDisplay") then return result,count end
        local value=text_value(scope,name.."_item")
        if value and value~="" then result[#result+1]=value end
    end
    return result,count
end

local function probe_record(scope,key,mode,old_consumption,slot)
    local record=building_record(key)
    local probe=scope and K.find(scope,"tk_auto_native_record_probe")
    -- Native prices, food and eligibility govern the player's budget/reserves.
    -- A missing or stale probe cannot authorize a zero-cost/zero-food order.
    local option={key=key,slot_expression=slot,record=record,record_id=nil,
        cost=0,food=0,allowed=false,unverified=true}
    if not probe or not record then
        K.warn("city_native_probe_unavailable:"..slot..":"..key,
            "Native record probe unavailable for "..key.."; construction waits for a readable scope")
        return option
    end
    local component="Component("..K.quote(probe:Id())..")"
    if not K.command(component..'.ClearContext("CcoBuildingLevelRecord", true)') or
        not K.command(component..".PropagateContext("..record..")") then
        K.warn("city_native_probe_context:"..slot..":"..key,
            "Native record probe could not adopt "..key.."; construction waits for a readable scope")
        return option
    end
    local id=text_value(probe,"native_record_id")
    if not id or id=="" or text_value(probe,"native_key")~=key or
        tostring(id or "")~=tostring(K.read("GetContextObjectId("..record..")") or "") then
        K.warn("city_native_probe:"..slot,"Native construction record probe is stale for "..key)
        return option
    end
    option.record_id=id
    -- Match the stock building-upgrade label and CreateInCurrentSlot receiver.
    -- Passing the inherited settlement explicitly can apply its modifiers a
    -- second time: the native test charged 2650 while that probe returned 662.
    -- Require the no-argument price; an explicit-context fallback can spend
    -- through the player's reserve even when both labels are readable.
    local cost=tonumber(text_value(probe,"native_cost_bare"))
    local contextual_cost=tonumber(text_value(probe,"native_cost"))
    if cost and contextual_cost and cost~=contextual_cost then
        K.warn("city_price_context:"..key,"Native price differs for "..key..
            ": stock="..cost.." explicit_settlement="..contextual_cost.."; using stock price")
    end
    local food=tonumber(text_value(probe,"native_food")) or tonumber(text_value(probe,"native_food_native"))
    -- Sum over an empty native effect list displays an empty string, not 0.
    -- Only a readable count of zero proves that this record has no signed food
    -- effects; a missing count or an unreadable nonempty sum still blocks orders.
    if food==nil and tonumber(text_value(probe,"native_food_effect_count"))==0 then food=0 end
    local allowed=text_value(probe,"native_allowed_"..mode)
    -- The native order receiver treats a step as possible when either
    -- CanBuildInCurrentSlot or CanConvertToInCurrentSlot holds (that union is
    -- literally the guard inside construction_context.twui.xml). Reading only
    -- the build flag made every branch change - port upgrades above all - look
    -- forbidden, so the corresponding orders were never issued.
    if mode=="build" or mode=="convert" then
        local other=text_value(probe,"native_allowed_"..(mode=="build" and "convert" or "build"))
        if allowed~="1" and other=="1" then allowed="1" end
    end
    -- Read price/food/eligibility from the existing native widget expressions.
    -- Never compile extra slot x record fallback expressions in this loop: that
    -- was a separate regression discovered after v16 and can exhaust the CCO VM.
    option.cost_verified=cost~=nil
    option.food_verified=food~=nil
    if cost then
        option.cost=math.max(0,cost)
    else
        K.warn("city_native_cost:"..slot..":"..key,
            "Native construction price unreadable for "..key.."; construction waits for a readable price")
    end
    if food then option.food=math.max(0,old_consumption-food) end
    if allowed=="0" or allowed=="1" then
        option.allowed=(allowed=="1")
        option.unverified=false
    else
        K.warn("city_native_eligibility:"..slot..":"..key,
            "Native eligibility unreadable for "..key.."; construction waits for native permission")
    end
    -- Unknown prices/food must not be treated as zero: that bypasses reserves
    -- and the player's food constraint when considering city growth.
    if cost==nil or food==nil then option.allowed=false;option.unverified=true end
    return option
end

local function submit_native(slot,mode,key)
    if slot_busy(slot) then return false end
    -- The actual game log rejects creating CcoCampaignRegionSlot from a string
    -- id. Use the propagated native UI scope instead of that unsupported API.
    -- The receiver validates slot identity, native permission and a unique ticket.
    local scope=bind_slot(slot)
    if not scope then return false end
    local slot_id=text_value(scope,"native_slot_id")
    local option=probe_record(scope,key,mode,0,slot)
    if not option or not option.allowed or not option.record then return false end
    -- No state overrides; native eligibility is re-read after every preceding
    -- order and also checked inside the native command receiver.
    local name=mode=="downgrade" and "tk_auto_native_commit_downgrade" or "tk_auto_native_commit_build"
    local commit=K.find(scope,name)
    if not commit or not option.record_id or option.record_id=="" then return false end
    -- Two plots can construct the same level record. Clear the receiver's old
    -- record while disarmed so the second SetContext is a new context event.
    if not K.command("Component("..K.quote(name)..').ClearContext("CcoBuildingLevelRecord", false)') then return false end
    native_ticket=native_ticket+1
    if not K.command("Component("..K.quote(name)..").SetProperty(\"tk_auto_expected_slot\", "..K.quote(slot_id)..")") or
        not K.command("Component("..K.quote(name)..").SetProperty(\"tk_auto_dispatched\", \"0\")") or
        not K.command("Component("..K.quote(name)..").SetProperty(\"tk_auto_ticket\", "..K.quote(native_ticket)..")") or
        not arm_commit(name,1) then return false end
    local ok=K.command("Component("..K.quote(commit:Id())..").SetContext("..option.record..")")
    local dispatched=K.number("Component("..K.quote(name)..").GetProperty(\"tk_auto_dispatched\")",-1)==native_ticket
    arm_commit(name,0)
    if ok and not dispatched then K.warn("city_native_dispatch:"..key,"Native construction callback did not consume order for "..key) end
    return ok and dispatched
end

local function slot_candidates(scope,keys,mode,old_consumption,slot)
    local result={}
    if not keys then return nil end
    for _,key in ipairs(keys) do
        if TK_AUTO_BUILDINGS[key] then
            local candidate=probe_record(scope,key,mode,old_consumption,slot)
            candidate.submit=function() return submit_native(slot,mode,key) end
            result[#result+1]=candidate
        end
    end
    return result
end

local function root_keys(goals)
    -- Empty plots have no existing building to upgrade. Find the first visible
    -- prerequisite of each configured route in the effective local DB graph,
    -- then let CanBuildInCurrentSlot authorize each actual native record.
    -- This does not depend on a hovered/selected building group or chain UI.
    local result,seen={},{}
    for _,goal in ipairs(goals or {}) do
        local data=TK_AUTO_BUILDINGS[goal]
        if data then
            local route={goal}
            for key in pairs(data.ancestors) do
                local ancestor=TK_AUTO_BUILDINGS[key]
                if ancestor and ancestor.template_slot and ancestor.visible then route[#route+1]=key end
            end
            local level=data.level
            for _,key in ipairs(route) do level=math.min(level,TK_AUTO_BUILDINGS[key].level) end
            table.sort(route)
            for _,key in ipairs(route) do
                if TK_AUTO_BUILDINGS[key].level==level and not seen[key] then
                    result[#result+1]=key;seen[key]=true
                end
            end
        end
    end
    return result
end

-- Read-only fallback when native list labels are unavailable. Orders still
-- require a successfully rebound native UI scope with readable prices/food.
local function read_list_direct(slot,list)
    local size=tonumber(try(slot.."."..list..".Size"))
    if size==nil or size<0 or size>128 then return nil end
    local keys={}
    for i=0,size-1 do
        local key=try(slot.."."..list..".At("..i..").Key")
        if key and tostring(key)~="" then keys[#keys+1]=tostring(key) end
    end
    return keys
end

local function fill_from_lua(item,slot,goals,old)
    local up=read_list_direct(slot,"PossibleUpgradeWithoutConversionsList")
    local conv=read_list_direct(slot,"PossibleUpgradeOnlyConversionsList")
    local down=read_list_direct(slot,"PossibleDowngradeList")
    item.native_counts=item.native_counts or {}
    item.native_counts.upgrades=up and #up or -1
    item.native_counts.conversions=conv and #conv or -1
    item.native_counts.downgrades=down and #down or -1
    item.native_counts.chains=item.native_counts.chains or -1
    if up then item.upgrades=slot_candidates(nil,up,"build",old,slot) or {} end
    if conv then item.conversions=slot_candidates(nil,conv,"convert",old,slot) or {} end
    if down then item.downgrades=slot_candidates(nil,down,"downgrade",old,slot) or {} end
    if not item.key then item.roots=slot_candidates(nil,root_keys(goals),"build",old,slot) or {} end
    return up or conv or down
end

slot_busy=function(slot)
    return K.bool("IsContextValid("..slot..".ConstructionItemContext)") or
        K.bool(slot..".IsRepairing") or K.bool(slot..".IsDismantling") or K.bool(slot..".IsDemolishing") or
        K.bool(slot..".IsUpgrading") or K.bool(slot..".IsBuildingNew")
end

local function read_slot(settlement,index,goals)
    local p=settlement..".RegionSlotList.At("..index..")"
    local empty=K.bool(p..".IsEmpty")
    local key=not empty and K.read(p..".BuildingContext.BuildingLevelRecordContext.Key") or nil
    local item={index=index,expression=p,key=key,
        busy=slot_busy(p),
        demolishing=K.bool(p..".IsDemolishing"),
        damaged=not empty and K.bool(p..".BuildingContext.IsDamaged"),
        foreign=not empty and not K.bool(p..".BuildingContext.BuildingLevelRecordContext.CanPlayerBuildThis"),
        can_demolish=K.bool(p..".CanDemolish"),can_convert=K.number(p..".PossibleUpgradeOnlyConversionsList.Size")>0,
        can_repair=K.bool(p..".CanRepair"),repair_cost=K.number(p..".RepairCost")}
    local old=not empty and food_balance(p..".BuildingContext.BuildingLevelRecordContext") or 0
    item.old_consumption=old
    if item.busy then
        item.can_cancel=false
        if K.bool("IsContextValid("..p..".ConstructionItemContext)") then
            local pending=K.read(p..".ConstructionItemContext.BuildingCultureVariantRecordContext.BuildingLevelRecordContext.Key")
            if pending and TK_AUTO_BUILDINGS[pending] then
                item.pending_key=pending
                item.key=pending;item.foreign=false
                item.can_cancel=not item.demolishing
            end
        end
        return item
    end
    local scope=bind_slot(p)
    if not scope then
        -- The hidden bridge could not be bound for this slot. Read the native
        -- lists straight from the model for diagnosis and free cleanup actions.
        -- Construction still requires a successfully rebound native UI scope.
        item.bridge_missing=true
        if fill_from_lua(item,p,goals,old) then
            K.warn("city_bridge_fallback:"..p,
                "Hidden construction bridge unavailable for "..p.."; native lists were read directly")
        else
            item.bridge_missing=true;item.busy=true
            K.warn("city_bridge_missing:"..p,"Native construction lists unreadable for "..p)
        end
        return item
    end
    local upgrades,up_count=native_list(scope,"native_upgrades")
    local conversions,conv_count=native_list(scope,"native_conversions")
    local downgrades,down_count=native_list(scope,"native_downgrades")
    item.native_counts={upgrades=up_count or -1,conversions=conv_count or -1,
        downgrades=down_count or -1,chains=tonumber(text_value(scope,"native_chains_count")) or -1}
    item.upgrades=slot_candidates(scope,upgrades,"build",old,p) or {}
    item.conversions=slot_candidates(scope,conversions,"convert",old,p) or {}
    item.downgrades=slot_candidates(scope,downgrades,"downgrade",old,p) or {}
    item.roots={}
    if empty then
        item.roots=slot_candidates(scope,root_keys(goals),"build",old,p) or {}
        local groups=native_list(scope,"native_groups")
        local seen_fixed,seen_district=false,false
        for _,resource in ipairs(groups or {}) do
            if resource=="1" then seen_fixed=true elseif resource=="0" then seen_district=true end
        end
        if seen_fixed or seen_district then item.fixed_only=seen_fixed and not seen_district end
        -- Dedicated port slots can be commerce groups too. The slot's native
        -- chain list identifies a fixed-only plot without adding ports to a
        -- city template or probing unrelated building routes.
        local chains=native_list(scope,"native_chains")
        local fixed_chain,district_chain=false,false
        for _,chain in ipairs(chains or {}) do
            if fixed_chains[chain] then fixed_chain=true else district_chain=true end
        end
        if fixed_chain and not district_chain then item.fixed_only=true end
    end
    if up_count==nil or conv_count==nil or down_count==nil then
        -- Only an unreadable list *count* proves the slot context never reached
        -- the probe. A single unreadable entry no longer discards the slot,
        -- because the direct native command can still be dispatched.
        item.bridge_missing=true;item.busy=true
        K.warn("city_native_lists:"..p,"Native construction probe failed: slot="..p..
            " upgrades="..item.native_counts.upgrades.." conversions="..item.native_counts.conversions..
            " downgrades="..item.native_counts.downgrades.." chains="..item.native_counts.chains)
    end
    return item
end

local function city_snapshot(region)
    local p=K.settlement(region)
    local config=region_config(region)
    if not config or not K.owns_region(region) or not K.bool(p..".IsProvinceCapital") then return nil end
    local city={region=region,expression=p,owned=true,paused=config.paused,profile=config.profile,
        siege=K.bool(p..".IsUnderSiege"),slots={},capacity=0}
    local goals={}
    local source=C.state.profiles[config.profile] or {}
    local size=K.number(p..".RegionSlotList.Size")
    local has_protected_resource=false
    -- In a Ten Slot hybrid capital, a former resource plot may survive.
    -- Such plots are protected and must not consume a standard district goal.
    for i=0,size-1 do
        local slot=p..".RegionSlotList.At("..i..")"
        if K.bool(slot..".IsVisible") and not K.bool(slot..".IsEmpty") then
            local record=slot..".BuildingContext.BuildingLevelRecordContext"
            local key=K.read(record..".Key")
            local chain=K.read(record..".BuildingChainRecordContext.Key")
            local d=key and TK_AUTO_BUILDINGS[key]
            if (d and d.fixed) or (chain and fixed_chains[chain]) or
               K.bool(record..".IsResourceBuilding") or
               (type(key)=="string" and key:find("3k_resource_",1,true)==1) then
                has_protected_resource=true
                K.log("HYBRID_FIXED region="..region.." slot="..i.." key="..tostring(key))
            end
        end
    end
    local palace="3k_district_government_administration_5"
    for i=1,10 do
        local goal=source[i]
        if TK_AUTO_BUILDINGS[goal] and not (has_protected_resource and config.profile=="recommended" and goal==palace) then
            goals[#goals+1]=goal
        end
    end
    if has_protected_resource and config.profile=="recommended" then
        K.log("HYBRID_GOALS region="..region.." resource_protected=true palace_excluded=true goals="..#goals)
    end
    city.effective_goals=goals
    for i=0,size-1 do
        local slot=p..".RegionSlotList.At("..i..")"
        if K.bool(slot..".IsPrimary") then
            city.primary=read_slot(p,i)
        elseif K.bool(slot..".IsVisible") then
            local existing=K.read(slot..".BuildingContext.BuildingLevelRecordContext.Key")
            local data=existing and TK_AUTO_BUILDINGS[existing]
            -- Capacity must survive demolition. The global UI-group query used
            -- previously had no stored province and made every empty plot vanish.
            -- Include unknown foreign districts too; fixed ports/resources stay
            -- outside templates and cannot be demolished by the district planner.
            local empty=K.bool(slot..".IsEmpty")
            local record=slot..".BuildingContext.BuildingLevelRecordContext"
            local chain=not empty and K.read(record..".BuildingChainRecordContext.Key") or nil
            local fixed=not empty and ((data and data.fixed) or
                (chain and fixed_chains[chain]) or K.bool(record..".IsResourceBuilding") or
                (type(existing)=="string" and existing:find("3k_resource_",1,true)==1))
            if not fixed and (empty or not data or data.template_slot) then
                local item=read_slot(p,i,goals)
                if not item.fixed_only then city.slots[#city.slots+1]=item end
            end
        end
    end
    -- Unlock points are not slot counts (the vanilla city uses two points per
    -- district). Visible district slots are the game's actual current capacity.
    city.capacity=#city.slots
    -- Resource and bandit addon slots are not included in a commandery capital template.
    local active={}
    for _,slot in ipairs(city.slots) do
        if #active<city.capacity then active[#active+1]=slot end
    end
    city.slots=active
    return city
end
C.snapshot=city_snapshot

-- The fixed-building branch chosen for a city type lives with the templates.
-- Resolved defensively so a partially loaded store can never abort a run.
local function template_ports(profile)
    local store=TK_AUTO_TEMPLATE_STORE
    if not profile or type(store)~="table" or type(store.port_of)~="function" then return nil end
    local ports=store.port_of(C.state.profiles[profile])
    if next(ports)==nil then return nil end
    return ports
end

local function fixed_snapshot(region)
    local p=K.settlement(region)
    if not K.owns_region(region) then return nil end
    local capital=K.read(p..".ProvinceContext.CapitalSettlementContext.RegionRecordKey")
    -- A county remains independent when its capital belongs to another faction.
    local config=capital and K.owns_region(capital) and region_config(capital) or nil
    local city={region=region,capital=config and capital or nil,expression=p,owned=true,paused=config and config.paused or false,
        siege=K.bool(p..".IsUnderSiege"),slots={}}
    -- Ports and bandit buildings are fixed, so they are managed by this pass.
    -- Each port family follows the branch picked for the city type; with no type
    -- assigned nothing is chosen for any of them.
    local profile=config and config.profile or nil
    city.fixed_targets=template_ports(profile)
    city.can_clear_bandits=can_clear_bandits()
    for i=0,K.number(p..".RegionSlotList.Size")-1 do
        local slot=p..".RegionSlotList.At("..i..")"
        local key=K.read(slot..".BuildingContext.BuildingLevelRecordContext.Key")
        local data=key and TK_AUTO_BUILDINGS[key]
        local fixed=data and data.fixed
        if key and not data then
            local record=slot..".BuildingContext.BuildingLevelRecordContext"
            fixed=fixed_chains[K.read(record..".BuildingChainRecordContext.Key")] or K.bool(record..".IsResourceBuilding")
        end
        if fixed then city.slots[#city.slots+1]=read_slot(p,i) end
    end
    return city
end

-- The county planner owns ONLY ordinary, non-primary slots. The original
-- fixed_snapshot still upgrades its resource building separately.
local function diagnose_county_slots(region, source)
    local p=K.settlement(region)
    local n=K.number(p..".RegionSlotList.Size")
    K.log("COUNTY_DIAG_BEGIN region="..tostring(region).." source="..tostring(source)..
        " is_capital="..tostring(K.bool(p..".IsProvinceCapital")).." slots="..tostring(n))
    for i=0,math.min(n-1,19) do
        local slot=p..".RegionSlotList.At("..i..")"
        local visible=K.bool(slot..".IsVisible")
        local primary=K.bool(slot..".IsPrimary")
        local empty=K.bool(slot..".IsEmpty")
        local rec=slot..".BuildingContext.BuildingLevelRecordContext"
        local key=not empty and K.read(rec..".Key") or nil
        local d=key and TK_AUTO_BUILDINGS[key] or nil
        local chain=not empty and K.read(rec..".BuildingChainRecordContext.Key") or nil
        local fixed=not empty and ((d and d.fixed) or fixed_chains[chain] or K.bool(rec..".IsResourceBuilding")) or false
        local part={"slot="..i,"visible="..tostring(visible),"primary="..tostring(primary),
            "empty="..tostring(empty),"fixed="..tostring(fixed),
            "key="..tostring(key),"chain="..tostring(chain)}
        if visible and not primary and not fixed then
            local ok,info=pcall(read_slot,p,i,{})
            if ok and type(info)=="table" then
                part[#part+1]="bridge_missing="..tostring(info.bridge_missing)
                part[#part+1]="fixed_only="..tostring(info.fixed_only)
                part[#part+1]="roots="..tostring(#(info.roots or {}))
                part[#part+1]="upgrades="..tostring(#(info.upgrades or {}))
                if info.native_counts then part[#part+1]="native_chains="..tostring(info.native_counts.chains) end
            else part[#part+1]="probe_error="..tostring(info) end
        end
        K.log("COUNTY_DIAG "..tostring(region).." "..table.concat(part," "))
    end
    K.log("COUNTY_DIAG_END region="..tostring(region))
end

C.diagnose_county_slots=diagnose_county_slots
local function county_snapshot(region)
    local p=K.settlement(region)
    if not K.owns_region(region) or K.bool(p..".IsProvinceCapital") then return nil end
    local city={region=region,expression=p,owned=true,paused=false,
        siege=K.bool(p..".IsUnderSiege"),slots={},capacity=0}
    local resource_element=nil
    local size=K.number(p..".RegionSlotList.Size")
    -- Stage 1: classify fixed buildings AND identify the resource element.
    -- A missing/ambiguous fixed resource means NO automatic district actions.
    local fixed_index={}
    for i=0,size-1 do
        local slot=p..".RegionSlotList.At("..i..")"
        if K.bool(slot..".IsVisible") and not K.bool(slot..".IsEmpty") then
            -- Resource buildings are often PRIMARY (slot 0). Scan those for
            -- the five-element identity; exclude them from district planning.
            local record=slot..".BuildingContext.BuildingLevelRecordContext"
            local key=K.read(record..".Key")
            local data=key and TK_AUTO_BUILDINGS[key]
            local chain=K.read(record..".BuildingChainRecordContext.Key")
            local fixed=(data and data.fixed) or fixed_chains[chain] or K.bool(record..".IsResourceBuilding")
            if fixed then
                fixed_index[i]=true
                local element=get_element(key) or get_element(chain) or
                    get_element(data and data.superchain)
                if element then
                    if resource_element and resource_element~=element then
                        K.warn("county_mixed:"..region,"Multiple resource elements; skip county "..region)
                        return nil
                    end
                    resource_element=element
                    K.log("COUNTY_ELEMENT region="..region.." slot="..i.." key="..tostring(key).." element="..element)
                end
            end
        end
    end
    if not resource_element then K.log("COUNTY_SKIP region="..region.." reason=no_resource_element fixed_scan="..tostring(size));return nil end
    local targets=county_settings()[resource_element]
    if not targets or not (TK_AUTO_BUILDINGS[targets[1]] or TK_AUTO_BUILDINGS[targets[2]]) then return nil end
    local goals={}
    for i=1,2 do if TK_AUTO_BUILDINGS[targets[i]] then goals[#goals+1]=targets[i] end end
    -- Stage 2: only put verifiable district plots into the normal planner.
    for i=0,size-1 do
        local slot=p..".RegionSlotList.At("..i..")"
        if not fixed_index[i] and K.bool(slot..".IsVisible") and not K.bool(slot..".IsPrimary") then
            local empty=K.bool(slot..".IsEmpty")
            local key=not empty and K.read(slot..".BuildingContext.BuildingLevelRecordContext.Key") or nil
            local data=key and TK_AUTO_BUILDINGS[key]
            local record=slot..".BuildingContext.BuildingLevelRecordContext"
            local chain=not empty and K.read(record..".BuildingChainRecordContext.Key") or nil
            local is_fixed=(data and data.fixed) or (chain and fixed_chains[chain]) or
                (not empty and K.bool(record..".IsResourceBuilding"))
            if not is_fixed and (empty or (data and data.template_slot)) then
                local item=read_slot(p,i,goals)
                -- Empty county plots are accepted only when the native group
                -- probe positively confirms a district plot, NOT nil/unknown.
                if (not empty or item.fixed_only==false) and not item.bridge_missing then
                    city.slots[#city.slots+1]=item
                end
            end
        end
    end
    if #city.slots==0 then K.log("COUNTY_SKIP region="..region.." reason=no_verified_ordinary_slots element="..tostring(resource_element));return nil end
    -- No hardcoded two-slot indexing: an ordinary six-slot game simply finds
    -- no county district plots and does nothing.
    -- Prefer plots holding an existing target-line building; otherwise take
    -- empties. Do not expose unselected plots to template cleanup/demolition.
    if #city.slots>2 then
        local selected,seen={},{}
        for _,item in ipairs(city.slots) do
            if item.key then
                local data=TK_AUTO_BUILDINGS[item.key]
                for _,goalkey in ipairs(goals) do
                    local goal=TK_AUTO_BUILDINGS[goalkey]
                    if data and goal and data.superchain==goal.superchain and
                        not seen[goal.superchain] and #selected<2 then
                        selected[#selected+1]=item
                        seen[goal.superchain]=true
                        break
                    end
                end
            end
        end
        for _,item in ipairs(city.slots) do
            if #selected>=2 then break end
            local included=false
            for _,chosen in ipairs(selected) do if chosen.index==item.index then included=true end end
            if not included and not item.key then selected[#selected+1]=item end
        end
        for _,item in ipairs(city.slots) do
            if #selected>=2 then break end
            local included=false
            for _,chosen in ipairs(selected) do if chosen.index==item.index then included=true end end
            if not included then selected[#selected+1]=item end
        end
        city.slots=selected
    end
    city.capacity=#city.slots
    city.element=resource_element
    K.log("COUNTY_READY region="..region.." element="..resource_element.." ordinary_slots="..#city.slots)
    return city
end
C.county_snapshot=county_snapshot

local function is_gate_pass(region)
    if not TK_AUTO_GATES then return false end
    local ok,value=pcall(TK_AUTO_GATES.is_gate,region)
    if not ok then K.warn("gate_detect:"..tostring(region),"Gate detection failed: "..tostring(value)) end
    return ok and value==true
end
C.is_gate_pass=is_gate_pass

local function gate_snapshot(region)
    if not TK_AUTO_GATES then return nil end
    local ok,city=pcall(TK_AUTO_GATES.snapshot,region,read_slot,C.state.profiles.gate or {})
    if ok then return city end
    K.warn("gate_snapshot:"..tostring(region),"Gate snapshot failed: "..tostring(city))
end

local function reserve_one_settlement(i)
    local p="PlayersFaction.SettlementList.At("..i..")"
    local region=K.read(p..".RegionRecordKey")
    local result=0
    local slots=K.number(p..".RegionSlotList.Size")
    for j=0,slots-1 do
        local slot=p..".RegionSlotList.At("..j..")"
        local mark=tostring(region)..":"..j
        if K.bool("IsContextValid("..slot..".ConstructionItemContext)") then
            local old=K.bool(slot..".IsEmpty") and 0 or food_balance(slot..".BuildingContext.BuildingLevelRecordContext")
            local new=food_balance(slot..".ConstructionItemContext.BuildingCultureVariantRecordContext.BuildingLevelRecordContext")
            result=result+math.max(C.state.reservations[mark] or 0,old-new,0)
        else C.state.reservations[mark]=nil end
    end
    return result
end

local function treasury() return K.number("PlayersFaction.TreasuryAmount") end
local function food_total() return K.number('PlayersFaction.PooledResourceContext("'..FOOD..'").Total') end

local step
local function finish(suppress_rerun)
    local run=C.run
    C.busy=false
    if run then
        K.log("Cities ("..tostring(run.reason).."): settlements="..#run.cities..
            " submitted="..run.actions.." confirmed="..(run.confirmed or 0)..
            " treasury="..run.start_cash.." food="..run.start_food.." spent="..run.spent)
        if run.actions>0 then
            if run.synchronous then
                C.ui_message=K.L("orders_sent")..run.actions..K.L("orders_sent2")
            else
                C.ui_message=K.L("orders_batch")..run.actions..K.L("orders_batch2")..(run.confirmed or 0)..K.L("orders_batch3")
            end
        elseif (run.scope_failures or 0)>0 then
            C.ui_message=K.L("no_read")
        else
            C.ui_message=K.L("nothing_to_do")
        end
        -- State both the spendable amount and the faction total, plus what is
        -- reserved. Showing only the spendable figure made a healthy run look
        -- broken: the panel said "food 1" while the top bar said 9, and the
        -- difference was entirely food already committed to buildings under
        -- construction.
        local faction_money=math.floor(treasury()+0.5)
        local faction_food=math.floor(food_total()+0.5)
        local free_money=math.floor(math.max(0,run.start_cash-run.spent-C.state.reserve_money)+0.5)
        local free_food=math.floor(run.start_food-run.reserved_food-C.state.reserve_food+0.5)
        C.ui_message=C.ui_message..
            K.L("budget_money")..free_money..K.L("budget_of")..faction_money..
            K.L("budget_food")..free_food..K.L("budget_of")..faction_food..
            K.L("budget_reserved")..math.floor(run.reserved_food+0.5)..
            K.L("budget_yours")..C.state.reserve_food
        C.run_summary={cities=#run.cities,actions=run.actions,confirmed=run.confirmed or 0,
            reasons=run.reasons}
        -- Codes in the log (they are what a bug report needs), translated text on
        -- the panel. Only after a manual run: showing it after every automatic pass
        -- put a line on the panel the player never asked for.
        local idle,region_names={},{}
        for region,why in pairs(run.reasons or {}) do
            if not (run.acted or {})[region] then
                idle[#idle+1]={region=tostring(region),why=tostring(why)}
            end
        end
        table.sort(idle,function(a,b) return a.region<b.region end)
        if #idle>0 then
            local codes={}
            for _,entry in ipairs(idle) do codes[#codes+1]=entry.region.."="..entry.why end
            K.log("City pass idle reasons: "..table.concat(codes,", "))
        end
        if run.reason=="manual" and #idle>0 then
            local top={}
            for i=1,math.min(#idle,3) do
                local entry=idle[i]
                -- One read per shown settlement, only on a manual pass.
                if region_names[entry.region]==nil then
                    local name=K.read(K.settlement(entry.region)..".ProvinceContext.Name")
                    region_names[entry.region]=(name and tostring(name)~="") and tostring(name) or entry.region
                end
                top[#top+1]=region_names[entry.region].."："..K.reason(entry.why)
            end
            C.ui_reasons=K.L("reason_prefix")..table.concat(top,"；")
        else
            C.ui_reasons=nil
        end
    end
    C.run=nil
    if C.ui_refresh then pcall(C.ui_refresh) end
    local again=C.rerun
    C.rerun=false
    if not suppress_rerun and (C.force_pending or 0)>0 then
        C.force_pending=C.force_pending-1
        K.defer(function() C.run_now(false,"global_recommended") end,0.1,"tk_auto_force_again")
    elseif again and not suppress_rerun then C.request_run(C.pending_reason or "queued_event") end
end

local function schedule(run,fn,delay,name)
    K.defer(function()
        if C.run~=run then return end
        local ok,err=pcall(fn)
        if not ok then K.log("City pass stopped: "..tostring(err));finish(true) end
    end,delay,name)
end

local function available(synchronous)
    if not synchronous then return K.ready() end
    -- AboutToEndTurn runs before the UI command window closes. The ordinary
    -- FactionTurnEnd listener remains a fallback; native permissions still apply.
    return not cm:is_multiplayer() and not cm:is_processing_battle()
end

-- Never interpret a broken native context bridge as an empty settlement.
-- Some UI callbacks can return a valid local turn but an invalid CCO context.
local function bridge_healthy()
    if not effect or type(effect.get_context_value)~="function" then return false end
    local ok,treasury=pcall(function() return effect.get_context_value("PlayersFaction.TreasuryAmount") end)
    if not ok or tonumber(treasury)==nil then return false end
    local good,count=pcall(function() return effect.get_context_value("PlayersFaction.SettlementList.Size") end)
    return good and tonumber(count)~=nil and tonumber(count)>0
end

local function process_next(run)
    if C.run~=run or not C.state.enabled or run.actions>=48 or not available(run.synchronous) then return nil end
    if not bridge_healthy() then
        run.bridge_failed=true
        K.log("BRIDGE_GUARD abort: native campaign context unavailable; no more construction commands will be issued")
        return nil
    end
    local descriptor=run.cities[run.index]
    if not descriptor then return nil end
    local region=descriptor.region
    local config=region_config(region)
    local fixed=descriptor.kind=="fixed"
    local county=descriptor.kind=="county"
    local gate=descriptor.kind=="gate"
    if gate and not C.state.auto_gate then run.index=run.index+1;return false end
    local snapshot_key=region..":"..descriptor.kind
    local city=run.snapshots[snapshot_key]
    if not city then
        if gate then city=gate_snapshot(region)
        elseif fixed then city=fixed_snapshot(region)
        elseif county then
            if (C.diagnostic_count or 0)<12 then
                C.diagnostic_count=(C.diagnostic_count or 0)+1
                diagnose_county_slots(region,"run")
            end
            city=county_snapshot(region)
        else city=city_snapshot(region) end
        run.snapshots[snapshot_key]=city
    end
    local live_config
    if gate or county then live_config=nil
    elseif fixed then
        live_config=city and city.capital and K.owns_region(city.capital) and region_config(city.capital) or nil
    else live_config=config end
    if not city or (live_config and live_config.paused) or (not gate and not fixed and not county and not config) then
        run.index=run.index+1;return false
    end
    city.paused=live_config and live_config.paused or false
    for _,slot in ipairs(city.slots) do
        local ordered=C.submitted[region..":"..slot.index]
        if ordered then
            slot.busy=true
            slot.ordered_this_pass=true
            if type(ordered)=="table" and ordered.key then slot.key=ordered.key;slot.foreign=false end
        end
    end
    for _,slot in ipairs(city.district_slots or {}) do
        local ordered=C.submitted[region..":"..slot.index]
        if ordered then slot.busy=true;slot.ordered_this_pass=true end
    end
    if city.primary and C.submitted[region..":"..city.primary.index] then city.primary.busy=true end
    -- Slots whose demolition we already ordered, still holding the same building.
    -- The planners must neither re-issue the command (Demolish toggles, so a second
    -- one cancels the demolition) nor treat the pending order as a stale
    -- construction order and cancel it. Both were undoing demolitions the mod had
    -- just started.
    city.demolishing={}
    for _,slot in ipairs(city.slots) do
        local mark=region..":"..slot.index
        local recorded=C.demolish_order[mark]
        if recorded then
            if slot.key==nil then
                C.demolish_order[mark]=nil          -- it is gone; forget the order
            elseif slot.key~=recorded.key then
                C.demolish_order[mark]=nil          -- replaced by something else
            elseif slot.busy or slot.demolishing then
                recorded.idle=0                     -- demolition is running
                city.demolishing[slot.index]=true
            else
                -- Not busy and still standing. Give the native flag a couple of
                -- passes to settle before concluding the order was lost, because
                -- re-issuing Demolish while it is in flight cancels it.
                -- The old counter counted planner invocations, sometimes many
                -- in one pass. Count distinct turns instead of 0.18s callbacks.
                local turn=cm:query_model():turn_number()
                if recorded.last_idle_turn~=turn then
                    recorded.idle=(recorded.idle or 0)+1
                    recorded.last_idle_turn=turn
                end
                if recorded.idle<3 then
                    city.demolishing[slot.index]=true
                else
                    C.demolish_order[mark]=nil
                    K.log("Demolition order was never confirmed; allowing another attempt: "..mark)
                end
            end
        end
    end
    local cash=math.max(0,math.min(treasury(),run.start_cash-run.spent)-C.state.reserve_money)
    local food=math.min(food_total(),run.start_food)-run.reserved_food-C.state.reserve_food
    -- Remember the budget this settlement actually saw: it is what the player is
    -- shown after the pass, and it is usually the whole explanation.
    run.available_cash,run.available_food=cash,food
    local plan,reason
    if gate then
        local gate_goals=C.state.profiles.gate or {}
        -- Ordinary district slots in gates share the city planner; the special
        -- gate-only construction chain remains under the original gate planner.
        if city.district_slots and #city.district_slots>0 and has_targets(gate_goals) then
            local district={region=region,owned=true,paused=false,siege=city.siege,
                slots=city.district_slots,capacity=math.min(#city.district_slots,6)}
            plan,reason=K.next_city_action(district,gate_goals,TK_AUTO_BUILDINGS,
                cash,food,false,C.state.build_focus,C.state.build_sort)
        end
        if not plan then
            local ok,result,why=pcall(TK_AUTO_GATES.next_action,city,TK_AUTO_BUILDINGS,cash,food)
            if ok then plan,reason=result,why
            else reason="gate_waiting";K.warn("gate_plan:"..region,"Gate planner failed: "..tostring(result)) end
        end
    elseif fixed then plan,reason=K.next_fixed_action(city,TK_AUTO_BUILDINGS,cash,food)
    elseif county then
        plan,reason=K.next_city_action(city,county_settings()[city.element] or {},TK_AUTO_BUILDINGS,
            cash,food,false,C.state.build_focus,C.state.build_sort)
    else plan,reason=K.next_city_action(city,city.effective_goals or C.state.profiles[config.profile] or {},TK_AUTO_BUILDINGS,cash,food,C.state.auto_growth,C.state.build_focus,C.state.build_sort) end
    C.status[region]=reason or (plan and plan.kind) or "waiting"
    run.reasons[region]=C.status[region]
    if not plan then
        local empty,roots,allowed,upgrades,can_upgrade,bridge_missing=0,0,0,0,0,0
        for _,slot in ipairs(city.slots) do
            if not slot.key then empty=empty+1 end
            if slot.bridge_missing then bridge_missing=bridge_missing+1 end
            for _,option in ipairs(slot.roots or {}) do roots=roots+1;if option.allowed then allowed=allowed+1 end end
            for _,option in ipairs(slot.upgrades or {}) do upgrades=upgrades+1;if option.allowed then can_upgrade=can_upgrade+1 end end
        end
        if city.primary and city.primary.bridge_missing then bridge_missing=bridge_missing+1 end
        -- An empty district slot that is never filled is otherwise impossible to
        -- diagnose from the counters alone: print the native root candidates for
        -- that exact slot (key=1 buildable, key=0 rejected by the native check)
        -- together with the template it is being matched against.
        if descriptor.kind=="city" then
            local detail={}
            for _,slot in ipairs(city.slots) do
                if not slot.key and not slot.busy then
                    for _,option in ipairs(slot.roots or {}) do
                        detail[#detail+1]=option.key..(option.allowed and "=1" or "=0")
                    end
                end
            end
            if #detail>0 then
                K.log("City empty slot: region="..region.." roots=["..table.concat(detail,",").."]"..
                    " cash="..cash.." food="..food)
            end
            local goals={}
            local template=live_config and C.state.profiles[live_config.profile] or {}
            for i=1,10 do if template[i] then goals[#goals+1]=template[i] end end
            if #goals>0 then
                K.log("City template: region="..region.." profile="..tostring(live_config and live_config.profile)..
                    " goals=["..table.concat(goals,",").."]")
            end
        end
        local primary_upgrades=city.primary and #(city.primary.upgrades or {}) or 0
        local native_upgrades=0
        for _,slot in ipairs(city.slots) do
            native_upgrades=native_upgrades+(slot.native_counts and math.max(0,slot.native_counts.upgrades) or 0)
        end
        if bridge_missing>0 then
            C.status[region]="construction_context_unavailable"
            run.scope_failures=(run.scope_failures or 0)+bridge_missing
        end
        K.log("City waiting: region="..region.." kind="..descriptor.kind.." capacity="..(city.capacity or #city.slots)..
            " empty="..empty.." roots="..roots.." allowed="..allowed.." upgrades="..upgrades.." upgrade_allowed="..can_upgrade..
            " primary_upgrades="..primary_upgrades.." native_upgrade_records="..native_upgrades..
            " missing_scopes="..bridge_missing.." cash="..cash.." food="..food.." reason="..C.status[region])
        run.index=run.index+1;return false
    end
    if plan.kind=="demolish" then
        local slot=city.expression..".RegionSlotList.At("..plan.slot..")"
        plan.food=math.max(0,food_balance(slot..".BuildingContext.BuildingLevelRecordContext"))
    end
    local mark=region..":"..plan.slot
    if (gate and not C.state.auto_gate) or (live_config and live_config.paused) or not K.owns_region(region) then
        run.index=run.index+1;return false
    end
    local money_before=treasury()
    local accepted
    if type(plan.expression)=="function" then
        local ok,value=pcall(plan.expression)
        accepted=ok and value~=false
        if not ok then K.warn("city_submit:"..mark,tostring(value)) end
    else accepted=K.command(plan.expression) end
    if not accepted then
        C.status[region]="native_order_not_dispatched"
        run.index=run.index+1;return false
    end
    C.submitted[mark]=plan
    run.acted[region]=true
    if plan.kind=="demolish" or plan.kind=="demolish_bandit" then
        local key=plan.key
        if not key then
            for _,item in ipairs(city.slots) do
                if item.index==plan.slot then key=item.key end
            end
        end
        C.demolish_order[mark]={key=key or true,idle=0}
    end
    local actual_spent=math.max(0,money_before-treasury())
    K.log("City order: region="..region.." slot="..plan.slot.." kind="..plan.kind.." key="..tostring(plan.key)..
        " cost="..plan.cost.." charged="..actual_spent)
    -- Retain the quoted commitment if a native deduction is deferred, and
    -- account for a larger synchronous deduction before considering another slot.
    run.spent=run.spent+math.max(plan.cost,actual_spent)
    run.reserved_food=run.reserved_food+plan.food
    C.state.reservations[mark]=plan.food
    run.actions=run.actions+1
    return {city=city,plan=plan,region=region}
end

step=function()
    local run=C.run
    if not run then return end
    local submitted=process_next(run)
    if submitted==nil then finish(run.bridge_failed == true);return end
    if not submitted then schedule(run,step,0.04,"tk_auto_city_step");return end
    schedule(run,function()
        local slot=submitted.city.expression..".RegionSlotList.At("..submitted.plan.slot..")"
        if not slot_busy(slot) and not (submitted.plan.kind=="demolish" and K.bool(slot..".IsEmpty")) then
            C.status[submitted.region]="order_not_confirmed"
            K.warn("city_order:"..submitted.region..":"..submitted.plan.slot,
                "Building order not confirmed for "..submitted.region.."; slot skipped this pass")
        else
            run.confirmed=(run.confirmed or 0)+1
        end
        step()
    end,0.18,"tk_auto_city_ack")
end

function C.run_now(synchronous,reason)
    synchronous=synchronous==true
    -- Both early exits below are silent no-ops otherwise, and a button that
    -- appears to do nothing is indistinguishable from a broken one. Say why.
    if not C.state.enabled then
        C.ui_message=K.L("run_off")
        if C.ui_refresh then pcall(C.ui_refresh) end
        return
    end
    if not available(synchronous) then
        C.pending=true
        C.ui_message=K.L("run_waiting")
        if C.ui_refresh then pcall(C.ui_refresh) end
        K.log("Cities request deferred: reason="..tostring(reason).." awaiting local turn/battle completion")
        return
    end
    -- Automatic campaign events can fire several times in the same player turn.
    -- One automatic construction pass per turn; explicit manual requests are exempt.
    -- Store the turn in saved state so reloading does not re-apply the template.
    local current_turn=cm:query_model():turn_number()
    local manual=(reason=="manual" or reason=="global_recommended" or reason=="city_acquired" or reason=="city_captured")
    if not manual and C.state.auto_last_processed_turn==current_turn then
        K.log("City automatic pass skipped: already processed turn "..tostring(current_turn).." ("..tostring(reason)..")")
        return
    end
    local carry_submitted={}
    local carry_food,carry_cash=0,nil
    if C.busy then
        if not synchronous then C.rerun=true;return end
        -- Preserve this pass's slot marks when finishing at turn end, so a
        -- previously submitted order is never repeated while awaiting its ack.
        carry_submitted=C.submitted
        carry_food=C.run and C.run.reserved_food or 0
        carry_cash=C.run and math.max(0,C.run.start_cash-C.run.spent) or nil
        finish(true)
    end
    C.pending=false
    C.submitted=carry_submitted
    local cities={}
    for region,config in pairs(C.state.cities) do
        local p=K.settlement(region)
        if not config.paused and has_targets(C.state.profiles[config.profile]) and K.owns_region(region) and K.bool(p..".IsProvinceCapital") and not is_gate_pass(region) then
            local province=p..".ProvinceContext"
            -- Current city tier, used by the "growth" order so that cheap upgrades
            -- (which open building slots) are paid for before expensive ones.
            local tier_key=K.read(p..".PrimaryRegionSlotContext.BuildingContext.BuildingLevelRecordContext.Key")
            local tier_data=tier_key and TK_AUTO_BUILDINGS[tier_key]
            cities[#cities+1]={region=region,kind="city",profile=config.profile,income=K.number(province..".Income"),
                growth=tier_data and tier_data.display_level or 99,
                food=K.number('PlayersFaction.PooledResourceContext("'..FOOD..'").ProvinceBreakdownContext('..province..').Total')}
        end
    end
    if C.state.global_capitals then
        for i=0,K.number("PlayersFaction.SettlementList.Size")-1 do
            local p="PlayersFaction.SettlementList.At("..i..")"
            local region=K.read(p..".RegionRecordKey")
            local config=region and region_config(region)
            if region and config and not config.paused and K.owns_region(region) and
                K.bool(p..".IsProvinceCapital") and not is_gate_pass(region) and
                not C.state.cities[region] and has_targets(C.state.profiles[config.profile]) then
                local province=p..".ProvinceContext"
                local tier_key=K.read(p..".PrimaryRegionSlotContext.BuildingContext.BuildingLevelRecordContext.Key")
                local tier_data=tier_key and TK_AUTO_BUILDINGS[tier_key]
                cities[#cities+1]={region=region,kind="city",profile=config.profile,
                    income=K.number(province..".Income"),growth=tier_data and tier_data.display_level or 99,
                    food=K.number('PlayersFaction.PooledResourceContext("'..FOOD..'").ProvinceBreakdownContext('..province..').Total')}
            end
        end
    end
    -- Owned gate passes follow their own chain; counties and ports remain fixed resources.
    for i=0,K.number("PlayersFaction.SettlementList.Size")-1 do
        local p="PlayersFaction.SettlementList.At("..i..")"
        local region=K.read(p..".RegionRecordKey")
        if region and K.owns_region(region) then
            local province=p..".ProvinceContext"
            if is_gate_pass(region) then
                if C.state.auto_gate then
                    cities[#cities+1]={region=region,kind="gate",profile="other",income=K.number(province..".Income"),
                        food=K.number('PlayersFaction.PooledResourceContext("'..FOOD..'").ProvinceBreakdownContext('..province..').Total')}
                end
            else
                local capital=K.read(province..".CapitalSettlementContext.RegionRecordKey")
                local config=capital and K.owns_region(capital) and region_config(capital) or nil
                if not (config and config.paused) then
                    if C.state.auto_counties and not K.bool(p..".IsProvinceCapital") then
                        cities[#cities+1]={region=region,kind="county",profile="other",
                            income=K.number(province..".Income"),
                            food=K.number('PlayersFaction.PooledResourceContext("'..FOOD..'").ProvinceBreakdownContext('..province..').Total')}
                    end
                    cities[#cities+1]={region=region,kind="fixed",profile=config and config.profile or "other",
                        income=K.number(province..".Income"),
                        food=K.number('PlayersFaction.PooledResourceContext("'..FOOD..'").ProvinceBreakdownContext('..province..').Total')}
                end
            end
        end
    end
    -- Captures are scoped to newly-owned settlement(s), never a second global pass.
    if reason=="city_acquired" or reason=="city_captured" then
        local selected={}
        local wanted=C.capture_pending_regions or {}
        for _,entry in ipairs(cities) do if wanted[entry.region] then selected[#selected+1]=entry end end
        K.log("CAPTURE_SCOPE requested="..tostring(C.capture_pending_count or 0).." tasks="..#selected)
        cities=selected
        C.capture_pending_regions={}
        C.capture_pending_count=0
    end
    K.sort_cities(cities,C.state.city_sort)
    C.diagnostic_count=0
    local run={cities=cities,snapshots={},index=1,actions=0,confirmed=0,start_cash=math.min(treasury(),carry_cash or treasury()),start_food=food_total(),spent=0,
        reserved_food=0,synchronous=synchronous,reason=reason or "settings",reasons={},acted={}}
    C.run=run;C.busy=true
    if not bridge_healthy() then
        K.log("BRIDGE_GUARD abort_before_scan: native campaign context unavailable")
        C.pending=true
        finish(true)
        return
    end
    if not manual then C.state.auto_last_processed_turn=cm:query_model():turn_number() end
    K.log("Cities started: reason="..tostring(run.reason).." candidates="..#cities)
    local settlements=K.number("PlayersFaction.SettlementList.Size")
    if synchronous then
        -- Complete the bounded pass inside the end-turn event. Timers would
        -- advance into AI turns and cause the ordinary readiness check to skip it.
        local ok,err=pcall(function()
            for i=0,settlements-1 do run.reserved_food=run.reserved_food+reserve_one_settlement(i) end
            run.reserved_food=math.max(run.reserved_food,carry_food)
            while process_next(run)~=nil do end
        end)
        if not ok then K.log("End-turn city pass stopped: "..tostring(err)) end
        finish(true)
        return
    end
    local i=0
    local ledger_step
    ledger_step=function()
        if not K.ready() or not bridge_healthy() then
            K.log("BRIDGE_GUARD abort_food_ledger: native campaign context unavailable")
            C.pending=true;finish(true);return
        end
        if i>=settlements then schedule(run,step,0.08,"tk_auto_city_step");return end
        run.reserved_food=run.reserved_food+reserve_one_settlement(i)
        i=i+1
        schedule(run,ledger_step,0.03,"tk_auto_food_ledger")
    end
    schedule(run,ledger_step,0.08,"tk_auto_food_ledger")
end

function C.request_run(reason)
    reason=reason or "settings"
    local forced=(reason=="manual" or reason=="global_recommended")
    if forced then
        C.force_pending=(C.force_pending or 0)+1
        K.log("FORCE_REQUEST reason="..reason.." queued="..C.force_pending)
        if C.busy then return end
        C.force_pending=C.force_pending-1
        C.run_now(false,reason)
        return
    end
    C.pending=true
    C.pending_reason=reason
    C.requests=C.requests+1
    if C.busy then C.rerun=true;return end
    local request=C.requests
    K.defer(function()
        if request==C.requests then C.run_now(false,C.pending_reason) end
    end,0.45,"tk_auto_city_request")
end

function C.end_turn()
    local turn=cm:query_model():turn_number()
    if C.last_end_turn==turn then return end
    C.last_end_turn=turn
    C.requests=C.requests+1 -- invalidate pending debounced callbacks
    C.run_now(true,"turn_end")
end


local function initialize()
    K.runtime_probe("cities_before_init")
    migrate_templates()
    if USER_CONFIG.enabled then
        local ok=true
        for i,key in ipairs(USER_CONFIG.capital) do
            if key and not (TK_AUTO_BUILDINGS[key] and TK_AUTO_BUILDINGS[key].template_slot) then ok=false end
        end
        for _,element in ipairs(ELEMENTS) do
            local pair=USER_CONFIG[element]
            for i=1,2 do
                local key=pair[i]
                if key and not (TK_AUTO_BUILDINGS[key] and TK_AUTO_BUILDINGS[key].template_slot) then ok=false end
            end
        end
        if ok then
            C.state.profiles.agriculture=C.state.profiles.agriculture or {}
            for i,key in ipairs(USER_CONFIG.capital) do
                if key then C.state.profiles.agriculture[i]=key end
            end
            C.state.global_capitals=has_targets(C.state.profiles.agriculture)
            for _,element in ipairs(ELEMENTS) do
                local pair=USER_CONFIG[element]
                if pair[1] or pair[2] then C.set_county_targets(element,pair[1],pair[2]) end
            end
            -- Optional one-time capture from designated fully-developed examples.
            if USER_CONFIG.sample_capital then
                local success,err=C.capture_capital_template(USER_CONFIG.sample_capital)
                K.log("Sample capital capture: "..tostring(success).." / "..tostring(err))
            end
            for _,element in ipairs(ELEMENTS) do
                local sample=USER_CONFIG.sample_counties[element]
                if sample then
                    local success,err=C.capture_county_template(sample)
                    K.log("Sample county "..element.." capture: "..tostring(success).." / "..tostring(err))
                end
            end
            C.state.auto_counties=true
        else K.log("USER_CONFIG contains unknown buildings; skipped") end
    end
    K.log("Auto Cities "..C.version.." loaded; profile assignments are opt-in")
    if cm:is_multiplayer() then K.log("Auto Cities disabled in multiplayer");return end
    core:add_listener("tk_auto_cities_turn","FactionTurnStart",
        function(c) return c:faction():name()==cm:get_local_faction(true) end,
        function() C.request_run("turn_start") end,true)
    core:add_listener("tk_auto_cities_turn_end","FactionTurnEnd",
        function(c) return c:faction():name()==cm:get_local_faction(true) end,
        function() C.end_turn() end,true)
    core:add_listener("tk_auto_cities_before_turn_end","FactionAboutToEndTurn",
        function(c) return c:faction():name()==cm:get_local_faction(true) end,
        function() C.end_turn() end,true)
    -- Snapshot the owned regions at init; events compare before/after ownership.
    C.known_owned_regions={}
    for i=0,K.number("PlayersFaction.SettlementList.Size")-1 do
        local key=K.read("PlayersFaction.SettlementList.At("..i..").RegionRecordKey")
        if key then C.known_owned_regions[key]=true end
    end
    local function handle_new_regions(reason)
        local new_count=0
        C.capture_pending_regions=C.capture_pending_regions or {}
        for i=0,K.number("PlayersFaction.SettlementList.Size")-1 do
            local key=K.read("PlayersFaction.SettlementList.At("..i..").RegionRecordKey")
            if key and not C.known_owned_regions[key] then
                C.known_owned_regions[key]=true
                if not C.capture_pending_regions[key] then
                    C.capture_pending_regions[key]=true
                    new_count=new_count+1
                    K.log("CAPTURE_NEW region="..key.." reason="..reason)
                end
            end
        end
        C.capture_pending_count=(C.capture_pending_count or 0)+new_count
        if new_count>0 then C.request_run("city_acquired") end
    end
    C.handle_new_regions=handle_new_regions
    core:add_listener("tk_auto_cities_occupied","GarrisonOccupiedEvent",
        function(c) return c:query_character():faction():name()==cm:get_local_faction(true) end,
        function() handle_new_regions("garrison_occupied") end,true)
    core:add_listener("tk_auto_cities_new_owner","RegionOwnershipChanged",
        function(c) return not c:new_owner():is_null_interface() and c:new_owner():name()==cm:get_local_faction(true) end,
        function() handle_new_regions("ownership_changed") end,true)
    core:add_listener("tk_auto_cities_battle_ready","ScriptEventPlayerBattleSequenceFullyCompleteSP",
        function() return C.pending==true end,
        function() C.request_run(C.pending_reason or "city_captured") end,true)
    -- This is the faction lookup used by 3k_campaign_commentary_events.lua;
    -- AI construction completions must not schedule a player-wide scan.
    core:add_listener("tk_auto_cities_completed","BuildingCompleted",
        function(c) return c:building():faction():name()==cm:get_local_faction(true) end,
        function() K.log("AUTO_EVENT building_completed deferred_until_next_turn") end,true)
    -- World/model events drive automation; opening menus only adds controls.
    -- The army planner is its own MOD (tk_auto_army.pack) and registers itself
    -- from its own entry point, so the two can be switched independently.
    if TK_AUTO_CITY_UI then TK_AUTO_CITY_UI.init() end
    K.runtime_probe("cities_after_init")
    K.defer(function() C.request_run("load_or_turn_start") end,1.1,"tk_auto_city_start")
end

function tk_auto_cities()
    cm:add_first_tick_callback(function()
        local ok,err=pcall(initialize)
        if not ok then K.log("Cities initialization failed: "..tostring(err)) end
    end)
end
