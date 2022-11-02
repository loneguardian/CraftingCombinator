if not late_migrations then return end

late_migrations["0.1.2"] = function()
    -- remove obsolete globals
    if global.dead_combinator_settings then global.dead_combinator_settings = nil end

    global.clone_placeholder = global.clone_placeholder or {}
    global.main_uid_by_part_uid = {}

    -- populate global.main_uid_by_part_uid
    for k, v in pairs(global.cc.data) do
        global.main_uid_by_part_uid[v.module_chest.unit_number] = k
    end
    for k, v in pairs(global.rc.data) do
        global.main_uid_by_part_uid[v.output_proxy.unit_number] = k
    end
end