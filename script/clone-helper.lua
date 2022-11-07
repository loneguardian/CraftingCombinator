---@alias ph_type
---|'combinator-main'
---|'combinator-part'
---|'cache'

local config = require "config"
local util = require "script.util"
local cc_control = require "script.cc"

local ph_combinator, ph_cache, ph_timestamp, main_uid_by_part_uid
local on_load = function()
    ph_combinator = global.clone_placeholder.combinator
    ph_cache = global.clone_placeholder.cache
    ph_timestamp = global.clone_placeholder.timestamp -- key: old_main_uid, value: game.tick
    main_uid_by_part_uid = global.main_uid_by_part_uid
end

--- ph_type lookup by entity name
---@type { [string]: ph_type }
local get_ph_type = {
    [config.CC_NAME] = "combinator-main",
    [config.MODULE_CHEST_NAME] = "combinator-part",
    [config.RC_NAME] = "combinator-main",
    [config.RC_PROXY_NAME] = "combinator-part",
    [config.SIGNAL_CACHE_NAME] = "cache"
}

--- state type lookup by entity name
---@type { [string]: ph_type }
local get_state_type = {
    [config.CC_NAME] = "cc",
    [config.MODULE_CHEST_NAME] = "cc",
    [config.RC_NAME] = "rc",
    [config.RC_PROXY_NAME] = "rc",
    [config.SIGNAL_CACHE_NAME] = "cache"
}

---comment
---@param ph_type ph_type
---@param old_uid uid
---@param new_entity LuaEntity
---@return table|unknown
local get_ph = function(ph_type, old_uid, new_entity, current)
    local ph, old_main_uid
    if ph_type ~= "cache" then
        if ph_type == "combinator-main" then
            old_main_uid = old_uid
            ph = ph_combinator[old_uid]
        elseif ph_type == "combinator-part" then
            old_main_uid = main_uid_by_part_uid[old_uid]
            ph = ph_combinator[old_main_uid]
        end
        if not ph then
            local new_entity_name = new_entity.name
            -- create new ph
            ph = {entity = false}
            if new_entity_name == config.CC_NAME or new_entity_name == config.MODULE_CHEST_NAME then
                ph.module_chest = false
            elseif new_entity_name == config.RC_NAME or new_entity_name == config.RC_PROXY_NAME then
                ph.output_proxy = false
            end
            ph_combinator[old_main_uid] = ph
            ph_combinator.count = ph_combinator.count + 1
            ph_timestamp[old_main_uid] = current
        end
    else
        old_main_uid = main_uid_by_part_uid[old_uid] or old_uid
        ph = ph_cache[old_main_uid]
        if not ph then
            local old_cache_state = global.signals.cache[old_main_uid] -- for main that does not have a cache
            if old_cache_state then
                -- create new ph
                ph = {entity = false}
                -- create keys based on signals cache
                for k in pairs(old_cache_state.__cache_entities) do
                    ph[k] = false
                end
                ph_cache[old_main_uid] = ph
                ph_cache.count = ph_cache.count + 1
                ph_timestamp[old_main_uid] = current
            end
        end
    end
    ::exit::
    return ph, old_main_uid
end

local update_ph = function(ph, old_uid, new_entity)
    local new_entity_name = new_entity.name
    if new_entity_name == config.CC_NAME or new_entity_name == config.RC_NAME then
        ph.entity = new_entity
    elseif new_entity_name == config.MODULE_CHEST_NAME then
        ph.module_chest = new_entity
    elseif new_entity_name == config.RC_PROXY_NAME then
        ph.output_proxy = new_entity
    elseif new_entity_name == config.SIGNAL_CACHE_NAME then
        local old_cache_state = global.signals.cache[main_uid_by_part_uid[old_uid]]
        for lamp_type, entity in pairs(old_cache_state.__cache_entities) do
            if entity.unit_number == old_uid then
                ph[lamp_type] = new_entity
                break
            end
        end
    end
end

local update_main_by_part_lookup = function(ph)
    local main_uid = ph.entity.unit_number
    for k, part in pairs(ph) do
        if not(k == "entity") then
            global.main_uid_by_part_uid[part.unit_number] = main_uid
        end
    end
end

local cleanup_ph = function(old_main_uid, clone_ph)
    clone_ph[old_main_uid] = nil
    clone_ph.count = clone_ph.count - 1
    ph_timestamp[old_main_uid] = nil
end


