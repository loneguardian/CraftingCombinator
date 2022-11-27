local config = require 'config'
local housekeeping = require "script.housekeeping"
local cc_control = require "script.cc"
local rc_control = require "script.rc"
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

        local entities = surface.find_entities(area)
        game.print({"", surface.find_entity(config.CC_NAME, build_position) ~= nil, "1"})
        player.build_from_cursor{position=build_position}

        entities = surface.find_entities(area)
        game.print({"", surface.find_entity(config.CC_NAME, build_position) ~= nil, "2"})
    end

    local entity

    before_each(function()
        build_cc()
        entity = surface.find_entity(config.CC_NAME, build_position)
    end)

    test("Build CC", function()
        assert.is_false(cursor.valid_for_read)

        -- find entity
        assert.is_true(entity ~= nil)

        -- check state data
        local global_data = global.cc.data
        local uid = entity.unit_number
        assert.is_true(entity.valid)
        assert.are.equal(uid, global_data[uid].entityUID)
    end)

    describe("destroy CC", function()
        local inventory
        before_all(function()
            inventory = player.get_inventory(defines.inventory.character_main)
        end)
        after_each(function()
            inventory.clear()
        end)
        test("Player mine CC - Empty Inventory", function()
            assert.is_false(cursor.valid_for_read)

            -- clear inventory
            inventory.clear()

            local success = player.mine_entity(entity)

            -- mined successfully?
            assert.is_true(success)

            -- check inventory
            assert.are_equal(inventory.get_item_count(config.CC_NAME), 1)

            -- check global data

            -- check main_uid_by_part_uid
        end)

        test("Player mine CC - Full Inventory", function()
            assert.is_false(cursor.valid_for_read)

            -- make sure inventory is full
            local itemstack = {name="iron-plate"}
            while not inventory.is_full() do
                inventory.insert(itemstack)
            end

            -- load module chest
            local module_chest_inventory = surface.find_entity(config.MODULE_CHEST_NAME, build_position).get_inventory(defines.inventory.chest)
            module_chest_inventory.insert(itemstack)
            
            local success = player.mine_entity(entity, false)

            -- failed to mine?
            assert.is_falsy(success) -- doesn't work for god_main, editor_main, character_main inventory, always return success = true

            -- check global data


            -- check main_uid_by_part_uid
        end)
    end)

    -- TODO: handle surface cleared, surface deleted
end)

test.skip("normal player build > mine", function()
    cursor.set_stack({name=config.CC_NAME, count = 1})
    local position = player.position

    position.x = position.x + 1
    position.y = position.y + 1

    player.build_from_cursor{position=position}

    local entity = surface.find_entity(config.CC_NAME, position)
    if not entity then
        cursor.clear()
        return
    end

    local inventory = player.get_inventory(defines.inventory.character_main)
    local itemstack = "iron-plate"

    while not inventory.is_full() do
        inventory.insert(itemstack)
    end

    local success = player.mine_entity(entity, false)

    game.print({"", "normal player success:", success})
end)