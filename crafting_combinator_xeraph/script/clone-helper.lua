local config = require "config"
local util = require "script.util"
local table_size = table_size

-- Clone placeholder - key: old main uid, value: new partial state
-- Key should be released once the state construction is deemed complete

---@alias uid integer old main uid

---@class partial_state table new partial state being constructed
---@field last_update integer The tick when the partial_state was last updated

---@type {[uid]: partial_state}
local clone_ph
local on_load = function()
    clone_ph = global.clone_placeholder
end

---Called everytime after the state for an entity part is constructed: on_main_cloned() on_part_cloned()
---@param uid integer uid for old main entity
local verify_partial_state = function(uid)
    local new_entity = clone_ph[uid].entity
    -- check if everything is complete:
    if not(new_entity and new_entity.valid) then return end
    
    local entity_name = new_entity.name
    if entity_name == config.CC_NAME then
        if not(clone_ph[uid].module_chest and clone_ph[uid].module_chest.valid) then return end
    else
        if not(clone_ph[uid].output_proxy and clone_ph[uid].output_proxy.valid) then return end
    end

    -- release last_update key
    clone_ph[uid].last_update = nil

    -- push new uids to global.main_uid_by_part_uid
    if entity_name == config.CC_NAME then
        global.main_uid_by_part_uid[clone_ph[uid].module_chest.unit_number] = clone_ph[uid].entityUID
    else
        global.main_uid_by_part_uid[clone_ph[uid].output_proxy.unit_number] = clone_ph[uid].entityUID
    end
        
    -- push to data using new entity uid as
    if entity_name == config.CC_NAME then
        global.cc.data[clone_ph[uid].entityUID] = clone_ph[uid]
    else
        global.rc.data[clone_ph[uid].entityUID] = clone_ph[uid]
    end

    -- push to ordered
    if entity_name == config.CC_NAME then
        table.insert(global.cc.ordered, clone_ph[uid])
    else
        table.insert(global.rc.ordered, clone_ph[uid])
    end

    if entity_name == config.CC_NAME then
        -- find_chest/assembler
        clone_ph[uid]:find_chest()
        clone_ph[uid]:find_assembler()

        -- update_chests (for module chest)
        clone_ph[uid].update_chests(new_entity.surface, clone_ph[uid].module_chest)
    end

    -- release key from ph
    clone_ph[uid] = nil
end

---Handler for when main entities are cloned
---@param event any Pass only cc or rc clone events
local on_main_cloned = function(event)
    local new_entity = event.destination
    if not (new_entity and new_entity.valid) then return end

    local entity_name = new_entity.name
    local old_main_uid = event.source.unit_number
    -- check for skip_clone_helper and return early
    if entity_name == config.CC_NAME and global.cc.data[old_main_uid].skip_clone_helper then
        global.cc.data[old_main_uid].skip_clone_helper = nil
        return
    end

    local new_main_uid = new_entity.unit_number
    local is_new_partial_state = false
    -- check for partially constructed state (existing key)
    if not clone_ph[old_main_uid] then
        is_new_partial_state = true

        -- deepcopy old state into partial state
        if entity_name == config.CC_NAME then
            clone_ph[old_main_uid] = util.deepcopy(global.cc.data[old_main_uid])
        else
            clone_ph[old_main_uid] = util.deepcopy(global.rc.data[old_main_uid])
        end

        -- remove references to old parts
        if entity_name == config.CC_NAME then
            clone_ph[old_main_uid].module_chest = false
            clone_ph[old_main_uid].inventories.module_chest = false
        else
            clone_ph[old_main_uid].output_proxy = false
            clone_ph[old_main_uid].control_behavior = false
        end
    end

    -- update references to new main
    clone_ph[old_main_uid].entity = new_entity
    clone_ph[old_main_uid].entityUID = new_main_uid
    if entity_name == config.CC_NAME then
        clone_ph[old_main_uid].control_behavior = new_entity.get_or_create_control_behavior()
    else
        clone_ph[old_main_uid].input_control_behavior = new_entity.get_or_create_control_behavior()
    end

    -- restore signal cache if present
    local old_signal_cache = global.signals.cache[old_main_uid]
    if old_signal_cache then
        local cache = util.deepcopy(old_signal_cache)
        cache.__entity = new_entity

        local connected_entities = new_entity.circuit_connected_entities.red
        for i=1,#connected_entities do
            if connected_entities[i].name == config.SIGNAL_CACHE_NAME then
                local cb = connected_entities[i].get_or_create_control_behavior()
                if cb.circuit_condition.condition.comparator == "≤" then
                    cache.__cache_entities.highest = connected_entities[i]
                    cache.highest.__cb = cb
                elseif cb.circuit_condition.condition.comparator == "≠" then
                    cache.__cache_entities.highest_present = connected_entities[i]
                    cache.highest_present.__cb = cb
                elseif cb.circuit_condition.condition.comparator == "=" then
                    cache.__cache_entities.highest_count = connected_entities[i]
                    cache.highest_count.__cb = cb
                end
            end
        end
        global.signals.cache[new_main_uid] = cache
    end

    -- last_update = event.tick
    clone_ph[old_main_uid].last_update = event.tick

    -- verify_partial_state() if partial state is not new
    if not is_new_partial_state then verify_partial_state(old_main_uid) end
