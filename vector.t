
local mem = terralib.require("mem")
local templatize = terralib.require("templatize")
local cstdlib = terralib.includec("stdlib.h")
local cstring = terralib.includec("string.h")
local cstdio = terralib.includec("stdio.h")


local expandFactor = 1.5


return templatize(function(T)

	if T:isstruct() then
		error("Vector - Templatizing on struct types is forbidden (use pointer to struct instead).")
	end

	local st = terralib.sizeof(T)
	
	local struct Vector
	{
		__data : &T,
		__capacity : uint,
		size : uint
	}

	terra Vector:construct()
		self.size = 0
		self:__resize(1)
	end

	terra Vector:construct(initialSize: uint, val: T)
		var initCap = initialSize
		if initCap == 0 then initCap = 1 end
		self:__resize(initCap)
		self.size = initialSize
		for i=0,initialSize do
			self.__data[i] = val
		end
	end

	terra Vector:destruct()
		self:clear()
		self.__capacity = 0
		cstdlib.free(self.__data)
		self.__data = nil
	end

	terra Vector:__resize(size: uint)
		self.__capacity = size
		if self.__data == nil then
			self.__data = [&T](cstdlib.malloc(size*st))
		else
			self.__data = [&T](cstdlib.realloc(self.__data, size*st))
		end
	end

	terra Vector:__expand()
		self:__resize(self.__capacity*expandFactor)
	end

	terra Vector:get(index: uint)
		return self.__data[index]
	end

	terra Vector:set(index: uint, val: T)
		self.__data[index] = val
	end

	terra Vector:push(val: T)
		self.size = self.size + 1
		if self.size > self.__capacity then
			self:__expand()
		end
		self.__data[self.size-1] = val
	end

	terra Vector:pop()
		if self.size > 0 then
			self.size = self.size - 1
		end
	end

	terra Vector:insert(index: uint, val: T)
		if index <= self.size then
			if index == self.size then
				self:push(val)
			else
				if self.size+1 > self.__capacity then
					self:__expand()
				end
				cstring.memmove(self.__data+(index+1), self.__data+index, (self.size-index)*st)
				self.__data[index] = val
				self.size = self.size + 1
			end
		else
			cstdio.printf("Vector:insert - index out of range.\n")
			cstdlib.exit(1)
		end
	end

	terra Vector:remove(index: uint)
		if index < self.size then
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
		self.size = 0
	end

	mem.addConstructors(Vector)
	return Vector

end)