local config = require 'config'
local areas = require("__testorio__.testUtil.areas") --[[@as TestUtilAreas]]

local test_area = areas.test_area

local main_entity_name = config.RC_NAME
local part_entity_name = config.RC_PROXY_NAME

-- upvalues

local surface, area
local build_position
local player
local cursor
local global_data

before_all(function()
    surface, area = test_area(1, "entity-test")
    -- readjust coordinate
    build_position = {
        x = area.left_top.x+0.5,
        y = area.left_top.y+0.5
    }
    player = game.get_player(1)
    cursor = player.cursor_stack
    global_data = global.rc.data

    -- TODO: exit editor mode
end)

after_each(function()
    if cursor then cursor.clear() end
    local entities = surface.find_entities(area)
    for i=1,#entities do
        entities[i].destroy()
    end
end)

local build_entity = function()
    cursor.set_stack({name=main_entity_name, count = 1})

    -- local entities = surface.find_entities(area)
    -- game.print({"", surface.find_entity(config.CC_NAME, build_position) ~= nil, "1"})

    player.build_from_cursor{position=build_position}

    -- entities = surface.find_entities(area)
    -- game.print({"", surface.find_entity(config.CC_NAME, build_position) ~= nil, "2"})
end

local rc_entity, output_proxy
local main_uid, part_uid

before_each(function()
    build_entity()
    local entities = surface.find_entities(area)
    for i=1,#entities do
        if entities[i].name == main_entity_name then
            rc_entity = entities[i]
            main_uid = rc_entity.unit_number
        elseif entities[i].name == part_entity_name then
            output_proxy = entities[i]
            part_uid = output_proxy.unit_number
        end
    end
end)

test("build RC", function()
    -- check if item in cursor was spent to build
    assert.is_false(cursor.valid_for_read)

    -- find entity
    assert.is_truthy(rc_entity)

    -- check state data
    assert.is_true(rc_entity.valid)
    assert.are_equal(main_uid, global_data[main_uid].entityUID)
end)

describe("destroy RC", function()
    local inventory
    before_all(function()
        inventory = player.get_inventory(defines.inventory.character_main)
    end)
    after_each(function()
        inventory.clear()
    end)
    test("Player mine RC - empty inventory - success", function()
        -- check if item in cursor was spent to build
        assert.is_false(cursor.valid_for_read)

        -- clear inventory
        inventory.clear()

        player.mine_entity(rc_entity)

        -- check inventory
        assert.are_equal(inventory.get_item_count(main_entity_name), 1)

        -- check global data
        assert.is_nil(rawget(global_data, main_uid))

        -- check main_uid_by_part_uid
        assert.is_nil(global.main_uid_by_part_uid[part_uid])
    end)

    test("Player mine RC - full Inventory - fail", function()
        -- check if item in cursor was spent to build
        assert.is_false(cursor.valid_for_read)

        -- make sure inventory is full
        local itemstack = "iron-plate"
        local inv_size = #inventory
        for i=1,inv_size do
            inventory[i].set_stack(itemstack)
        end
        
        player.mine_entity(rc_entity)

        -- check cursor
        assert.is_false(cursor.valid_for_read)

        -- check inventory
        assert.are_equal(inventory.get_item_count(main_entity_name), 0)

        -- check global data
        assert.is_nil(rawget(global_data, main_uid))
    end)
end)

-- TODO: handle surface cleared, surface deleted