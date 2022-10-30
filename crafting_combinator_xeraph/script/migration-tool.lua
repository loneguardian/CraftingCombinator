-- should only be called on_init

-- check for migration mod, if absent then return
-- remote check migration data status, should return a table if migration-mod is ready to forward-migrate, else return

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
for _, combinator in pairs(imported.cc.data) do
    local entity = combinator.entity
    if entity and entity.valid then
        if combinator.module_chest and combinator.module_chest.valid then
            cc_control.create(entity, _, combinator)
            count.cc_migrated = count.cc_migrated + 1
        else
            count.invalid_module_chest = count.invalid_module_chest + 1
        end
    else
        count.invalid_cc_entity = count.invalid_cc_entity + 1
    end
end

-- rc data
for _, combinator in pairs(imported.rc.data) do
    local entity = combinator.entity
    if entity and entity.valid then
        if combinator.output_proxy and combinator.output_proxy.valid then
            rc_control.create(entity, _, combinator)
            count.rc_migrated = count.rc_migrated + 1
        else
            count.invalid_output_proxy = count.invalid_output_proxy + 1
        end
    else
        count.invalid_rc_entity = count.invalid_rc_entity + 1
    end
end

log("Migation summary:")
log(serpent.block(count))

-- TODO: check data?
-- perform entity scan and get list of cc, module-chests, rc, output-proxies
-- compare cc and rc entity list to data
-- compare module-chest and output-proxy entity list to data
-- handle orphans? -- They do not cost UPS if they are not in ordered list.

-- remote set migration data status
-- migration complete