
local function stringifyTypeList(...)
	local str = ""
	for i=1,select("#", ...) do
		local t = (select(i, ...))
		if not terralib.types.istype(t) then
			print(debug.traceback())
			error(string.format("Argument %d to 'templatize' is not a type!", i))
		end
		local tostr = t.__tostring
		getmetatable(t).__tostring = nil
		local mystr = tostring(t):gsub("table: ", "")
		getmetatable(t).__tostring = tostr
		str = string.format("%s%s,", str, mystr)
	end
	return str
end

local function templatize(creationFn)
	local Template = { cache = {} }
	setmetatable(Template,
	{
		__call = function(self, ...)	
			local key = stringifyTypeList(...)
			local val = self.cache[key]
			if not val then
				val = creationFn(...)
				self.cache[key] = val
			end
			return val
		end,
	})
	return Template
end

return templatize