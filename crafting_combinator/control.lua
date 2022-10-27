require 'script.bootstrap'

local config = require 'config'
local cc_control = require 'script.cc'
local rc_control = require 'script.rc'
local signals = require 'script.signals'
local util = require 'script.util'
local gui = require 'script.gui'
local blueprint = require 'script.blueprint'


local cc_rate, rc_rate = 1, 1

local function init_global()
	global.delayed_blueprint_tag_state = {}
	global.dead_combinator_settings = {}
end

local function enable_recipes()
	for _, force in pairs(game.forces) do
		if force.technologies['circuit-network'].researched then
			force.recipes[config.CC_NAME].enabled = true
			force.recipes[config.RC_NAME].enabled = true
		end
	end
end

local function on_load(forced)
	if not forced and next(late_migrations.__migrations) ~= nil then return; end
	
	cc_control.on_load()
	rc_control.on_load()
	signals.on_load()
	cc_rate = settings.global[config.REFRESH_RATE_CC_NAME].value
	rc_rate = settings.global[config.REFRESH_RATE_RC_NAME].value
	
	if remote.interfaces['PickerDollies'] then
		script.on_event(remote.call('PickerDollies', 'dolly_moved_entity_id'), function(event)
			local entity = event.moved_entity
			local combinator
			if entity.name == config.CC_NAME then combinator = global.cc.data[entity.unit_number]
			elseif entity.name == config.RC_NAME then combinator = global.rc.data[entity.unit_number]; end
			if combinator then combinator:update_inner_positions(); end
		end)
	end
end

script.on_init(function()
	cc_control.init_global()
	rc_control.init_global()
	signals.init_global()
	init_global()
	on_load(true)
end)
script.on_load(on_load)

script.on_configuration_changed(function(changes)
	late_migrations(changes)
	on_load(true)
	enable_recipes()
end)

local function on_built(event)
	local entity = event.created_entity or event.entity
	if not (entity and entity.valid) then return end

	local entity_name = entity.name
	if entity_name == config.CC_NAME then
		cc_control.create(entity);
	elseif entity_name == config.RC_NAME then
		rc_control.create(entity);
	else
		local entity_type = entity.type
		if entity_type == 'assembling-machine' then
			cc_control.update_assemblers(entity.surface, entity);
		else -- util.CONTAINER_TYPES[entity.type]
			cc_control.update_chests(entity.surface, entity);
		end
	end

	-- blueprint events
	blueprint.handle_event(event)
end

local function save_dead_combinator_settings(uid, settings)
	-- entry is created during on_entity_died and removed during on_post_entity_died
	global.dead_combinator_settings[uid] = util.deepcopy(settings)
end

local function on_destroyed(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	local entity_name = entity.name
	if entity_name == config.CC_NAME then
		if event.name == defines.events.on_entity_died then
			local uid = entity.unit_number
			save_dead_combinator_settings(uid, global.cc.data[uid].settings)
		end
		if cc_control.destroy(entity, event.player_index) then return; end -- Return if the entity was coppied
	elseif entity_name == config.MODULE_CHEST_NAME then
		return cc_control.destroy_by_robot(entity)
	elseif entity_name == config.RC_NAME then
		if event.name == defines.events.on_entity_died then
			local uid = entity.unit_number
			save_dead_combinator_settings(uid, global.rc.data[uid].settings)
		end
		rc_control.destroy(entity)
	else
		local entity_type = entity.type
		if entity_type == 'assembling-machine' then
			cc_control.update_assemblers(entity.surface, entity, true)
		else -- util.CONTAINER_TYPES[entity.type]
			cc_control.update_chests(entity.surface, entity, true)
		end
	end

	-- Todo: destroy gui before entity is destroyed
end

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
	cc_rate = settings.global[config.REFRESH_RATE_CC_NAME].value
	rc_rate = settings.global[config.REFRESH_RATE_RC_NAME].value
end)

local function run_update(tab, tick, rate)
	for i = tick % (rate + 1) + 1, #tab, (rate + 1) do tab[i]:update(); end
end
script.on_event(defines.events.on_tick, function(event)
	if global.cc.inserter_empty_queue[event.tick] then
		for _, e in pairs(global.cc.inserter_empty_queue[event.tick]) do
			if e.entity.valid and e.assembler and e.assembler.valid then e:empty_inserters(); end
		end
		global.cc.inserter_empty_queue[event.tick] = nil
	end
	
	run_update(global.cc.ordered, event.tick, cc_rate)
	run_update(global.rc.ordered, event.tick, rc_rate)
end)

script.on_event(defines.events.on_player_rotated_entity, function(event)
	if event.entity.name == config.CC_NAME then
		local combinator = global.cc.data[event.entity.unit_number]
		combinator:find_assembler()
		combinator:find_chest()
	end
end)

