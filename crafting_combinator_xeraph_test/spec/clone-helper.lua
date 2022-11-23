local combine = require("__crafting_combinator_xeraph_test__.lib.combine")
local config = require("config")

local unique_int = 0
local get_unique_int = function()
    unique_int = unique_int + 1
    return unique_int
end

local elements = {
    main = {"cc", "rc"},
    cache = {"highest", "highest_count", "highest_present", "signal_present"}
}

local spec_elements_list = {}
-- Generate spec elements list
-- Specs combination: choose one main + combination of all subsets for cache
for i=1,#elements.main do
    local main = elements.main[i]
    local f = combine.powerset(elements.cache)
    while true do
        local spec = {main, f()}
        spec_elements_list[#spec_elements_list + 1] = spec
        if #spec == 1 then break end
    end
end

-- Generate spec prototype using spec elements list

---`Key`: spec_name, `Value`: spec prototype - lookup table for entities in that spec
---@type table<string,table<string,LuaEntity>>
local spec_prototype = {}

for i = 1, #spec_elements_list do
    local spec =  spec_elements_list[i]
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
    spec_prototype[spec_name] = entity_group
end

-- Generate event list using spec prototype
-- Sequential unique_int assigned to unit_number

---`Key`: spec_name, `Value`: array of events for the spec
---@type table<string,EventData.on_entity_cloned[]>
local events_by_spec_name = {}
for spec_name, prototype in pairs(spec_prototype) do
    local events = {}

    for i=1,#elements.main do
        local main_type = elements.main[i]
        if prototype[main_type] then
            local event = {source = {}, destination = {}, tick = 0}
            event.source.name = prototype[main_type].name
            event.destination.name = prototype[main_type].name
            event.source.unit_number = get_unique_int()
            event.destination.unit_number = get_unique_int()
            events[#events+1] = event
        end
    end
    if prototype.cache then
        for _, entity in pairs(prototype.cache) do
            local event = {source = {}, destination = {}, tick = 0}
            event.source.name = entity.name
            event.destination.name = entity.name
            event.source.unit_number = get_unique_int()
            event.destination.unit_number = get_unique_int()
            events[#events+1] = event
        end
    end
    events_by_spec_name[spec_name] = events
end

---list of:
---1. spec name
---2. array of on_entity_cloned events
---@alias TestSpecCloneUnit {[1]: string, [2]: EventData.on_entity_cloned[]}

---list to be consumed by `test.each()`
---@type TestSpecCloneUnit[]
local test_list = {}
for spec_name, events in pairs(events_by_spec_name) do
    test_list[#test_list + 1] = {spec_name, events}
end

local spec = {
    unit_test = {
        elements = elements,
        spec_prototype = spec_prototype,
        events_by_spec_name = events_by_spec_name,
        test_list = test_list
    }
}

return spec