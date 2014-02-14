local m = terralib.require("mem")
local templatize = terralib.require("templatize")
local util = terralib.require("util")

local C = terralib.includecstring [[
#include <stdlib.h>
]]

-- A simple 2D grid of values, like a matrix, but without
--    any linear algebra operations defined.
-- Useful as an interchange format for e.g. Eigen
local Grid2D = templatize(function(valueType)

	local struct GridT
	{
		rows: int,
		cols: int,
		data: &valueType
	}

	GridT.metamethods.__apply = macro(function(self, i, j)
		return `self.data[i*self.cols + j]
	end)

	terra GridT:__construct(r: int, c: int)
		self.rows = r
		self.cols = c
		self.data = [&valueType](C.malloc(r*c*sizeof(valueType)))
		for i=0,r do
			for j=0,c do
				m.init(self(i,j))
			end
		end
	end

	terra GridT:__copy(other: &GridT)
		self.rows = other.rows
		self.cols = other.cols
		self.data = [&valueType](C.malloc(self.rows*self.cols*sizeof(valueType)))
		for i=0,self.rows do
			for j=0,self.cols do
				self(i,j) = m.copy(other(i,j))
			end
		end
	end

	terra GridT:__destruct()
		C.free(self.data)
	end

	-- Completely wipes all the stored data
	terra GridT:resize(r: int, c: int)
		if r ~= self.rows or c ~= self.cols then
			self:__destruct()
			self:__construct(r, c)
		end
	end

	-- OK, OK, I probably really ought to refactor this class into a "Matrix"
	--    class, but I'm putting that off for now
	terra GridT:matMul(v: &Vector(valueType), vout: &Vector(valueType))
		util.assert(self.cols == v.size,
			"Attempt to matrix multiply a Grid by a Vector of incompatible dimensions\n")
		vout:resize(self.rows)
		for i=0,self.rows, do
			var sum = valueType(0.0)
			for j=0,self.cols do
				sum = sum + self(i,j)*v(j)
			end
			vout(i) = sum
		end
	end

	m.addConstructors(GridT)
	return GridT

end)


return 
{
	Grid2D = Grid2D
}