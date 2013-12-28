local util = terralib.require("util")

-- Mac OSX only, for now
if not (util.osName() == "Darwin\n") then
	error("GLUT/OpenGL module currently only supported on OSX.")
end

-- Automatically generate functions that return commonly-used macro constants
--    that are otherwise not accessible from Terra.
local function genConstantAccessorDef(constantName)
	return string.format("inline int m%s() { return %s; }\n", constantName, constantName)
end
local function genAllConstantAccessorDefs(constantNames)
	local code = ""
	for name,_ in pairs(constantNames) do
		code = code .. genConstantAccessorDef(name)
	end
	return code
end

-- Constants to be exposed
local constTable = {}
local function addConstants(constants)
	for _,c in ipairs(constants) do
		constTable[c] = true
	end
end
addConstants({
"GL_PROJECTION",
"GL_MODELVIEW",
"GL_COLOR_BUFFER_BIT",
"GL_DEPTH_BUFFER_BIT",
"GL_POINTS",
"GL_LINES",
"GL_QUADS",
"GL_QUAD_STRIP",
"GL_POLYGON",
"GL_TRIANGLES",
"GL_TRIANGLE_STRIP",
"GL_RGB",
"GL_RGBA",
"GL_UNSIGNED_BYTE",
"GLUT_RGB",
"GLUT_RGBA",
"GLUT_SINGLE",
"GLUT_DOUBLE",
"GLUT_DEPTH"
})

local function loadHeaders()
	-- Get GLUT header, adding functions for constants
	return util.includecstring_path(string.format([[
	#include <GLUT/glut.h>
	%s
	]], genAllConstantAccessorDefs(constTable)))
end

-- Initialize the module with the default set of constants exposed
local gl = loadHeaders()

-- Link dynamic libraries
terralib.linklibrary("/System/Library/Frameworks/OpenGL.framework/Libraries/libGL.dylib")
terralib.linklibrary("/System/Library/Frameworks/OpenGL.framework/Libraries/libGLU.dylib")
terralib.linklibrary("/System/Library/Frameworks/GLUT.framework/GLUT")

-- If you need access to additional macro constants, use this function.
-- It will reload the GLUT/OpenGL headers and add accessor functions for
--    the requested constants.
-- This is cumulative; it will provide access to all constants requested
--    up to this call as well.
function gl.exposeConstants(constants)
	addConstants(constants)
	local h = loadHeaders()
	for k,v in pairs(h) do gl[k] = v end
end

return gl





