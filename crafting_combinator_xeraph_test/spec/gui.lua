--local combine = require("__crafting_combinator_xeraph_test__.lib.combine")
local util = require("__crafting_combinator_xeraph_test__.util")

local spec_prototype = {
    cc = {
        on_gui_click = {
            "button",
            "random"
        },
        on_gui_selection_state_changed = {
            "dropdown",
            "random"
        },
        on_gui_checked_state_changed = {
            ""
        },
        on_gui_text_changed = {

        },
        on_gui_opened = {
            "key-found",
            "key-not-found"
        },
    },
    rc = {
        on_gui_click = {
            "random"
        },
        on_gui_checked_state_changed = {
            ""
        },
        on_gui_text_changed = {

        },
        on_gui_opened = {

        },
    }
}

-- test spec by spec_name:
-- mock cc/rc state, gui_elements, argument_list (each argument is one event) -> events
local test_spec_by_spec_name = {}

-- pack test spec into test_list:
local test_list = {}

-- this function has to be called during setup (before_all/before_each)
local randomise = function()
    game.print(util.randomString(50))
end

return {
    unit_test = {
        randomise= randomise,
        test_list = test_list
    }
}