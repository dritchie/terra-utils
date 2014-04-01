
local C = terralib.includecstring [[
#define LPSOLVEAPIFROMLIB
#include "lp_lib.h"

// Expose frequently-used constants
inline int _LE() { return LE; }
inline int _EQ() { return EQ; }
inline int _GE() { return GE; }
]]

C.LE = C._LE()
C.EQ = C._EQ()
C.GE = C._GE()

terralib.linklibrary("liblpsolve55.dylib")

return C