---Verify placeholder for clone destination information for all components,
---if all present then contruct/clone new state
---@param ph table
---@param state_type string
local verify_ph = function(ph, state_type, old_main_uid)
    -- loop through all keys, check for entity.valid
    for _, entity in pairs(ph) do
        if not(entity and entity.valid) then return end
    end
    
    -- all entity valid
    -- construct new state
    local new_main_uid = ph.entity.unit_number
    if state_type == "cc" then
        ---@type CcState
        local state = util.deepcopy(global.cc.data[old_main_uid])
        state.entity = ph.entity
        state.entityUID = new_main_uid
        state.control_behavior = state.entity.get_or_create_control_behavior()
        state.module_chest = ph.module_chest
        state.inventories.module_chest = state.module_chest.get_inventory(defines.inventory.chest)
        state:find_assembler() -- latch to assembler
		state:find_chest() -- latch to chest
        cc_control.update_chests(state.entity.surface, state.module_chest)
        global.cc.data[new_main_uid] = state
        table.insert(global.cc.ordered, state)
    elseif state_type == "rc" then
        ---@type RcState
        local state = util.deepcopy(global.rc.data[old_main_uid])
        state.entity = ph.entity
        state.entityUID = new_main_uid
        state.output_proxy = ph.output_proxy
        state.input_control_behavior = state.entity.get_or_create_control_behavior()
        state.control_behavior = state.output_proxy.get_or_create_control_behavior()
        global.rc.data[new_main_uid] = state
        table.insert(global.rc.ordered, state)
    elseif state_type == "cache" then
        local state = util.deepcopy(global.signals.cache[old_main_uid])
        state.__entity = ph.entity
        for lamp_type, lamp in pairs(ph) do
            if lamp_type ~= "entity" then
                state.__cache_entities[lamp_type] = lamp
                state[lamp_type].__cb = lamp.get_or_create_control_behavior()
            end
        end
        global.signals.cache[new_main_uid] = state
    end
    update_main_by_part_lookup(ph)
    if state_type == "cache" then
        cleanup_ph(old_main_uid, ph_cache)
    else
        cleanup_ph(old_main_uid, ph_combinator)
    end
end

---Clone-helper's handler for on_entity_cloned.
---Should receives only cc entities
---@param event EventData.on_entity_cloned
local on_entity_cloned = function(event)
    local old_uid = event.source.unit_number ---@type uint
    local new_entity = event.destination
    local new_entity_name = new_entity.name
    local ph_type = get_ph_type[new_entity_name]
    local current = event.tick

    -- if main, it will trigger its own ph + cache ph
    if ph_type == 'combinator-main' then
        local ph, old_main_uid = get_ph(ph_type, old_uid, new_entity, current)
        update_ph(ph, old_uid, new_entity)
        local state_type = get_state_type[new_entity_name]
        verify_ph(ph, state_type, old_main_uid)

        -- cache
        ph, old_main_uid = get_ph('cache', old_uid, nil, current)
        if ph then
            update_ph(ph, old_uid, new_entity)
            verify_ph(ph, 'cache', old_main_uid)
        end
    else
        local ph, old_main_uid = get_ph(ph_type, old_uid, new_entity, current)
        update_ph(ph, old_uid, new_entity) -- TODO: Merge get and update
        local state_type = get_state_type[new_entity_name]
        verify_ph(ph, state_type, old_main_uid)
    end
    -- TODO: listen to chest and assembler clone events and link them with a lookup (possible UPS optimisation)?
end

---Called by on_nth_tick() for placeholder clean up
---@param event any
local periodic_clean_up = function(event)
    if (ph_combinator.count == 0) and (ph_cache.count == 0) then return end
    local list = {ph_combinator, ph_cache}
    for i=1,#list do
        local ph_list = list[i]
        if ph_list.count > 0 then
            for k, ph in pairs(ph_list) do
                if k ~= "count" then
                    for _, new_entity in pairs(ph) do
                        if new_entity and new_entity.valid then
                            local uid = new_entity.unit_number
                            -- if entity is just cloned (same tick?) then ignore ph
                            if ph_timestamp[uid] == event.tick then goto next_ph end

                            log({"", "Partially cloned entity destroyed: ", new_entity.name, new_entity.unit_number})
                            game.print({"", "[Crafting Combinator Xeraph's Fork]", " Partially cloned entity destroyed."})
                            new_entity.destroy()
                            ph_timestamp[uid] = nil
                        end
                    end
                    ph_list[k] = nil
                    ph_list.count = ph_list.count - 1
                end
                ::next_ph::
            end
        end
    end
    if (ph_combinator.count == 0) and (ph_cache.count == 0) then
        for uid in pairs(ph_timestamp) do
            ph_timestamp[uid] = nil
        end
    end
end

return {
    on_load = on_load,
    on_nth_tick = periodic_clean_up,
    on_entity_cloned = on_entity_cloned
}