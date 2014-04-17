local templatize = terralib.require("templatize")
local m = terralib.require("mem")
local util = terralib.require("util")
local ad = terralib.require("ad")

local C = terralib.includecstring [[
#include <stdio.h>
]]

-- Code gen helpers
local function replicate(val, n)
	local t = {}
	for i=1,n do table.insert(t, val) end
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

local Vec
Vec = templatize(function(real, dim)

	local struct VecT
	{
		entries: real[dim]
	}
	VecT.metamethods.__typename = function(self)
		return string.format("Vec(%s, %d)", tostring(real), dim)
	end
	VecT.RealType = real
	VecT.Dimension = dim

	local function entryList(self)
		local t = {}
		for i=1,dim do table.insert(t, `[self].entries[ [i-1] ]) end
		return t
	end
	local function symbolList()
		local t = {}
		for i=1,dim do table.insert(t, symbol(real)) end
		return t
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
	VecT.__templatecopy = templatize(function(real2, dim2)
		util.luaAssertWithTrace(dim2 == dim, "Cannot templatecopy to a vector of different dimensionality.")
		return terra(self: &VecT, other: &Vec(real2, dim2))
			[entryList(self)] = [wrap(entryList(other),
				function(a) return `[m.templatecopy(real)](a) end)]
		end
	end)

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
	terra VecT:angleBetween(v: VecT)
		var nd = (self:dot(v) / self:norm()) / v:norm()
		if nd == 1.0 then
			return real(0.0)
		else
			return ad.math.acos(nd)
		end
	end
	util.inline(VecT.methods.angleBetween)
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
	terra VecT:normalize()
		var n = self:norm()
		if n > 0.0 then
			[entryList(self)] = [wrap(entryList(self), function(a) return `a/n end)]
		end
	end
	util.inline(VecT.methods.normalize)

	local collinearThresh = 1e-16
	terra VecT:collinear(other: VecT)
		var n1 = self:norm()
		var n2 = other:norm()
		return 1.0 - ad.math.fabs(n1:dot(n2)/(n1*n2)) < collinearThresh
	end
	util.inline(VecT.methods.collinear)

	local planeThresh = 1e-16
	terra VecT:inPlane(p: VecT, n: VecT) : bool
		return ad.math.fabs((@self - p):dot(n)) < planeThresh
	end
	util.inline(VecT.methods.inPlane)

	-- Specific stuff for 3D Vectors
	if dim == 3 then
		terra VecT:cross(other: VecT)
			return VecT.stackAlloc(
				self(1)*other(2) - self(2)*other(1),
				self(2)*other(0) - self(0)*other(2),
				self(0)*other(1) - self(1)*other(0)
			)
		end
		util.inline(VecT.methods.cross)

		terra VecT:inPlane(p1: VecT, p2: VecT, p3: VecT) : bool
			var v1 = p2 - p1
			var v2 = p3 - p1
			var n = v1:cross(v2)
			return self:inPlane(p1, n)
		end
		util.inline(VecT.methods.inPlane)
	end

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
	VecT.elements = VecT.entryExpList

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

	-- absolute value
	terra VecT:absInPlace()
		[entryList(self)] = [wrap(entryList(self), function(a) return `ad.math.fabs(a) end)]
	end
	util.inline(VecT.methods.absInPlace)

	terra VecT:abs()
		var v = m.copy(@self)
		v:absInPlace()
		return v
	end
	util.inline(VecT.methods.abs)

	-- I/O
	terra VecT:print()
		C.printf("[")
		[wrap(entryList(self), function(a) return `C.printf("%g,", ad.val(a)) end)]
		C.printf("]")
	end
	util.inline(VecT.methods.print)

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


-- -- Convenience method for defining AD primitives that take Vec arguments
-- function Vec.makeADPrimitive(argTypes, fwdMacro, adjMacro)
-- 	-- Pack a block of scalars into a vector
-- 	local vecpack = macro(function(...)
-- 		local scalars = {...}
-- 		local typ = (select(1,...)):gettype()
-- 		return `[Vec(typ, #scalars)].stackAlloc([scalars])
-- 	end)
-- 	-- Generate code to pack blocks of symbols into vectors
-- 	local function packBlocks(symBlocks, doTouch)
-- 		local function touch(x) if doTouch then return `[x]() else return x end end
-- 		local function touchAll(xs)
-- 			if doTouch then
-- 				local out = {}
-- 				for _,x in ipairs(xs) do table.insert(out, touch(x)) end
-- 				xs = out
-- 			end
-- 			return xs
-- 		end
-- 		local args = {}
-- 		for _,syms in ipairs(symBlocks) do
-- 			if #syms == 1 then
-- 				table.insert(args, touch(syms[1]))
-- 			else
-- 				table.insert(args, `vecpack([touchAll(syms)]))
-- 			end
-- 		end
-- 		return args
-- 	end
-- 	-- Figure out how many components we have per type
-- 	local compsPerType = {}
-- 	for _,t in ipairs(argTypes) do
-- 		-- argType must either be a double or a Vec of doubles
-- 		assert(t == double or (t.__generatorTemplate == Vec and t.RealType == double))
-- 		local comps = 0
-- 		if t.__generatorTemplate == Vec then comps = t.Dimension else comps = 1 end
-- 		table.insert(compsPerType, comps)
-- 	end
-- 	-- Build symbols to refer to forward function parameters
-- 	local symbolBlocks = {}
-- 	for _,numc in ipairs(compsPerType) do
-- 		local syms = {}
-- 		for i=1,numc do table.insert(syms, symbol(double)) end
-- 		table.insert(symbolBlocks, syms)
-- 	end
-- 	local allsyms = util.concattables(unpack(symbolBlocks))
-- 	-- Build the forward function
-- 	local terra fwdFn([allsyms])
-- 		return fwdMacro([packBlocks(symbolBlocks)])
-- 	end
-- 	-- Now, the adjoint function
-- 	local function adjFn(...)
-- 		local adjArgTypes = {}
-- 		symbolBlocks = {}
-- 		local index = 1
-- 		-- Build symbol blocks
-- 		for _,numc in ipairs(compsPerType) do
-- 			local typ = (select(index,...))
-- 			table.insert(adjArgTypes, typ)
-- 			index = index + numc
-- 			local syms = {}
-- 			for i=1,numc do table.insert(syms, symbol(typ)) end
-- 			table.insert(symbolBlocks, syms)
-- 		end
-- 		allsyms = util.concattables(unpack(symbolBlocks))
-- 		return terra(v: ad.num, [allsyms])
-- 			return adjMacro(v, [packBlocks(symbolBlocks, true)])
-- 		end
-- 	end
-- 	-- Construct an AD primitive
-- 	local adprim = ad.def.makePrimitive(fwdFn, adjFn, compsPerType)
-- 	-- Return a wrapper for this AD primitive that unpacks vectors into
-- 	--    blocks of scalars.
-- 	return macro(function(...)
-- 		local unpackedArgs = {}
-- 		for i=1,select("#",...) do
-- 			local arg = (select(i,...))
-- 			local typ = arg:gettype()
-- 			if typ.__generatorTemplate == Vec then
-- 				unpackedArgs = util.concattables(unpackedArgs, typ.entryExpList(arg))
-- 			else
-- 				table.insert(unpackedArgs, arg)
-- 			end
-- 		end
-- 		return `adprim([unpackedArgs])
-- 	end)
-- end





local Mat
Mat = templatize(function(real, rowdim, coldim)
	local numelems = rowdim*coldim
	local struct MatT
	{
		entries: real[numelems]
	}
	MatT.RealType = real
	MatT.RowDimension = rowdim
	MatT.ColDimension = coldim

	MatT.metamethods.__typename = function(self)
		return string.format("Mat(%s, %d, %d)", tostring(real), rowdim, coldim)
	end

	local function entryList(self)
		local t = {}
		for i=1,numelems do table.insert(t, `[self].entries[ [i-1] ]) end
		return t
	end

	local function index(row, col)
		return row*coldim + col
	end

	local function diagonalElems(self)
		local t = {}
		for i=1,rowdim do
			table.insert(t, `self.entries[ [index(i-1,i-1)] ])
		end
		return t
	end

	-- Constructors and factories

	terra MatT:__construct()
		[entryList(self)] = [replicate(`0.0, numelems)]
	end

	MatT.methods.zero = terra()
		return MatT.stackAlloc()
	end

	MatT.methods.identity = terra()
		var mat = MatT.stackAlloc()
		[diagonalElems(mat)] = [replicate(`1.0, rowdim)]
		return mat
	end


	-- Copying and casting

	terra MatT:__copy(other: &MatT)
		[entryList(self)] = [entryList(other)]
	end

	MatT.__templatecopy = templatize(function(real2, rowdim2, coldim2)
		util.luaAssertWithTrace(rowdim == rowdim2 and coldim == coldim2,
			"Cannot templatecopy to a matrix of different dimensionality")
		return terra(self: &MatT, other: &Mat(real2, rowdim2, coldim2))
			[entryList(self)] = [wrap(entryList(other),
				function(a) return `[m.templatecopy(real)](a) end)]
		end
	end)

	function MatT.metamethods.__cast(from, to, exp)
		if (from.__generatorTemplate == Mat) and
		   (to.__generatorTemplate == Mat) and
		   (from.RowDimension == to.RowDimension) and
		   (from.ColDimension == to.ColDimension) then
		   return `[m.templatecopy(to.RealType)](from)
		elseif from.__generatorTemplate ~= Mat then
			error(string.format("Cannot cast non-matrix type %s to matrix type %s", from, to))
		elseif to.__generatorTemplate ~= Mat then
			error(string.format("Cannot cast matrix type %s to non-matrix type %s", from, to))
		elseif from.RowDimension ~= to.RowDimension or from.ColDimension ~= to.RowDimension then
			error(string.format("Cannot cast matrix type %s to differently-dimensioned matrix type %s", from, to))
		else
			error("Bad matrix cast")
		end
	end


	-- Element access

	MatT.metamethods.__apply = macro(function(self, i, j)
		return `self.entries[ i*coldim + j ]
	end)


	-- Matrix/matrix and Matrix/vector arithmetic

	terra MatT:addInPlace(m2: &MatT)
		[entryList(self)] = [zip(entryList(self), entryList(m2),
			function(a,b) return `a+b end)]
	end
	util.inline(MatT.methods.addInPlace)
	MatT.metamethods.__add = terra(m1: MatT, m2: MatT)
		var mat : MatT
		mat:addInPlace(&m2)
		return mat
	end
	util.inline(MatT.metamethods.__add)

	terra MatT:subInPlace(m2: &MatT)
		[entryList(self)] = [zip(entryList(self), entryList(m2),
			function(a,b) return `a-b end)]
	end
	util.inline(MatT.methods.subInPlace)
	MatT.metamethods.__sub = terra(m1: MatT, m2: MatT)
		var mat : MatT
		mat:subInPlace(m2)
		return mat
	end
	util.inline(MatT.metamethods.__sub)

	terra MatT:scaleInPlace(s: real)
		[entryList(self)] = [wrap(entryList(self),
			function(a) return `s*a end)]
	end
	util.inline(MatT.methods.scaleInPlace)
	MatT.metamethods.__mul = terra(m1: MatT, s: real)
		var mat: MatT
		mat:scaleInPlace(s)
		return mat
	end
	MatT.metamethods.__mul:adddefinition((terra(s: real, m1: MatT)
		var mat: MatT
		mat:scaleInPlace(s)
		return mat
	end):getdefinitions()[1])

	terra MatT:divInPlace(s: real)
		[entryList(self)] = [wrap(entryList(self),
			function(a) return `a/s end)]
	end
	util.inline(MatT.methods.divInPlace)
	MatT.metamethods.__div = terra(m1: MatT, s: real)
		var mat: MatT
		mat:divInPlace(s)
		return mat
	end
	util.inline(MatT.metamethods.__div)

	-- At the moment, I'll only support matrix/matrix multiply between
	--    square matrices
	if rowdim == coldim then
		local dim = rowdim
		MatT.metamethods.__mul:adddefinition((terra(m1: MatT, m2: MatT)
			var mout : MatT
			[(function()
				local stmts = {}
				for i=0,dim-1 do
					for j=0,dim-1 do
						local sumexpr = `real(0.0)
						for k=0,dim-1 do
							sumexpr = `[sumexpr] + m1(i,k)*m2(k,j)
						end
						table.insert(stmts, quote mout(i,j) = [sumexpr] end)
					end
				end
				return stmts
			end)()]
			return mout
		end):getdefinitions()[1])
		terra MatT:mulInPlace(m2: &MatT)
			@self = @self * @m2
		end
		util.inline(MatT.methods.mulInPlace)
	end

	local InVecT = Vec(real, coldim)
	local OutVecT = Vec(real, rowdim)
	MatT.metamethods.__mul:adddefinition((terra(m1: MatT, v: InVecT)
		var vout : OutVecT
		[(function()
			local stmts = {}
			for i=0,rowdim-1 do
				local sumexpr = `real(0.0)
				for j=0,coldim-1 do
					sumexpr = `[sumexpr] + m1(i,j)*v(j)
				end
				table.insert(stmts, quote vout(i) = [sumexpr] end)
			end
			return stmts
		end)()]
		return vout
	end):getdefinitions()[1])

	util.inline(MatT.metamethods.__mul)


	-- 3D Transformation matrices
	if rowdim == 4 and coldim == 4 then
		local Vec3 = Vec(real, 3)
		local Vec4 = Vec(real, 4)

		terra MatT:transformPoint(v: Vec3)
			var vout = @self * Vec4.stackAlloc(v(0), v(1), v(2), 1.0)
			if vout(3) == 0.0 then
				return Vec3.stackAlloc(0.0, 0.0, 0.0)
			else
				return Vec3.stackAlloc(vout(0), vout(1), vout(2)) / vout(3)
			end
		end
		util.inline(MatT.methods.transformPoint)

		terra MatT:transformVector(v: Vec3)
			var vout = @self * Vec4.stackAlloc(v(0), v(1), v(2), 0.0)
			return Vec3.stackAlloc(vout(0), vout(1), vout(2))
		end
		util.inline(MatT.methods.transformVector)

		MatT.methods.translate = terra(tx: real, ty: real, tz: real) : MatT
			var mat = MatT.identity()
			mat(0, 3) = tx
			mat(1, 3) = ty
			mat(2, 3) = tz
			return mat
		end
		MatT.methods.translate:adddefinition((terra(tv: Vec3) : MatT
			return MatT.translate(tv(0), tv(1), tv(2))
		end):getdefinitions()[1])

		MatT.methods.scale = terra(sx: real, sy: real, sz: real) : MatT
			var mat = MatT.identity()
			mat(0,0) = sx
			mat(1,1) = sy
			mat(2,2) = sz
			return mat
		end
		MatT.methods.scale:adddefinition((terra(s: real) : MatT
			return MatT.scale(s, s, s)
		end):getdefinitions()[1])

		MatT.methods.rotateX = terra(r: real)
			var mat = MatT.identity()
			var cosr = ad.math.cos(r)
			var sinr = ad.math.sin(r)
			mat(1,1) = cosr
			mat(1,2) = -sinr
			mat(2,1) = sinr
			mat(2,2) = cosr
			return mat
		end

		MatT.methods.rotateY = terra(r: real)
			var mat = MatT.identity()
			var cosr = ad.math.cos(r)
			var sinr = ad.math.sin(r)
			mat(0,0) = cosr
			mat(2,0) = -sinr
			mat(0,2) = sinr
			mat(2,2) = cosr
			return mat
		end

		MatT.methods.rotateZ = terra(r: real)
			var mat = MatT.identity()
			var cosr = ad.math.cos(r)
			var sinr = ad.math.sin(r)
			mat(0,0) = cosr
			mat(0,1) = -sinr
			mat(1,0) = sinr
			mat(1,1) = cosr
			return mat
		end

		MatT.methods.rotate = terra(axis: Vec3, angle: real) : MatT
			var c = ad.math.cos(angle)
			var s = ad.math.sin(angle)
			var t = 1.0 - c

			axis:normalize()
			var x = axis(0)
			var y = axis(1)
			var z = axis(2)

			var result : MatT

			result(0,0) = 1 + t*(x*x-1)
			result(1,0) = z*s+t*x*y
			result(2,0) = -y*s+t*x*z
			result(3,0) = 0.0

			result(0,1) = -z*s+t*x*y
			result(1,1) = 1+t*(y*y-1)
			result(2,1) = x*s+t*y*z
			result(3,1) = 0.0

			result(0,2) = y*s+t*x*z
			result(1,2) = -x*s+t*y*z
			result(2,2) = 1+t*(z*z-1)
			result(3,2) = 0.0

			result(0,3) = 0.0
			result(1,3) = 0.0
			result(2,3) = 0.0
			result(3,3) = 1.0

			return result
		end

		MatT.methods.rotate:adddefinition((terra(axis: Vec3, angle: real, center: Vec3) : MatT
			return MatT.translate(center) * MatT.rotate(axis, angle) * MatT.translate(-center)
		end):getdefinitions()[1])

		MatT.methods.face = terra(fromVec: Vec3, toVec: Vec3)
			var axis = fromVec:cross(toVec)
			if axis:norm() == 0.0 then
				return MatT.identity()
			else
				var ang = fromVec:angleBetween(toVec)
				return MatT.rotate(axis, ang)
			end
		end

	end


	m.addConstructors(MatT)
	return MatT
end)




return
{
	Vec = Vec,
	Mat = Mat
}




