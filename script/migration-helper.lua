local config = require 'config'
local cc_control = require 'script.cc'
local rc_control = require 'script.rc'
local signals = require 'script.signals'
local housekeeping = require 'script.housekeeping'

---Second step of migration after remote data migration is complete.
---Performs entity scan and tries to build state data based on their positions or connections.
---@param migrated_uids table Table of uids for entities migrated using remote data
---fun(PARAM: table): nil
local migrate_by_entity_scan = function(migrated_uids)
    -- perform entity scan and get list of cc, module-chests, rc, output-proxies, signal-cache-lamps
    local all_cc_entities = housekeeping.get_all_cc_entities()
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
        signal_cache_lamp_restored = 0,
        destroyed = {
            module_chest = 0,
            output_proxy = 0,
            signal_cache_lamp = 0
        }
    }

    -- get list of orphans.
    local entity_by_uid = { cc = {}, module_chest = {}, rc = {}, output_proxy = {}, signal_cache_lamp = {} }

    -- entity_name --> variables map
    local get_entity_table = {
        [config.CC_NAME] = { entity_by_uid.cc, "cc" },
        [config.MODULE_CHEST_NAME] = { entity_by_uid.module_chest, "module_chest" },
        [config.RC_NAME] = { entity_by_uid.rc, "rc" },
        [config.RC_PROXY_NAME] = { entity_by_uid.output_proxy, "output_proxy" },
        [config.SIGNAL_CACHE_NAME] = { entity_by_uid.signal_cache_lamp, "signal_cache_lamp" }
    }

    -- sort them into dictionaries, filtering those that has migrated.
    for i = 1, #all_cc_entities do
        local entity = all_cc_entities[i]
        local uid = entity.unit_number
        if not (migrated_uids and migrated_uids[uid]) then
            local entity_by_uid = get_entity_table[entity.name][1] -- entity by uid table
            entity_by_uid[uid] = entity

            local stat_key = get_entity_table[entity.name][2]
            count.orphaned[stat_key] = count.orphaned[stat_key] + 1
        end
    end

    -- main_type -> procedure map for trying to pair main to part
    ---@class main_maps
    ---@field main_control table cc or rc control module
    ---@field main_data table global cc or rc data
    local main_maps = {
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

    for main_type, map in pairs(main_maps) do
        for uid, entity in pairs(map.mains) do
            local part_name = map.part_name -- entity name
            local part_key = map.part_key -- key for migrated_state
            local part_entity = entity.surface.find_entity(part_name, entity.position)
            local migrated_state
            if part_entity then
                migrated_state = { [part_key] = part_entity }
                map.parts[part_entity.unit_number] = nil
            end
            map.main_control.create(entity, nil, migrated_state) -- create method for rc/cc state

            local stat_key = map.stat_key
            count[stat_key] = count[stat_key] + 1 -- stat: rc/cc data created

            local combinator = map.main_data[uid] -- global cc/rc data
            if main_type == "cc" then
                combinator:find_assembler()
                combinator:find_chest()
            end
        end
    end

    -- redundant part list - for destroy()
    for main_type, map in pairs(main_maps) do
        local stat_key = map.stat_key
        for _, entity in pairs(map.parts) do
            if main_type == "cc" then -- module-chest
                map.main_control.update_chests(entity.surface, entity)
            end
            entity.destroy()
            count.destroyed[stat_key] = count.destroyed[stat_key] + 1
        end
    end

    -- signal cache
    -- use connections, if no valid connections destroy
    for uid, lamp in pairs(entity_by_uid.signal_cache_lamp) do
        if signals.migrate_lamp(lamp) then
            entity_by_uid.signal_cache_lamp[uid] = nil
            count.signal_cache_lamp_restored = count.signal_cache_lamp_restored + 1
        else
            -- destroy redundant lamps
            lamp.destroy()
            count.destroyed.signal_cache_lamp = count.destroyed.signal_cache_lamp + 1
        end
    end
    

    -- update combinators after signal cache migration
    -- update will invoke get_recipe -> signal cache -> new signal lamps are created if no cache
    for _, map in pairs(main_maps) do
        local mains = map.mains
        for uid, _ in pairs(mains) do
            local combinator = map.main_data[uid]
            combinator:update(true)
        end
    end

    log("[Crafting Combinator Xeraph's Fork] Migration-by-entity-scan summary:")
    log(serpent.block(count, { sortkeys = false }))
end

---First step of migration, migration of states by using remote call global data.
---@return table migrated_uids
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
        rc_migrated = 0,
        invalid_signal_cache_lamp = 0,
        signal_cache_state_migrated = 0
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

    -- signal cache data
    for uid, cache_state in pairs(migrated_state.signals.cache) do
        for _, entity in pairs(cache_state.__cache_entities) do
            if entity.valid then
                migrated_uids[entity.unit_number] = true
            else
                count.invalid_signal_cache_lamp = count.invalid_signal_cache_lamp + 1
            end
        end
        signals.migrate(uid, cache_state)
        count.signal_cache_state_migrated = count.signal_cache_state_migrated + 1
    end

    log("[Crafting Combinator Xeraph's Fork] Migration-by-remote-data summary:")
    log(serpent.block(count, { sortkeys = false }))

    remote.call("crafting_combinator_xeraph_migration", "complete_migration")

    return migrated_uids
end

return {
    migrate = function(changes)
        if not (changes and changes.mod_changes) then return end
        if (changes.mod_changes.crafting_combinator and (not changes.mod_changes.crafting_combinator.new_version)) -- original mod removed
        and (changes.mod_changes.crafting_combinator_xeraph and (not changes.mod_changes.crafting_combinator_xeraph.old_version)) then -- xeraph fork added
            local migrated_uids = migrate_by_remote_data()
            migrate_by_entity_scan(migrated_uids)
        end
    end
}
