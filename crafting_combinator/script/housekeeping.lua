local config = require 'config'

local check_orphaned_combinator = function()
    local cc_entities = {}
    local rc_entities = {}
    for _, s in pairs(game.surfaces) do
        for _, entity in pairs(s.find_entities_filtered({name = config.CC_NAME})) do
            cc_entities[entity.unit_number] = entity
        end
        for _, entity in pairs(s.find_entities_filtered({name = config.RC_NAME})) do
            rc_entities[entity.unit_number] = entity
        end
    end

    local count = {
        entities_not_in_data = 0,
        invalid_entity_in_data = 0,
        invalid_entity_in_ordered = 0
    }

    -- Count entities not in data
    for k, _ in pairs(cc_entities) do
        if not global.cc.data[k] then count.entities_not_in_data = count.entities_not_in_data + 1 end
    end

    for k, _ in pairs(rc_entities) do
        if not global.rc.data[k] then count.entities_not_in_data = count.entities_not_in_data + 1 end
    end

    game.print({"crafting_combinator.chat-message", {"", "check_orphaned_combinator ", "entities_not_in_data: ", count.entities_not_in_data}})

    -- Count data that has invalid entities
    for k, v in pairs(global.cc.data) do
        if not (v.entity and v.entity.valid) then
            count.invalid_entity_in_data = count.invalid_entity_in_data + 1
        end
    end

    for k, v in pairs(global.rc.data) do
        if not (v.entity and v.entity.valid) then
            count.invalid_entity_in_data = count.invalid_entity_in_data + 1
        end
    end

    game.print({"crafting_combinator.chat-message", {"", "check_orphaned_combinator ", "invalid_entity_in_data: ", count.invalid_entity_in_data}})


    -- Count ordered that has invalid entities
    for k, v in pairs(global.cc.ordered) do
        if not (v.entity and v.entity.valid) then
            count.invalid_entity_in_ordered = count.invalid_entity_in_ordered + 1
        end
    end

    for k, v in pairs(global.rc.ordered) do
        if not (v.entity and v.entity.valid) then
            count.invalid_entity_in_ordered = count.invalid_entity_in_ordered + 1
        end
    end

    game.print({"crafting_combinator.chat-message", {"", "check_orphaned_combinator ", "invalid_entity_in_ordered: ", count.invalid_entity_in_ordered}})
end

local check_uid = function()
    local count_mismatch_cached_uid = 0
    local count_mismatch_key = 0
    for k, v in pairs(global.cc.data) do
        if v.entity and v.entity.valid then
            if k ~= v.entity.unit_number then
                count_mismatch_key = count_mismatch_key + 1
            end
            if v.entityUID ~= v.entity.unit_number then
                count_mismatch_cached_uid = count_mismatch_cached_uid + 1
            end
        end
    end

    game.print({"crafting_combinator.chat-message", {"", "check_uid ", "uid mismatch: ", count_mismatch_key, " | cached uid mismatch: ", count_mismatch_cached_uid}})
end

-- local check_data_vs_ordered = function()
--     local count = 0
--     for k, v in pairs(global.cc.data) do
--         count = count + 1
--     end
-- end

-- local rebuild_ordered_table = function()
-- end

local cleanup_delayed_bp_state = function()
    if global.delayed_blueprint_tag_state then
        -- old structure depreciated
        global.delayed_blueprint_tag_state.is_queued = nil
        global.delayed_blueprint_tag_state.data = nil
    end
end

local h = {
    check_orphaned_combinator = check_orphaned_combinator,
    check_uid = check_uid,

    cleanup_delayed_bp_state = cleanup_delayed_bp_state
}

return h