end

---Handler for when part/accesory entities are cloned
---@param event any Pass only module_chest, output_proxy and signal_cache_entities clone events
local on_part_cloned = function(event)
    local new_entity = event.destination
    if not (new_entity and new_entity.valid) then return end

    local entity_name = new_entity.name
    local old_main_uid = global.main_uid_by_part_uid[event.source.unit_number]
    local is_new_partial_state = false
    -- check for partially constructed state (existing key)
    if not clone_ph[old_main_uid] then
        is_new_partial_state = true

        -- deepcopy old state into partial state
        if entity_name == config.MODULE_CHEST_NAME then
            clone_ph[old_main_uid] = util.deepcopy(global.cc.data[old_main_uid])
        else
            clone_ph[old_main_uid] = util.deepcopy(global.rc.data[old_main_uid])
        end

        -- remove references to old main
        clone_ph[old_main_uid].entity = false
        clone_ph[old_main_uid].entityUID = false
        if entity_name == config.MODULE_CHEST_NAME then
            clone_ph[old_main_uid].control_behavior = false
        else
            clone_ph[old_main_uid].input_control_behavior = false
        end
    end

    -- update references to new part
    if entity_name == config.MODULE_CHEST_NAME then
        clone_ph[old_main_uid].module_chest = new_entity
        clone_ph[old_main_uid].inventories.module_chest = new_entity.get_inventory(defines.inventory.chest)
    else
        clone_ph[old_main_uid].output_proxy = new_entity
        clone_ph[old_main_uid].control_behavior = new_entity.get_or_create_control_behavior()
    end

    -- last_update = event.tick
    clone_ph[old_main_uid].last_update = event.tick
    
    -- verify_partial_state() if partial state is not new
    if not is_new_partial_state then verify_partial_state(old_main_uid) end
end

---Called by on_nth_tick() for placeholder clean up
---@param event any
local clean_up = function(event)
    if table_size(clone_ph) == 0 then return end
    for k, v in pairs(clone_ph) do
        if v.last_update < event.tick then
            game.print("Partially cloned entity found. Entity will be destroyed.")
            log({"", "Entities destroyed for key: ", k})
            if v.entity and v.entity.valid then
                log(v.entity.name)
                v.entity.destroy()
            end
            if v.module_chest and v.module_chest.valid then
                log(v.module_chest.name)
                v.module_chest.destroy()
            end
            if v.output_proxy and v.output_proxy.valid then
                log(v.output_proxy.name)
                v.output_proxy.destroy()
            end
            clone_ph[k] = nil
        end
    end
end

return {
    on_load = on_load,
    on_nth_tick = clean_up,

    on_main_cloned = on_main_cloned,
    on_part_cloned = on_part_cloned
}