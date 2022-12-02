describe("global cc/rc.data", function()
    ---@type luassert.match
    local match = require("__testorio__.luassert.match")
    local state_names = {"cc","rc"}
    local test_key = "non-existent key"
    local global_data
    local on_key_not_found

    describe.each(state_names, "%s", function(state_name)
        before_each(function ()
            global_data = global[state_name].data
            assert.is_not_nil(global_data)
            assert.is_nil(rawget(global_data, test_key))
            
            on_key_not_found = spy.on(getmetatable(global_data), "on_key_not_found")
            assert.is_not_nil(on_key_not_found)
        end)

        after_each(function ()
            if on_key_not_found then on_key_not_found:revert() end
        end)

        -- global data key not found
        test("generic key not found", function()
            -- index global data with non-existent key (literally)
            local result = global_data[test_key]
            assert.is_nil(result)
            assert.spy(on_key_not_found).was_called()
            assert.spy(on_key_not_found).was_called_with(test_key, match.Matches(state_name)) -- Matches() tries to find the substring
        end)

        -- gui key not found
        -- gui element name e.g. "crafting_combinator:crafting-combinator:4287"
        describe("gui key not found", function()
            local config = require "config"
            local gui = require "script.gui"
            local gui_events = {
                on_gui_click = defines.events.on_gui_click,
                on_gui_text_changed = defines.events.on_gui_text_changed,
                on_gui_selection_state_changed = defines.events.on_gui_selection_state_changed,
                on_gui_checked_state_changed = defines.events.on_gui_checked_state_changed,
                on_gui_opened = defines.events.on_gui_opened
            }
            local test_entity = {
                valid = true,
                unit_number = -1,
                name = nil
            }
            local test_event = {
                name = nil,
                entity = test_entity,
                element = {
                    valid = true,
                    name = nil
                }
            }
            local get_element_entity_name = {
                cc = "crafting-combinator",
                rc = "recipe-combinator"
            }
            local get_entity_name = {
                cc = config.CC_NAME,
                rc = config.RC_NAME
            }

            -- build specs
            local specs = {}
            for event_name, event_id in pairs(gui_events) do
                if state_name == "rc" and event_id == defines.events.on_gui_click then goto next_event end
                specs[#specs+1] = {event_name, event_id}
                ::next_event::
            end

            test.each(specs, "%s", function(_, event_id)
                test_event.name = event_id
                test_event.entity.name = get_entity_name[state_name]
                test_event.element.name = "crafting_combinator:" .. get_element_entity_name[state_name] .. ":" .. tostring(test_event.entity.unit_number)
                gui.gui_event_handler(test_event)
                assert.spy(on_key_not_found).was_called()
                assert.spy(on_key_not_found).was_called_with(-1, match.Matches(state_name))
            end)
        end)
    end)
end)