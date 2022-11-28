local config = require 'config'
local areas = require("__testorio__.testUtil.areas")

---@type fun(surface_index: uint, surface_name: string): LuaSurface, BoundingBox
local test_area = areas.test_area
---@type LuaSurface
local surface, area
---@type LuaPlayer
local player
local build_position
local cursor
before_all(function()
    player = game.get_player(1)
    cursor = player.cursor_stack
    surface, area = test_area(1, "entity-test")

    -- readjust coordinate
    build_position = {
        x = area.left_top.x+0.5,
        y = area.left_top.y+0.5
    }

    -- TODO: exit editor mode
end)

after_each(function()
    if cursor then cursor.clear() end
    local entities = surface.find_entities(area)
    for i=1,#entities do
        entities[i].destroy()
    end
end)

describe("Entity test - CC", function()
    local build_cc = function()
        cursor.set_stack({name=config.CC_NAME, count = 1})

        -- local entities = surface.find_entities(area)
        -- game.print({"", surface.find_entity(config.CC_NAME, build_position) ~= nil, "1"})

        player.build_from_cursor{position=build_position}

        -- entities = surface.find_entities(area)
        -- game.print({"", surface.find_entity(config.CC_NAME, build_position) ~= nil, "2"})
    end

    local cc_entity, module_chest
    local main_uid, part_uid

    before_each(function()
        build_cc()
        local entities = surface.find_entities(area)
        for i=1,#entities do
            if entities[i].name == config.CC_NAME then
                cc_entity = entities[i]
                main_uid = cc_entity.unit_number
            elseif entities[i].name == config.MODULE_CHEST_NAME then
                module_chest = entities[i]
                part_uid = module_chest.unit_number
            end
        end
    end)

    test("Build CC", function()
        -- check if item in cursor was spent to build
        assert.is_false(cursor.valid_for_read)

        -- find entity
        assert.is_truthy(cc_entity)

        -- check state data
        assert.is_true(cc_entity.valid)
        assert.are_equal(main_uid, global.cc.data[main_uid].entityUID)
    end)

    describe("destroy CC", function()
        local inventory
        before_all(function()
            inventory = player.get_inventory(defines.inventory.character_main)
        end)
        after_each(function()
            inventory.clear()
        end)
        test("Player mine CC - empty inventory - success", function()
            -- check if item in cursor was spent to build
            assert.is_false(cursor.valid_for_read)

            -- clear inventory
            inventory.clear()

            player.mine_entity(cc_entity)

            -- check inventory
            assert.are_equal(inventory.get_item_count(config.CC_NAME), 1)

            -- check global data
            assert.is_nil(rawget(global.cc.data, main_uid))

            -- check main_uid_by_part_uid
            assert.is_nil(global.main_uid_by_part_uid[part_uid])
        end)

        test("Player mine CC - full Inventory + module chest filled - fail", function()
            -- check if item in cursor was spent to build
            assert.is_false(cursor.valid_for_read)

            -- make sure inventory is full
            local itemstack = "iron-plate"
            local inv_size = #inventory
            for i=1,inv_size do
                inventory[i].set_stack(itemstack)
            end

            -- load module chest
            local module_chest_inventory = module_chest.get_inventory(defines.inventory.chest)
            module_chest_inventory.insert(itemstack)
            
            player.mine_entity(cc_entity)

            -- no easy check for failed to mine
            -- only the module chest part will return success = false, mining cc will always return success = true

            -- check cursor
            assert.is_false(cursor.valid_for_read)

            -- check inventory
            assert.are_equal(inventory.get_item_count(config.CC_NAME), 0)

            -- check global data -- old uid should be nil
            assert.is_nil(rawget(global.cc.data, main_uid))

            local new_main_uid = surface.find_entity(config.CC_NAME, build_position).unit_number

            -- check global data -- new main uid should be truthy
            assert.is_truthy(global.cc.data[new_main_uid])

            -- check main_uid_by_part_uid -- part_uid should map to new main_uid
            assert.are_equal(global.main_uid_by_part_uid[part_uid], new_main_uid)
        end)
    end)

    -- TODO: handle surface cleared, surface deleted
end)