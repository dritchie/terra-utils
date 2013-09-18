
local m = terralib.require("mem")
local templatize = terralib.require("templatize")
local util = terralib.require("util")
local cstdlib = terralib.includec("stdlib.h")

-- Constants taken from Java hash map implementation
local defaultInitialCapacity = 16
local loadFactor = 0.75

-- We'll provide default hash functions for all primitive types,
--    but we expect to see a __hash method for all aggregate types.
-- We can provide a 'default' hash for aggregates that can be
--    easily adopted but is not present unless explicity asked for.

local function getDefaultHash(typ)
	-- TODO: Implement
end

local HM = templatize(function(K, V)

	local hashfn = nil
	if K:isprimitive() or K:ispointer() then
		hashfn = getDefaultHash(K)
	else if K:isstruct() and K:getmethod("__hash") then
		hashfn = K:getmethod("__hash")
	else
		error(string.format("No __hash method for aggregate type '%s'", tostring(K)))
	end

	local struct HashCell
	{
		key: K,
		val: V,
		next: &&HashCell
	}

	terra HashCell:__construct(k: K, v: V)
		self.key = m.copy(k)
		self.val = m.copy(v)
		self.next = nil
	end

	terra HashCell:__destruct()
		m.destruct(self.key)
		m.destruct(self.val)
		if self.next then
			m.delete(self.next)
		end
	end

	m.addConstructors(HashCell)

	-----

	local struct HashMap
	{
		__cells: &HashCell,
		__capacity: uint,
		size: uint
	}

	terra HashMap:__construct()
		self.__capacity = defaultInitialCapacity
		self.__cells = cstdlib.malloc(defaultInitialCapacity*sizeof(&HashCell))
		for i=0,self.__capacity do
			self.__cells[i] = nil
		end
		self.size = 0
	end

	terra HashMap:__destruct()
		for i=0,self.__capacity do
			if self.__cells[i] ~= nil then
				m.delete(self.__cells[i])
			end
		end
		cstdlib.free(self.__cells)
	end

	terra HashMap:hash(key: K)
		return hashfn(key) % self.__capacity
	end
	util.inline(HashMap.methods.hash)

	terra HashMap:get(key: K, outval: &V)
		var cell = self.__cells[self:hash(key)]
		while cell ~= nil do
			if cell.key == key then
				@outval = m.copy(cell.val)
				return true
			end
			cell = cell.next
		end
		return false
	end

	-- Expand and rehash
	terra HashMap:__expand()
		-- TODO: Implement this!!!!!
	end

	terra HashMap:put(key: K, val: V)
		var index = self:hash(key)
		var cell = self.__cells[index]
		if cell == nil then
			cell = HashCell.heapAlloc(key, val)
			self.__cells[index] = cell
		else
			-- Check if this key is already present, and if so, replace it
			var origcell = cell
			while cell ~= nil do
				if cell.key == key then
					m.destruct(cell.val)
					cell.val = m.copy(val)
					return
				end
				cell = cell.next
			end
			cell = origcell
			-- Otherwise, insert new cell at head of linked list
			var newcell = HashCell.heapAlloc(key, val)
			newcell.next = cell
			self.__cells[index] = newcell
		end
		self.size = self.size + 1
		if [float](self.size)/self.__capacity > loadFactor then
			self:__expand()
		end
	end

	terra HashMap:remove(key: K)
		var index = self:hash(key)
		var cell = self.__cells[index)]
		var prevcell = nil
		while cell ~= nil do
			if cell.key == key then
				-- CASE: Found it in the first cell
				if prevcell == nil then
					self__cells[index] = cell.next
					return
				-- CASE: Found it in a cell further along
				else
					prevcell.next = cell.next
				end
				self.size = self.size - 1
				m.delete(cell)
				return
			end
			prevcell = cell
			cell = cell.next
		end
	end

	m.addConstructors(HashMap)
	return HashMap
	
end)

function HM.defaultHash = getDefaultHash

return HM


