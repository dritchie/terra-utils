local m = terralib.require("mem")
local Vector = terralib.require("vector")
local Grid2D = terralib.require("grid").Grid2D
local ad = terralib.require("ad")
local linsolve = terralib.require("linsolve")
local util = terralib.require("util")
local C = terralib.includecstring [[
#include <stdio.h>
#include <math.h>
#include <float.h>
inline double dbl_epsilon() { return DBL_EPSILON; }
]]


-- Takes a function (or macro) from dual vectors to dual vectors and wraps it in a macro
--    that behaves like an overloaded function with two definitions: (1) from double
--    vectors to double vectors and (2) from double vectors to double vectors with an added Jacobian.
local function wrapDualFn(fn)
	return macro(function(...)
		local args = {...}
		local numargs = select("#", ...)
		assert(numargs == 2 or numargs == 3)
		local x = args[1]
		local y = args[2]
		local J = args[3]
		return quote
			var x_dual = [Vector(ad.num)].stackAlloc(x.size, 0.0)
			for i=0,x.size do x_dual(i) = ad.num(x(i)) end
			var y_dual = [Vector(ad.num)].stackAlloc()
			fn(&x_dual, &y_dual)
			y:resize(y_dual.size)
			for i=0,y.size do y(i) = y_dual(i):val() end
			-- Simple version that just executes the primal version and throws away
			--    the tape.
			[util.optionally(numargs == 2, function() return quote
				ad.recoverMemory()
			end end)]
			-- Full version, with Jacobian and everything
			[util.optionally(numargs == 3, function() return quote
				ad.jacobian(&y_dual, &x_dual, J)
			end end)]
			m.destruct(x_dual)
			m.destruct(y_dual)
		end
	end)
end


-- Return codes for Newton solvers
local ReturnCodes = 
{
	ConvergedToSolution = 0,
	ConvergedToLocalMinimum = 1,
	ConvergedToNonSolution = 2,
	DidNotConverge = 3
}


-- NOTE: In general, everything in this file generates and returns macros, rather than functions,
--    because we don't know anything about where the function-like object F comes from. In particular
--    if it refers to a variable from another function's scope (emulating a closure), then we cannot
--    use it in any other function--we must use macros instead.


