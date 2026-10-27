TK_AUTO = TK_AUTO or {}
local K = TK_AUTO

function K.building_matches(current, target, catalog)
    if not current or not target then return false end
    local a, b = catalog[current], catalog[target]
    if not a or not b then return current == target end
    return current == target or b.ancestors[current] == true or a.ancestors[target] == true
end

local function usable(candidate, target, catalog, budget, food)
    local goal = catalog[target]
    if not candidate or not goal or not candidate.allowed then return false end
    if candidate.key ~= target and not goal.ancestors[candidate.key] then return false end
    return candidate.cost <= budget and (candidate.food == 0 or candidate.food <= food)
end

local function best_candidate(candidates, target, catalog, budget, food)
    local best
    for _, item in ipairs(candidates or {}) do
        if usable(item,target,catalog,budget,food) then
            if not best or (catalog[item.key].level > catalog[best.key].level) or
               (catalog[item.key].level == catalog[best.key].level and item.cost < best.cost) then best=item end
        end
    end
    return best
end

local function construction(candidate,method)
    -- Runtime snapshots provide a native UI-context dispatcher. The callback is
    -- invoked only after budgeting; it binds and validates this exact slot again.
    if candidate.submit then return function() return candidate.submit(method) end end
    return candidate.expression.."."..(method or "ConstructInCurrentSlot")
end

-- Captured bandit-only buildings (the "no benefit to anyone but a bandit lord"
-- set: charity tents, black markets, drill grounds, mountain camps) are fixed
-- buildings. The ordinary district planner therefore never sees them, and the
-- fixed planner would otherwise repair or upgrade them. Remove them instead.
K.bandit_superchain="3k_resource_bandit_buildings"

-- Slot 0 of a template stores a port end point. The set of superchains that
-- count as a city port comes from the generated port catalogue.
local port_superchains
function K.is_port_superchain(superchain)
    if not superchain or superchain=="" then return false end
    if not port_superchains then
        port_superchains={}
        for _,entry in ipairs(TK_AUTO_PORT_TARGETS or {}) do port_superchains[entry.superchain]=true end
    end
    return port_superchains[superchain]==true
end

-- A building is on the way to the goal when it is the goal itself or one of the
-- goal's ancestors, exactly the relation the native upgrade graph uses.
local function on_port_route(key,goal)
    if not key or not goal then return false end
    return key==goal.key or goal.ancestors[key]==true
end

local function has_route(candidates,goal,catalog)
    local target=catalog[goal]
    if not target then return false end
    for _,candidate in ipairs(candidates or {}) do
        if candidate.key==goal or target.ancestors[candidate.key] then return true end
    end
    return false
end

-- Find a common upgrade ancestor and move backwards one native step at a time.
-- This is intentionally a *route planner*, not a synthetic command executor:
-- only downgrades exposed by the current game's slot snapshot are submitted.
-- The catalogue is used for reachability; the slot interface controls legality.
local function shared_ancestor(current_key, target_key, catalog)
    local current, target=catalog[current_key],catalog[target_key]
    if not current or not target or current.superchain~=target.superchain then return nil end
    local best,best_level=nil,-math.huge
    local function consider(key)
        local record=catalog[key]
        if record and (key==target_key or target.ancestors[key]) and
            (key==current_key or current.ancestors[key]) then
            local level=record.display_level or record.level or 0
            if level>best_level then best,best_level=key,level end
        end
    end
    consider(current_key)
    for key in pairs(current.ancestors or {}) do consider(key) end
    return best
end
K.shared_ancestor=shared_ancestor

