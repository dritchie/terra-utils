
local m = require("mem")
local util = require("util")
local Vec = require("linalg").Vec
local gl = require("gl")

local Vec3d = Vec(double, 3)
local Color4d = Vec(double, 4)


-- Simple camera class that packages up data needed to establish 3D
--    viewing / projection transforms
local struct Camera
{
	eye: Vec3d,
	target: Vec3d,
	up: Vec3d,
	fovy: double,	-- in degrees
	aspect: double,
	znear: double,
	zfar: double
}

-- Default camera is looking down -z
terra Camera:__construct()
	self.eye = Vec3d.stackAlloc(0.0, 0.0, 0.0)
	self.target = Vec3d.stackAlloc(0.0, 0.0, -1.0)
	self.up = Vec3d.stackAlloc(0.0, 1.0, 0.0)
	self.fovy = 45.0
	self.aspect = 1.0
	self.znear = 1.0
	self.zfar = 100.0
end

terra Camera:__construct(eye: Vec3d, target: Vec3d, up: Vec3d, fovy: double, aspect: double, znear: double, zfar: double)
	self.eye = eye
	self.target = target
	self.up = up
	self.fovy = fovy
	self.aspect = aspect
	self.znear = znear
	self.zfar = zfar
end

-- OpenGL 1.1 style
terra Camera:setupGLPerspectiveView()
	gl.glMatrixMode(gl.mGL_MODELVIEW())
	gl.glLoadIdentity()
	gl.gluLookAt(self.eye(0), self.eye(1), self.eye(2),
				 self.target(0), self.target(1), self.target(2),
				 self.up(0), self.up(1), self.up(2))
	gl.glMatrixMode(gl.mGL_PROJECTION())
	gl.glLoadIdentity()
	gl.gluPerspective(self.fovy, self.aspect, self.znear, self.zfar)
end

m.addConstructors(Camera)


-- Simple light class that packages up parameters about lights
local LightType = uint
local Directional = 0
local Point = 1
local struct Light
{
	type: LightType,
	union
	{
		pos: Vec3d,
		dir: Vec3d
	},
	ambient: Color4d,
	diffuse: Color4d,
	specular: Color4d
}
Light.LightType = LightType
Light.Point = Point
Light.Directional = Directional

terra Light:__construct()
	self.type = Directional
	self.dir = Vec3d.stackAlloc(1.0, 1.0, 1.0)
	self.ambient = Color4d.stackAlloc(0.3, 0.3, 0.3, 1.0)
	self.diffuse = Color4d.stackAlloc(1.0, 1.0, 1.0, 1.0)
	self.specular = Color4d.stackAlloc(1.0, 1.0, 1.0, 1.0)
end

terra Light:__construct(type: LightType, posOrDir: Vec3d, ambient: Color4d, diffuse: Color4d, specular: Color4d) : {}
	self.type = type
	self.pos = posOrDir
	self.ambient = ambient
	self.diffuse = diffuse
	self.specular = specular
end

terra Light:__construct(type: LightType, posOrDir: Vec3d, diffuse: Color4d, ambAmount: double, specular: Color4d) : {}
	self.type = type
	self.pos = posOrDir
	self.ambient = ambAmount * diffuse; self.ambient(3) = self.diffuse(3)
	self.diffuse = diffuse
	self.specular = specular
end

-- OpenGL 1.1 style
terra Light:setupGLLight(lightID: int)
	util.assert(lightID >= 0 and lightID < gl.mGL_MAX_LIGHTS(),
		"lightID must be in the range [0,%d); got %d instead\n", 0, gl.mGL_MAX_LIGHTS(), lightID)
	var lightNumFlag = gl.mGL_LIGHT0() + lightID
	gl.glEnable(lightNumFlag)
	var floatArr = arrayof(float, [Color4d.elements(`self.ambient)])
	gl.glLightfv(lightNumFlag, gl.mGL_AMBIENT(), floatArr)
	floatArr = arrayof(float, [Color4d.elements(`self.diffuse)])
	gl.glLightfv(lightNumFlag, gl.mGL_DIFFUSE(), floatArr)
	floatArr = arrayof(float, [Color4d.elements(`self.specular)])
	gl.glLightfv(lightNumFlag, gl.mGL_SPECULAR(), floatArr)
	-- Leverage the fact that the light type flags correspond to the value of the w coordinate
	floatArr = arrayof(float, [Vec3d.elements(`self.pos)], self.type)
	gl.glLightfv(lightNumFlag, gl.mGL_POSITION(), floatArr)
end

m.addConstructors(Light)



-- Simple material class to package up material params
struct Material
{
	ambient: Color4d,
	diffuse: Color4d,
	specular: Color4d,
	shininess: double
}

terra Material:__construct()
	self.ambient = Color4d.stackAlloc(0.8, 0.8, 0.8, 1.0)
	self.diffuse = Color4d.stackAlloc(0.8, 0.8, 0.8, 1.0)
	self.specular = Color4d.stackAlloc(0.0, 0.0, 0.0, 1.0)
	self.shininess = 0.0
end

terra Material:__construct(ambient: Color4d, diffuse: Color4d, specular: Color4d, shininess: double)
	self.ambient = ambient
	self.diffuse = diffuse
	self.specular = specular
	self.shininess = shininess
end

terra Material:__construct(diffuse: Color4d, specular: Color4d, shininess: double)
	self.ambient = diffuse
	self.diffuse = diffuse
	self.specular = specular
	self.shininess = shininess
end

-- OpenGL 1.1 style
terra Material:setupGLMaterial()
	-- Just default everything to only affecting the front faces
	var flag = gl.mGL_FRONT()
	var floatArr = arrayof(float, [Color4d.elements(`self.ambient)])
	gl.glMaterialfv(flag, gl.mGL_AMBIENT(), floatArr)
	floatArr = arrayof(float, [Color4d.elements(`self.diffuse)])
	gl.glMaterialfv(flag, gl.mGL_DIFFUSE(), floatArr)
	floatArr = arrayof(float, [Color4d.elements(`self.specular)])
	gl.glMaterialfv(flag, gl.mGL_SPECULAR(), floatArr)
	gl.glMaterialf(flag, gl.mGL_SHININESS(), self.shininess)
end

m.addConstructors(Material)


return
{
	Camera = Camera,
	Light = Light,
	Material = Material
}





