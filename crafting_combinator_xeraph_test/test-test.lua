local config = require "config"

local cursor
local surface
local build_position = {x=0.5,y=0.5}
--local entity_name = "constant-combinator"
local entity_name = config.CC_NAME
local entity

before_all(function()
    local player = game.players[1]
    surface = player.surface
    cursor = player.cursor_stack
    cursor.set_stack({name=entity_name, count = 1})

    entity = surface.find_entity(entity_name, build_position)
    game.print({"",entity ~= nil,"1"})
    
    player.build_from_cursor{position=build_position}

    entity = surface.find_entity(entity_name, build_position)
    game.print({"",entity ~= nil,"2"})
end)

after_all(function()
    if cursor then cursor.clear() end
    if entity then entity.destroy() end
end)

test("TEST LA", function()
    assert.is_false(cursor.valid_for_read)
end)