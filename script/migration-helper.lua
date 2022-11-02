local config = require 'config'
local cc_control = require 'script.cc'
local rc_control = require 'script.rc'

---Second step of migration after remote data migration is complete.
---Performs entity scan and tries to build state data based on their positions or connections.
---@param migrated_uids table Table of uids for entities migrated using remote data
local migrate_by_entity_scan = function(migrated_uids)
    -- perform entity scan and get list of cc, module-chests, rc, output-proxies, signal-cache-lamps
    local entities = {}
    for _, surface in pairs(game.surfaces) do
        local surface_entities = surface.find_entities_filtered {
            name = {
                config.CC_NAME,
                config.MODULE_CHEST_NAME,
                config.RC_NAME,
                config.RC_PROXY_NAME,
                config.SIGNAL_CACHE_NAME
            }
        }
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
            output_proxy = 0,
            signal_cache_lamp = 0
        },
        cc_data_created = 0,
        rc_data_created = 0,
        destroyed = {
            module_chest = 0,
            output_proxy = 0,
            signal_cache_lamp = 0
        }
    }

    -- get list of orphans.
    local entity_by_uid = { cc = {}, module_chest = {}, rc = {}, output_proxy = {}, signal_cache_lamp = {} }

    -- dictionary group by entityName
    local get_entity_table = {
        [config.CC_NAME] = { entity_by_uid.cc, "cc" },
        [config.MODULE_CHEST_NAME] = { entity_by_uid.module_chest, "module_chest" },
        [config.RC_NAME] = { entity_by_uid.rc, "rc" },
        [config.RC_PROXY_NAME] = { entity_by_uid.output_proxy, "output_proxy" },
        [config.SIGNAL_CACHE_NAME] = { entity_by_uid.signal_cache_lamp, "signal_cache_lamp" }
    }

    -- sort them into dictionaries, filtering those that has migrated.
    for i = 1, #entities do
        local entity = entities[i]
        local uid = entity.unit_number
        if not (migrated_uids and migrated_uids[uid]) then
            local entity_by_uid = get_entity_table[entity.name][1]
            entity_by_uid[uid] = entity

            local stat_key = get_entity_table[entity.name][2]
            count.orphaned[stat_key] = count.orphaned[stat_key] + 1
        end
    end

    -- main list for trying to pair main to part
    local main_list = {
        cc = {
            mains = entity_by_uid.cc,
            parts = entity_by_uid.module_chest,
            part_name = config.MODULE_CHEST_NAME,
            part_key = "module_chest",
            main_control = cc_control,
            stat_key = "cc_data_created",
            main_data = global.cc.data
        },
        rc = {
            mains = entity_by_uid.rc,
            parts = entity_by_uid.output_proxy,
            part_name = config.RC_PROXY_NAME,
            part_key = "output_proxy",
            main_control = rc_control,
            stat_key = "rc_data_created",
            main_data = global.rc.data
        }
    }

    for i, _ in pairs(main_list) do
        local mains = main_list[i].mains -- entity_by_uid.cc/rc
        for uid, entity in pairs(mains) do
            local part_name = main_list[i].part_name -- entity name
            local part_key = main_list[i].part_key -- key for migrated state
            local part_entity = entity.surface.find_entity(part_name, entity.position)
            local migrated_state
            if part_entity then
                migrated_state = { [part_key] = part_entity }
                main_list[i].parts[part_entity.unit_number] = nil
            end
            main_list[i].main_control.create(entity, nil, migrated_state) -- create method for rc/cc state

            local stat_key = main_list[i].stat_key
            count[stat_key] = count[stat_key] + 1 -- stat: rc/cc data created

            local combinator = main_list[i].main_data[uid] -- global cc/rc data
            if i == 1 then -- cc state
                combinator:find_assembler()
                combinator:find_chest()
            end
            combinator:update(true)
        end
    end

    -- redundant part list - for destroy()
    local part_list = { {entity_by_uid.module_chest, "module_chest"}, {entity_by_uid.output_proxy, "output_proxy"} }
    for i = 1, #part_list do
        local stat_key = part_list[i][2]
        for _, entity in part_list[i][1] do
            if i == 1 then
                cc_control.update_chests(entity.surface, entity)
            end
            entity.destroy()
            count.destroyed[stat_key] = count.destroyed[stat_key] + 1
        end
    end

    -- signal cache
    -- use connections, if no valid connections destroy
    for _, entity in pairs(entity_by_uid.signal_cache_lamp) do

    end

    -- destroy redundant signal cache entities


    log("[Crafting Combinator Xeraph's Fork] Migration-by-entity-scan summary:")
    log(serpent.block(count, { sortkeys = false }))
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
    log(serpent.block(count, { sortkeys = false }))

    remote.call("crafting_combinator_xeraph_migration", "complete_migration")

    return migrated_uids
end

return { migrate = function(changes)
    if changes.mod_changes
        and (changes.mod_changes.crafting_combinator and (not changes.mod_changes.crafting_combinator.new_version))
        -- original mod removed
        and
        (
        changes.mod_changes.crafting_combinator_xeraph and
            (not changes.mod_changes.crafting_combinator_xeraph.old_version
            )) then -- xeraph fork added
        local migrated_uids = migrate_by_remote_data()
        migrate_by_entity_scan(migrated_uids)
    end
end }
