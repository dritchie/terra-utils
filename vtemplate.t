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

-- Create a stub method to be put in a concrete vtable
-- When the stub is called, it will replace itself with the actual virtual method
--    that's being requested (via JIT)
local function addStub(concreteDatum)
	-- We're adding to the end of the vtable, so the vtable index is the end
	--    of the vector.
	local vtableindex = concreteDatum.vtable:getpointer().size
	local abstractDatum = concreteDatum.abstractDatum
	local params = abstractDatum.id2params[vtableindex+1]
	local typ = abstractDatum:specialzedFnType(unpack(params))
	local syms = {}
	for _,t in ipairs(typ.type.parameters) do table.insert(syms, symbol(t)) end
	local terra stub([syms])
		-- Replace this stub with the actual implementation
		[concreteDatum.compileAndReplace](vtableindex)
		-- Re-invoke the virtual template function, which will call the newly
		--    compiled implementation instead of the stub.
		return [abstractDatum.templatefn(unpack(params))]([syms])
	end
	-- Add the stub to the vtable
	table.insert(vmethods, stub)
	Vector(&opaque).methods.push(concreteDatum.vtable:getpointer(), stub:getpointer())
end

local datumMT =
{
	vtableName = function(self) return string.format("%sVtable", self.name) end,
	specialzedFnType = function(self, ...)
		local typ = self.typfn(...)
		local newparams = util.copytable(typ.type.parameters)
		local newreturns = util.copytable(typ.type.returns)
		table.insert(newparams, 1, &self.class)
		return terralib.types.funcpointer(newparams, newreturns)
	end
}
datumMT.__index = datumMT
local function newFunction(class, name, typfn, fn)
	local nextid = 1
	local datum =
	{
		class = class,
		name =name,
		typfn = typfn,
		-- Unique ID for every parameter set
		params2id = templatize(function(...)
			nextid = nextid + 1
			return nextid - 1
		end),
		-- Map from ID back to parameters
		id2params = {},
		-- Concrete implementations of this function
		concretes = {}
	}
	setmetatable(datum, datumMT)
	-- Call function on parameter set, returns a "specialized virtual function"
	-- (Actually a macro that invokes the right vtable entry)
	datum.templatefn = templatize(function(...)
		local typ = datum:specialzedFnType(...)
		local id = datum.params2id(...)
		local vtableindex = id-1
		-- If this is a new param setting (i.e. the id is bigger than the length
		--    of our id->params map), then make a new stub for all registered
		--    concrete implementations of this vtemplate
		if id > #datum.id2params then
			datum.id2params[id] = {...}
			for _,concreteDatum in ipairs(datum.concretes) do
				addStub(concreteDatum)
			end
		end
		return macro(function(inst, ...)
			local fnptr = `[typ]([inst].[datum:vtableName()]:get(vtableindex))
			local args = {...}
			table.insert(args, 1, inst)
			return `fnptr([args])
		end)
	end)
	-- vtable pointer (every instance of class has one)
	class.entries:insert({field = datum:vtableName(), type = &Vector(&opaque)})
	return datum
end

local function setupConcreteImplementation(concreteClass, concreteFn, datum)
	local concreteDatum = 
	{
		abstractDatum = datum,
		class = concreteClass,
		fn = concreteFn,
		vtable = global(Vector(&opaque))
	}
	Vector(&opaque).methods.__construct(concreteDatum.vtable:getpointer())
	-- When a stub is called, compile the actual implementation and put
	--    in the vtable where the stub used to be.
	concreteDatum.compileAndReplace = function(vtableindex)
		local params = datum.id2params[vtableindex+1]
		local specfn = concreteFn(unpack(params))
		table.insert(vmethods, specfn)
		Vector(&opaque).methods.set(concreteDatum.vtable:getpointer(), vtableindex, specfn:getpointer())
	end
	-- Create stubs for all the parameter sets we've seen so far.
	for i,params in ipairs(datum.id2params) do
		addStub(concreteDatum)
	end
	-- Add a vtable initializer method to the class
	concreteClass.methods[string.format("init_%s", datum:vtableName())] = terra(self: &concreteClass)
		self.[datum:vtableName()] = &[concreteDatum.vtable]
	end
	-- Finally, register this new concrete implementation with the abstract datum.
	-- This is critical: If/when new parameter sets are encountered, new stubs can be added
	--    to this concrete class's vtable.
	table.insert(datum.concretes, concreteDatum)
end

-- typfn is a function from template parameters to a function type
-- fn only needs to be provided for concrete derived classes
local function virtualTemplate(class, name, typfn, fn)
	local classDatum = getDataForClass(class)
	local nameDatum = classDatum[name]
	if not nameDatum then
		nameDatum = newFunction(class, name, typfn, fn)
		classDatum[name] = nameDatum
	end
	if fn then
		setupConcreteImplementation(class, fn, nameDatum)
	end
	return nameDatum.templatefn
end

return virtualTemplate




