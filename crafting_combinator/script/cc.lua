local util = require 'script.util'
local gui = require 'script.gui'
local recipe_selector = require 'script.recipe-selector'
local config = require 'config'
local signals = require 'script.signals'

local table = table

local _M = {}
local combinator_mt = {__index = _M}


local CHEST_POSITION_NAMES = {'behind', 'left', 'right', 'behind-left', 'behind-right'}
local CHEST_POSITIONS = {}; for key, name in pairs(CHEST_POSITION_NAMES) do CHEST_POSITIONS[name] = key; end
local CHEST_DIRECTIONS = {
	[CHEST_POSITIONS.behind] = 180,
	[CHEST_POSITIONS.right] = 90,
	[CHEST_POSITIONS.left] = -90,
	[CHEST_POSITIONS['behind-right']] = 135,
	[CHEST_POSITIONS['behind-left']] = -135,
}

local STATUS_SIGNALS = {}
for name, signal in pairs(config.MACHINE_STATUS_SIGNALS) do
	if defines.entity_status[name] then
		STATUS_SIGNALS[defines.entity_status[name]] = signal
	end
end

-- General housekeeping

function _M.init_global()
	global.cc = global.cc or {}
	global.cc.data = global.cc.data or {}
	global.cc.ordered = global.cc.ordered or {}
	global.cc.inserter_empty_queue = {}
end

function _M.on_load()
	for _, combinator in pairs(global.cc.data) do setmetatable(combinator, combinator_mt); end
end


-- Lifecycle events

function _M.create(entity)
	local combinator = setmetatable({
		entityUID = entity.unit_number,
		entity = entity,
		control_behavior = entity.get_or_create_control_behavior(),
		module_chest = entity.surface.create_entity {
			name = config.MODULE_CHEST_NAME,
			position = entity.position,
			force = entity.force,
			create_build_effect_smoke = false,
		},
		settings = util.deepcopy(config.CC_DEFAULT_SETTINGS),
		inventories = {},
		items_to_ignore = {},
		last_flying_text_tick = -config.FLYING_TEXT_INTERVAL,
		enabled = true,
		last_recipe = false,
		last_assembler_recipe = false,
		read_mode_cb = false,
		sticky = false,
		allow_sticky = true,
		craft_n_before_switch = {
			unstick_at_tick = 0
		}
	}, combinator_mt)
	
	combinator.module_chest.destructible = false
	combinator.inventories.module_chest = combinator.module_chest.get_inventory(defines.inventory.chest)
	
	global.cc.data[entity.unit_number] = combinator
	table.insert(global.cc.ordered, combinator)
	combinator:find_assembler()
	combinator:find_chest()
	
	-- Other combinators can use the module chest as overflow output, so let them know it's there
	_M.update_chests(entity.surface, combinator.module_chest)
end

function _M.mark_for_deconstruction(entity)
	local combinator = global.cc.data[entity.surface.find_entity(config.CC_NAME, entity.position).unit_number]
	combinator.enabled = false
	combinator:update()
end
function _M.cancel_deconstruction(entity)
	local combinator = global.cc.data[entity.surface.find_entity(config.CC_NAME, entity.position).unit_number]
	combinator.enabled = true
	combinator:update()
end
function _M.fix_undo_deconstruction(entity, player_index)
	local combinator = global.cc.data[entity.unit_number]
	local player = player_index and game.get_player(player_index)
	local force = player and player.force or entity.force
	entity.cancel_deconstruction(force, player)
	combinator.module_chest.order_deconstruction(force, player)
end

function _M.destroy_by_robot(entity)
	local combinator_entity = entity.surface.find_entity(config.CC_NAME, entity.position)
	if not combinator_entity then return; end
	_M.destroy(combinator_entity)
	combinator_entity.destroy()
end

function _M.destroy(entity)
	local unit_number = entity.unit_number
	local combinator = global.cc.data[unit_number]

	-- Todo: destroy gui before cc/rc data is destroyed

	combinator.module_chest.destroy();
	signals.cache.drop(unit_number)
	
	global.cc.data[unit_number] = nil
	for k, v in pairs(global.cc.ordered) do
		if v.entityUID == unit_number then
			table.remove(global.cc.ordered, k)
			break
		end
	end
end

