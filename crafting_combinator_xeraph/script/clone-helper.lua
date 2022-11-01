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

---Called in check_state()
---@param uid integer uid for old main entity
local link_parts = function(uid)
end

---Called everytime after the state for an entity part is constructed: on_main_cloned() on_part_cloned()
---@param uid integer uid for old main entity
local check_state = function(uid)
    -- if everything is complete:
        -- link parts
        -- release last_update key
        -- push to data using new entity uid as key
        -- push to ordered
        -- release key from ph
        -- update_chests (for module chest)
        -- find_chest/assembler
end

---Handler for when main entities are cloned
---@param event any Pass only cc or rc clone events
local on_main_cloned = function(event)
    local new_entity = event.destination
    if not (new_entity and new_entity.valid) then return end

    local entity_name = new_entity.name
    local old_main_uid = event.source.unit_number
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
            clone_ph[old_main_uid].module_chest = nil
            clone_ph[old_main_uid].inventories.module_chest = nil
        else
        end
    end

    -- update references to new main
    clone_ph[old_main_uid].entity = new_entity
    clone_ph[old_main_uid].entityUID = new_entity.unit_number
    clone_ph[old_main_uid].control_behaviour = new_entity.get_or_create_control_behavior()

    -- last_update = event.tick
    clone_ph[old_main_uid].last_update = event.tick

    -- check_state() if partial state is not new
    if not is_new_partial_state then check_state(old_main_uid) end
end

---Handler for when part/accesory entities are cloned
---@param event any Pass only module_chest or output_proxy clone events
local on_part_cloned = function(event)
    local new_entity = event.destination
    if not (new_entity and new_entity.valid) then return end

    local entity_name = new_entity.name
    local old_main_uid = global.cc.main_uid_by_part_uid[event.source.unit_number]
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
        if entity_name == config.MODULE_CHEST_NAME then
            clone_ph[old_main_uid].entity = nil
            clone_ph[old_main_uid].entityUID = nil
            clone_ph[old_main_uid].control_behaviour = nil
        else
        end
    end

    -- update references to new part
    if entity_name == config.MODULE_CHEST_NAME then
        clone_ph[old_main_uid].module_chest = new_entity
        clone_ph[old_main_uid].inventories.module_chest = new_entity.get_inventory(defines.inventory.chest)
    else
    end

    -- last_update = event.tick
    clone_ph[old_main_uid].last_update = event.tick
    
    -- check_state() if partial state is not new
    if not is_new_partial_state then check_state(old_main_uid) end
end

---Called by on_nth_tick() for placeholder clean up
---@param event any
local clean_up = function(event)
    if table_size(clone_ph) == 0 then return end
    for k, v in pairs(clone_ph) do
        if v.last_update < event.tick then
            game.print("Partially cloned entity found. Entity will be destroyed.")
            log("Entities destroyed for key: ", k)
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

---Called when a cc / rc state is not found, usually from clicking of incomplete rc / cc entity to open gui.
---Function checks for partially constructed state. When found, deletes incomplete entities and state and informs that cloning was not complete.
---@param event any
local on_state_not_found = function(event)
    
end

return {
    on_load = on_load,
    on_nth_tick = clean_up,

    on_main_cloned = on_main_cloned,
    on_part_cloned = on_part_cloned
}