---@alias ph_type
---|'combinator-main'
---|'combinator-part'
---|'cache'

local config = require "config"
local util = require "script.util"
local signals = require "script.signals"

-- Clone placeholder - key: old main uid, value: new partial state
-- Key should be released once the state construction is deemed complete
local ph_combinator, ph_cache, ph_timestamp, main_uid_by_part_uid
local on_load = function()
    ph_combinator = global.clone_placeholder.combinator
    ph_cache = global.clone_placeholder.cache
    ph_timestamp = global.clone_placeholder.timestamp
    main_uid_by_part_uid = global.main_uid_by_part_uid
end

--- ph_type lookup by entity name
---@type { [string]: ph_type }
local get_ph_type = {
    [config.CC_NAME] = "combinator-main",
    [config.MODULE_CHEST_NAME] = "combinator-part",
    [config.RC_NAME] = "combinator-main",
    [config.RC_PROXY_NAME] = "combinator-part",
    [config.SIGNAL_CACHE_NAME] = 'cache'
}

---comment
---@param ph_type ph_type
---@param old_uid uid
---@param new_entity LuaEntity
---@return table|unknown
local get_ph = function(ph_type, old_uid, new_entity)
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
            -- create new ph
            ph = {entity = false}
            if new_entity.name == config.CC_NAME or new_entity.name == config.MODULE_CHEST_NAME then
                ph.module_chest = false
            else -- rc entities
                ph.output_proxy = false
            end
            ph_combinator[old_main_uid] = ph
            ph_combinator.count = ph_combinator.count + 1
        end
    else
        old_main_uid = main_uid_by_part_uid[old_uid]
        ph = ph_cache[old_main_uid]
        if not ph then
            -- create new ph
            ph = {__entity = false}
            -- create keys based on signals cache
            for k in pairs(global.signals.cache[old_main_uid].__cache_entities) do
                ph[k] = false
            end
            ph_cache[old_main_uid] = ph
            ph_cache.count = ph_cache.count + 1
        end
    end
    return ph
end

local update_ph = function(ph, old_uid, new_entity)
    if new_entity.name == config.CC_NAME or new_entity.name == config.RC_NAME then
        ph.entity = new_entity
    elseif new_entity.name == config.MODULE_CHEST_NAME then
        ph.module_chest = new_entity
    elseif new_entity.name == config.RC_PROXY_NAME then
        ph.output_proxy = new_entity
    elseif new_entity.name == config.SIGNAL_CACHE_NAME then
        local old_cache_state = global.signals.cache[main_uid_by_part_uid[old_uid]]
        for lamp_type, entity in pairs(old_cache_state.__cache_entities) do
            if entity.unit_number == old_uid then
                ph[lamp_type] = new_entity
                break
            end
        end
    end
end

local verify_ph = function()
    -- loop through all keys, if all entity valid then construct new state
end

---Clone-helper's handler for on_entity_cloned.
---Should receives only cc entities
---@param event EventData.on_entity_cloned
local on_entity_cloned = function(event)
    local old_uid = event.source.unit_number
    local new_entity = event.destination
    local ph_type = get_ph_type[new_entity.name]

    local ph = get_ph(ph_type, old_uid, new_entity)
    update_ph(ph, old_uid, new_entity)
    verify_ph()
end

---------------------------------
---------------------------------

