-- this clone-helper unit test module mainly tests the data integrity of placeholder for
-- on_entity_cloned event.
-- methods tested: get_ph(), update_ph()
-- verify_ph() should be tested in integration test with real entities

local combine = require("__crafting_combinator_xeraph_test__.lib.combine")
local spec = require("__crafting_combinator_xeraph_test__.spec.clone-helper").unit_test
local clone = require("script.clone-helper")
local config = require("config")

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

-- entity key lookup table for asserts
---@type table<uid, string>
local entity_key_by_new_uid = {}

---Lamp type lookup table for asserts
---@type table<uid, string>
local lamp_type_by_new_uid = {}

before_all(function()
    local events_by_spec_name = spec.events_by_spec_name

    --  randomise uid for all entities in event_list
    for _, events in pairs(events_by_spec_name) do
        for i=1,#events do
            local event = events[i]
            event.source.unit_number = get_random_unique_int("uid")
            event.destination.unit_number = get_random_unique_int("uid")
        end
    end

    local old_main_uid_by_spec_name = {}
    for spec_name, events in pairs(events_by_spec_name) do
        -- randomise events
        combine.shuffle(events)

        for i=1,#events do
            local event = events[i]
            -- create main_uid_by_spec_name lookup tables
            if event.source.name == config.CC_NAME or event.source.name == config.RC_NAME then
                old_main_uid_by_spec_name[spec_name] = event.source.unit_number
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
    for spec_name, events in pairs(events_by_spec_name) do
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
                local lamp_types = spec.spec_prototype[spec_name].cache
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
        end
    end
end)

after_all(function()
     -- clear all states and lookup
     local global_dict = {
        global.cc.data,
        global.rc.data,
        global.main_uid_by_part_uid,
        global.signals.cache
    }
    local global_list = {
        global.cc.ordered,
        global.rc.ordered
    }
    for i=1,#global_dict do
        for k in pairs(global_dict[i]) do
            global_dict[i][k] = nil
        end
    end
    for i=1,#global_list do
        for j = 1, #global_list[i] do
            global_list[i][j] = nil
        end
    end
end)


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

test.each(spec.test_list, "%s", function(_, events)
    for i=1,#events do
        ---@type EventData.on_entity_cloned
        local event = events[i]

        ---@type uid, LuaEntity, string, StateType, ph_type, uint
        local old_uid, new_entity, new_entity_name, state_type, ph_type, current
        
        old_uid = event.source.unit_number
        new_entity = event.destination
        new_entity_name = new_entity.name
        state_type = clone.unit_test.get_state_type[event.destination.name]
        ph_type = clone.unit_test.get_ph_type[event.destination.name]
        current = event.tick

-- get_ph()

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

        if ph then

-- update_ph()

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