local m = terralib.require("mem")
local util = terralib.require("util")

local TemplatizedEntity = {}

function TemplatizedEntity:new(creationFn)
	local newobj = 
	{
		creationFn = creationFn,
		cache = {}
	}
	setmetatable(newobj, self)
	self.__index = self
	return newobj
end

function TemplatizedEntity:__explicit(...)
	local key = util.stringify(...)
	local val = self.cache[key]
	if not val then
		val = self.creationFn(...)
		self.cache[key] = val
	end
	return val
end

function TemplatizedEntity:__implicit(...)
	local types = {}
	for i=1,select("#",...) do
		table.insert(types, (select(i,...)):gettype())
	end
	local spec = self:__explicit(unpack(types))
	if terralib.isfunction(spec) or
		(terralib.typeof(spec):isstruct() and terralib.typeof(spec).metamethods.__apply) then
		local args = {}
		for i=1,select("#",...) do table.insert(args, (select(i,...))) end
		return `spec([args])
	else
		print(debug.traceback("Inferred templatize specialization but could not call resulting value."))
		error(string.format())
	end
end

-- Apply is like implicit, but for calling the specialized
-- function from Lua code.
function TemplatizedEntity:apply(...)
	local types = {}
	for i=1,select("#",...) do
		table.insert(types, terralib.typeof(select(i,...)))
	end
	local spec = self:__explicit(unpack(types))
	return m.gc(spec(...))
end

function TemplatizedEntity:__call(...)
	return self:__explicit(...)
end

local function templatize(creationFn)
	local tent = TemplatizedEntity:new(creationFn)

	-- The templatized function takes types as arguments
	--    and explicitly returns the specialized result for those types
	local explicit = tent

	-- It is also possible to call the function on values, for which
	--    the types will be inferred and the specialization retrieved
	--    implicitly.
	-- NOTE: This only works if there is one template type for each argument,
	--   and the argument types match the template types.
	local implicit = macro(function(...)
		return tent:__implicit(...)
	end)

	-- You can switch between these two options freely
	explicit.explicit = explicit
	implicit.explicit = explicit
	explicit.implicit = implicit
	implicit.implicit = implicit


	-- We default to the explicit version
	return explicit
end

return templatize