---Called everytime after the state for an entity part is constructed: on_main_cloned() on_part_cloned()
---@param uid uid for old main entity
local verify_partial_state = function(uid)
    local new_entity = ph_combinator[uid].entity
    -- check if everything is complete:
    if not(new_entity and new_entity.valid) then return end
    
    local entity_name = new_entity.name
    if entity_name == config.CC_NAME then
        if not(ph_combinator[uid].module_chest and ph_combinator[uid].module_chest.valid) then return end
    else
        if not(ph_combinator[uid].output_proxy and ph_combinator[uid].output_proxy.valid) then return end
    end

    -- release last_update key
    ph_combinator[uid].last_update = nil

    -- push new uids to global.main_uid_by_part_uid
    if entity_name == config.CC_NAME then
        main_uid_by_part_uid[ph_combinator[uid].module_chest.unit_number] = ph_combinator[uid].entityUID
    else
        main_uid_by_part_uid[ph_combinator[uid].output_proxy.unit_number] = ph_combinator[uid].entityUID
    end
        
    -- push to data using new entity uid as
    if entity_name == config.CC_NAME then
        global.cc.data[ph_combinator[uid].entityUID] = ph_combinator[uid]
    else
        global.rc.data[ph_combinator[uid].entityUID] = ph_combinator[uid]
    end

    -- push to ordered
    if entity_name == config.CC_NAME then
        table.insert(global.cc.ordered, ph_combinator[uid])
    else
        table.insert(global.rc.ordered, ph_combinator[uid])
    end

    if entity_name == config.CC_NAME then
        -- find_chest/assembler
        ph_combinator[uid]:find_chest()
        ph_combinator[uid]:find_assembler()

        -- update_chests (for module chest)
        ph_combinator[uid].update_chests(new_entity.surface, ph_combinator[uid].module_chest)

        -- TODO: listen to chest and assembler clone events and link them with a lookup? Should help with ups
        -- new problem of verifying partial state
        -- maybe delay state completion until all cloned parts information is received?
    end

    -- release key from ph
    ph_combinator[uid] = nil
    ph_combinator.count = ph_combinator.count - 1
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
    if not ph_combinator[old_main_uid] then
        is_new_partial_state = true

        -- deepcopy old state into partial state
        if entity_name == config.CC_NAME then
            ph_combinator[old_main_uid] = util.deepcopy(global.cc.data[old_main_uid])
        else
            ph_combinator[old_main_uid] = util.deepcopy(global.rc.data[old_main_uid])
        end

        -- remove references to old parts
        if entity_name == config.CC_NAME then
            ph_combinator[old_main_uid].module_chest = false
            ph_combinator[old_main_uid].inventories.module_chest = false
        else
            ph_combinator[old_main_uid].output_proxy = false
            ph_combinator[old_main_uid].control_behavior = false
        end

        ph_combinator.count = ph_combinator.count + 1
    end

    -- update references to new main
    ph_combinator[old_main_uid].entity = new_entity
    ph_combinator[old_main_uid].entityUID = new_main_uid
    if entity_name == config.CC_NAME then
        ph_combinator[old_main_uid].control_behavior = new_entity.get_or_create_control_behavior()
    else
        ph_combinator[old_main_uid].input_control_behavior = new_entity.get_or_create_control_behavior()
    end

    -- last_update = event.tick
    ph_combinator[old_main_uid].last_update = event.tick

    -- verify_partial_state() if partial state is not new
    if not is_new_partial_state then verify_partial_state(old_main_uid) end
end

---Handler for when part/accesory entities are cloned
---@param event any Pass only module_chest, output_proxy clone events
local on_part_cloned = function(event)
    local new_entity = event.destination
    if not (new_entity and new_entity.valid) then return end

    local entity_name = new_entity.name
    local old_uid = event.source.unit_number
    local old_main_uid = global.main_uid_by_part_uid[old_uid]
    local is_new_partial_state = false
    -- check for partially constructed state (existing key)
    if not ph_combinator[old_main_uid] then
        is_new_partial_state = true

        -- deepcopy old state into partial state
        if entity_name == config.MODULE_CHEST_NAME then
            ph_combinator[old_main_uid] = util.deepcopy(global.cc.data[old_main_uid])
        else
            ph_combinator[old_main_uid] = util.deepcopy(global.rc.data[old_main_uid])
        end

        -- remove references to old main
        ph_combinator[old_main_uid].entity = false
        ph_combinator[old_main_uid].entityUID = false
        if entity_name == config.MODULE_CHEST_NAME then
            ph_combinator[old_main_uid].control_behavior = false
        else
            ph_combinator[old_main_uid].input_control_behavior = false
        end

        ph_combinator.count = ph_combinator.count + 1
    end

    -- update references to new part
    if entity_name == config.MODULE_CHEST_NAME then
        ph_combinator[old_main_uid].module_chest = new_entity
        ph_combinator[old_main_uid].inventories.module_chest = new_entity.get_inventory(defines.inventory.chest)
    else
        ph_combinator[old_main_uid].output_proxy = new_entity
        ph_combinator[old_main_uid].control_behavior = new_entity.get_or_create_control_behavior()
    end

    -- last_update = event.tick
    ph_combinator[old_main_uid].last_update = event.tick
    
    -- verify_partial_state() if partial state is not new
    if not is_new_partial_state then verify_partial_state(old_main_uid) end
end

local on_lamp_cloned = function(event)
    local new_entity = event.destination
    if not (new_entity and new_entity.valid) then return end

    local entity_name = new_entity.name
    local old_uid = event.source.unit_number
    local old_main_uid = global.main_uid_by_part_uid[old_uid]
    local is_new_partial_state = false
    -- check for partially constructed state (existing key)
    if not ph_cache[old_main_uid] then
        is_new_partial_state = true
    end

    -- verify_partial_state() if partial state is not new
    if not is_new_partial_state then verify_partial_state(old_main_uid) end
end

---Called by on_nth_tick() for placeholder clean up
---@param event any
local clean_up = function(event)
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
end

return {
    on_load = on_load,
    on_nth_tick = clean_up,

    on_main_cloned = on_main_cloned,
    on_part_cloned = on_part_cloned,
    on_lamp_cloned = on_lamp_cloned,
    on_entity_cloned = on_entity_cloned
}