-- Returns (native downgrade option, route_exists, temporarily_blocked).
-- A5 -> A4 -> A3 -> shared L2 -> B3 ... is legal even though A4/A3
-- are NOT ancestors of B5. Never force demolition merely because the first
-- downgrade is still on the wrong branch.
local function branch_downgrade(slot, goal, catalog, budget, food)
    local common=shared_ancestor(slot.key,goal,catalog)
    if not common or common==slot.key then return nil,false,false end
    local current=catalog[slot.key]
    local best,blocked=nil,false
    for _,candidate in ipairs(slot.downgrades or {}) do
        local next_record=catalog[candidate.key]
        if next_record and candidate.key~=slot.key and
           current.ancestors[candidate.key] and
           (candidate.key==common or next_record.ancestors[common]) then
            if candidate.allowed and candidate.cost<=budget and
               (candidate.food==0 or candidate.food<=food) then
                if not best or (next_record.display_level or 0)>(catalog[best.key].display_level or 0) then
                    best=candidate
                end
            else
                blocked=true
            end
        end
    end
    return best,true,blocked
end
K.branch_downgrade=branch_downgrade

local function growth_action(city,budget,food,allow_growth)
    local primary=city.primary
    if not allow_growth or not primary or primary.busy then return nil end
    if primary.damaged and primary.can_repair and primary.repair_cost<=budget then
        return {kind="city_repair",slot=primary.index,cost=primary.repair_cost,food=0,expression=primary.expression..".Repair"}
    end
    -- Cheapest affordable step first: opening a small city's next slot costs a
    -- couple of food and unlocks more of them, while jumping a tier 9 city costs
    -- tens. Taking the first option in table order spent the whole budget on one
    -- big city and starved every small one.
    local options=primary.foreign and primary.conversions or primary.upgrades
    local best
    for _,candidate in ipairs(options or {}) do
        if candidate.allowed and candidate.cost<=budget and (candidate.food==0 or candidate.food<=food) then
            if not best or candidate.food<best.food or
                (candidate.food==best.food and candidate.cost<best.cost) then best=candidate end
        end
    end
    if best then
        return {kind=primary.foreign and "city_convert" or "city_upgrade",slot=primary.index,key=best.key,
            cost=best.cost,food=best.food,expression=construction(best)}
    end
end

-- A slot the mod has already ordered demolished and that still holds the same
-- building. Two things go wrong without this:
--   * the native Demolish command toggles, so issuing it a second time cancels the
--     demolition that is already running;
--   * a pending demolition still reports a building key, so the template cleanup
--     saw an order that "no longer serves the template" and cancelled it.
-- Together those are exactly the "it demolished it and then cancelled it" the
-- player saw.
local function demolishing(city,slot)
    return slot.demolishing==true or
        (city.demolishing ~= nil and city.demolishing[slot.index] == true)
end
K.demolishing=demolishing