script.on_event(defines.events.on_entity_settings_pasted, function(event)
	local source, destination
	if event.source.name == config.CC_NAME and event.destination.name == config.CC_NAME then
		source, destination = global.cc.data[event.source.unit_number], global.cc.data[event.destination.unit_number]
	elseif event.source.name == config.RC_NAME and event.destination.name == config.RC_NAME then
		source, destination = global.rc.data[event.source.unit_number], global.rc.data[event.destination.unit_number]
	else return; end
	
	destination.settings = util.deepcopy(source.settings)
	if destination.entity.name == config.RC_NAME then destination:update(true)
	elseif destination.entity.name == config.CC_NAME then destination:copy(source); end
end)

-- filter for built and destroyed events
local filter_built_destroyed = {}

-- filter: cc or rc
table.insert(filter_built_destroyed, {filter = "name", name = config.CC_NAME})
table.insert(filter_built_destroyed, {filter = "name", name = config.RC_NAME})

-- filter: module-chest
table.insert(filter_built_destroyed, {filter = "name", name = config.MODULE_CHEST_NAME})

-- filter: assembling-machine
table.insert(filter_built_destroyed, {filter = "type", type = 'assembling-machine'})

-- filter: containers
for container, _ in pairs(util.CONTAINER_TYPES) do
	table.insert(filter_built_destroyed, {filter = "type", type = container})
end

-- entity built events
script.on_event(defines.events.on_built_entity, on_built, filter_built_destroyed)
script.on_event(defines.events.on_robot_built_entity, on_built, filter_built_destroyed)
script.on_event(defines.events.script_raised_built, on_built, filter_built_destroyed)
script.on_event(defines.events.script_raised_revive, on_built, filter_built_destroyed)

-- entity destroyed events
script.on_event(defines.events.on_pre_player_mined_item, on_destroyed, filter_built_destroyed)
script.on_event(defines.events.on_robot_pre_mined, on_destroyed, filter_built_destroyed)
script.on_event(defines.events.script_raised_destroy, on_destroyed, filter_built_destroyed)
script.on_event(defines.events.on_entity_died, on_destroyed, filter_built_destroyed)

-- additional blueprint events
script.on_event(defines.events.on_player_setup_blueprint, blueprint.handle_event)
script.on_event(defines.events.on_post_entity_died, blueprint.handle_event)

-- decontruction events
script.on_event(defines.events.on_marked_for_deconstruction, function(event)
	if event.entity.name == config.CC_NAME then cc_control.fix_undo_deconstruction(event.entity, event.player_index); end
	if event.entity.name == config.MODULE_CHEST_NAME then cc_control.mark_for_deconstruction(event.entity); end
end)
script.on_event(defines.events.on_cancelled_deconstruction, function(event)
	if event.entity.name == config.MODULE_CHEST_NAME then cc_control.cancel_deconstruction(event.entity); end
end)
script.on_event(defines.events.on_pre_ghost_deconstructed, function(event)
	event.entity = event.ghost
	on_destroyed(event)
end)

-- GUI events
script.on_event(defines.events.on_gui_opened, function(event)
	local entity = event.entity
	if entity then
		if entity.name == config.CC_NAME then global.cc.data[entity.unit_number]:open(event.player_index); end
		if entity.name == config.RC_NAME then global.rc.data[entity.unit_number]:open(event.player_index); end
	end
end)
script.on_event(defines.events.on_gui_closed, function(event)
	local element = event.element
	if element and element.valid and element.name and element.name:match('^crafting_combinator:') then
		element.destroy()
	end

	-- blueprint gui
	blueprint.handle_event(event)
end)
script.on_event(defines.events.on_gui_checked_state_changed, function(event)
	local element = event.element
	if element and element.valid and element.name and element.name:match('^crafting_combinator:') then
		local gui_name, unit_number, element_name = gui.parse_entity_gui_name(element.name)
		
		if gui_name == 'crafting-combinator' then
			global.cc.data[unit_number]:on_checked_changed(element_name, element.state, element)
		end
		if gui_name == 'recipe-combinator' then
			global.rc.data[unit_number]:on_checked_changed(element_name, element.state, element)
		end
	end
end)
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
	local element = event.element
	if element and element.valid and element.name and element.name:match('^crafting_combinator:') then
		local gui_name, unit_number, element_name = gui.parse_entity_gui_name(element.name)
		if gui_name == 'crafting-combinator' then
			global.cc.data[unit_number]:on_selection_changed(element_name, element.selected_index)
		end
	end
end)
script.on_event(defines.events.on_gui_text_changed, function(event)
	local element = event.element
	if element and element.valid and element.name and element.name:match('^crafting_combinator:') then
		local gui_name, unit_number, element_name = gui.parse_entity_gui_name(element.name)
		if gui_name == 'recipe-combinator' then
			global.rc.data[unit_number]:on_text_changed(element_name, element.text)
		elseif gui_name == 'crafting-combinator' then
			global.cc.data[unit_number]:on_text_changed(element_name, element.text)
		end
	end
end)
script.on_event(defines.events.on_gui_click, function(event)
	local element = event.element
	if element and element.valid and element.name and element.name:match('^crafting_combinator:') then
		local gui_name, unit_number, element_name = gui.parse_entity_gui_name(element.name)
		if gui_name == 'crafting-combinator' then
			global.cc.data[unit_number]:on_click(element_name, element)
		end
	end
end)