function _M.mine_module_chest(unit_number, player_index)
	if player_index then
		local player = game.get_player(player_index)
		local combinator = global.cc.data[unit_number]
		local success = player.mine_entity(combinator.module_chest)
		if success then
			return success
		else
			-- Clone the combinator entity as replacement
			local old_entity = combinator.entity
			combinator.entity = old_entity.clone{position = old_entity.position, create_build_effect_smoke = false}
			combinator.control_behavior = combinator.entity.get_or_create_control_behavior()

			-- Replace the entity if a player was trying to pick it up
			local new_uid = combinator.entity.unit_number
			global.cc.data[unit_number] = nil
			global.cc.data[new_uid] = combinator
			combinator.entityUID = new_uid

			for _, connection in pairs(old_entity.circuit_connection_definitions) do
				combinator.entity.connect_neighbour(connection)
			end

			old_entity.destroy()
		end
	end
end

function _M.update_assemblers(surface, assembler, ignore)
	local combinators = surface.find_entities_filtered {
		area = util.area(assembler.prototype.selection_box):expand(config.ASSEMBLER_SEARCH_DISTANCE) + assembler.position,
		name = config.CC_NAME,
	}
	for _, entity in pairs(combinators) do global.cc.data[entity.unit_number]:find_assembler(ignore and assembler or nil); end
end

function _M.update_chests(surface, chest, ignore)
	local combinators = surface.find_entities_filtered {
		area = util.area(chest.prototype.selection_box):expand(config.CHEST_SEARCH_DISTANCE) + chest.position,
		name = config.CC_NAME,
	}
	for _, entity in pairs(combinators) do global.cc.data[entity.unit_number]:find_chest(ignore and chest or nil); end
end

local params = {data = {}}
function params:clear()
	for i = 1, #self.data do self.data[i] = nil end
end

function _M:update()
	if self.enabled and self.assembler and self.assembler.valid then
		self.assembler.active = true

		if self.settings.mode == 'w' then
			if self.read_mode_cb then
				params:clear()
				self.control_behavior.parameters = params.data
				self.read_mode_cb = false
			end
			self:set_recipe()
		--elseif self.settings.mode == 'r' then
		else
			self.read_mode_cb = true
			params:clear()
			if self.settings.read_recipe then self:read_recipe(params.data); end
			if self.settings.read_speed then self:read_speed(params.data); end
			if self.settings.read_machine_status then self:read_machine_status(params.data); end
			-- TODO: add setting for read_machine_crafting_progress
			self.control_behavior.parameters = params.data
		end
	end
end


function _M:open(player_index)
	local root = gui.entity(self.entity, {
		title_elements = {
			gui.button('open-module-chest'),
			gui.dropdown('chest-position', CHEST_POSITION_NAMES, self.settings.chest_position, {tooltip=true}),
		},
		
		gui.section {
			name = 'mode',
			gui.radio('w', self.settings.mode, {locale='mode-write', tooltip=true}),
			gui.radio('r', self.settings.mode, {locale='mode-read', tooltip=true}),
		},
		gui.section {
			name = 'misc',
			gui.checkbox('wait-for-output-to-clear', self.settings.wait_for_output_to_clear, {tooltip = true}),
			gui.checkbox('discard-items', self.settings.discard_items),
			gui.checkbox('discard-fluids', self.settings.discard_fluids),
			gui.checkbox('empty-inserters', self.settings.empty_inserters),
			gui.checkbox('read-recipe', self.settings.read_recipe),
			gui.checkbox('read-speed', self.settings.read_speed),
			gui.checkbox('read-machine-status', self.settings.read_machine_status),
		},
		gui.section {
			name = 'sticky',
			gui.checkbox('craft-until-zero', self.settings.craft_until_zero, {tooltip = true}),
			gui.number_picker('craft-n-before-switch', self.settings.craft_n_before_switch)
		}
	}):open(player_index)
	
	self:update_disabled_checkboxes(root)
	self:update_disabled_textboxes(root)
end

function _M:on_checked_changed(name, state, element)
	local category, name = name:gsub(':.*$', ''), name:gsub('^.-:', ''):gsub('-', '_')
	if category == 'mode' then
		self.settings.mode = name
		for _, el in pairs(element.parent.children) do
			if el.type == 'radiobutton' then
				local _, _, el_name = gui.parse_entity_gui_name(el.name)
				el.state = el_name == 'mode:'..name
			end
		end
	end
	if category == 'misc' or category == 'sticky' then self.settings[name] = state; end
	if name == 'craft_until_zero' and self.settings.craft_until_zero then
		self.last_recipe = nil
	end
	
	self:update_disabled_checkboxes(gui.get_root(element))
	self:update_disabled_textboxes(gui.get_root(element))
