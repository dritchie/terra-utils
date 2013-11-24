
local mem = terralib.require("mem")
local util = terralib.require("util")
local templatize = terralib.require("templatize")
local hash = terralib.require("hash")
local cstdlib = terralib.includec("stdlib.h")
local cstring = terralib.includec("string.h")
local cstdio = terralib.includec("stdio.h")
local cmath = terralib.includec("math.h")


local expandFactor = 1.5
local minCapacity = 2


local V = templatize(function(T)

	-- if T:isstruct() and (T:getmethod("__destruct") or T:getmethod("__copy")) then
	-- 	error("vector.t: cannot templatize on struct types with non-trivial destructors and/or copy constructors")
	-- end

	local st = terralib.sizeof(T)
	
	local struct Vector
	{
		__data : &T,
		__capacity : uint,
		size : uint
	}

	Vector.methods.fill = macro(function(self, ...)
		local numargs = select("#",...)
		local args = {}
		for i=1,numargs do
			local a = (select(i,...))
			table.insert(args, `mem.copy(a))
		end
		local function buildLHS(vec)
			local arrayelems = {}
			for i=1,numargs do
				local index = i-1
				table.insert(arrayelems, `vec.__data[index])
			end
			return arrayelems
		end
		return quote
			var vec = self
			vec:__resize(numargs)
			vec.size = numargs
			[buildLHS(vec)] = [args]
		in
			vec
		end
	end)

	terra Vector:__construct()
		self.size = 0
		self.__data = nil
		self:__resize(minCapacity)
	end

	terra Vector:__construct(initialSize: uint, val: T)
		self.__data = nil
		var initCap = initialSize
		if initCap < minCapacity then initCap = minCapacity end
		self:__resize(initCap)
		self.size = initialSize
		for i=0,initialSize do
			self.__data[i] = mem.copy(val)
		end
	end

	terra Vector:__copy(v: &Vector)
		self.__data = nil 
		self:__resize(v.size)
		self.size = v.size
		for i=0,self.size do
			self.__data[i] = mem.copy(v.__data[i])
		end
	end

	terra Vector:__destruct()
		self:clear()
		self.__capacity = 0
		cstdlib.free(self.__data)
		self.__data = nil
	end

	Vector.metamethods.__eq = terra(self: &Vector, other: Vector)
		if self.size ~= other.size then return false
		else
			for i=0,self.size do
				if not (self.__data[i] == other.__data[i]) then return false end
			end
			return true
		end
	end

	terra Vector:__hash()
		return hash.rawhash([&int8](self.__data), self.size*st)
	end
	util.inline(Vector.methods.__hash)

	terra Vector:__resize(size: uint)
		self.__capacity = size
		if self.__data == nil then
			self.__data = [&T](cstdlib.malloc(size*st))
		else
			self.__data = [&T](cstdlib.realloc(self.__data, size*st))
		end
	end

	terra Vector:__expand()
		self:__resize(cmath.ceil(self.__capacity*expandFactor))
	end

	terra Vector:reserve(cap: uint)
		while self.__capacity < cap do
			self:__expand()
		end
	end

	terra Vector:resize(size: uint)
		var oldsize = self.size
		self.size = size
		while self.size > self.__capacity do
			self:__expand()
		end
		for i=oldsize,self.size do
			mem.init(self.__data[i])
		end
	end

	terra Vector:incrementSize()
		self.size = self.size + 1
		if self.size > self.__capacity then
			self:__expand()
		end
	end

	-- IMPORTANT: Client code must capture the return value of this function
	--    and eventually destruct it. Otherwise, a memory leak may result
	terra Vector:get(index: uint)
		return mem.copy(self.__data[index])
	end
	util.inline(Vector.methods.get)

	terra Vector:getPointer(index: uint)
		return &(self.__data[index])
	end
	util.inline(Vector.methods.getPointer)


	Vector.metamethods.__apply = macro(function(self, index)
		return `self.__data[index]
	end)


	terra Vector:set(index: uint, val: T)
		mem.destruct(self.__data[index])
		self.__data[index] = mem.copy(val)
	end
	util.inline(Vector.methods.set)

	terra Vector:push(val: T)
		self:incrementSize()
		self.__data[self.size-1] = mem.copy(val)
	end

	terra Vector:pop()
		if self.size > 0 then
			mem.destruct(self.__data[self.size-1])
			self.size = self.size - 1
		end
	end

	-- IMPORTANT: Client code must capture the return value of this function
	--    and eventually destruct it. Otherwise, a memory leak may result
	terra Vector:back()
		return mem.copy(self.__data[self.size-1])
	end
	util.inline(Vector.methods.back)

	terra Vector:backPointer()
		return &(self.__data[self.size-1])
	end
	util.inline(Vector.methods.backPointer)

	terra Vector:insert(index: uint, val: T)
		if index <= self.size then
			if index == self.size then
				self:push(val)
			else
				if self.size+1 > self.__capacity then
					self:__expand()
				end
				cstring.memmove(self.__data+(index+1), self.__data+index, (self.size-index)*st)
				self.__data[index] = mem.copy(val)
				self.size = self.size + 1
			end
		else
			cstdio.printf("Vector:insert - index out of range.\n")
			cstdlib.exit(1)
		end
	end

	terra Vector:remove(index: uint)
		if index < self.size then
			mem.destruct(self.__data[index])
			if index < self.size - 1 then
				cstring.memmove(self.__data+index, self.__data+(index+1), (self.size-index-1)*st)
			end
			self.size = self.size - 1
		else
			cstdio.printf("Vector:remove - index out of range.\n")
			cstdlib.exit(1)
		end
	end

	terra Vector:clear()
		for i=0,self.size do mem.destruct(self.__data[i]) end
		self.size = 0
	end

	terra Vector:clearAndReclaimMemory()
		self:clear()
		self:__resize(minCapacity)
	end

	mem.addConstructors(Vector)
	return Vector

end)



V.fromItems = macro(function(...)
	local T = (select(1,...)):gettype()
	local args = {}
	for i=1,select("#",...) do
		table.insert(args, (select(i,...)))
	end
	return `[V(T)].stackAlloc():fill([args])
end)

-- Like fromItems, but callable from Lua code, and gc's the resulting object
function V.fromNums(...)
	local v = terralib.new(V(double))
	V(double).methods.__construct(v)
	V(double).methods.resize(v, select("#",...))
	for i=1,select("#",...) do
		V(double).methods.set(v, i-1, (select(i,...)))
	end
	mem.gc(v)
	return v
end


return V


