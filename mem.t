
local cstdlib = terralib.includec("stdlib.h")


local new = macro(function(type)
	local t = type:astype()
	return `[&t](cstdlib.malloc(sizeof(t)))
end)

local delete = macro(function(ptr)
	local t = ptr:gettype()
	if t:ispointertostruct() and t.type:getmethod("__destruct") then
		t.type:complete()
		return quote
			[ptr]:__destruct()
			cstdlib.free([ptr])
		end
	else
		return `cstdlib.free([ptr])
	end
end)

local destruct = macro(function(val)
	local t = val:gettype()
	if t:isstruct() and t:getmethod("__destruct") then
		t:complete()
		return `val:__destruct()
	end
end)

local copy = macro(function(val)
	local t = val:gettype()
	if t:isstruct() and t:getmethod("__copy") then
		return quote
			var cp : t
			cp:__copy(val)
		in
			cp
		end
	else
		return val
	end
end)


-- Decorate any struct type with this method
--    to automatically add the "stackAlloc" and
--    "heapAlloc" methods to the type
local function addConstructors(structType)
	local function genConstructStatement(inst, args)
		if structType:getmethod("__construct") then
			return `inst:__construct([args])
		end
	end
	local function genVtableInitStatement(inst)
		if structType:getmethod("__initvtable") then
			return `inst:__initvtable()
		end
	end
	structType.methods.stackAlloc = macro(function(...)
		structType:complete()
		local args = {}
		for i=1,select("#", ...) do
			args[i] = (select(i, ...))
		end
		return quote
			var x : structType
			[genVtableInitStatement(x)]
			[genConstructStatement(x, args)]
		in
			x
		end
	end)
	structType.methods.heapAlloc = macro(function(...)
		structType:complete()
		local args = {}
		for i=1,select("#", ...) do
			args[i] = (select(i, ...))
		end
		return quote
			var x = new(structType)
			[genVtableInitStatement(x)]
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
	destruct = destruct,
	copy = copy,
	addConstructors = addConstructors
}