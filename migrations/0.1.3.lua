if not late_migrations then return end

late_migrations["0.1.3"] = function(changes)
    local change = changes.mod_changes['crafting_combinator_xeraph']
	if not change or not change.old_version then return; end

    local config = require 'config'
    -- remove obsolete globals
    if global.dead_combinator_settings then global.dead_combinator_settings = nil end

    global.clone_placeholder = global.clone_placeholder or {}
    global.main_uid_by_part_uid = {}

    
    for k, v in pairs(global.cc.data) do
        -- populate global.main_uid_by_part_uid
        global.main_uid_by_part_uid[v.module_chest.unit_number] = k

        -- additional setting in cc_state
        v.settings.input_buffer_size = config.CC_DEFAULT_SETTINGS.input_buffer_size
    end

    for k, v in pairs(global.rc.data) do
        -- populate global.main_uid_by_part_uid
        global.main_uid_by_part_uid[v.output_proxy.unit_number] = k
    end

    -- signals cache code from housekeeping
    for uid, state in pairs(global.signals.cache) do
        ---@cast state SignalsCacheState
        local combinator_entity = state.__entity
        if combinator_entity and combinator_entity.valid then
             -- check lamps and update main_uid_by_part_uid
             local lamp_types = {"highest", "highest_count", "highest_present", "signal_present"}
             for i= 1, #lamp_types do
                local lamp_type = lamp_types[i]
                 if rawget(state, lamp_type) then
                     local lamp_cb = state[lamp_type].__cb
                     local lamp_entity = state.__cache_entities[lamp_type]
                     if lamp_cb and lamp_entity and lamp_entity.valid then
                        global.main_uid_by_part_uid[lamp_entity.unit_number] = uid
                     end
                 end
             end
        end
    end
end