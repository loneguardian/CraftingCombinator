local config = require 'config'
local areas = require("__testorio__.testUtil.areas")
local test_area = areas.test_area
local surface, area
local player

before_all(function()
    player = game.get_player(1)
    surface, area = test_area(1, "entity-test")

    -- clear area
    local entities = surface.find_entities(area)
    for i = 1, #entities do
        entities[i].destroy()
    end

    -- TODO: exit editor mode
end)

describe("Entity test - CC", function()
    local build_position
    before_all(function()
        -- readjust coordinate
        build_position = {
            x = area.left_top.x+0.5,
            y = area.left_top.y+0.5
        }
    end)

    local build_cc = function()
        player.cursor_stack.set_stack({name=config.CC_NAME})
        player.build_from_cursor{position=build_position}
    end

    describe("build CC", function()
        test("Build CC", function()
            -- build
            build_cc()

            -- find entity
            local entity = surface.find_entity(config.CC_NAME, build_position)
            assert.is_true(entity ~= nil)

            -- check state data
            local global_data = global.cc.data
            local uid = entity.unit_number
            assert.is_true(entity.valid)
            assert.are.equal(uid, global_data[uid].entityUID)
        end)
    end)

    describe("destroy CC", function()
        local entity
        before_each(function()
            -- make sure cc is there
            entity = surface.find_entity(config.CC_NAME, build_position)
            if not entity then
                build_cc()
                entity = surface.find_entity(config.CC_NAME, build_position)
            end
        end)

        test("Player mine CC - Empty Inventory", function()
            local success = player.mine_entity(entity)

            -- mined successfully?
            assert.is_true(success)

            -- check global data

            -- check main_uid_by_part_uid
        end)

        test("Player mine CC - Full Inventory", function()
            -- make sure inventory is full
            
            local success = player.mine_entity(entity)

            -- mined successfully?
            assert.is_true(success)

            -- check global data


            -- check main_uid_by_part_uid
        end)
    end)

    -- TODO: handle surface cleared, surface deleted
end)