end

function _M:on_text_changed(name, text)
	if name == 'sticky:craft-n-before-switch:value' then
		self.sticky = false
		self.settings.craft_n_before_switch = tonumber(text) or self.settings.craft_n_before_switch
	end
end

function _M:update_disabled_checkboxes(root)
	self:disable_checkbox(root, 'misc:discard-items', 'w')
	self:disable_checkbox(root, 'misc:discard-fluids', 'w')
	self:disable_checkbox(root, 'misc:empty-inserters', 'w')
	self:disable_checkbox(root, 'sticky:craft-until-zero', 'w')
	self:disable_checkbox(root, 'misc:wait-for-output-to-clear', 'w')
	self:disable_checkbox(root, 'misc:read-recipe', 'r')
	self:disable_checkbox(root, 'misc:read-speed', 'r')
	self:disable_checkbox(root, 'misc:read-machine-status', 'r')
end

function _M:update_disabled_textboxes(root)
	self:disable_textbox(root, 'sticky:craft-n-before-switch', 'w')
end

function _M:disable_checkbox(root, name, mode)
	local checkbox = gui.find_element(root, gui.name(self.entity, name))
	checkbox.enabled = self.settings.mode == mode
end

function _M:disable_textbox(root, name, mode)
	local caption = gui.find_element(root, gui.name(self.entity, name, "caption"))
	local textbox = gui.find_element(root, gui.name(self.entity, name, "value"))

	if caption and caption.valid then
		caption.enabled = self.settings.mode == mode
	end

	if textbox and textbox.valid then
		textbox.enabled = self.settings.mode == mode
	end
end

function _M:on_selection_changed(name, selected)
	if name == 'title:chest-position:value' then
		self.settings.chest_position = selected
		self:find_chest()
	end
end

function _M:on_click(name, element)
	if name == 'title:open-module-chest' then
		game.get_player(element.player_index).opened = self.module_chest
	end
end


-- Other stuff

function _M:read_recipe(params)
	local recipe = self.assembler.get_recipe()
	if recipe then
		table.insert(params, {
			signal = recipe_selector.get_signal(recipe.name),
			count = 1,
			index = 1,
		})
	end
end

function _M:read_speed(params)
	local count = self.assembler.crafting_speed * 100
	table.insert(params, {
		signal = {type = 'virtual', name = config.SPEED_SIGNAL_NAME},
		count = count,
		index = 2,
	})
end

function _M:read_machine_status(params)
	local signal = STATUS_SIGNALS[self.assembler.status or "A dummy string to avoid indexing by nil"]
	if signal == nil then return end
	table.insert(params, {
		signal = {type = 'virtual', name = signal},
		count = 1,
		index = 3,
	})
end

