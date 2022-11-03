local config = require 'config'
local cc_control = require 'script.cc'
local rc_control = require 'script.rc'

local get_all_cc_entities = function ()
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
        for i = 1, #surface_entities do
            entities[#entities + 1] = surface_entities[i]
        end
    end
    return entities
end

local check_uid_mismatch = function()
    local count_mismatch_cached_uid = 0
    local count_mismatch_key = 0
    for k, v in pairs(global.cc.data) do
        if v.entity and v.entity.valid then
            if k ~= v.entity.unit_number then
                count_mismatch_key = count_mismatch_key + 1
            end
            if v.entityUID ~= v.entity.unit_number then
                count_mismatch_cached_uid = count_mismatch_cached_uid + 1
            end
        end
    end

    game.print({"crafting_combinator.chat-message", {"", "check_uid ", "uid mismatch: ", count_mismatch_key, " | cached uid mismatch: ", count_mismatch_cached_uid}})
end

local cleanup_delayed_bp_state = function()
    if global.delayed_blueprint_tag_state then
        -- old structure depreciated
        global.delayed_blueprint_tag_state.is_queued = nil
        global.delayed_blueprint_tag_state.data = nil
    end
end

local function cleanup()
    local count = {
        invalid = {
            cc = 0,
            module_chest = 0,
            rc = 0,
            output_proxy = 0,
            signals_cache = {
                cache_state = 0,
                lamp = 0
            },
        },
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

    local orphan = {cc = {}, module_chest = {}, rc = {}, output_proxy = {}, signal_cache_lamp = {}} --using stat_key

    local proc_data = {
        [config.CC_NAME] = {
            orphan_table = orphan.cc,
            check_global = true,
            global_data = global.cc.data,
            main_control = cc_control,
            stat_key = "cc"
        },
        [config.MODULE_CHEST_NAME]= {
            part = true,
            orphan_table = orphan.module_chest,
            check_global = false,
            global_data = global.cc.data,
            stat_key = "module_chest"
        },
        [config.RC_NAME] = {
            orphan_table = orphan.rc,
            check_global = true,
            global_data = global.rc.data,
            main_control = rc_control,
            stat_key = "rc"
        },
        [config.RC_PROXY_NAME] = {
            part = true,
            orphan_table = orphan.output_proxy,
            check_global = false,
            global_data = global.rc.data,
            stat_key = "output_proxy"
        },
        [config.SIGNAL_CACHE_NAME] = {
            part = true,
            orphan_table = orphan.signal_cache_lamp,
            check_global = true,
            global_data = global.signals.cache,
            stat_key = "signals_cache"
        }
    }

    -- global data cleanup
    global.main_uid_by_part_uid = {} -- reset main_uid_by_part_uid
    for entity_name, map in pairs(proc_data) do
        if not map.check_global then goto next_proc end

        -- find invalid entity entries
        -- else find part and update main_uid_by_part_uid
        for uid, state in pairs(map.global_data) do
            if entity_name == config.CC_NAME or entity_name == config.RC_NAME then
                if state.entity and state.entity.valid then
                    if entity_name == config.CC_NAME then
                        ---@cast state CcState
                        if state.module_chest and state.module_chest.valid then
                            global.main_uid_by_part_uid[state.module_chest.unit_number] = uid
                        else
                            count.invalid[proc_data[config.MODULE_CHEST_NAME].stat_key] = count.invalid[proc_data[config.MODULE_CHEST_NAME].stat_key] + 1
                        end
                    elseif entity_name == config.RC_NAME then
                        ---@cast state RcState
                        if state.output_proxy and state.output_proxy.valid then
                            global.main_uid_by_part_uid[state.output_proxy.unit_number] = uid
                        else
                            count.invalid[proc_data[config.RC_PROXY_NAME].stat_key] = count.invalid[proc_data[config.RC_PROXY_NAME].stat_key] + 1
                        end
                    end
                else
                    map.global_data[uid] = nil
                    count.invalid[map.stat_key] = count.invalid[map.stat_key] + 1
                end
            elseif entity_name == config.SIGNAL_CACHE_NAME then
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
                             else
                                 state[lamp_type] = nil
                                 state.__cache_entities[lamp_type] = nil
                                 count.invalid[map.stat_key].lamp = count.invalid[map.stat_key].lamp + 1
                             end
                         end
                     end
                else
                    map.global_data[uid] = nil
                    count.invalid[map.stat_key].cache_state = count.invalid[map.stat_key].cache_state + 1
                end
            end
        end
        ::next_proc::
    end

    local all_cc_entities = get_all_cc_entities()
    -- loop through all_cc_entities
    for i = #all_cc_entities, 1, -1 do
        local entity = all_cc_entities[i]
        local uid = entity.unit_number
        local entity_name = entity.name
        local global_data = proc_data[entity_name].global_data
        local stat_key = proc_data[entity_name].stat_key

        -- find orphaned cc - try to generate cc.data?
        if proc_data[entity_name].part then
            -- find orphaned parts -> destroy
            if not global.main_uid_by_part_uid[uid] then
                entity.destroy()
                if entity_name == config.SIGNAL_CACHE_NAME then
                    count.destroyed.signal_cache_lamp = count.destroyed.signal_cache_lamp + 1
                else
                    count.destroyed[stat_key] = count.destroyed[stat_key] + 1
                end
            end
        else
            if not global_data[uid] then
                -- find orphaned cc/rc - try to create global data
                local control = proc_data[entity_name].main_control
                if entity_name == config.CC_NAME then
                    control.create(entity)
                    count.cc_data_created = count.cc_data_created + 1
                elseif entity_name == config.RC_NAME then
                    control.create(entity)
                    count.rc_data_created = count.rc_data_created + 1
                end
            end
        end
    end

    if count.cc_data_created > 0 then
        game.print({"crafting_combinator.chat-message", {"", "a total of ", count.cc_data_created, " CC state(s) has been created with default settings."}})
    end
    if count.rc_data_created > 0 then
        game.print({"crafting_combinator.chat-message", {"", "a total of ", count.cc_data_created, " RC state(s) has been created with default settings."}})
    end

    game.print({"crafting_combinator.chat-message", {"", "Cleanup complete."}})
    log("Cleanup command invoked")
    log(serpent.block(count, {sortkeys = false}))
end

local function cc_command(command)
    if command.parameter == "cleanup" then cleanup() end
end

local h = {
    --cleanup_delayed_bp_state = cleanup_delayed_bp_state,
    cc_command = cc_command,
    get_all_cc_entities = get_all_cc_entities
}
return h