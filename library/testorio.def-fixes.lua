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
---@field test_area fun(surface_index: uint, surface_name: string): LuaSurface, BoundingBox