function _M:set_recipe()
	-- Check sticky state and return early if still sticky
	if self.sticky then
		-- craft-n-before-switch
		if game.tick >= self.craft_n_before_switch.unstick_at_tick then
			self.sticky = false
			self.allow_sticky = false
		else
			return true
		end
	end

	-- Update/get cc recipe
	local changed, recipe
	if self.settings.craft_until_zero then
		if not self.last_recipe or not signals.signal_present(self.entity, nil, self.entityUID) then
			local highest = signals.watch_highest_presence(self.entity, nil, self.entityUID)
			if highest then recipe = self.entity.force.recipes[highest.signal.name]
			else recipe = nil; end
			self.last_recipe = recipe
		else recipe = self.last_recipe; end
	else
		changed, recipe = recipe_selector.get_recipe(self.entity, nil, self.last_recipe and self.last_recipe.name, nil, self.entityUID)
		if changed then
			self.last_recipe = recipe
		else
			recipe = self.last_recipe
		end
	end
	
	if recipe and (recipe.hidden or not recipe.enabled) then recipe = nil; end

	-- If no recipe selected and no last_assembler_recipe cached then return. This bypasses the need
	-- to call get_recipe() for every update. However, manually set assemblers when no recipe is
	-- selected will not be automatically cleared by cc due to this return behaviour.
	if (not recipe) and (not self.last_assembler_recipe) then return true end
	
	-- Get current assembler recipe
	local assembler = self.assembler
	local current_assembler_recipe = assembler.get_recipe()

	-- If selected recipe is same as current_assembler_recipe then return
	if (recipe == current_assembler_recipe) then return true end
	
	-- Tag to indicate a new recipe has to be set, false indicates recipe has to be cleared
	local assembler_has_recipe = false

	-- set_recipe() decision proper:
	-- Switch 1: Assembler has a current recipe, and requires a change of recipe or clearing of recipe
	if current_assembler_recipe and ((not recipe) or (recipe ~= current_assembler_recipe)) then

		-- Check craft-n-before-switch
		if self.allow_sticky and self.settings.craft_n_before_switch > 0 then
			-- calculate unstick_at_tick
			local ticks_per_craft = current_assembler_recipe.energy * 60 / assembler.crafting_speed
			local progress_remaining = 1 - assembler.crafting_progress
			local full_craft_count = self.settings.craft_n_before_switch - 1

			local delay = math.ceil((progress_remaining + full_craft_count) * ticks_per_craft)
			
			self.craft_n_before_switch.unstick_at_tick = game.tick + delay
			self.sticky = true
			return true
		end

		if recipe then assembler_has_recipe = true end

		-- Move items if necessary
		local success, error = self:move_items()

		if not success then return self:on_chest_full(error); end

		if self.settings.empty_inserters then
			success, error = self:empty_inserters()
			if not success then return self:on_chest_full(error); end
			
			local tick = game.tick + config.INSERTER_EMPTY_DELAY
			global.cc.inserter_empty_queue[tick] = global.cc.inserter_empty_queue[tick] or {}
			table.insert(global.cc.inserter_empty_queue[tick], self)
		end
		
		-- Clear fluidboxes
		if self.settings.discard_fluids then
			for i=1, #self.assembler.fluidbox do self.assembler.fluidbox[i] = nil; end
		end

		-- Move modules if necessary
		if recipe then self:move_modules(recipe); end

	-- Switch 2: Assembler does not have a recipe, and requires setting a new recipe
	elseif (not current_assembler_recipe) and recipe then
		assembler_has_recipe = true
	end

	-- Finally attempt to switch/clear the recipe
	self.assembler.set_recipe(recipe)

	-- Check if assembler successfully switched recipe
	local new_assembler_recipe = self.assembler.get_recipe()
		
	if new_assembler_recipe and new_assembler_recipe ~= recipe then
		self.assembler.set_recipe(nil) -- failsafe for setting the wrong/forbidden recipe??
		--TODO: Some notification?
		self.last_assembler_recipe = false
	else
		self.last_assembler_recipe = new_assembler_recipe
	end
	
	if assembler_has_recipe then
		-- Move modules and items back into the machine
		self:insert_modules()
		self:insert_items()
	end

	self.allow_sticky = true
	
	return true
end

function _M:move_modules(recipe)
	local target = self.inventories.module_chest
	local inventory = self.inventories.assembler.modules
	for i = 1, #inventory do
		local stack = inventory[i]
		if stack.valid_for_read then
			local limitations = util.module_limitations()[stack.name]
			--TODO: Deal with not enough space in the chest
			if limitations and not limitations[recipe.name] then
				local r = target.insert(stack)
				if r < stack.count then
					stack.count = stack.count - r
				else
					stack.clear()
				end
			end
		end
	end
end

function _M:insert_modules()
	local inventory = self.inventories.module_chest
	if inventory.is_empty() then return; end
	local target = self.inventories.assembler.modules
	
	for i = 1, #inventory do
		local stack = inventory[i]
		if stack.valid_for_read then
			local r = target.insert(stack)
			if r < stack.count then stack.count = stack.count - r
			else stack.clear(); end
		end
	end
end

function _M:insert_items()
	local inventory = self.inventories.chest
	if not inventory or not inventory.valid or inventory.is_empty() then return; end
	local target = self.inventories.assembler.input
	
	for i = 1, #inventory do
		local stack = inventory[i]
		if stack.valid_for_read then
			local r = target.insert(stack)
			if r < stack.count then stack.count = stack.count - r
			else stack.clear(); end
		end
	end
end

