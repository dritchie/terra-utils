
local cstdlib = terralib.includec("stdlib.h")

local function genVtableInitStatement(inst, typ)
	if typ:isstruct() and typ:getmethod("__initvtable") then
		return `inst:__initvtable()
	else
		return quote end
	end
end

local function initerr(typ)
	error(string.format("Non-POD type '%s' must have a no-argument constructor.", tostring(typ)))
end
local init = macro(function(val)
	local t = val:gettype()
	if t:isstruct() then
		t:complete()
		local ctors = t:getmethod("__construct")
		if not ctors then return quote end end
		for _,d in ipairs(ctors:getdefinitions()) do
			if #d:gettype().parameters == 1 then
				return quote
					[genVtableInitStatement(val, t)]
					val:__construct()
				end
			end
		end
		initerr(t)
	else
		return quote
			[genVtableInitStatement(val, t)]
		end
	end
end)

local new = macro(function(type)
	local t = type:astype()
	return quote
		var nt = [&t](cstdlib.malloc(sizeof(t)))
		[genVtableInitStatement(nt, t)]
	in
		nt
	end
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
	else
		return quote end
	end
end)

local function copyfn(val)
	local t = val:gettype()
	if t:isstruct() and t:getmethod("__copy") then
		t:complete()
		return quote
			var cp : t
			[genVtableInitStatement(cp, t)]
			cp:__copy(&val)
		in
			cp
		end
	else
		return quote
			[genVtableInitStatement(val, t)]
		in
			val
		end
	end
end
local copy = macro(copyfn)

local function templatecopy(...)
	local Params = {}
	for i=1,select("#",...) do table.insert(Params, (select(i,...))) end
	return macro(function(val)
		local t = val:gettype()
		if t:isstruct() and t.__generatorTemplate and t.__templatecopy then
			local newt = t.__generatorTemplate(unpack(Params))
			return quote
				var cp : newt
				[genVtableInitStatement(cp, newt)]
				[t.__templatecopy(unpack(t.__templateParams))](&cp, &val)
			in
				cp
			end
		else
			return copyfn(val)
		end
	end)
end


-- Ensure that a cdata object returned from Terra code to Lua code gets properly destructed.
-- Call this (only) if the Lua code is assuming ownership of the returned object.
local ffi = require("ffi")
local function gc(cdata)
	local t = terralib.typeof(cdata)
	if t:isstruct() and t:getmethod("__destruct") then
		local dtor = t:getmethod("__destruct")
		ffi.gc(cdata, function(obj)
			dtor(cdata)
		end)		
	end
end


-- Decorate any struct type with this method
--    to automatically add the "stackAlloc" and
--    "heapAlloc" methods to the type
local function addConstructors(structType)
	local function genConstructStatement(inst, args)
		if structType:getmethod("__construct") then
			return `inst:__construct([args])
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
			[genVtableInitStatement(x, structType)]
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
			[genConstructStatement(x, args)]
		in
			x
		end
	end)
end

return
{
	init = init,
	new = new,
	delete = delete,
	destruct = destruct,
	copy = copy,
	templatecopy = templatecopy,
	gc = gc,
	addConstructors = addConstructors
}