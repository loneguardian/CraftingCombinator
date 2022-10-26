if not late_migrations then return end

late_migrations['100.0.1'] = function(changes)
    local change = changes.mod_changes['crafting_combinator']
	if not change or not change.old_version then return end

    for _, combinator in pairs(global.cc.data) do
        combinator.last_combinator_mode = nil

        combinator.entityUID = combinator.entity.unit_number
        combinator.last_assembler_recipe = false
        combinator.read_mode_cb = false
    end

    for _, combinator in pairs(global.rc.data) do
        combinator.entityUID = combinator.entity.unit_number
    end
end