function _M:move_items()
	if self.settings.wait_for_output_to_clear and not self.inventories.assembler.output.is_empty() then
		return false, 'waiting-for-output'
	end
	
	if self.settings.discard_items then return true; end
	
	local target = self:get_chest_inventory()
	
	-- Compensate for half-finished crafts
	-- Do this first to avoid losing a lot of items
	if self.assembler.crafting_progress > 0 then
		local success = true
		for _, ing in pairs(self.assembler.get_recipe().ingredients) do
			if ing.type == 'item' then
				if not target then return false, 'no-chest'; end
				local r = target.insert{name = ing.name, count = ing.amount}
				if r < ing.amount then success = false; end
			end
		end
		self.assembler.crafting_progress = 0
		if not success then return false, 'chest-full'; end
	end
	
	-- Clear the assembler inventories
	-- This may become somewhat problematic if the input items can be moved, but the output can't, since inserters will
	-- continue to replace the items that were removed. I guess that's up to the player to deal with tho...
	for _, inventory in pairs{self.inventories.assembler.input, self.inventories.assembler.output} do
		for i=1, #inventory do
			local stack = inventory[i]
			if stack.valid_for_read then
				if not target then return false, 'no-chest'; end
				local r = target.insert(stack)
				if r < stack.count then
					stack.count = stack.count - r -- Make sure the items don't get duplicated
					return false, 'chest-full'
				end
				inventory[i].clear()
			end
		end
	end
	
	return true
end

function _M:on_chest_full(error)
	-- Prevent the assembler from crafting any more shit
	self.assembler.active = false
	if game.tick - self.last_flying_text_tick >= config.FLYING_TEXT_INTERVAL then
		self.last_flying_text_tick = game.tick
		self.entity.surface.create_entity {
			name = 'flying-text',
			position = self.entity.position,
			text = {'crafting_combinator_gui.switching-stuck:'..(error or 'chest-full')},
			color = {255, 0, 0},
		}
	end
end

function _M:empty_inserters()
	local target = self:get_chest_inventory()
	
	for _, inserter in pairs(self.assembler.surface.find_entities_filtered {
				area = util.area(self.assembler.prototype.selection_box):expand(config.INSERTER_SEARCH_RADIUS) + self.assembler.position,
				type = 'inserter',
			}) do
		if inserter.drop_target == self.assembler then
			local stack = inserter.held_stack
			if stack.valid_for_read and not self.settings.discard_items then
				if not target then return false, 'no-chest'; end
				local r = target.insert(stack)
				if r < stack.count then
					stack.count = stack.count - r
					return false, 'chest-full'
				end
				stack.clear()
			else stack.clear(); end
		end
	end
	return true
end

function _M:find_assembler(assembler_to_ignore)
	self.assembler = self.entity.surface.find_entities_filtered {
		position = util.position(self.entity.position):shift(self.entity.direction, config.ASSEMBLER_DISTANCE),
		type = 'assembling-machine',
	}[1]
	if self.assembler and (self.assembler == assembler_to_ignore or self.assembler.prototype.fixed_recipe) then
		self.assembler = nil
	end
	
	if self.assembler then
		self.inventories.assembler = {
			output = self.assembler.get_inventory(defines.inventory.assembling_machine_output),
			input = self.assembler.get_inventory(defines.inventory.assembling_machine_input),
			modules = self.assembler.get_inventory(defines.inventory.assembling_machine_modules),
		}
	else self.inventories.assembler = {}; end
end

function _M:find_chest(chest_to_ignore)
	local direction = util.direction(self.entity.direction):rotate(CHEST_DIRECTIONS[self.settings.chest_position])
	self.chest = self.entity.surface.find_entities_filtered {
		position = util.position(self.entity.position):shift(direction, config.CHEST_DISTANCE),
		type = {'container', 'logistic-container'},
	}[1]
	if self.chest == chest_to_ignore then self.chest = nil; end
	self.inventories.chest = self.chest and self.chest.get_inventory(defines.inventory.chest)
end

function _M:get_chest_inventory()
	local inventory = self.inventories.chest
	if not inventory or inventory.valid then return inventory; end
	self:find_chest()
	return self.inventories.chest
end


function _M:update_inner_positions()
	self.module_chest.teleport(self.entity.position)
end


function _M:copy(source)
	self.inventories.module_chest.set_bar(source.inventories.module_chest.get_bar())
end


return _M
