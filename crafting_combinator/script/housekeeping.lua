local h = {
    cleanup_invalid_entity = function()
        local table_data = {cc_data = global.cc.data, rc_data = global.rc.data}
        local table_ordered = {cc_ordered = global.cc.ordered, rc_ordered = global.rc.ordered}

        for k, t in pairs(table_data) do
            local counter = 0
            for k, v in pairs(t) do
                if not v.entity.valid then
                    t[k] = nil
                    counter = counter + 1
                else
                    if not v.update then
                        t[k] = nil
                        counter = counter + 1
                    end
                end
            end
            print("CC: housekeeping", k, counter, "entries removed")
        end

        for k, t in pairs(table_ordered) do
            local counter = 0
            for i = 1, #t do
                if not t[i] then break end

                while t[i] and t[i].entity and not t[i].entity.valid do
                    table.remove(t, i)
                    counter = counter + 1
                end

                if t[i] and not t[i].update then
                    table.remove(t, i)
                    counter = counter + 1
                end
            end
            print("CC: housekeeping", k, counter, "entries removed")
        end
    end,

    cleanup_delayed_bp_state = function()
        if global.delayed_blueprint_tag_state then
            -- old structure depreciated
            global.delayed_blueprint_tag_state.is_queued = nil
            global.delayed_blueprint_tag_state.data = nil
        end
    end
}

return h