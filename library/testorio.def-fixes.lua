---@meta
---@diagnostic disable

-- describe/test.each()

---@class TestCreatorBase
local test

---@generic T
---@param values `T`[][]
---@param name string
---@param func fun(...:T)
---@return TestBuilder<fun(...:T)>
function test.each(values, name, func) end

---@generic T
---@param values `T`[]
---@param name string
---@param func fun(v: T)
---@return TestBuilder<fun(v: T)>
function test.each(values, name, func) end

---@generic T
---@param values `T`[][]
---@return fun(name: string, func: fun(...:T))
function test.each(values) end

---@generic T
---@param values `T`[]
---@return fun(name: string, func: fun(v: T))
function test.each(values) end


---@class DescribeCreatorBase
local describe

---@generic T
---@param values `T`[][]
---@param name string
---@param func fun(...:T)
function describe.each(values, name, func) end

---@generic T
---@param values `T`[]
---@param name string
---@param func fun(v: T)
function describe.each(values, name, func) end

---@generic T
---@param values `T`[][]
---@return fun(name: string, func: fun(...:T))
function describe.each(values) end

---@generic T
---@param values `T`[]
---@return fun(name: string, func: fun(v: T))
function describe.each(values) end


-- TestUtil
-- test_areas

---@class TestUtilAreas
---Behaves similarly to `enable_all`, but also checks that all entities were previously disabled.
---This ensures that no entities were active before the test is run,
---possibly causing inconsistent behavior if other tests that take multiple ticks were run before.
---@field test_area fun(surface_index: uint, surface_name: string): LuaSurface, BoundingBox
---@field enable_all TestUtilAreasToggle
---@field disable_all TestUtilAreasToggle

---Enable or disable all entities (set active to true or false) in a given area on a surface.
---The area can be specified either with a BoundingBox or with the name/id of a script area (script areas can be created in the map editor).
---Returns the resulting lua surface and bounding box, as two return values.
---@alias TestUtilAreasToggle fun(surface: SurfaceIdentification, area: BoundingBox | string | number): (LuaSurface, BoundingBox)