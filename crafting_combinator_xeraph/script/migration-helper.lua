local config = require 'config'
local cc_control = require 'script.cc'
local rc_control = require 'script.rc'

local migrate_by_entity_scan = function(migrated_uids)
    -- perform entity scan and get list of cc, module-chests, rc, output-proxies
    local entities = {}
    for _, surface in pairs(game.surfaces) do
        local surface_entities = surface.find_entities_filtered{name = {config.CC_NAME, config.MODULE_CHEST_NAME, config.RC_NAME, config.RC_PROXY_NAME}}
        local total = #entities
        for i = 1, #surface_entities do
            entities[total + i] = surface_entities[i]
        end
    end

    local count = {
        orphaned = {
            cc = 0,
            module_chest = 0,
            rc = 0,
            output_proxy = 0
        },
        cc_data_created = 0,
        rc_data_created = 0,
        destroyed = {
            module_chest = 0,
            output_proxy = 0
        }
    }

    -- get list of orphans
    -- sort them into dictionaries, filtering those that has migrated
    local entity_by_uid = {cc = {}, module_chest = {}, rc = {}, output_proxy = {}}

    for i = 1, #entities do
        local entity = entities[i]
        local uid = entity.unit_number
        if entity.name == config.CC_NAME then
            if not migrated_uids or not migrated_uids[uid] then
                entity_by_uid.cc[uid] = entity
                count.orphaned.cc = count.orphaned.cc + 1
            end
        elseif entity.name == config.MODULE_CHEST_NAME then
            if not migrated_uids or not migrated_uids[uid] then
                entity_by_uid.module_chest[uid] = entity
                count.orphaned.module_chest = count.orphaned.module_chest + 1
            end
        elseif entity.name == config.RC_NAME then
            if not migrated_uids or not migrated_uids[uid] then
                entity_by_uid.rc[uid] = entity
                count.orphaned.rc = count.orphaned.rc + 1
            end
        elseif entity.name == config.RC_PROXY_NAME then
            if not migrated_uids or not migrated_uids[uid] then
                entity_by_uid.output_proxy[uid] = entity
                count.orphaned.output_proxy = count.orphaned.output_proxy + 1
            end
        end
    end

    -- cc_data
    -- try to pair combinator entity with module_chest at the same position
    for _, entity in pairs(entity_by_uid.cc) do
        local migrated_state
        local module_chest = entity.surface.find_entity(config.MODULE_CHEST_NAME, entity.position)
        if module_chest then
            migrated_state = {module_chest = module_chest}
            entity_by_uid.module_chest[module_chest.unit_number] = nil
        end
        cc_control.create(entity, nil, migrated_state)
        count.cc_data_created = count.cc_data_created + 1
    end

    -- destroy redundant module_chests
    for _, module_chest in pairs(entity_by_uid.module_chest) do
        script.raise_event(defines.events.script_raised_destroy, {entity = module_chest, skip_cc_destroy = true})
        module_chest.destroy()
        count.destroyed.module_chest = count.destroyed.module_chest + 1
    end

    for uid, _ in pairs(entity_by_uid.cc) do
        local combinator = global.cc.data[uid]
        combinator:find_assembler()
        combinator:find_chest()
        combinator:update(true)
    end

    -- rc_data
    -- pair rc with output proxy
    for _, entity in pairs(entity_by_uid.rc) do
        local migrated_state
        local output_proxy = entity.surface.find_entity(config.RC_PROXY_NAME, entity.position)
        if output_proxy then
            migrated_state = {output_proxy = output_proxy}
            entity_by_uid.output_proxy[output_proxy.unit_number] = nil
        end
        rc_control.create(entity, nil, migrated_state)
        count.rc_data_created = count.rc_data_created + 1
    end

    -- destroy redundant output proxy
    for _, output_proxy in pairs(entity_by_uid.output_proxy) do
        output_proxy.destroy({raise_destroy = true})
        count.destroyed.output_proxy = count.destroyed.output_proxy + 1
    end

    for uid, _ in pairs(entity_by_uid.rc) do
        local combinator = global.rc.data[uid]
        combinator:update(true)
    end

    log("[Crafting Combinator Xeraph's Fork] Migration-by-entity-scan summary:")
    log(serpent.block(count, {sortkeys = false}))
end

local migrate_by_remote_data = function()
    if not remote.interfaces["crafting_combinator_xeraph_migration"] then return end

    local migrated_state = remote.call("crafting_combinator_xeraph_migration", "get_migrated_state")

    if not migrated_state then return end

    -- summary counts
    local count = {
        invalid_cc_entity = 0,
        invalid_module_chest = 0,
        cc_migrated = 0,
        invalid_rc_entity = 0,
        invalid_output_proxy = 0,
        rc_migrated = 0
    }

    -- migrated entities
    local migrated_uids = {}

    -- cc data
    for _, combinator in pairs(migrated_state.cc.data) do
        local entity = combinator.entity
        if entity and entity.valid then
            if combinator.module_chest and combinator.module_chest.valid then
                cc_control.create(entity, nil, combinator)
                migrated_uids[entity.unit_number] = true
                migrated_uids[combinator.module_chest.unit_number] = true
                count.cc_migrated = count.cc_migrated + 1
            else
                count.invalid_module_chest = count.invalid_module_chest + 1
            end
        else
            count.invalid_cc_entity = count.invalid_cc_entity + 1
        end
    end

    -- rc data
    for _, combinator in pairs(migrated_state.rc.data) do
        local entity = combinator.entity
        if entity and entity.valid then
            if combinator.output_proxy and combinator.output_proxy.valid then
                rc_control.create(entity, nil, combinator)
                migrated_uids[entity.unit_number] = true
                migrated_uids[combinator.output_proxy.unit_number] = true
                count.rc_migrated = count.rc_migrated + 1
            else
                count.invalid_output_proxy = count.invalid_output_proxy + 1
            end
        else
            count.invalid_rc_entity = count.invalid_rc_entity + 1
        end
    end

    log("[Crafting Combinator Xeraph's Fork] Migration-by-remote-data summary:")
    log(serpent.block(count, {sortkeys = false}))

    remote.call("crafting_combinator_xeraph_migration", "complete_migration")

    return migrated_uids
end

return {migrate = function(changes)
    if changes.mod_changes
    and (changes.mod_changes.crafting_combinator and (not changes.mod_changes.crafting_combinator.new_version)) -- original mod removed
    and (changes.mod_changes.crafting_combinator_xeraph and (not changes.mod_changes.crafting_combinator_xeraph.old_version)) then -- xeraph fork added
        local migrated_uids = migrate_by_remote_data()
        migrate_by_entity_scan(migrated_uids)
    end
end}