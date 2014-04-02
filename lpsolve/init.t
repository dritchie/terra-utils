local util = terralib.require("util")


local sourcefile = debug.getinfo(1, "S").source:gsub("@", "")
local header = sourcefile:gsub("init.t", "lp_lib.h")

local lpsolve = terralib.includecstring(string.format([[
#define LPSOLVEAPIFROMLIB
#include "%s"

// Expose frequently-used constants
inline int _LE() { return LE; }
inline int _EQ() { return EQ; }
inline int _GE() { return GE; }
inline int _NOMEMORY() { return NOMEMORY; }
inline int _OPTIMAL() { return OPTIMAL; }
inline int _SUBOPTIMAL() { return SUBOPTIMAL; }
inline int _INFEASIBLE() { return INFEASIBLE; }
inline int _UNBOUNDED() { return UNBOUNDED; }
inline int _DEGENERATE() { return DEGENERATE; }
inline int _NUMFAILURE() { return NUMFAILURE; }
]], header))

lpsolve.LE = lpsolve._LE()
lpsolve.EQ = lpsolve._EQ()
lpsolve.GE = lpsolve._GE()
lpsolve.NOMEMORY = lpsolve._NOMEMORY()
lpsolve.OPTIMAL = lpsolve._OPTIMAL()
lpsolve.SUBOPTIMAL = lpsolve._SUBOPTIMAL()
lpsolve.INFEASIBLE = lpsolve._INFEASIBLE()
lpsolve.UNBOUNDED = lpsolve._UNBOUNDED()
lpsolve.DEGENERATE = lpsolve._DEGENERATE()
lpsolve.NUMFAILURE = lpsolve._NUMFAILURE()

local dylib = sourcefile:gsub("init.t", "liblpsolve55.dylib")
terralib.linklibrary(dylib)


-- terra test()
-- 	-- Make lp with no constraints and 2 variables
-- 	var lp = lpsolve.make_lp(0, 2)

-- 	lpsolve.set_verbose(lp, 0)

-- 	-- Bound the first variable between -1 and 1
-- 	lpsolve.set_lowbo(lp, 0, -1.0)
-- 	lpsolve.set_upbo(lp, 0, 1.0)

-- 	-- Constrain the sum of the two variables to be 0.5
-- 	-- (first element of the array has to be zero, apparently.)
-- 	var coeffs = array(0.0, 1.0, 1.0)
-- 	lpsolve.add_constraint(lp, coeffs, lpsolve.EQ, 0.5)

-- 	-- Going to try *not* setting the objective function, since
-- 	--    I only care about feasibility testing. Hopefully this
-- 	--    will work OK...

-- 	lpsolve.solve(lp)

-- 	lpsolve.print_objective(lp)
-- 	lpsolve.print_solution(lp, 1)
-- 	lpsolve.print_constraints(lp, 1)
-- end
-- test()


return lpsolve