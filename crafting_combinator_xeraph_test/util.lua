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

return {
    randomString = randomString
}