-- Generates functions that do Newton's method to try and solve non-linear systems
--    of equations
-- F: Function describing system to be solved. Should be overloaded with two definitions:
--    - #1: Takes a vector of input doubles and fills in a
--    		   vector of output doubles.
--    - #2: Takes a vector of input doubles and fills in a
--    		   vector of output doubles as well as an output Jacobian grid.
--    F can also be a macro that behaves in this way.
-- linsolver: Function that solves the linear system Ax = b, taking a grid A and a vector b and
--    fills in a vector x. Can be a fully-determined solve or a least-squares/min-norm solve.
function newton(F, linsolver, convergeThresh, maxIters)
	convergeThresh = convergeThresh or 1e-10
	maxIters = maxIters or 100
	return macro(function(x)
		return quote
			var y = [Vector(double)].stackAlloc()
			var J = [Grid2D(double)].stackAlloc(2, 2)
			var delta = [Vector(double)].stackAlloc()
			var b = [Vector(double)].stackAlloc()
			var converged = ReturnCodes.DidNotConverge
			for iter=0,maxIters do
				F(x, &y, &J)
				-- Update rule is J(x) * (x' - x) = -F(x)
				b:resize(y.size)
				for i=0,y.size do b(i) = -y(i) end
				linsolver(&J, &b, &delta)
				-- Update x in place
				for i=0,x.size do
					x(i) = x(i) + delta(i)
				end
				-- We've converged to a solution if the outputs are zero
				var ynorm = 0.0
				for i=0,y.size do
					ynorm = ynorm + y(i)*y(i)
				end
				if ynorm < convergeThresh then
					converged = ReturnCodes.ConvergedToSolution
					break
				end
				-- Also terminate if the parameters aren't changing, though
				--    this is 'bad' convergence (so don't mark it as 'converged')
				var deltaNorm = 0.0
				for i=0,y.size do
					deltaNorm = deltaNorm + delta(i)*delta(i)
				end
				if deltaNorm < convergeThresh then
					converged = ReturnCodes.ConvergedToNonSolution
					break
				end
			end
			m.destruct(b)
			m.destruct(delta)
			m.destruct(J)
			m.destruct(y)
		in
			converged
		end
	end)
end

--
-- TODO: This doesn't seem to work very well. Figure out what's going on(?)
--
-- Like newton, but uses backtracking line search for better convergence.
-- stepMax is a threshold on the norm of the initial Newton step. If the step is bigger than this,
--    we first normalize it.
-- (Implementation based on that of Numerical Recipes 3rd edition)
function backtrackingNewton(F, linsolver, convergeThresh, maxIters, stepMax)
	convergeThresh = convergeThresh or 1e-10
	maxIters = maxIters or 100
	stepMax = stepMax or 1e5

	-- Compute f(x) = 1/2 * F(x) * F(x)
	local terra halfDotProd(y: &Vector(double))
		var sum = 0.0
		for i=0,y.size do sum = y(i)*y(i) end
		return 0.5*sum
	end
	local f = macro(function(x)
		return quote
			var y = [Vector(double)].stackAlloc()
			F(x, &y)
			var ret = halfDotProd(&y)
			m.destruct(y)
		in
			ret
		end
	end)

	-- Given initial point x0 and Newton step p, fill in a new point xOut along p that
	--    decreases the value of f sufficiently.
	-- Returns true if the search succeeded, false if the new point is too close
	--    to the starting point.
	local alpha = 1e-4
	local lineSearch = macro(function(x0, f0, fGrad0, p, xOut)
		return quote
			-- Vars we'll need
			var f2 = 0.0
			var lambda2 = 0.0
			-- Compute slope of the step as a function of lambda at x0
			var slope = 0.0
			for i=0,p.size do slope = slope + fGrad0(i) * p(i) end
			-- Have to normalize initial step?
			var pnorm = 0.0
			for i=0,p.size do pnorm = pnorm + p(i)*p(i) end
			pnorm = C.sqrt(pnorm)
			if pnorm > stepMax then for i=0,p.size do p(i) = p(i)/pnorm end end
			-- Figure out the minimum lambda we're willing to accept
			var test = 0.0
			for i=0,p.size do
				var temp = C.fabs(p(i))/C.fmax(C.fabs(x0(i)), 1.0)
				test = C.fmax(test, temp)
			end
			var lambdaMin = C.dbl_epsilon() / test
			-- C.printf("lambdaMin: %g\n", lambdaMin)
			-- Start the backtracking loop
			var lambda = 1.0
			xOut:resize(x0.size)
			var succeeded = false
			while true do
				-- C.printf("lambda: %g\n", lambda)
				for i=0,p.size do xOut(i) = x0(i) + lambda*p(i) end
				var f1 = f(xOut)
				-- Terminate if we're too close to the starting point; this may signify
				--    convergence, or we may be stuck in a local minimum of f
				if lambda < lambdaMin then
					break
				end
				-- Terminate if we've sufficiently decreased f
				if f1 <= f0 + alpha*lambda*slope then
					succeeded = true
					break
				end
				-- Otherwise, we need to backtrack
				var tmpLambda = lambda
				-- If this is the first backtrack, use a quadratic approximation
				if lambda == 1.0 then
					tmpLambda = -slope / (2.0 * (f1 - f0 - slope))
				-- If this is backtrack #2 or higher, use a cubic approximation
				else
					var rhs1 = f1 - f0 - lambda*slope
					var rhs2 = f2 - f0 - lambda2*slope
					var a = (rhs1 / (lambda*lambda) - rhs2 / (lambda2*lambda2)) / (lambda - lambda2)
					var b = (-lambda2*rhs1 / (lambda*lambda) + lambda*rhs2 / (lambda2*lambda2)) / (lambda - lambda2)
					if a == 0.0 then
						tmpLambda = -slope / (2.0*b)
					else
						var disc = b*b - 3.0*a*slope
						if disc < 0.0 then tmpLambda = 0.5*lambda
						elseif b <= 0 then tmpLambda = (-b + C.sqrt(disc)) / (3.0*a)
						else tmpLambda = -slope / (b + C.sqrt(disc)) end
					end
					-- Guard against too big lambdas
					tmpLambda = C.fmin(tmpLambda, 0.5*lambda)
				end
				lambda2 = lambda
				f2 = f1
				-- Guard against too small lambdas
				lambda = C.fmax(tmpLambda, 0.1*lambda)
			end
		in
			succeeded
		end
	end)

	return macro(function(x)
		return quote
			var xNew = [Vector(double)].stackAlloc(x.size, 0.0)
			var fGrad0 = [Vector(double)].stackAlloc(x.size, 0.0)
			var y = [Vector(double)].stackAlloc()
			var J = [Grid2D(double)].stackAlloc(2, 2)
			var p = [Vector(double)].stackAlloc()
			var b = [Vector(double)].stackAlloc()
			var converged = ReturnCodes.DidNotConverge
			for iter=0,maxIters do
				F(x, &y, &J)
				-- Compute full Newton step: p = J(x) * (x' - x) = -F(x)
				b:resize(y.size)
				for i=0,y.size do b(i) = -y(i) end
				linsolver(&J, &b, &p)

				-- Backtracking line search
				var f0 = halfDotProd(&y)
				-- The gradient of f w.r.t x is just y*J, or a vector where element j
				--    is the dot product of y with column j of J (i.e. J(.,j))
				for j=0,x.size do
					var sum = 0.0
					for i=0,y.size do
						sum = sum + y(i)*J(i,j)
					end
					fGrad0(j) = sum
				end
				var lineSearchSucceeded = lineSearch(x, f0, &fGrad0, &p, &xNew)

				-- If y has converged to zeros, then we know we can terminate
				var ynorm = 0.0
				for i=0,y.size do
					ynorm = ynorm + y(i)*y(i)
				end
				if ynorm < convergeThresh then
					converged = ReturnCodes.ConvergedToSolution
					-- C.printf("Terminating due to output convergence\n")
					break
				end

				-- If the search failed to find a distant enough point, then we
				--    also terminate, though this is a 'bad' convergence, since
				--    the equations have not been satisfied.
				-- We also check whether the termination was caused by us reaching
				--    a local mininum of f (i.e. gradient of f all zeros)
				if not lineSearchSucceeded then
					var gradnorm = 0.0
					for i=0,fGrad0.size do gradnorm = gradnorm + fGrad0(i)*fGrad0(i) end
					gradnorm = C.sqrt(gradnorm)
					if gradnorm < convergeThresh then
						converged = ReturnCodes.ConvergedToLocalMinimum
					else
						converged = ReturnCodes.ConvergedToNonSolution
					end
					-- C.printf("Line search failed to find a distant enough point\n")
					break
				end

				-- Finally, we terminate if the parameters haven't changed much.
				-- (Again, this is a 'bad' convergence)
				var pnorm = 0.0
				for i=0,x.size do
					var diff = xNew(i) - x(i)
					pnorm = pnorm + diff*diff
					x(i) = xNew(i)
				end
				if pnorm < convergeThresh then
					converged = ReturnCodes.ConvergedToNonSolution
					-- C.printf("Terminating due to parameter convergence\n")
					break
				end
			end
			m.destruct(b)
			m.destruct(p)
			m.destruct(J)
			m.destruct(y)
			m.destruct(fGrad0)
			m.destruct(xNew)
		in
			converged
		end
	end)
end


-- 
-- TODO: ehhh, this also doesn't really work...
--
-- Like backtrackingNewton, but does its line search using a stupid-simple
--    halving approach
local function simpleBacktrackingNewton(F, linsolver, convergeThresh, maxIters)
	convergeThresh = convergeThresh or 1e-10
	maxIters = maxIters or 100

	-- Compute f(x) = 1/2 * F(x) * F(x)
	local terra halfDotProd(y: &Vector(double))
		var sum = 0.0
		for i=0,y.size do sum = y(i)*y(i) end
		return 0.5*sum
	end
	local f = macro(function(x)
		return quote
			var y = [Vector(double)].stackAlloc()
			F(x, &y)
			var ret = halfDotProd(&y)
			m.destruct(y)
		in
			ret
		end
	end)

	-- Really dumb 'line search' that just repeatedly halves lambda until it finds a step that
	--    decreases f (or it gives up due to a too-small step)
	local alpha = 1e-4
	local lineSearch = macro(function(x0, f0, fGrad0, p, xOut)
		return quote
			-- Compute slope of the step as a function of lambda at x0
			var slope = 0.0
			for i=0,p.size do slope = slope + fGrad0(i) * p(i) end
			-- Figure out the minimum lambda we're willing to accept
			var test = 0.0
			for i=0,p.size do
				var temp = C.fabs(p(i))/C.fmax(C.fabs(x0(i)), 1.0)
				test = C.fmax(test, temp)
			end
			var lambdaMin = C.dbl_epsilon() / test
			-- Start the backtracking loop
			var lambda = 1.0
			xOut:resize(x0.size)
			var succeeded = false
			while true do
				for i=0,p.size do xOut(i) = x0(i) + lambda*p(i) end
				var f1 = f(xOut)
				-- Terminate if we're too close to the starting point; this may signify
				--    convergence, or we may be stuck in a local minimum of f
				if lambda < lambdaMin then
					break
				end
				-- Terminate if we've sufficiently decreased f
				-- if f1 <= f0 + alpha*lambda*slope then return true end
				if f1 < f0 then
					succeeded = true
					break
				end
				-- Otherwise, we need to backtrack
				lambda = 0.5*lambda
			end
		in
			succeeded
		end
	end)

	return macro(function(x)
		return quote
			var xNew = [Vector(double)].stackAlloc(x.size, 0.0)
			var fGrad0 = [Vector(double)].stackAlloc(x.size, 0.0)
			var y = [Vector(double)].stackAlloc()
			var J = [Grid2D(double)].stackAlloc(2, 2)
			var p = [Vector(double)].stackAlloc()
			var b = [Vector(double)].stackAlloc()
			var converged = ReturnCodes.DidNotConverge
			for iter=0,maxIters do
				F(x, &y, &J)
				-- Compute full Newton step: p = J(x) * (x' - x) = -F(x)
				b:resize(y.size)
				for i=0,y.size do b(i) = -y(i) end
				linsolver(&J, &b, &p)

				-- Backtracking line search
				var f0 = halfDotProd(&y)
				-- The gradient of f w.r.t x is just y*J, or a vector where element j
				--    is the dot product of y with column j of J (i.e. J(.,j))
				for j=0,x.size do
					var sum = 0.0
					for i=0,y.size do
						sum = sum + y(i)*J(i,j)
					end
					fGrad0(j) = sum
				end
				var lineSearchSucceeded = lineSearch(x, f0, &fGrad0, &p, &xNew)

				-- If y has converged to zeros, then we know we can terminate
				var ynorm = 0.0
				for i=0,y.size do
					ynorm = ynorm + y(i)*y(i)
				end
				if ynorm < convergeThresh then
					converged = ReturnCodes.ConvergedToSolution
					-- C.printf("Terminating due to output convergence\n")
					break
				end

				-- If the search failed to find a distant enough point, then we
				--    also terminate, though this is a 'bad' convergence, since
				--    the equations have not been satisfied.
				-- We also check whether the termination was caused by us reaching
				--    a local mininum of f (i.e. gradient of f all zeros)
				if not lineSearchSucceeded then
					var gradnorm = 0.0
					for i=0,fGrad0.size do gradnorm = gradnorm + fGrad0(i)*fGrad0(i) end
					gradnorm = C.sqrt(gradnorm)
					if gradnorm < convergeThresh then
						converged = ReturnCodes.ConvergedToLocalMinimum
					else
						converged = ReturnCodes.ConvergedToNonSolution
					end
					-- C.printf("Line search failed to find a distant enough point\n")
					break
				end

				-- Finally, we terminate if the parameters haven't changed much.
				-- (Again, this is a 'bad' convergence)
				var pnorm = 0.0
				for i=0,x.size do
					var diff = xNew(i) - x(i)
					pnorm = pnorm + diff*diff
					x(i) = xNew(i)
				end
				if pnorm < convergeThresh then
					converged = ReturnCodes.ConvergedToNonSolution
					-- C.printf("Terminating due to parameter convergence\n")
					break
				end
			end
			m.destruct(b)
			m.destruct(p)
			m.destruct(J)
			m.destruct(y)
			m.destruct(fGrad0)
			m.destruct(xNew)
		in
			converged
		end
	end)
end


function newtonLeastSquares(F, convergeThresh, maxIters)
	return newton(F, linsolve.leastSquares, convergeThresh, maxIters)
end

function newtonFullRank(F, convergeThresh, maxIters)
	return newton(F, linsolve.fullRankGeneral, convergeThresh, maxIters)
end

-- function backtrackingNewtonLeastSquares(F, convergeThresh, maxIters)
-- 	return backtrackingNewton(F, linsolve.leastSquares, convergeThresh, maxIters)
-- end

-- function backtrackingNewtonFullRank(F, convergeThresh, maxIters)
-- 	return backtrackingNewton(F, linsolve.fullRankGeneral, convergeThresh, maxIters)
-- end

local _module = 
{
	wrapDualFn = wrapDualFn,
	ReturnCodes = ReturnCodes,
	newton = newton,
	newtonLeastSquares = newtonLeastSquares,
	newtonFullRank = newtonFullRank
	-- backtrackingNewton = backtrackingNewton,
	-- backtrackingNewtonLeastSquares = backtrackingNewtonLeastSquares,
	-- backtrackingNewtonFullRank = backtrackingNewtonFullRank
}


--------- TESTS ----------

-- -- (x-4)*(y-5) = 0
-- -- (Infinitely many roots with x = 4 or y = 5)
-- local terra underdetermined_impl(input: &Vector(ad.num), output: &Vector(ad.num))
-- 	output:resize(1)
-- 	output(0) = (input(0) - 4.0) * (input(1) - 5.0)
-- end
-- local underdetermined = wrapDualFn(underdetermined_impl)

-- -- x*y - 12 = 0
-- local terra underdetermined2_impl(input: &Vector(ad.num), output: &Vector(ad.num))
-- 	output:resize(1)
-- 	output(0) = input(0)*input(1) - 12.0
-- end
-- local underdetermined2 = wrapDualFn(underdetermined2_impl)

-- -- (x-4)*(y-5) = 0
-- -- x*y - 12 = 0
-- -- (Roots are (4,3) and (2.4,5))
-- local terra fullydetermined_impl(input: &Vector(ad.num), output: &Vector(ad.num))
-- 	output:resize(2)
-- 	output(0) = (input(0) - 4.0) * (input(1) - 5.0)
-- 	output(1) = input(0)*input(1) - 12.0
-- end
-- local fullydetermined = wrapDualFn(fullydetermined_impl)

-- local assertConverged = macro(function(testnum, retcode)
-- 	return quote
-- 		util.assert(retcode == ReturnCodes.ConvergedToSolution, "Test %d terminated with return code %d\n", testnum, retcode)
-- 	end
-- end)

-- local function tests(method)
-- 	return terra()
-- 		var x = [Vector(double)].stackAlloc()
-- 		var converged : int
			
-- 		-- 1: Underdetermined, least-squares
-- 		x:clear()
-- 		x:push(0.0); x:push(0.0)
-- 		converged = [method(underdetermined, linsolve.leastSquares)](&x)
-- 		-- C.printf("%g, %g\n", x(0), x(1))
-- 		assertConverged(1, converged)

-- 		-- 2: Underdetermined (2), least-squares
-- 		x:clear()
-- 		x:push(1.0); x:push(1.0)
-- 		converged = [method(underdetermined2, linsolve.leastSquares)](&x)
-- 		-- C.printf("%g, %g\n", x(0), x(1))
-- 		assertConverged(2, converged)

-- 		-- 3: Fully-determined, least-squares
-- 		x:clear()
-- 		x:push(5.0); x:push(10.0)
-- 		converged = [method(fullydetermined, linsolve.leastSquares)](&x)
-- 		-- C.printf("%g, %g\n", x(0), x(1))
-- 		assertConverged(3, converged)

-- 		-- 4: Fully-determined, full rank solver
-- 		x:clear()
-- 		x:push(5.0); x:push(10.0)
-- 		converged = [method(fullydetermined, linsolve.fullRankGeneral)](&x)
-- 		-- C.printf("%g, %g\n", x(0), x(1))
-- 		assertConverged(4, converged)

-- 	end
-- end

-- print("Testing simple newton solver...")
-- tests(newton)()
-- -- print("Testing backtracking newton solver...")
-- -- tests(backtrackingNewton)()
-- -- print("Testing simple backtracking newton solver...")
-- -- tests(simpleBacktrackingNewton)()
-- print("Done")

-------------------------

return _module





