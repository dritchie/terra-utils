local templatize = terralib.require("templatize")
local m = terralib.require("mem")
local util = terralib.require("util")
local ad = terralib.require("ad")

local Vec
Vec = templatize(function(real, dim)

	local struct VecT
	{
		entries: real[dim]
	}
	VecT.RealType = real
	VecT.Dimension = dim

	-- Code gen helpers
	local function entryList(self)
		local t = {}
		for i=1,dim do table.insert(t, `[self].entries[ [i-1] ]) end
		return t
	end
	local function replicate(val, n)
		local t = {}
		for i=1,n do table.insert(t, val) end
		return t
	end
	local function symbolList()
		local t = {}
		for i=1,dim do table.insert(t, symbol(real)) end
		return t
	end
	local function wrap(exprs, unaryFn)
		local t = {}
		for _,e in ipairs(exprs) do table.insert(t, `[unaryFn(e)]) end
		return t
	end
	local function copyWrap(exprs)
		return wrap(exprs, function(e) return `m.copy(e) end)
	end
	local function destructWrap(exprs)
		return wrap(exprs, function(e) return `m.destruct(e) end)
	end
	local function zip(expList1, expList2, binaryFn)
		assert(#expList1 == #expList2)
		local t = {}
		for i=1,#expList1 do
			local e1 = expList1[i]
			local e2 = expList2[i]
			table.insert(t, binaryFn(e1, e2))
		end
		return t
	end
	local function reduce(exprs, accumFn)
		local curr = exprs[1]
		for i=2,#exprs do
			local e = exprs[i]
			curr = `[accumFn(e, curr)]
		end
		return curr
	end

	-- Constructors/destructors/etc.
	terra VecT:__construct()
		[entryList(self)] = [replicate(`0.0, dim)]
	end
	local ctorags = symbolList()
	terra VecT:__construct([ctorags])
		[entryList(self)] = [copyWrap(ctorags)]
	end
	if dim > 1 then
		terra VecT:__construct(val: real)
			[entryList(self)] = [replicate(val, dim)]
		end
	end
	terra VecT:__destruct()
		[destructWrap(entryList(self))]
	end
	terra VecT:__copy(other: &VecT)
		[entryList(self)] = [copyWrap(entryList(other))]
	end

	-- Apply metamethod does element access (as a macro, so you can both
	--    read and write elements this way)
	VecT.metamethods.__apply = macro(function(self, index)
		return `self.entries[index]
	end)

	-- Casting vector types (e.g. Vec(float, 3) --> Vec(double, 3))
	function VecT.metamethods.__cast(from, to, exp)
		if (from.__generatorTemplate == Vec) and
		   (to.__generatorTemplate == Vec) and
		   (from.Dimension == to.Dimension) then
		   return `[to].stackAlloc([entryList(exp)])
		elseif from.__generatorTemplate ~= Vec then
			error(string.format("'%s' is not a Vec type", from))
		elseif to.__generatorTemplate ~= Vec then
			error(string.format("'%s' is not a Vec type", to))
		elseif from.Dimension ~= to.Dimension then
			error(string.format("'%s' has dimension %u, but '%s' has dimension %u",
				from, from.Dimension, to, to.Dimension))
		end
	end

	-- Arithmetic operators
	VecT.metamethods.__add = terra(v1: VecT, v2: VecT)
		var v : VecT
		[entryList(v)] = [zip(entryList(v1), entryList(v2),
			function(a, b) return `a+b end)]
		return v
	end
	util.inline(VecT.metamethods.__add)
	VecT.metamethods.__sub = terra(v1: VecT, v2: VecT)
		var v : VecT
		[entryList(v)] = [zip(entryList(v1), entryList(v2),
			function(a, b) return `a-b end)]
		return v
	end
	util.inline(VecT.metamethods.__sub)
	VecT.metamethods.__mul = terra(v1: VecT, s: real)
		var v : VecT
		[entryList(v)] = [zip(entryList(v1), replicate(s, dim),
			function(a, b) return `a*b end)]
		return v
	end
	VecT.metamethods.__mul:adddefinition((terra(s: real, v1: VecT)
		var v : VecT
		[entryList(v)] = [zip(entryList(v1), replicate(s, dim),
			function(a, b) return `a*b end)]
		return v
	end):getdefinitions()[1])
	VecT.metamethods.__mul:adddefinition((terra(v1: VecT, v2: VecT)
		var v : VecT
		[entryList(v)] = [zip(entryList(v1), entryList(v2),
			function(a, b) return `a*b end)]
		return v
	end):getdefinitions()[1])
	util.inline(VecT.metamethods.__mul)
	VecT.metamethods.__div = terra(v1: VecT, s: real)
		var v : VecT
		[entryList(v)] = [zip(entryList(v1), replicate(s, dim),
			function(a, b) return `a/b end)]
		return v
	end
	VecT.metamethods.__div:adddefinition((terra(v1: VecT, v2: VecT)
		var v: VecT
		[entryList(v)] = [zip(entryList(v1), entryList(v2),
			function(a, b) return `a/b end)]
		return v
	end):getdefinitions()[1])
	util.inline(VecT.metamethods.__div)
	VecT.metamethods.__unm = terra(v1: VecT)
		var v : VecT
		[entryList(v)] = [wrap(entryList(v1), function(e) return `-e end)]
		return v
	end
	util.inline(VecT.metamethods.__unm)

	-- Comparison operators
	VecT.metamethods.__eq = terra(v1: VecT, v2: VecT)
		return [reduce(zip(entryList(v1), entryList(v2),
						   function(a,b) return `a == b end),
					   function(a,b) return `a and b end)]
	end
	VecT.metamethods.__eq:adddefinition((terra(v1: VecT, s: real)
		return [reduce(zip(entryList(v1), replicate(s, dim),
						   function(a,b) return `a == b end),
					   function(a,b) return `a and b end)]
	end):getdefinitions()[1])
	VecT.metamethods.__gt = terra(v1: VecT, v2: VecT)
		return [reduce(zip(entryList(v1), entryList(v2),
						   function(a,b) return `a > b end),
					   function(a,b) return `a and b end)]
	end
	VecT.metamethods.__gt:adddefinition((terra(v1: VecT, s: real)
		return [reduce(zip(entryList(v1), replicate(s, dim),
						   function(a,b) return `a > b end),
					   function(a,b) return `a and b end)]
	end):getdefinitions()[1])
	VecT.metamethods.__ge = terra(v1: VecT, v2: VecT)
		return [reduce(zip(entryList(v1), entryList(v2),
						   function(a,b) return `a >= b end),
					   function(a,b) return `a and b end)]
	end
	VecT.metamethods.__ge:adddefinition((terra(v1: VecT, s: real)
		return [reduce(zip(entryList(v1), replicate(s, dim),
						   function(a,b) return `a >= b end),
					   function(a,b) return `a and b end)]
	end):getdefinitions()[1])
	VecT.metamethods.__lt = terra(v1: VecT, v2: VecT)
		return [reduce(zip(entryList(v1), entryList(v2),
						   function(a,b) return `a < b end),
					   function(a,b) return `a and b end)]
	end
	VecT.metamethods.__lt:adddefinition((terra(v1: VecT, s: real)
		return [reduce(zip(entryList(v1), replicate(s, dim),
						   function(a,b) return `a < b end),
					   function(a,b) return `a and b end)]
	end):getdefinitions()[1])
	VecT.metamethods.__le = terra(v1: VecT, v2: VecT)
		return [reduce(zip(entryList(v1), entryList(v2),
						   function(a,b) return `a <= b end),
					   function(a,b) return `a and b end)]
	end
	VecT.metamethods.__le:adddefinition((terra(v1: VecT, s: real)
		return [reduce(zip(entryList(v1), replicate(s, dim),
						   function(a,b) return `a <= b end),
					   function(a,b) return `a and b end)]
	end):getdefinitions()[1])

	-- Other mathematical operations
	terra VecT:dot(v: VecT)
		return [reduce(zip(entryList(self), entryList(v), function(a,b) return `a*b end),
					   function(a,b) return `a+b end)]
	end
	util.inline(VecT.methods.dot)
	terra VecT:distSq(v: VecT)
		return [reduce(wrap(zip(entryList(self), entryList(v),
								function(a,b) return `a-b end),
							function(a) return quote var aa = a in aa*aa end end),
					   function(a,b) return `a+b end)]
	end
	util.inline(VecT.methods.distSq)
	terra VecT:dist(v: VecT)
		return ad.math.sqrt(self:distSq(v))
	end
	util.inline(VecT.methods.distSq)
	terra VecT:normSq()
		return [reduce(wrap(entryList(self),
							function(a) return `a*a end),
					   function(a,b) return `a+b end)]
	end
	util.inline(VecT.methods.normSq)
	terra VecT:norm()
		return ad.math.sqrt(self:normSq())
	end
	util.inline(VecT.methods.norm)

	terra VecT:distSqToLineSeg(a: VecT, b: VecT) : real
		var sqlen = a:distSq(b)
		-- Degenerate zero length segment
		if sqlen == 0.0 then return self:distSq(a) end
		var t = (@self - a):dot(b - a) / sqlen
		-- Beyond the bounds of the segment
		if t < 0.0 then return self:distSq(a) end
		if t > 1.0 then return self:distSq(b) end
		-- Normal case (projection onto segment)
		var proj = a + t*(b - a)
		return self:distSq(proj)
	end

	-- Mapping arbitrary functions over vector elements
	function VecT.map(vec, fn)
		return quote
			var v : VecT
			[entryList(v)] = [wrap(entryList(vec), fn)]
		in
			v
		end
	end
	function VecT.zip(vec1, vec2, fn)
		return quote
			var v : VecT
			[entryList(v)] = [zip(entryList(vec1), entryList(vec2), fn)]
		in
			v
		end
	end
	function VecT.foreach(vec, fn)
		return quote
			[wrap(entryList(vec), fn)]
		end
	end
	function VecT.foreachPair(vec1, vec2, fn)
		return quote
			[zip(entryList(vec1), entryList(vec2), fn)]
		end
	end
	function VecT.foreachTuple(fn, ...)
		local entryLists = {}
		for i=1,select("#",...) do
			table.insert(entryLists, entryList((select(i,...))))
		end
		local stmts = {}
		for i=1,#entryLists[1] do
			local entries = {}
			for _,eList in ipairs(entryLists) do
				table.insert(entries, eList[i])
			end
			table.insert(stmts, fn(unpack(entries)))
		end
		return stmts
	end
	function VecT.entryExpList(vec)
		return entryList(vec)
	end

	-- Min/max
	terra VecT:maxInPlace(other: VecT)
		[entryList(self)] = [zip(entryList(self), entryList(other),
			function(a,b) return `ad.math.fmax(a, b) end)]
	end
	util.inline(VecT.methods.maxInPlace)
	terra VecT:max(other: VecT)
		var v = m.copy(@self)
		v:maxInPlace(other)
		return v
	end
	util.inline(VecT.methods.max)
	terra VecT:minInPlace(other: VecT)
		[entryList(self)] = [zip(entryList(self), entryList(other),
			function(a,b) return `ad.math.fmin(a, b) end)]
	end
	util.inline(VecT.methods.minInPlace)
	terra VecT:min(other: VecT)
		var v = m.copy(@self)
		v:minInPlace(other)
		return v
	end
	util.inline(VecT.methods.min)


	if real == ad.num then
		-- Conversion to raw double vector
		terra VecT:val()
			var v : Vec(double, dim)
			[entryList(v)] = [wrap(entryList(self),
				function(x) return `x:val() end)]
			return v
		end
		util.inline(VecT.methods.val)
	end


	m.addConstructors(VecT)
	return VecT

end)


-- Convenience method for defining AD primitives that take Vec arguments
function Vec.makeADPrimitive(argTypes, fwdMacro, adjMacro)
	-- Pack a block of scalars into a vector
	local vecpack = macro(function(...)
		local scalars = {...}
		local typ = (select(1,...)):gettype()
		return `[Vec(typ, #scalars)].stackAlloc([scalars])
	end)
	-- Generate code to pack blocks of symbols into vectors
	local function packBlocks(symBlocks, doTouch)
		local function touch(x) if doTouch then return `[x]() else return x end end
		local function touchAll(xs)
			if doTouch then
				local out = {}
				for _,x in ipairs(xs) do table.insert(out, touch(x)) end
				xs = out
			end
			return xs
		end
		local args = {}
		for _,syms in ipairs(symBlocks) do
			if #syms == 1 then
				table.insert(args, touch(syms[1]))
			else
				table.insert(args, `vecpack([touchAll(syms)]))
			end
		end
		return args
	end
	-- Figure out how many components we have per type
	local compsPerType = {}
	for _,t in ipairs(argTypes) do
		-- argType must either be a double or a Vec of doubles
		assert(t == double or (t.__generatorTemplate == Vec and t.RealType == double))
		local comps = 0
		if t.__generatorTemplate == Vec then comps = t.Dimension else comps = 1 end
		table.insert(compsPerType, comps)
	end
	-- Build symbols to refer to forward function parameters
	local symbolBlocks = {}
	for _,numc in ipairs(compsPerType) do
		local syms = {}
		for i=1,numc do table.insert(syms, symbol(double)) end
		table.insert(symbolBlocks, syms)
	end
	local allsyms = util.concattables(unpack(symbolBlocks))
	-- Build the forward function
	local terra fwdFn([allsyms])
		return fwdMacro([packBlocks(symbolBlocks)])
	end
	-- Now, the adjoint function
	local function adjFn(...)
		local adjArgTypes = {}
		symbolBlocks = {}
		local index = 1
		-- Build symbol blocks
		for _,numc in ipairs(compsPerType) do
			local typ = (select(index,...))
			table.insert(adjArgTypes, typ)
			index = index + numc
			local syms = {}
			for i=1,numc do table.insert(syms, symbol(typ)) end
			table.insert(symbolBlocks, syms)
		end
		allsyms = util.concattables(unpack(symbolBlocks))
		return terra(v: ad.num, [allsyms])
			return adjMacro(v, [packBlocks(symbolBlocks, true)])
		end
	end
	-- Construct an AD primitive
	local adprim = ad.def.makePrimitive(fwdFn, adjFn, compsPerType)
	-- Return a wrapper for this AD primitive that unpacks vectors into
	--    blocks of scalars.
	return macro(function(...)
		local unpackedArgs = {}
		for i=1,select("#",...) do
			local arg = (select(i,...))
			local typ = arg:gettype()
			if typ.__generatorTemplate == Vec then
				unpackedArgs = util.concattables(unpackedArgs, typ.entryExpList(arg))
			else
				table.insert(unpackedArgs, arg)
			end
		end
		return `adprim([unpackedArgs])
	end)
end


return
{
	Vec = Vec
}



