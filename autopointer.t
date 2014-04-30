
local util = terralib.require("util")
local m = terralib.require("mem")
local templatize = terralib.require("templatize")

-- local C = terralib.includecstring [[
-- #include "stdio.h"
-- ]]

-- Pretty much just like stl::auto_ptr

local struct RefCount
{
	count: uint
}

terra RefCount:__construct()
	self.count = 1
end

terra RefCount:retain()
	self.count = self.count + 1
end

terra RefCount:release()
	util.assert(self.count > 0,
		"Cannot release on a RefCount with zero references\n")
	self.count = self.count - 1
end

terra RefCount:empty()
	return self.count == 0
end

m.addConstructors(RefCount)


local AutoPtr = templatize(function(T)
	local struct AutoPtrT
	{
		ptr: &T,
		refCount: &RefCount
	}

	AutoPtrT.metamethods.__typename = function(self)
		return string.format("AutoPtr(%s)", tostring(T))
	end

	terra AutoPtrT:__construct()
		self.ptr = nil
		self.refCount = nil
	end

	terra AutoPtrT:__construct(ptr: &T)
		self.ptr = ptr
		self.refCount = RefCount.heapAlloc()
	end

	terra AutoPtrT:__copy(other: &AutoPtrT)
		self.ptr = other.ptr
		self.refCount = other.refCount
		self.refCount:retain()
	end

	terra AutoPtrT:__destruct()
		if self.ptr ~= nil and self.refCount ~= nil then
			self.refCount:release()
			if self.refCount:empty() then
				-- C.printf("deleting\n")
				m.delete(self.refCount)
				m.delete(self.ptr)
			end
		end
	end

	AutoPtrT.metamethods.__entrymissing = macro(function(fieldname, self)
		return `self.ptr.[fieldname]
	end)
	
	-- I use this more complicated behavior, rather than just using __methodmissing,
	--    because I want AutoPtrT:getmethod to still return nil exactly when T:getmethod
	--    would return nil.
	AutoPtrT.metamethods.__getmethod = function(self, methodname)
		-- If AutoPtrT has the method (i.e. is it __construct, __destruct, __copy),
		--    then just return that
		local mymethod = self.methods[methodname]
		if mymethod then return mymethod end
		-- Otherwise, if T has it, then return a macro that will invoke T's
		--    method on the .ptr member
		local tmethod = T:getmethod(methodname)
		if tmethod then
			return macro(function(self, ...)
				local args = {...}
				return `[tmethod](self.ptr, [args])
			end)
		end
		-- Otherwise, return nil
		return nil
	end

	m.addConstructors(AutoPtrT)
	return AutoPtrT
end)

-- Convience macro to create a new auto pointer without explicitly specifying the type
-- It'll figure out the type from the type of the argument
AutoPtr.wrap = macro(function(ptr)
	local pT = ptr:gettype()
	util.luaAssertWithTrace(pT:ispointertostruct(),
		"Can only create an auto pointer from a pointer to a struct.")
	local T = pT.type
	return `[AutoPtr(T)].stackAlloc(ptr)
end)


------- TESTS

-- local struct Foo { x: int }
-- terra Foo:__construct() end
-- terra Foo:setX(x: int) self.x = x end
-- m.addConstructors(Foo)

-- local terra test()
-- 	var f = Foo.heapAlloc()
-- 	var af = [AutoPtr(Foo)].stackAlloc(f)
-- 	af:setX(42)
-- 	var x = af.x
-- 	var af2 = m.copy(af)
-- 	m.destruct(af)
-- 	m.destruct(af2)
-- 	return x
-- end
-- test:compile()
-- print(test())

-------


return AutoPtr






