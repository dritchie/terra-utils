local util = terralib.require("util")

-- Mac OSX only, for now
if not (util.osName() == "Darwin\n") then
	error("GLUT/OpenGL module currently only supported on OSX.")
end

-- Get GLUT header
local glut = util.includec_path("GLUT/glut.h")

-- Link dynamic libraries (Mac OSX only, for now)
terralib.linklibrary("/System/Library/Frameworks/OpenGL.framework/Libraries/libGL.dylib")
terralib.linklibrary("/System/Library/Frameworks/OpenGL.framework/Libraries/libGLU.dylib")
terralib.linklibrary("/System/Library/Frameworks/GLUT.framework/GLUT")

-- Add functions to module to return commonly-used macro constants that
--    are otherwise not accessible from Terra.

return glut