
local mem = terralib.require("mem")
local templatize = terralib.require("templatize")
local cstdlib = terralib.includec("stdlib.h")


local expandFactor = 2


local function makeVector(T)
	
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
		self:__resize(initialSize)
		self.size = initialSize
		for i=0,initialSize do
			self.__data[i] = val
		end
	end

	terra Vector:destruct()
		self.size = 0
		self.__capacity = 0
		cstdlib.free(self.__data)
		self.__data = nil
	end

	terra Vector:__resize(size: uint)
		self.__capacity = size
		if self.__data == nil then
			self.__data = [&T](cstdlib.malloc(size*sizeof(T)))
		else
			self.__data = [&T](cstdlib.realloc(self.__data, size*sizeof(T)))
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

	terra Vector:clear()
		self.size = 0
	end

	-- TODO: add (at index)
	-- TODO: remove (at index)

	mem.addConstructors(Vector)
	return Vector

end


return templatize(makeVector)