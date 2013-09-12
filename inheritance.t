-- Really simple single inheritance (with no dynamic dispatch)

local util = require("util")

local Inheritance = {}

-- map from child class to parent class
local parentMap = {}

local function issubclass(child,parent)
	if child == parent then
		return true
	else
		local par = parentMap[child]
		return par and issubclass(par,parent)
	end
end

-- classB inherits from classA
function Inheritance.extend(classA, classB)
	local par = parentMap[classB]
	if par then
		error(string.format("'%s' already inherits from some type -- multiple inheritance not allowed.", classB.name))
	end
	parentMap[classB] = classA

	-- First, we copy all the fields from A into B (before B's fields)
	for i,e in ipairs(classA.entries) do table.insert(classB.entries, i, e) end

	-- Then we set up a mechanism for B to look in A's method table
	-- when a method is not found in its method table.
	classB.metamethods.__getmethod = function(self, methodname)
		local m = self.methods[methodname]
		if not m then
			m = classA.methods[methodname]
		end
		return m
	end

	-- Finally, we enable casting from B to A
	classB.metamethods.__cast = function(from, to, exp)
		if from:ispointer() and to:ispointer() and issubclass(from.type, to.type) then
			return `[to](exp)
		else
			error(string.format("'%s' does not inherit from '%s'", from.name, to.name))
		end
	end
end

return Inheritance