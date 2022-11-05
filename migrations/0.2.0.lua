if not late_migrations then return end

late_migrations["0.2.0"] = function(changes)
    local change = changes.mod_changes['crafting_combinator_xeraph']
    if not change or not change.old_version then return; end

    -- update all module chest lookup in main_uid_by_part_uid
    for uid, state in pairs(global.cc.data) do
        global.main_uid_by_part_uid[state.module_chest.unit_number] = uid
    end
end