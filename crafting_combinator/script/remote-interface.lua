remote.add_interface("crafting_combinator",
{
    get_migration_data = function()
        local migrated_state = {}
        migrated_state.cc = global.cc
        migrated_state.rc = global.rc
        return migrated_state
    end,
})