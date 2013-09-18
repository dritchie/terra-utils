
local m = terralib.require("mem")
local templatize = terralib.require("templatize")
local util = terralib.require("util")
local cstdlib = terralib.includec("stdlib.h")
local fasthash = terralib.includec("fasthash.h").SuperFastHash


local defaultInitialCapacity = 8
local expandFactor = 2
local loadFactor = 4.0


-- We'll provide default hash functions for all primitive types,
--    but we expect to see a __hash method for all aggregate types.
-- We can provide a 'default' hash for aggregates that can be
--    easily adopted but is not present unless explicity asked for.
local function getDefaultHash(typ)
	local fn = terra(val: typ)
		return fasthash([&int8](&val), sizeof(typ))
	end
	util.inline(fn)
	return fn
end


local HM = templatize(function(K, V)

	local hashfn = nil
	if K:isprimitive() or K:ispointer() then
		hashfn = getDefaultHash(K)
	elseif K:isstruct() and K:getmethod("__hash") then
		hashfn = K:getmethod("__hash")
	else
		error(string.format("No __hash method for aggregate type '%s'", tostring(K)))
	end

	local struct HashCell
	{
		key: K,
		val: V,
		next: &HashCell
	}

	terra HashCell:__construct(k: K, v: V)
		self.key = m.copy(k)
		self.val = m.copy(v)
		self.next = nil
	end

	terra HashCell:__destruct() : {}
		m.destruct(self.key)
		m.destruct(self.val)
		if self.next ~= nil then
			m.delete(self.next)
		end
	end

	m.addConstructors(HashCell)

	-----

	local struct HashMap
	{
		__cells: &&HashCell,
		__capacity: uint,
		size: uint
	}

	terra HashMap:__construct(initialCapacity: uint) : {}
		self.__capacity = initialCapacity
		self.__cells = [&&HashCell](cstdlib.malloc(initialCapacity*sizeof([&HashCell])))
		for i=0,self.__capacity do
			self.__cells[i] = nil
		end
		self.size = 0
	end

	terra HashMap:__construct() : {}
		self:__construct(defaultInitialCapacity)
	end

	terra HashMap:clear()
		for i=0,self.__capacity do
			if self.__cells[i] ~= nil then
				m.delete(self.__cells[i])
				self.__cells[i] = nil
			end
		end
		self.size = 0
	end

	terra HashMap:__destruct()
		self:clear()
		cstdlib.free(self.__cells)
	end

	terra HashMap:hash(key: K)
		return hashfn(key) % self.__capacity
	end
	util.inline(HashMap.methods.hash)

	terra HashMap:getPointer(key: K)
		var cell = self.__cells[self:hash(key)]
		while cell ~= nil do
			if cell.key == key then
				return &cell.val
			end
			cell = cell.next
		end
		return nil
	end

	terra HashMap:get(key: K, outval: &V)
		var vptr = self:getPointer(key)
		if vptr == nil then
			return false
		else
			@outval = m.copy(@vptr)
			return true
		end
	end

	-- Expand and rehash
	terra HashMap:__expand()
		var oldcap = self.__capacity
		var oldcells = self.__cells
		self:__construct(2*oldcap)
		for i=0,oldcap do
			var cell = oldcells[i]
			while cell ~= nil do
				self:put(cell.key, cell.val)
				cell = cell.next
			end
		end
		cstdlib.free(oldcells)
	end

	terra HashMap:put(key: K, val: V) : {}
		var index = self:hash(key)
		var cell = self.__cells[index]
		if cell == nil then
			cell = HashCell.heapAlloc(key, val)
			self.__cells[index] = cell
		else
			-- Check if this key is already present, and if so, replace
			-- its value
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
		var cell = self.__cells[index]
		var prevcell : &HashCell = nil
		while cell ~= nil do
			if cell.key == key then
				-- CASE: Found it in the first cell
				if prevcell == nil then
					self.__cells[index] = cell.next
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

	-----

	local struct Iterator
	{
		srcmap: &HashMap,
		currblock: uint,
		currcell: &HashCell
	}

	terra Iterator:__construct(map: &HashMap)
		self.srcmap = map
		self.currblock = 0
		self.currcell = map.__cells[0]
		if self.currcell == nil then
			self:next()
		end
	end

	terra Iterator:next()
		-- First, just try to move to the next cell in the
		--    current chain
		if self.currcell ~= nil then
			self.currcell = self.currcell.next
		end
		-- Look for a non-nil cell
		-- Traverse the current cell chain until it ends, then
		--    move to the enxt one
		-- Stop if we get to the end of the last chain
		while self.currcell == nil and
			  (self.currblock < self.srcmap.__capacity-1) do
			self.currblock = self.currblock + 1
			self.currcell = self.srcmap.__cells[self.currblock]
		end
	end

	terra Iterator:done()
		return self.currcell == nil
	end
	util.inline(Iterator.methods.done)

	terra Iterator:key()
		return m.copy(self.currcell.key)
	end
	util.inline(Iterator.methods.key)

	terra Iterator:val()
		return m.copy(self.currcell.val)
	end
	util.inline(Iterator.methods.val)

	terra Iterator:valPointer()
		return &(self.currcell.val)
	end
	util.inline(Iterator.methods.valPointer)

	terra Iterator:keyval()
		return self:key(), self:val()
	end
	util.inline(Iterator.methods.keyval)

	m.addConstructors(Iterator)


	-----


	terra HashMap:iterator()
		return Iterator.stackAlloc(self)
	end


	return HashMap
	
end)

HM.defaultHash = getDefaultHash

return HM


