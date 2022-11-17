---@meta
---@diagnostic disable

---@alias uint integer
---@alias unit_number uint
---@alias uid unit_number

-- CC State

---@class AssemblerInventories
---@field input LuaInventory?
---@field output LuaInventory?

---@class CcInventories
---@field module_chest LuaInventory?
---@field chest LuaInventory?
---@field assembler AssemblerInventories

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

-- Signals Cache

---@class CacheEntities
---@field highest LuaEntity
---@field highest_present LuaEntity
---@field highest_count LuaEntity
---@field signal_present LuaEntity

---@class CacheCb
---@field _cb LuaControlBehavior
---@field valid boolean
---@field value CacheValue

---@class CacheValue
---@field signal CacheSignal

---@class CacheSignal
---@field type string
---@field name string

---@class SignalsCacheState
---@field __entity LuaEntity
---@field __circuit_id defines.circuit_connector_id
---@field __cache_entities CacheEntities
---@field highest CacheCb
---@field highest_present CacheCb
---@field highest_count CacheCb
---@field signal_present CacheCb