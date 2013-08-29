
local cstdlib = terralib.includec("stdlib.h")


local new = macro(function(type)
	local t = type:astype()
	return `[&t](cstdlib.malloc(sizeof(t)))
end)

local delete = macro(function(ptr)
	local t = ptr:gettype()
	if t:ispointertostruct() and t.type.methods.destruct then
		return quote
			[ptr]:destruct()
			cstdlib.free([ptr])
		end
	else
		return `cstdlib.free([ptr])
	end
end)


-- Decorate any struct type with this method
--    to automatically add the "newStack" and
--    "newHeap" methods to the type
local function addConstructors(structType)
	local function genConstructStatement(inst, args)
		if structType.methods.construct then
			return `inst:construct([args])
		end
	end
	structType.methods.newStack = macro(function(...)
		local args = {}
		for i=1,select("#", ...) do
			args[i] = select(i, ...)
		end
		return quote
			var x : structType
			[genConstructStatement(x, args)]
		in
			x
		end
	end)
	structType.methods.newHeap = macro(function(...)
		local args = {}
		for i=1,select("#", ...) do
			args[i] = select(i, ...)
		end
		return quote
			var x = new(structType)
			[genConstructStatement(x, args)]
		in
			x
		end
	end)
end

return
{
	new = new,
	delete = delete,
	addConstructors = addConstructors
}