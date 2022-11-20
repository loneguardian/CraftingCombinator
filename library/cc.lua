---@meta
---@diagnostic disable

---@alias uint64 integer
---@alias uint integer
---@alias unit_number uint
---@alias uid unit_number

-- Global

---@type CraftingCombinatorGlobal
__crafting_combinator_xeraph__global = nil
---@type CraftingCombinatorGlobal
__crafting_combinator_xeraph_test__global = nil

---@class GlobalCc
---@field data table<uid, CcState>
---@field ordered table<uint, CcState>
---@field inserter_empty_queue table

---@class GlobalRc
---@field data table<uid, RcState>
---@field ordered table<uint, RcState>

---@class GlobalSignals
---@field cache table<uid, SignalsCacheState>

---@class CraftingCombinatorGlobal
---@field delayed_blueprint_tag_state table
---@field cc GlobalCc
---@field rc GlobalRc
---@field signals GlobalSignals
---@field clone_placeholder table
---@field main_uid_by_part_uid table<uid, uid>

-- CC State

---@class AssemblerInventories
---@field input LuaInventory?
---@field output LuaInventory?

---@class CcInventories
---@field module_chest LuaInventory?
---@field chest LuaInventory?
---@field assembler AssemblerInventories

---@class CcSettings
---@field chest_position integer
---@field mode string
---@field wait_for_output_to_clear boolean
---@field discard_items boolean
---@field discard_fluids boolean
---@field empty_inserters boolean
---@field read_recipe boolean
---@field read_speed boolean
---@field read_machine_status boolean
---@field craft_until_zero boolean
---@field craft_n_before_switch integer

---@class CcState
---@field entityUID uid Combinator entity's uid
---@field entity LuaEntity Combinator entity
---@field control_behavior LuaControlBehavior? Combinator's control behavior
---@field module_chest LuaEntity Module chest entity associated to this CC
---@field assembler LuaEntity Assembler entity associated to this CC
---@field settings CcSettings CC settings table
---@field inventories CcInventories
---@field items_to_ignore table ???
---@field last_flying_text_tick integer
---@field enabled boolean
---@field last_recipe LuaRecipe|boolean|nil
---@field last_assembler_recipe LuaRecipe|boolean|nil
---@field read_mode_cb boolean
---@field sticky boolean
---@field allow_sticky boolean
---@field unstick_at_tick integer
---@field update function Method to update CC state
---@field find_assembler function
---@field find_chest function

-- RC State

---@alias RcMode
---| 'ing' Find ingredients
---| 'mac' Find machines
---| 'prod' Find products
---| 'rec' Find recipe
---| 'use' Find uses

---@class RcSettings
---@field mode RcMode,
---@field multiply_by_input boolean
---@field divide_by_output boolean
---@field differ_output boolean
---@field time_multiplier number

---@class RcState
---@field entityUID uid Combinator entity's uid
---@field entity LuaEntity Combinator entity
---@field output_proxy LuaEntity
---@field control_behavior LuaControlBehavior
---@field input_control_behavior LuaControlBehavior
---@field settings RcSettings
---@field last_signal string|false
---@field last_name string|false
---@field last_count int|false

-- Signals Cache

---@class CacheEntities
---@field highest LuaEntity
---@field highest_present LuaEntity
---@field highest_count LuaEntity
---@field signal_present LuaEntity

---@class CacheCb
---@field __cb LuaLampControlBehavior
---@field valid boolean
---@field value CacheValue

---@class CacheValue
---@field signal SignalID

---@class SignalsCacheState
---@field __entity LuaEntity
---@field __circuit_id defines.circuit_connector_id
---@field __cache_entities CacheEntities
---@field highest CacheCb
---@field highest_present CacheCb
---@field highest_count CacheCb
---@field signal_present CacheCb