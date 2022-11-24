-- randomString()
-- source: https://gist.github.com/haggen/2fd643ea9a261fea2094

local charset = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890"
local upper_bound = #charset
---Generates a random string
---@param length uint
---@return string|nil
local function randomString(length)
    if length <= 0 then return end
	local ret = {}
	local r
	for i = 1, length do
		r = math.random(1, upper_bound)
		ret[#ret + 1] = charset:sub(r, r)
	end
	return table.concat(ret)
end

-- deepcopy function adapted from factorio lualib
---@param object table
---@param skip_metatable? true `true` to bypass `setmetatable()`
---@return table
local function deepcopy(object, skip_metatable)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
            -- don't copy factorio rich objects
        elseif object.__self then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        if skip_metatable then
            return new_table
        else
            return setmetatable(new_table, getmetatable(object))
        end
    end

    return _copy(object)
end


return {
    randomString = randomString,
	deepcopy = deepcopy
}