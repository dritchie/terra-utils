local templatize = terralib.require("templatize")
local inheritance = terralib.require("inheritance")
local Vector = terralib.require("vector")
local util = terralib.require("util")


local data = {}
local vmethods = {}		-- So function pointers don't get gc'ed


local function getDataForClass(class)
	for c,d in pairs(data) do
		if inheritance.issubclass(class, c) then
			return d
		end
	end
	local d = {}
	data[class] = d
	return d
end

local function vtableName(name)
	return string.format("%sVtable", name)
end

local function desugarFuncType(class, typ)
	local newparams = util.copytable(typ.type.parameters)
	local newreturns = util.copytable(typ.type.returns)
	table.insert(newparams, 1, &class)
	return terralib.types.funcpointer(newparams, newreturns)
end

local function newFunction(class, name, typ, fn)
	local nextid = 1
	local datum =
	{
		fntyp = desugarFuncType(class, typ),
		-- Unique ID for every parameter set
		params2id = templatize(function(...)
			nextid = nextid + 1
			return nextid - 1
		end),
		id2params = {},
	}
	-- Call function on parameter set, returns a "specialized virtual function"
	-- (Actually a macro that invokes the right vtable entry)
	datum.tfn = templatize(function(inst, ...)
		local id = datum.params2id(...)
		local vtableindex = id-1
		datum.id2params[id] = {...}
		return macro(function(...)
			local args = {}
			for i=1,select("#",...) do table.insert(args, (select(i,...))) end
			if #args > 0 then
				return `[inst].[vtableName(name)]:get(vtableindex)([inst], [args])
			else
				return `[inst].[vtableName(name)]:get(vtableindex)([inst])
			end
		end)
	end)
	-- vtable pointer (every instance of class has one)
	class.entries:insert({field = vtableName(name), type = &Vector(datum.fntyp)})
	return datum
end

local function setupConcreteImplementation(datum, class, name, fn)
	local typ = datum.fntyp
	-- Initialize actual vtable
	local vtable = global(Vector(typ))
	Vector(typ).methods.__construct(vtable:getpointer())
	local vtableIsFilled = global(bool, false)
	-- We call back into Lua to compile everything in the vtable
	local function fillVtable()
		for _,params in ipairs(datum.id2params) do
			local specfn = fn(unpack(params))
			table.insert(vmethods, specfn)
			Vector(typ).methods.push(vtable:getpointer(), specfn:getpointer())
		end
		vtableIsFilled:set(true)
	end
	-- Run this method whenever initializing an instance of class
	-- TODO: make this happen automatically?
	class.methods[string.format("init_%s", vtableName(name))] = terra(self: &class)
		if not vtableIsFilled then
			fillVtable()
		end
		self.[vtableName(name)] = &vtable
	end
end

local function virtualTemplate(class, name, typ, fn)
	local classDatum = getDataForClass(class)
	local nameDatum = classDatum[name]
	if not nameDatum then
		nameDatum = newFunction(class, name, typ, fn)
		classDatum[name] = nameDatum
	end
	if fn then
		setupConcreteImplementation(nameDatum, class, name, fn)
	end
	return nameDatum.tfn
end

return virtualTemplate




