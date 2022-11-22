local combine = require("__crafting_combinator_xeraph_test__.lib.combine")

local cc_control = require("script.cc")
local rc_control = require("script.rc")
local signals = require("script.signals")
local clone = require("script.clone-helper")
local config = require("config")

local unique_int = 0

local get_unique_int = function()
    unique_int = unique_int + 1
    return unique_int
end

local uid_history = {}
local tick_history = {}

-- This function has to be called in test/setup/teardown
---@param list "uid"|nil `uid` for unique uid
---@param n? uint upper bound for random number, can cause infinite loop once the table is saturated with all the integers within bound
---@return uint
local get_random_unique_int = function(list, n)
    n = n or 1000000
    local uid
    local t = (list == "uid") and uid_history or tick_history
    repeat
        uid = math.random(n) --[[@as uint]]
    until not t[uid]
    t[uid] = true
    return uid
end


local elements = {
    main = {"cc", "rc"},
    cache = {"highest", "highest_count", "highest_present", "signal_present"}
}
local spec_list = {}
-- Generate spec list
-- Specs combination: choose one main + combination of all subsets for cache
for i=1,#elements.main do
    local main = elements.main[i]
    local f = combine.powerset(elements.cache)
    while true do
        local spec = {main, f()}
        spec_list[#spec_list + 1] = spec
        if #spec == 1 then break end
    end
end

-- Generate entity and old state using spec list

---`Key`: spec_name, `Value`: lookup table for entities in that spec
---@type table<string,table<string,LuaEntity>>
local entity_list = {}

for i = 1, #spec_list do
    local spec =  spec_list[i]
    local spec_name = table.concat(spec, ":")
    ---@type table<string,LuaEntity>|{cache:table<string,LuaEntity>}
    local entity_group = {}

    for j = 1, #spec do
        if spec[j] == "cc" then
            entity_group.cc = {name = config.CC_NAME}
            entity_group.module_chest = {name = config.MODULE_CHEST_NAME}
        elseif spec[j] == "rc" then
            entity_group.rc = {name = config.RC_NAME}
            entity_group.output_proxy = {name = config.RC_PROXY_NAME}
        else
            entity_group.cache = entity_group.cache or {}
            entity_group.cache[spec[j]] = {name = config.SIGNAL_CACHE_NAME}
        end
    end
    entity_list[spec_name] = entity_group
end

-- Generate event list using entity list

---`Key`: spec_name, `Value`: array of events for the spec
---@type table<string,EventData.on_entity_cloned[]>
local event_list = {}

for spec_name, entity_group in pairs(entity_list) do
    local events = {}

    for i=1,#elements.main do
        local main_type = elements.main[i]
        if entity_group[main_type] then
            local event = {source = {}, destination = {}, tick = 0}
            event.source.name = entity_group[main_type].name
            event.destination.name = entity_group[main_type].name
            event.source.unit_number = get_unique_int()
            event.destination.unit_number = get_unique_int()
            events[#events+1] = event
        end
    end
    if entity_group.cache then
        for _, entity in pairs(entity_group.cache) do
            local event = {source = {}, destination = {}, tick = 0}
            event.source.name = entity.name
            event.destination.name = entity.name
            event.source.unit_number = get_unique_int()
            event.destination.unit_number = get_unique_int()
            events[#events+1] = event
        end
    end
    event_list[spec_name] = events
end

-- final test_list to be consumed by test.each()
---@type table<string, EventData.on_entity_cloned[]>
local test_list = {}
for spec_name, events in pairs(event_list) do
    test_list[#test_list + 1] = {spec_name, events}
end

-- entity key lookup table for asserts
---@type table<uid, string>
local entity_key_by_new_uid = {}

---Lamp type lookup table for asserts
---@type table<uid, string>
local lamp_type_by_new_uid = {}

before_all(function()
    -- clear all states and lookup
    local global_states = {
        global.cc.data,
        global.cc.ordered,
        global.rc.data,
        global.rc.ordered,
        global.main_uid_by_part_uid,
        global.signals.cache
    }
    for i=1,#global_states do
        for k in pairs(global_states[i]) do
            global_states[i][k] = nil
        end
    end

    --  randomise uid
    for _, events in pairs(event_list) do
        for i=1,#events do
            local event = events[i]
            event.source.unit_number = get_random_unique_int("uid")
            event.destination.unit_number = get_random_unique_int("uid")
        end
    end

    local old_main_uid_by_spec_name = {}
    local new_main_uid_by_spec_name = {}
    for spec_name, events in pairs(event_list) do
        -- randomise events
        combine.shuffle(events)

        for i=1,#events do
            local event = events[i]
            -- create main_uid_by_spec_name lookup tables
            if event.source.name == config.CC_NAME or event.source.name == config.RC_NAME then
                old_main_uid_by_spec_name[spec_name] = event.source.unit_number
                new_main_uid_by_spec_name[spec_name] = event.destination.unit_number
            end

            -- assert lookups
            if event.source.name == config.CC_NAME or event.source.name == config.RC_NAME then
                entity_key_by_new_uid[event.destination.unit_number] = "entity"
            elseif event.source.name == config.MODULE_CHEST_NAME then
                entity_key_by_new_uid[event.destination.unit_number] = "module_chest"
            elseif event.source.name == config.RC_PROXY_NAME then
                entity_key_by_new_uid[event.destination.unit_number] = "output_proxy"
            end
        end
    end

    -- create pre-clone states
    for spec_name, events in pairs(event_list) do
        for i=1,#events do
            local event = events[i]
            -- main_uid_by_part_uid
            if event.source.name == config.MODULE_CHEST_NAME
            or event.source.name == config.RC_PROXY_NAME
            or event.source.name == config.SIGNAL_CACHE_NAME then
                global.main_uid_by_part_uid[event.source.unit_number] = old_main_uid_by_spec_name[spec_name]
            end

            -- signals cache
            if event.source.name == config.SIGNAL_CACHE_NAME then
                local old_main_uid = old_main_uid_by_spec_name[spec_name]
                if not global.signals.cache[old_main_uid] then
                    global.signals.cache[old_main_uid] = {
                        __cache_entities = {}
                    }
                end
                local cache_entities = global.signals.cache[old_main_uid].__cache_entities
                local lamp_types = entity_list[spec_name].cache
                for lamp_type in pairs(lamp_types) do
                    if not cache_entities[lamp_type] then
                        cache_entities[lamp_type] = {
                            unit_number = event.source.unit_number
                        }

                        --- lamp type lookup table
                        lamp_type_by_new_uid[event.destination.unit_number] = lamp_type
                        break
                    end
                end
            end

            -- cc state

            -- rc state
        end
    end

    -- create
end)

---@type uid, LuaEntity, string, StateType, ph_type, uint
local old_uid, new_entity, new_entity_name, state_type, ph_type, current
local populate_upvalues = function(event)
    old_uid = event.source.unit_number
    new_entity = event.destination
    new_entity_name = new_entity.name
    state_type = clone.unit_test.get_state_type[event.destination.name]
    ph_type = clone.unit_test.get_ph_type[event.destination.name]
    current = event.tick
end

describe("get_ph()", function()
    local get_ph_components = {
        cc = {"module_chest"}, -- compulsory
        rc = {"output_proxy"}, -- compulsory
        cache = { -- all components optional, but at least one must be present
            highest = true,
            highest_count = true,
            highest_present = true,
            signal_present = true,
        }
    }

    test.each(test_list, "%s", function(_, events)
        for i=1,#events do
            local event = events[i]
            populate_upvalues(event)
            local ph, old_main_uid = clone.unit_test.get_ph(ph_type, old_uid, new_entity_name, current)

            -- if ph_type is combinator_main then uid should be same
            if ph_type == "combinator-main" then
                assert.are_equal(old_uid, old_main_uid)
            end

            -- ph must have entity as key
            assert.is_false(ph.entity)

            -- check other ph components
            local ph_components = get_ph_components[state_type]
            if state_type == "cc" or state_type == "rc" then
                local counter = #ph_components
                local extra = 0
                for k in pairs(ph) do
                    if k == "entity" then goto next_key end
                    for j = 1,#ph_components do
                        local component_name = ph_components[j]
                        if k == component_name then
                            counter = counter - 1
                        else
                            extra = extra + 1
                        end
                    end
                    ::next_key::
                end
                -- must match all components
                assert.is_true(counter == 0)
                -- must not have extra components
                assert.is_true(extra == 0)
            elseif state_type == "cache" then
                local counter = 0
                local extra = 0
                for k in pairs(ph) do
                    if k == "entity" then goto next_key end
                    if ph_components[k] then
                        counter = counter + 1
                    else
                        extra = extra + 1
                    end
                    ::next_key::
                end
                -- must have at least one component
                assert.is_true(counter > 0)
                -- must not have extra components
                assert.is_true(extra == 0)
            end
        end
    end)
end)

describe("update_ph()", function()
    test.each(test_list, "%s", function(_, events)
        for i=1,#events do
            local event = events[i]
            populate_upvalues(event)
            local ph, old_main_uid = clone.unit_test.get_ph(ph_type, old_uid, new_entity_name, current)
            if ph then
                clone.unit_test.update_ph(ph, new_entity, old_uid, old_main_uid)

                local entity_key = entity_key_by_new_uid[new_entity.unit_number]
                local updated_entity
                if entity_key then
                    updated_entity = ph[entity_key]
                else -- cache
                    local lamp_type = lamp_type_by_new_uid[new_entity.unit_number]
                    updated_entity = ph[lamp_type]
                end
                --check whether same entity has been registered in the ph
                assert.are_equal(new_entity, updated_entity)
            end
        end
    end)
end)

describe("verify_ph()", function()
    test.each(test_list, "%s", function(_, events)
        for i=1,#events do
            local event = events[i]
            populate_upvalues(event)
            local ph, old_main_uid = clone.unit_test.get_ph(ph_type, old_uid, new_entity_name, current)
            if ph then
                clone.unit_test.update_ph(ph, new_entity, old_uid, old_main_uid)
                clone.unit_test.verify_ph(ph, state_type, old_main_uid, current)
            end

            --

            --check whether cleanup completed
        end
    end)
end)