-- Returns one ordinary native construction/repair/conversion/demolition command.
-- build_focus and build_sort only reorder this city's own template entries: they
-- decide which of its six buildings is paid for first. They never reach the city
-- list, which is ordered separately by K.sort_cities.
function K.next_city_action(city, template, catalog, budget, food, allow_growth, build_focus, build_sort)
    if city.paused or city.siege or not city.owned then return nil, "paused_or_unavailable" end
    local goals, used, matched = {}, {}, {}
    local any_target=false
    -- Every configured entry is a candidate goal, in the player's left-to-right
    -- priority order. Capacity limits how many slots exist, not which entries are
    -- considered: truncating the list here meant a port city (one slot shorter)
    -- ignored its last entry even when that was the only one it could build.
    for i=1,10 do
        local key=template[i]
        if catalog[key] then
            any_target=true
            goals[#goals+1]=key
        end
    end
    if not any_target then return nil,"empty_template" end
    if #goals==0 then
        local growth=growth_action(city,budget,food,allow_growth)
        if growth then return growth end
        return nil,"no_active_template_entries"
    end
    goals=K.order_goals(goals,catalog,build_focus,build_sort)
    -- A slot already under construction still counts as this pass's slot, but if
    -- the pending order no longer serves any template entry it is cancelled
    -- rather than paid for and demolished a turn later. This is what makes
    -- changing a city's type mid-turn take effect immediately.
    for _,slot in ipairs(city.slots) do
        if slot.busy and slot.key and not demolishing(city,slot) and
            not slot.ordered_this_pass and slot.can_cancel~=false then
            local wanted=false
            for _,goal in ipairs(goals) do
                if K.building_matches(slot.key,goal,catalog) then wanted=true;break end
            end
            if not wanted then
                return {kind="cancel",slot=slot.index,cost=0,food=0,key=slot.key,
                    expression=slot.expression..".ConstructionItemContext.CancelConstruction"}
            end
        end
    end
    -- First retain compatible buildings, irrespective of their physical slot.
    for goal_index, goal in ipairs(goals) do
        for _, slot in ipairs(city.slots) do
            if not used[slot.index] and not slot.foreign and K.building_matches(slot.key,goal,catalog) then
                matched[goal_index]=slot; used[slot.index]=true; break
            end
        end
    end
    -- Captured buildings may have a different superchain, or an unknown key.
    -- Actual native conversion routes take precedence over chain-name matching.
    -- Retain a locked route too: temporary tech/money limits are not a reason
    -- to demolish a foreign building that can eventually become the template.
    for goal_index,goal in ipairs(goals) do
        if not matched[goal_index] then
            for _,slot in ipairs(city.slots) do
                if not used[slot.index] and slot.foreign and has_route(slot.conversions,goal,catalog) then
                    matched[goal_index]=slot;used[slot.index]=true;break
                end
            end
        end
    end
    -- Then pair wrong branches of the same superchain for native conversion.
    for goal_index, goal in ipairs(goals) do
        if not matched[goal_index] then
            local target=catalog[goal]
            for _, slot in ipairs(city.slots) do
                local current=catalog[slot.key]
                if not used[slot.index] and current and current.superchain==target.superchain then
                    matched[goal_index]=slot; used[slot.index]=true; break
                end
            end
        end
    end
    for goal_index, goal in ipairs(goals) do
        local slot=matched[goal_index]
        if slot and not slot.busy and not demolishing(city,slot) then
            if slot.foreign then
                local conversion=best_candidate(slot.conversions,goal,catalog,budget,food)
                if conversion then
                    return {kind="convert",slot=slot.index,key=conversion.key,cost=conversion.cost,food=conversion.food,
                        expression=construction(conversion)}
                end
                local route=has_route(slot.conversions,goal,catalog)
                if not route and slot.can_demolish then
                    return {kind="demolish",slot=slot.index,cost=0,food=0,expression=slot.expression..".Demolish"}
                elseif route and slot.damaged and slot.can_repair and slot.repair_cost<=budget then
                    return {kind="repair",slot=slot.index,cost=slot.repair_cost,food=0,expression=slot.expression..".Repair"}
                end
            elseif slot.damaged and slot.can_repair and slot.repair_cost<=budget then
                return {kind="repair",slot=slot.index,cost=slot.repair_cost,food=0,expression=slot.expression..".Repair"}
            elseif slot.key == goal or (catalog[slot.key] and catalog[slot.key].ancestors[goal]) then
                if slot.damaged and slot.can_repair and slot.repair_cost <= budget then
                    return {kind="repair",slot=slot.index,cost=slot.repair_cost,food=0,expression=slot.expression..".Repair"}
                end
            else
                local options = K.building_matches(slot.key,goal,catalog) and slot.upgrades or slot.conversions
                local candidate=best_candidate(options,goal,catalog,budget,food)
                if candidate then
                    return {kind=options==slot.conversions and "convert" or "upgrade",slot=slot.index,
                        key=candidate.key,cost=candidate.cost,food=candidate.food,expression=construction(candidate)}
                end
                if not K.building_matches(slot.key,goal,catalog) then
                    -- Wait for an existing conversion's normal money/technology/level requirements.
                    local conversion_route=has_route(slot.conversions,goal,catalog)
                    if not conversion_route then
                        -- Some branches are changed by native downgrade, then rebuilding upwards.
                        local downgrade,has_common,blocked=branch_downgrade(slot,goal,catalog,budget,food)
                        if downgrade then
                            return {kind="downgrade",slot=slot.index,key=downgrade.key,cost=downgrade.cost,
                                food=downgrade.food,expression=construction(downgrade,"DismantleInCurrentSlot")}
                        elseif has_common then
                            -- A valid backward route exists, but the native action may be
                            -- locked, unaffordable, or unavailable this turn. Do not tear
                            -- down the whole building in that situation.
                            -- If no downgrade is exposed, do not assume Demolish is better.
                        elseif slot.can_demolish then
                            return {kind="demolish",slot=slot.index,cost=0,food=0,expression=slot.expression..".Demolish"}
                        end
                    end
                end
            end
        elseif not slot then
            local free,candidate
            for _, item in ipairs(city.slots) do
                if not used[item.index] and not item.busy and not item.key then
                    free=free or item
                    candidate=best_candidate(item.roots,goal,catalog,budget,food)
                    if candidate then free=item;break end
                end
            end
            if free then
                if candidate then
                    return {kind="build",slot=free.index,key=candidate.key,cost=candidate.cost,
                        food=candidate.food,expression=construction(candidate)}
                end
            else
                for _, item in ipairs(city.slots) do
                    if not used[item.index] and not item.busy and item.key and item.can_demolish
                        and not demolishing(city,item) then
                        return {kind="demolish",slot=item.index,cost=0,food=0,expression=item.expression..".Demolish"}
                    end
                end
            end
        end
    end
    -- Remove unrelated or foreign leftovers only in an explicitly assigned city.
    for _, slot in ipairs(city.slots) do
        if not used[slot.index] and slot.key and not slot.busy and slot.can_demolish
            and not demolishing(city,slot) then
            return {kind="demolish",slot=slot.index,cost=0,food=0,expression=slot.expression..".Demolish"}
        end
    end
    local growth=growth_action(city,budget,food,allow_growth)
    if growth then return growth end
    return nil,"waiting_for_money_food_unlock_or_construction"
end

-- Follows one port slot towards the branch chosen in template slot 0. Returns
-- nil when the slot already is the goal or when nothing can be done yet.
local function port_step(slot,current,goal,catalog,budget,food)
    if slot.key==goal.key then return nil end
    local best,best_score
    for _,list in ipairs({slot.upgrades or {},slot.conversions or {}}) do
        for _,option in ipairs(list) do
            local data=catalog[option.key]
            if data and option.key~=slot.key and data.superchain==current.superchain and
                on_port_route(option.key,goal) and data.display_level>current.display_level and
                option.cost<=budget and (option.food==0 or option.food<=food) then
                -- A native-confirmed step always beats an unverified one; among
                -- equals the higher level wins.
                local score=((option.allowed and 1) or 0)*1000+data.display_level
                if not best or score>best_score or
                    (score==best_score and option.cost<best.cost) then best,best_score=option,score end
            end
        end
    end
    if best then
        if not best.allowed then
            K.warn("port_unverified:"..tostring(slot.expression),
                "Port step "..best.key.." towards "..goal.key.." is not confirmed by the native probe; the native command decides")
        end
        return {kind="port_upgrade",slot=slot.index,key=best.key,cost=best.cost,food=best.food,
            expression=construction(best)}
    end
    -- The slot sits on another branch (or above the shared trunk). Step down one
    -- level; the next pass can then climb towards the configured branch. Nothing
    -- is touched while the current level is already on the route.
    if not on_port_route(slot.key,goal) then
        local down
        for _,option in ipairs(slot.downgrades or {}) do
            local data=catalog[option.key]
            if data and data.superchain==current.superchain and
                data.display_level<current.display_level and
                option.cost<=budget and (option.food==0 or option.food<=food) then
                if not down or data.display_level>catalog[down.key].display_level then down=option end
            end
        end
        if down then
            return {kind="port_downgrade",slot=slot.index,key=down.key,cost=down.cost,food=down.food,
                expression=construction(down)}
        end
    end
    return nil
end

-- Fixed county/resource buildings keep their existing chain: repair or follow
-- native upgrades, without demolition, conversion, or occupying template slots.
-- Two exceptions: bandit-only buildings are removed, and a port follows the
-- branch stored in template slot 0 of the city's profile.
function K.next_fixed_action(city,catalog,budget,food)
    if city.paused or city.siege or not city.owned then return nil,"paused_or_unavailable" end
    -- The bandit sweep gets its own pass, before anything else this settlement
    -- wants. It used to sit inside the per-slot loop, so whenever an earlier slot
    -- had its own work to do the sweep was never reached - which is how a captured
    -- 粮帐 / 黑市 / 校场 sat in a city forever.
    if city.can_clear_bandits then
        for _,slot in ipairs(city.slots) do
            local current=catalog[slot.key]
            if not slot.busy and current and current.superchain==K.bandit_superchain and slot.can_demolish
                and not demolishing(city,slot) then
                return {kind="demolish_bandit",slot=slot.index,cost=0,food=0,expression=slot.expression..".Demolish"}
            end
        end
    end
    -- city.fixed_targets maps a port family (superchain) to the end point the
    -- player picked for this city type. A city can only host one family, so the
    -- lookup below is per slot rather than global.
    local targets=city.fixed_targets
    for _,slot in ipairs(city.slots) do
        if not slot.busy then
            local current=catalog[slot.key]
            local goal=nil
            if targets and current and targets[current.superchain] then
                goal=catalog[targets[current.superchain]]
            end
            if city.can_clear_bandits and current and current.superchain==K.bandit_superchain and slot.can_demolish
                and not demolishing(city,slot) then
                return {kind="demolish_bandit",slot=slot.index,cost=0,food=0,expression=slot.expression..".Demolish"}
            end
            if slot.damaged and slot.can_repair and slot.repair_cost<=budget then
                return {kind="repair",slot=slot.index,cost=slot.repair_cost,food=0,expression=slot.expression..".Repair"}
            end
            if current and goal and current.superchain==goal.superchain then
                local plan=port_step(slot,current,goal,catalog,budget,food)
                if plan then return plan end
            elseif current and K.is_port_superchain(current.superchain) then
                -- A configured branch exists for another port chain, or none at
                -- all. Never let the generic "highest level" rule pick a port
                -- branch on its own.
                if goal then
                    K.warn("port_chain:"..tostring(slot.expression),
                        "Port chain "..tostring(current.superchain).." does not match the configured branch "..goal.key)
                end
            else
                local best
                local options=slot.foreign and slot.conversions or slot.upgrades
                for _,option in ipairs(options or {}) do
                    local target=catalog[option.key]
                    if target and target.fixed and (slot.foreign or (current and target.superchain==current.superchain)) and
                        (slot.foreign or (current and target.display_level>current.display_level)) and target.display_level<=5 and
                        option.allowed and option.cost<=budget and (option.food==0 or option.food<=food) then
                        if not best or target.level>catalog[best.key].level or
                            (target.level==catalog[best.key].level and (option.cost<best.cost or
                            (option.cost==best.cost and option.key<best.key))) then best=option end
                    end
                end
                if best then
                    return {kind="county_upgrade",slot=slot.index,key=best.key,cost=best.cost,food=best.food,
                        expression=construction(best)}
                end
                -- Nothing to upgrade here. Report the building once (K.warn keeps
                -- one line per key) so a city that keeps something the player does
                -- not want can be diagnosed from the log instead of guessed at.
                K.warn("fixed_keep:"..tostring(slot.key),
                    "Fixed building left as is: region="..tostring(city.region).." slot="..tostring(slot.index)..
                    " key="..tostring(slot.key).." name="..tostring(current and current.name)..
                    " superchain="..tostring(current and current.superchain)..
                    " can_demolish="..tostring(slot.can_demolish))
            end
        end
    end
    return nil,"fixed_buildings_complete_or_waiting"
end

-- ---------------------------------------------------------------- ordering
-- Two independent orderings live here and they must not be confused:
--   * the building controls below rank the entries of one city's own template,
--     i.e. which of its six buildings gets the money first;
--   * K.sort_cities ranks cities against each other, i.e. which city gets the
--     budget first. Changing one must never move the other, which is why the
--     building controls are not consulted for the city list and vice versa.
K.BUILD_SORTS = {"income_high", "income_low", "food_high", "food_low"}
K.BUILD_FOCUSES = {"all", "agriculture", "commerce", "industry", "other"}
K.CITY_SORTS = {"big", "small", "under8"}

-- "other" is everything the three named categories do not cover, so the military
-- and government chains are reachable instead of silently never matching.
local FOCUS_CATEGORIES = {
    agriculture = {agriculture = true},
    commerce = {commerce = true},
    industry = {industry = true},
    other = {other = true, military = true, government = true},
}

function K.building_matches_focus(key, catalog, focus)
    if not focus or focus == "all" then return true end
    local wanted = FOCUS_CATEGORIES[focus]
    if not wanted then return true end
    local data = catalog[key]
    return data ~= nil and wanted[data.category] == true
end

-- The figure the building is ranked by. income and food come from the catalogue
-- (generated from the game's own effect tables); a building that produces neither
-- ranks last so an empty entry never wins over a productive one.
function K.building_rank(key, catalog, build_sort)
    local data = catalog[key]
    if not data then return 0 end
    if build_sort == "income_low" then return -(data.income or 0) end
    if build_sort == "food_high" then return data.food or 0 end
    if build_sort == "food_low" then return -(data.food or 0) end
    return data.income or 0
end

-- Reorder a template for priority. Entries of the chosen category come first,
-- ranked by the chosen figure; every other entry still follows, in the same
-- order, so a template can never end up with entries that are simply ignored:
-- the controls decide what is built *first*, not what is built at all.
function K.order_goals(goals, catalog, build_focus, build_sort)
    local ordered = {}
    local function append(only_focus)
        local group = {}
        for index, key in ipairs(goals) do
            if K.building_matches_focus(key, catalog, build_focus) == only_focus then
                group[#group + 1] = {key = key, index = index}
            end
        end
        table.sort(group, function(a, b)
            local av = K.building_rank(a.key, catalog, build_sort)
            local bv = K.building_rank(b.key, catalog, build_sort)
            if av ~= bv then return av > bv end
            return a.index < b.index
        end)
        for _, item in ipairs(group) do ordered[#ordered + 1] = item.key end
    end
    append(true)
    append(false)
    return ordered
end

function K.sort_cities(cities, city_sort)
    table.sort(cities, function(a, b)
        -- Cities are ranked against each other with the chosen metric. Gate
        -- passes and fixed county/port settlements have no tier to rank by, so
        -- they go after the cities and take whatever budget is left; leaving them
        -- in the same pool made them sort as tier 0 and swallow the budget first.
        local a_city = (a.kind or "city") == "city"
        local b_city = (b.kind or "city") == "city"
        if a_city ~= b_city then return a_city end
        local av, bv = a.growth or 0, b.growth or 0
        if not a_city then
            av, bv = a.income or 0, b.income or 0
            if av ~= bv then return av > bv end
        elseif city_sort == "big" then
            if av ~= bv then return av > bv end
        elseif city_sort == "under8" then
            local a_low, b_low = av < 8, bv < 8
            if a_low ~= b_low then return a_low end
            if av ~= bv then return av < bv end
        else
            -- "small" is the default: the cheapest next tier opens a slot, which
            -- is what eventually produces the food a bigger city needs.
            if av ~= bv then return av < bv end
        end
        if (a.income or 0) ~= (b.income or 0) then return (a.income or 0) > (b.income or 0) end
        if a.region ~= b.region then return a.region < b.region end
        return (a.kind or "city") < (b.kind or "city")
    end)
    return cities
end
