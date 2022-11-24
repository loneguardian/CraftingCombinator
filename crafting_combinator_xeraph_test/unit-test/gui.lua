local spec = require("__crafting_combinator_xeraph_test__.spec.gui").unit_test
local gui = require("script.gui")

describe.each(spec.test_list, "%s", function(spec_name, test_spec)
    before_each(function()
        spec.randomise(spec_name)
    
        -- populate state
    end)
    
    after_each(function()
        -- clear state
    end)

    test(spec_name, function()
        
    end)
end)