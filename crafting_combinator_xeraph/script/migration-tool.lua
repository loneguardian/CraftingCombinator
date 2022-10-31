-- should only be called on_init
-- check for migration mod, if absent then return
return {migrate = function()
    if not remote.interfaces["crafting_combinator_xeraph_migration"] then return end

    local migrated_state = remote.call("crafting_combinator_xeraph_migration", "get_migrated_state")

    if not migrated_state then return end

    local cc_control = require 'script.cc'
    local rc_control = require 'script.rc'

    -- summary counts
    local count = {
        cc_migrated = 0,
        rc_migrated = 0,
        invalid_cc_entity = 0,
        invalid_rc_entity = 0,
        invalid_module_chest = 0,
        invalid_output_proxy = 0,
        cc_data_created = 0,
        rc_data_created = 0
    }


    -- perform first round of migration on staged data, using create method for cc and rc
    -- cc data
    for _, combinator in pairs(migrated_state.cc.data) do
        local entity = combinator.entity
        if entity and entity.valid then
            if combinator.module_chest and combinator.module_chest.valid then
                cc_control.create(entity, nil, combinator)
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
                count.rc_migrated = count.rc_migrated + 1
            else
                count.invalid_output_proxy = count.invalid_output_proxy + 1
            end
        else
            count.invalid_rc_entity = count.invalid_rc_entity + 1
        end
    end

    log("[Crafting Combinator Migration] Migration summary:")
    log(serpent.block(count))

    -- TODO: check data?
    -- perform entity scan and get list of cc, module-chests, rc, output-proxies
    -- compare cc and rc entity list to data
    -- compare module-chest and output-proxy entity list to data
    -- handle orphans? -- They do not cost UPS if they are not in ordered list.

    -- remote set migration data status
    -- migration complete
    remote.call("crafting_combinator_xeraph_migration", "complete_migration")
end}