local util = terralib.require("util")

local sourcefile = debug.getinfo(1, "S").source:gsub("@", "")
local dir = sourcefile:gsub("init.t", "")

util.wait(string.format("cd %s; make", dir))

local header = sourcefile:gsub("init.t", "exports.h")
local linsolve = terralib.includec(header)

local lib = sourcefile:gsub("init.t", "liblinsolve.so")
terralib.linklibrary(lib)

------------------------------------------------------------

local Vector = terralib.require("vector")
local Grid2D = terralib.require("grid").Grid2D

-- Wrap solvers in Terra code that handles data conversion
terra leastSquares(A: &Grid2D(double), b: &Vector(double), x: &Vector(double))
	-- x should be as big as A has columns
	x:resize(A.cols)
	linsolve.leastSquares(A.rows, A.cols, A.data, b.__data, x.__data)
end
terra fullRankGeneral(A: &Grid2D(double), b: &Vector(double), x: &Vector(double))
	x:resize(A.cols)
	linsolve.fullRankGeneral(A.rows, A.cols, A.data, b.__data, x.__data)
end
terra fullRankSemidefinite(A: &Grid2D(double), b: &Vector(double), x: &Vector(double))
	x:resize(A.cols)
	linsolve.fullRankSemidefinite(A.rows, A.cols, A.data, b.__data, x.__data)
end

local _module = 
{
	leastSquares = leastSquares,
	fullRankGeneral = fullRankGeneral,
	fullRankSemidefinite = fullRankSemidefinite
}

--------- TESTS ----------

-- local m = terralib.require("mem")
-- local C = terralib.includecstring [[
-- #include <stdio.h>
-- #include <math.h>
-- ]]

-- local errThresh = 1e-6
-- local checkVal = macro(function(actual, target)
-- 	return quote
-- 		var err = C.fabs(actual-target)
-- 		util.assert(err < errThresh, "Value was %g, should've been %g\n", actual, target)
-- 	end
-- end)

-- local terra tests()

-- 	-- Fully determined
-- 	var A = [Grid2D(double)].stackAlloc(2, 2)
-- 	A(0,0) = 1.0; A(0,1) = 2.0;
-- 	A(1,0) = 3.0; A(1,1) = 4.0;
-- 	var b = [Vector(double)].stackAlloc(2, 0.0)
-- 	b(0) = 1.0; b(1) = 1.0;
-- 	var x = [Vector(double)].stackAlloc()
-- 	leastSquares(&A, &b, &x)
-- 	checkVal(x(0), -1.0)
-- 	checkVal(x(1), 1.0)

-- 	-- Fully determined, full rank solver
-- 	fullRankGeneral(&A, &b, &x)
-- 	checkVal(x(0), -1.0)
-- 	checkVal(x(1), 1.0)

-- 	-- Under-determined
-- 	A:resize(2, 3)
-- 	A(0,0) = 1.0; A(0,1) = 2.0; A(0,2) = 3.0;
-- 	A(1,0) = 4.0; A(1,1) = 5.0; A(1,2) = 6.0;
-- 	leastSquares(&A, &b, &x)
-- 	checkVal(x(0), -0.5)
-- 	checkVal(x(1), 0.0)
-- 	checkVal(x(2), 0.5)

-- 	-- Over-determined
-- 	A:resize(3, 2)
-- 	A(0,0) = 1.0; A(0,1) = 2.5;
-- 	A(1,0) = 3.0; A(1,1) = 4.0;
-- 	A(2,0) = 5.0; A(2,1) = 6.0;
-- 	b:resize(3);
-- 	b(0) = 1.0; b(1) = 1.0; b(2) = 1.0;
-- 	leastSquares(&A, &b, &x)
-- 	checkVal(x(0), -5.470085470085458e-01)
-- 	checkVal(x(1), 6.324786324786315e-01)

-- 	m.destruct(b)
-- 	m.destruct(x)
-- 	m.destruct(A)
-- end

-- tests()

-------------------------

return _module






