
local m = terralib.require("mem")
local Vec = terralib.require("linalg").Vec
local gl = terralib.require("gl")

local Vec3d = Vec(double, 3)

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

-- Default camera is lookuping down -z
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

-- Modify the OpenGL state machine
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



return
{
	Camera = Camera	
}





