local util = terralib.require("util")

-- Mac OSX only, for now
if not (util.osName() == "Darwin\n") then
	error("GLUT/OpenGL module currently only supported on OSX.")
end

-- Automatically generate functions that return commonly-used macro constants
--    that are otherwise not accessible from Terra.
local function genConstantAccessorDef(constantName, constantType)
	return string.format("inline %s m%s() { return %s; }\n", constantType, constantName, constantName)
end
local function genAllConstantAccessorDefs(constants)
	local code = ""
	for name,typ in pairs(constants) do
		code = code .. genConstantAccessorDef(name, typ)
	end
	return code
end

-- Constants to be exposed
local constTable = {}
local function addConstants(constants)
	for _,c in ipairs(constants) do
		-- default type of a constant is int
		if type(c) == "string" then
			constTable[c] = "int"
		elseif type(c) == "table" then
			constTable[c[1]] = c[2]
		else
			error("gl.addConstants: entries must be either names or {name, type} tables")
		end
	end
end
addConstants({
"GL_PROJECTION",
"GL_MODELVIEW",
"GL_COLOR_BUFFER_BIT",
"GL_DEPTH_BUFFER_BIT",
"GL_DEPTH_TEST",
"GL_POINTS",
"GL_LINES",
"GL_LINE_LOOP",
"GL_QUADS",
"GL_QUAD_STRIP",
"GL_POLYGON",
"GL_TRIANGLES",
"GL_TRIANGLE_STRIP",
"GL_RGB",
"GL_BGR",
"GL_RGBA",
"GL_UNSIGNED_BYTE",
"GLUT_RGB",
"GLUT_RGBA",
"GLUT_SINGLE",
"GLUT_DOUBLE",
"GLUT_DEPTH",
"GL_FILL",
"GL_LINE",
"GL_FRONT",
"GL_BACK",
"GL_FRONT_AND_BACK",
"GL_LIGHTING",
"GL_LIGHT0",
"GL_LIGHT1",
"GL_LIGHT2",
"GL_LIGHT3",
"GL_LIGHT4",
"GL_LIGHT5",
"GL_LIGHT6",
"GL_LIGHT7",
"GL_MAX_LIGHTS",
"GL_AMBIENT",
"GL_DIFFUSE",
"GL_SPECULAR",
"GL_POSITION",
"GL_SHININESS",
"GL_FLAT",
"GL_SMOOTH",
"GL_NORMALIZE",
"GL_CULL_FACE"
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





