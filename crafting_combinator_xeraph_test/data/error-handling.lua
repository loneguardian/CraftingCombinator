local config = require "config"
local gui = require "script.gui"

local gui_events = {
    on_gui_click = defines.events.on_gui_click,
    on_gui_text_changed = defines.events.on_gui_text_changed,
    on_gui_selection_state_changed = defines.events.on_gui_selection_state_changed,
    on_gui_checked_state_changed = defines.events.on_gui_checked_state_changed,
    on_gui_opened = defines.events.on_gui_opened
}

describe("global cc/rc data", function()
    ---@type luassert.match
    local match = require("__testorio__.luassert.match")
    local state_names = {"cc","rc"}
    local test_key = "non-existent key"
    local mt

    for i=1,#state_names do
        local state_name = state_names[i]
        local global_data
        test("get mt: " .. state_name .. " global data", function()
            global_data = global[state_name].data
            assert.is_not_nil(global_data)
            mt = getmetatable(global_data)
            assert.is_not_nil(mt)
        end)

        describe(state_name, function()
            before_each(function ()
                spy.on(mt, "on_key_not_found")
            end)
            
            -- global data key not found
            test("global data key not found", function()
                -- index global data with non-existent key (literally)
                local result = global_data[test_key]
                assert.is_nil(result)
                assert.spy(mt.on_key_not_found).was_called()
                assert.spy(mt.on_key_not_found).was_called_with(test_key, match.Matches(state_name))
            end)

            -- gui key not found
            -- gui element name e.g. "crafting_combinator:crafting-combinator:4287"
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
            describe("gui key not found", function()
                for k, event_name in pairs(gui_events) do
                    if state_name == "rc" and event_name == defines.events.on_gui_click then goto next_event end
                    test(k, function()
                        test_event.name = event_name
                        test_event.entity.name = get_entity_name[state_name]
                        test_event.element.name = "crafting_combinator:" .. get_element_entity_name[state_name] .. ":" .. tostring(test_event.entity.unit_number)
                        gui.gui_event_handler(test_event)
                        assert.spy(mt.on_key_not_found).was_called()
                        assert.spy(mt.on_key_not_found).was_called_with(-1, match.Matches(state_name))
                    end)
                    ::next_event::
                end
            end)
        end)
    end
end)