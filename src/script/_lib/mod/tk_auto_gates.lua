-- Optional gate automation. Recognition uses the campaign query interfaces,
-- never a new CCO expression for every building in every settlement.
TK_AUTO_GATES = {}
local G = TK_AUTO_GATES
local positive_cache = {}

local function gate_key(value)
    if type(value) ~= "string" then return false end
    -- Match key segments, so "delegate", "compass" and "passive" are not gates.
    for part in value:lower():gmatch("[^_]+") do
        if part == "gate" or part == "pass" or part == "gatepass" then return true end
    end
    return false
end

local function catalog_gate(data)
    return data and (gate_key(data.chain) or gate_key(data.superchain)) or false
end

local function query_region(region)
    if type(region) ~= "string" or region == "" or not cm then return nil end
    local query = cm:query_region(region)
    if not query or query:is_null_interface() then return nil end
    return query
end

local function building_chains(query)
    local result = {}
    local slots = query:slot_list()
    -- Native evidence: lib_campaign_misc.lua:1182-1185, and
    -- 3k_campaign_faction_council_world_data_queries.lua:2729-2732.
    for i = 0, slots:num_items() - 1 do
        local slot = slots:item_at(i)
        if slot:has_building() then
            local building = slot:building()
            result[building:name()] = building:chain()
        end
    end
    return result
end

function G.clear_cache() positive_cache = {} end

function G.is_gate(region, settlement_expression)
    -- The optional expression preserves the UI/queue call signature. Reading it
    -- here would recreate the per-settlement expression explosion from v0.1.17.
    if type(region) ~= "string" or region == "" then return false end
    if positive_cache[region] then return true end
    if gate_key(region) then positive_cache[region] = true; return true end
    local ok, result = pcall(function()
        local query = query_region(region)
        if not query then return false end
        local catalog = TK_AUTO_BUILDINGS or {}
        for key, chain in pairs(building_chains(query)) do
            if gate_key(chain) or catalog_gate(catalog[key]) then return true end
        end
        return false
    end)
    if ok and result then positive_cache[region] = true; return true end
    -- An unavailable query or a captured/reworked region must be reconsidered.
    -- No negative result is cached, and no recognition error escapes this module.
    return false
end

function G.snapshot(region, read_slot, district_goals)
    if type(read_slot) ~= "function" then return nil, "gate_reader_unavailable" end
    if not G.is_gate(region) then return nil, "not_a_gate" end
    local ok, snapshot, reason = pcall(function()
        local query = query_region(region)
        if not query then return nil, "gate_query_unavailable" end
        local owner = query:owning_faction()
        if not owner or owner:is_null_interface() or owner:name() ~= cm:get_local_faction(true) then
            return nil, "gate_not_owned"
        end
        local chains = building_chains(query)
        local catalog = TK_AUTO_BUILDINGS or {}
        local expression = TK_AUTO.settlement(region)
        local result = {region=region, expression=expression, owned=true, paused=false,
            siege=query:garrison_residence():is_under_siege(), slots={},district_slots={}}
        -- Only confirmed gates enter this path. Reuse the existing CCO reader;
        -- query slot ordering need not equal the UI RegionSlotList ordering.
        local count = TK_AUTO.number(expression .. ".RegionSlotList.Size")
        for index = 0, math.min(count, 64) - 1 do
            local slot = read_slot(expression, index, district_goals)
            if slot then
                local chain=slot.key and chains[slot.key] or nil
                if slot.key and (gate_key(chain) or catalog_gate(catalog[slot.key])) then
                    slot.gate_chain=chain or (catalog[slot.key] and catalog[slot.key].chain)
                    result.slots[#result.slots+1]=slot
                elseif not TK_AUTO.bool(expression..".RegionSlotList.At("..index..").IsPrimary") and
                    not slot.fixed_only and not slot.foreign and
                    (not slot.key or (catalog[slot.key] and catalog[slot.key].template_slot)) then
                    -- Only ordinary district plots; never feed native gate chains to
                    -- the generic city planner. Limit count at the planner instead.
                    result.district_slots[#result.district_slots+1]=slot
                end
            end
        end
        if #result.slots == 0 and #result.district_slots == 0 then return nil, "gate_slots_unavailable" end
        return result
    end)
    if not ok then return nil, "gate_snapshot_unavailable" end
    return snapshot, reason
end

local function same_family(current, target, slot)
    if not target then return false end
    if slot.gate_chain and target.chain == slot.gate_chain then return true end
    if not current then return false end
    return (current.chain and current.chain ~= "" and current.chain == target.chain) or
        (current.superchain and current.superchain ~= "" and current.superchain == target.superchain)
end

local function command(candidate)
    if type(candidate.submit) == "function" then
        return function() return candidate.submit() end
    end
    if type(candidate.expression) == "string" and candidate.expression ~= "" then
        return candidate.expression .. ".ConstructInCurrentSlot"
    end
    return nil
end

local function plan(snapshot, catalog, budget, food)
    if not snapshot or not snapshot.owned or snapshot.paused or snapshot.siege then
        return nil, "gate_paused_or_unavailable"
    end
    budget = tonumber(budget) or 0
    food = tonumber(food) or 0
    for _, slot in ipairs(snapshot.slots or {}) do
        if not slot.busy then
            local repair_cost = tonumber(slot.repair_cost)
            if slot.damaged and slot.can_repair and repair_cost and repair_cost >= 0 and
                repair_cost <= budget and type(slot.expression) == "string" then
                return {kind="repair", slot=slot.index, cost=repair_cost, food=0,
                    expression=slot.expression .. ".Repair"}
            end
            local current = catalog[slot.key]
            local options = slot.foreign and slot.conversions or slot.upgrades
            local best, best_level, best_command
            for _, option in ipairs(options or {}) do
                local target = catalog[option.key]
                local cost, food_cost = tonumber(option.cost), tonumber(option.food)
                local level = target and tonumber(target.level or target.display_level)
                local current_level = current and tonumber(current.level or current.display_level)
                local family = same_family(current, target, slot)
                local gate_conversion = slot.foreign and catalog_gate(target)
                if target and level and (family or gate_conversion) and option.key ~= slot.key and
                    (slot.foreign or not current_level or level > current_level) and
                    option.allowed == true and option.unverified ~= true and
                    option.cost_verified ~= false and option.food_verified ~= false and cost and cost >= 0 and
                    food_cost and food_cost >= 0 and cost <= budget and
                    (food_cost == 0 or food_cost <= food) then
                    local expression = command(option)
                    if expression and (not best or level > best_level or
                        (level == best_level and cost < tonumber(best.cost))) then
                        best, best_level, best_command = option, level, expression
                    end
                end
            end
            if best then
                return {kind=slot.foreign and "gate_convert" or "gate_upgrade", slot=slot.index,
                    key=best.key, cost=tonumber(best.cost), food=tonumber(best.food), expression=best_command}
            end
        end
    end
    return nil, "gate_complete_or_waiting"
end

function G.next_action(snapshot, catalog, budget, food)
    local ok, action, reason = pcall(plan, snapshot, catalog or {}, budget, food)
    if not ok then return nil, "gate_plan_unavailable" end
    return action, reason
end
