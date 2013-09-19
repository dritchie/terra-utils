-- Really simple single inheritance

local Inheritance = {}

-- metadata for class system
local metadata = {}

local function issubclass(child,parent)
	if child == parent then
		return true
	else
		local par = metadata[child].parent
		return par and issubclass(par,parent)
	end
end

local function setParent(child, parent)
	local md = metadata[child]
	if md then
		if md.parent then
			error(string.format("'%s' already inherits from some type -- multiple inheritance not allowed.", child.name))
		end
		md.parent = parent
	else
		metadata[child] = {parent = parent}
	end
end

local function castoperator(from, to, exp)
	if from:ispointer() and to:ispointer() and issubclass(from.type, to.type) then
		return `[to](exp)
	else
		error(string.format("'%s' does not inherit from '%s'", from.type.name, to.type.name))
	end
end

local function lookupParentStaticMethod(class, methodname)
	local parent = metadata[class].parent
	local m = class.methods[methodname]
	if not m then
		m = parent.methods[methodname]
	end
	return m
end

local function copyparentlayoutStatic(class)
	local parent = metadata[class].parent
	for i,e in ipairs(parent.entries) do table.insert(class.entries, i, e) end
	return class.entries
end

local function addstaticmetamethods(class)
	class.metamethods.__cast = castoperator
	class.metamethods.__getentries = copyparentlayoutStatic
	class.metamethods.__getmethod = lookupParentStaticMethod
end


-- child inherits data layout and method table from parent
function Inheritance.staticExtend(parent, child)
	setParent(child, parent)
	addstaticmetamethods(child)
end


------------------------------------------

-- Create the function which will initialize the __vtable field
-- in each struct instance.
local function initvtable(class)
	local md = metadata[class]
	-- global, because otherwise it would be GC'ed.
	md.vtable = global(md.vtabletype)
	terra class:__initvtable()
		self.__vtable = &md.vtable
	end
	assert(class.methods.__initvtable)
end

-- Finalize the vtable after the class has been compiled
local function finalizeVtable(class)
	local md = metadata[class]
	local vtbl = md.vtable:get()
	for methodname,impl in pairs(md.methodimpl) do
		impl:compile(function()
			vtbl[methodname] = impl:getpointer()  
		end)
	end
end

-- Create a 'stub' method which refers to the method of the same
-- name in the class's vtable
local function createstub(methodname,typ)
	local symbols = typ.parameters:map(symbol)
	local obj = symbols[1]
	local terra wrapper([symbols]) : typ.returns
		return obj.__vtable.[methodname]([symbols])
	end
	return wrapper
end

local function getdefinitionandtype(impl)
	if #impl:getdefinitions() ~= 1 then
			error(string.format("Overloaded function '%s' cannot be virtual.", method.name))
		end
	local impldef = impl:getdefinitions()[1]
	local success, typ = impldef:peektype()
	if not success then
		error(string.format("virtual method '%s' must have explicit return type", impl.name))
	end
	return impldef,typ
end

-- Finalize the layout of the struct
local function finalizeStructLayoutDynamic(class)
	local md = metadata[class]

	-- Start up the vtable data
	struct md.vtabletype {}
	md.methodimpl = {}

	-- Create __vtable field
	class.entries:insert(1, { field = "__vtable", type = &md.vtabletype})

	-- Copy data from parent
	local parent = md.parent
	if parent then
		-- Must do this to make sure the parent's layout has been finalized first
		parent:getentries()
		-- Static members (except the __vtable field)
		for i=2,#parent.entries do
			class.entries:insert(i, parent.entries[i])
		end
		-- vtable entries
		local pmd = metadata[parent]
		for i,m in ipairs(pmd.vtabletype.entries) do
			md.vtabletype.entries:insert(m)
			md.methodimpl[m.field] = pmd.methodimpl[m.field]
		end
	end

	-- Copy all my virtual methods into the vtable staging area
	for methodname, impl in pairs(class.methods) do
		if md.vmethods and md.vmethods[methodname] then
			local def, typ = getdefinitionandtype(impl)
			if md.methodimpl[methodname] == nil then
				md.vtabletype.entries:insert({field = methodname, type = &typ})
			end
			md.methodimpl[methodname] = def
		end
	end

	-- Create method stubs (overwriting any methods marked virtual)
	for methodname, impl in pairs(md.methodimpl) do
		local _,typ = impl:peektype()
		class.methods[methodname] = createstub(methodname, typ)
	end

	-- Make __vtable field initializer
	initvtable(class)

	return class.entries
end


-- Add metamethods necessary for dynamic dispatch
local function adddynamicmetamethods(class)
	class.metamethods.__cast = castoperator
	class.metamethods.__staticinitialize = finalizeVtable
	class.metamethods.__getentries = finalizeStructLayoutDynamic
	class.metamethods.__getmethod = lookupParentStaticMethod
end


-- Ensure that a struct is equipped for dynamic dispatch
-- (i.e. has a vtable, has the requisite metamethods)
local function ensuredynamic(class)
	if not metadata[class] then
		metadata[class] = {}
	end
	adddynamicmetamethods(class)
end

-- Mark a method as virtual
function Inheritance.virtual(class, methodname)
	ensuredynamic(class)
	local md = metadata[class]
	if not md.vmethods then
		md.vmethods = {}
	end
	md.vmethods[methodname] = true
end


-- child inherits data layout and method table from parent
-- child also inherits vtable from parent
function Inheritance.dynamicExtend(parent, child)
	ensuredynamic(parent)
	ensuredynamic(child)
	setParent(child, parent)
end

return Inheritance






