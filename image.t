local m = terralib.require("mem")
local templatize = terralib.require("templatize")
local util = terralib.require("util")
local Vec = terralib.require("linalg").Vec
local C = terralib.includecstring [[
#include <stdlib.h>
#include <stdio.h>
#include <math.h>
]]

local FI = os.getenv("FREEIMAGE_H_PATH") and terralib.includec(os.getenv("FREEIMAGE_H_PATH")) or
		   error("Environment variable 'FREEIMAGE_H_PATH' not defined.")
if os.getenv("FREEIMAGE_LIB_PATH") then
	terralib.linklibrary(os.getenv("FREEIMAGE_LIB_PATH"))
else
	error("Environment variable 'FREEIMAGE_LIB_PATH' not defined.")
end

FI.FreeImage_Initialise(0)
-- Tear down FreeImage only when it is safe to destroy this module
local struct FIMemSentinel {}
terra FIMemSentinel:__destruct()
	FI.FreeImage_DeInitialise()
end
local __fiMemSentinel = terralib.new(FIMemSentinel)
m.gc(__fiMemSentinel)


local function makeEnum(names, startVal)
	local enum = {}
	for i,n in ipairs(names) do
		enum[n] = startVal + (i-1)
	end
	return enum
end

-- FreeImage types
local Type = makeEnum({"UNKNOWN", "BITMAP", "UINT16", "INT16", "UINT32", "INT32", "FLOAT", "DOUBLE", "COMPLEX", "RGB16",
	"RGBA16", "RGBF", "RGBAF"}, 0)

-- FreeImage formats
local Format = makeEnum({"UNKNOWN", "BMP", "ICO", "JPEG", "JNG", "KOALA", "LBM", "MNG", "PBM", "PBMRAW",
	"PCD", "PCX", "PGM", "PGMRAW", "PNG", "PPM", "PPMRAW", "RAS", "TARGA", "TIFF", "WBMP", "PSD", "CUT", "XBM", "XPM",
	"DDS", "GIF", "HDR", "FAXG3", "SGI", "EXR", "J2K", "JP2", "PFM", "PICT", "RAW"}, -1)
Format.IFF = Format.LBM


-- Code gen helpers
local function arrayElems(ptr, num)
	local t = {}
	for i=1,num do
		local iminus1 = i-1
		table.insert(t, `ptr[iminus1])
	end
	return t
end
local function wrap(exprs, unaryFn)
	local t = {}
	for _,e in ipairs(exprs) do table.insert(t, `[unaryFn(e)]) end
	return t
end

local function typeAndBitsPerPixel(dataType, numChannels)
	-- Bytes to bits
	local function B2b(B)
		return 8*B
	end
	assert(numChannels > 0 and numChannels <= 4)
	-- 8-bit per channel image (standard bitmaps)
	if dataType == uint8 then
		return Type.BITMAP, B2b(terralib.sizeof(uint8)*numChannels)
	-- Signed 16-bit per channel image (only supports single channel)
	elseif dataType == int16 and numChannels == 1 then
		return Type.INT16, B2b(terralib.sizeof(int16))
	-- Unsigned 16-bit per channel image
	elseif dataType == uint16 then
		local s = terralib.sizeof(uint16)
		-- Single-channel
		if numChannels == 1 then
			return Type.UINT16, B2b(s)
		-- RGB
		elseif numChannels == 3 then
			return Type.RGB16, B2b(s*3)
		-- RGBA
		elseif numChannels == 4 then
			return Type.RGBA16, B2b(s*4)
		end
	-- Signed 32-bit per channel image (only supports single channel)
	elseif dataType == int32 and numChannels == 1 then
		return Type.INT32, B2b(terralib.sizeof(int32))
	-- Unsigned 32-bit per channel image (only supports single channel)
	elseif dataType == uint32 and numChannels == 1 then
		return Type.UINT32, B2b(terralib.sizeof(uint32))
	-- Single precision floating point per chanel image
	elseif dataType == float then
		local s = terralib.sizeof(float)
		-- Single-channel
		if numChannels == 1 then
			return Type.FLOAT, B2b(s)
		-- RGB
		elseif numChannels == 3 then
			return Type.RGBF, B2b(s*3)
		-- RGBA
		elseif numChannels == 4 then
			return Type.RGBAF, B2b(s*4)
		end
	-- Double-precision floating point image (only supports single channel)
	elseif dataType == double then
		return Type.DOUBLE, B2b(terralib.sizeof(double))
	else
		error(string.format("FreeImage does not support images with %u %s's per pixel", numChannels, tostring(dataType)))
	end
end


local Image = templatize(function(dataType, numChannels)

	local Color = Vec(dataType, numChannels)

	local struct ImageT
	{
		data: &Color,
		width: uint,
		height: uint
	}
	ImageT.Color = Color
	ImageT.metamethods.__typename = function(self)
		return string.format("Image(%s, %d)", tostring(dataType), numChannels)
	end

	terra ImageT:__construct()
		self.data = nil
		self.width = 0
		self.height = 0
	end

	terra ImageT:getPixelPtr(x: uint, y: uint)
		return self.data + y*self.width + x
	end
	util.inline(ImageT.methods.getPixelPtr)

	terra ImageT:getPixelValue(x: uint, y: uint)
		return m.copy(@self.getPixelPtr(x, y))
	end
	util.inline(ImageT.methods.getPixelValue)

	ImageT.metamethods.__apply = macro(function(self, x, y)
		return `@(self.data + y*self.width + x)
	end)

	terra ImageT:setPixel(x: uint, y: uint, color: &Color)
		var pix = self:getPixelPtr(x, y)
		[Color.entryExpList(pix)] = [Color.entryExpList(color)]
	end
	util.inline(ImageT.methods.setPixel)

	terra ImageT:__construct(width: uint, height: uint)
		self.width = width
		self.height = height
		self.data = [&Color](C.malloc(width*height*sizeof(Color)))
		for y=0,self.height do
			for x=0,self.width do
				self:getPixelPtr(x, y):__construct()
			end
		end
	end

	terra ImageT:__destruct()
		C.free(self.data)
	end

	terra ImageT:resize(width: uint, height: uint)
		self:__destruct()
		self:__construct(width, height)
	end

	terra ImageT:__copy(other: &ImageT)
		self.width = other.width
		self.height = other.height
		self.data = [&Color](C.malloc(self.width*self.height*sizeof(Color)))
		for y=0,self.height do
			for x=0,self.width do
				@self:getPixelPtr(x, y) = m.copy(@other:getPixelPtr(x, y))
			end
		end
	end

	terra ImageT:clear(color: Color)
		for y=0,self.height do
			for x=0,self.width do
				@self:getPixelPtr(x, y) = color
			end
		end
	end

	-- Quantize/dequantize channel values
	local makeQuantize = templatize(function(srcDataType, tgtDataType)
		local function B2b(B)
			return 8*B
		end
		return function(x)
			if tgtDataType:isfloat() and srcDataType:isintegral() then
				local tsize = terralib.sizeof(srcDataType)
				local maxtval = (2 ^ B2b(tsize)) - 1
				return `[tgtDataType](x/[tgtDataType](maxtval))
			elseif tgtDataType:isintegral() and srcDataType:isfloat() then
				local tsize = terralib.sizeof(tgtDataType)
				local maxtval = (2 ^ B2b(tsize)) - 1
				-- return `C.fmin(C.fmax([tgtDataType](x * maxtval), 0.0), maxtval)
				return `[tgtDataType](C.fmin(C.fmax(x, 0.0), 1.0) * maxtval)
			else
				return `[tgtDataType](x)
			end
		end
	end)

	-- Load and return an image
	local loadImage = templatize(function(fileDataType)
		local b2B = macro(function(b)
			return `b/8
		end)
		local quantize = makeQuantize(fileDataType, dataType)
		return terra(fibitmap: &FI.FIBITMAP)
			var bpp = FI.FreeImage_GetBPP(fibitmap)
			var fileNumChannels = b2B(bpp) / sizeof(fileDataType)
			var numChannelsToCopy = fileNumChannels
			if numChannels < numChannelsToCopy then numChannelsToCopy = numChannels end
			var w = FI.FreeImage_GetWidth(fibitmap)
			var h = FI.FreeImage_GetHeight(fibitmap)
			var image = ImageT.stackAlloc(w, h)
			for y=0,h do
				var scanline = [&fileDataType](FI.FreeImage_GetScanLine(fibitmap, y))
				for x=0,w do
					var fibitmapPixelPtr = scanline + x*fileNumChannels
					var imagePixelPtr = image:getPixelPtr(x, y)
					for c=0,numChannelsToCopy do
						imagePixelPtr(c) = [quantize(`fibitmapPixelPtr[c])]
					end
				end
			end
			return image
		end
	end)
	ImageT.methods.load = terra(format: int, filename: rawstring)
		var fibitmap = FI.FreeImage_Load(format, filename, 0)
		if fibitmap == nil then
			util.fatalError("Could not load image file '%s'\n", filename)
		end
		var fit = FI.FreeImage_GetImageType(fibitmap)
		var bpp = FI.FreeImage_GetBPP(fibitmap)

		var image : ImageT
		if fit == Type.BITMAP then 
			image = [loadImage(uint8)](fibitmap)
		elseif fit == Type.INT16 then
			image = [loadImage(int16)](fibitmap)
		elseif fit == Type.UINT16 or fit == Type.RGB16 or fit == Type.RGBA16 then
			image = [loadImage(uint16)](fibitmap)
		elseif fit == Type.INT32 then
			image = [loadImage(int32)](fibitmap)
		elseif fit == Type.UINT32 then
			image = [loadImage(uint32)](fibitmap)
		elseif fit == Type.FLOAT or fit == Type.RGBF or fit == Type.RGBAF then
			image = [loadImage(float)](fibitmap)
		elseif fit == Type.DOUBLE then
			image = [loadImage(double)](fibitmap)
		else
			util.fatalError("Attempt to load unsupported image type.\n")
		end

		FI.FreeImage_Unload(fibitmap)

		return image
	end

	-- Save an existing image
	ImageT.save = templatize(function(fileDataType)
		-- Default to internal dataType
		fileDataType = fileDataType or dataType
		local quantize = makeQuantize(dataType, fileDataType)
		local fit, bpp = typeAndBitsPerPixel(fileDataType, numChannels)
		return terra(image: &ImageT, format: int, filename: rawstring)
			var fibitmap = FI.FreeImage_AllocateT(fit, image.width, image.height, bpp, 0, 0, 0)
			if fibitmap == nil then
				util.fatalError("Unable to allocate FreeImage bitmap to save image.\n")
			end
			-- C.printf("width: %u, height: %u, fit: %d, bpp: %d\n", image.width, image.height, fit, bpp)
			for y=0,image.height do
				var scanline = [&fileDataType](FI.FreeImage_GetScanLine(fibitmap, y))
				for x=0,image.width do
					var fibitmapPixelPtr = scanline + x*numChannels
					var imagePixelPtr = image:getPixelPtr(x, y)
					for c=0,numChannels do
						fibitmapPixelPtr[c] = [quantize(`imagePixelPtr(c))]
					end
				end
			end
			if FI.FreeImage_Save(format, fibitmap, filename, 0) == 0 then
				util.fatalError("Failed to save image named '%s'\n", filename)
			end
			FI.FreeImage_Unload(fibitmap)
		end
	end)

	m.addConstructors(ImageT)
	return ImageT
end)


-- -- TEST
-- local terra test()
-- 	var flowersInt = [Image(uint8, 3)].load(Format.JPEG, "flowers.jpeg")
-- 	[Image(uint8, 3).save()](&flowersInt, Format.PNG, "flowersInt.png")
-- 	m.destruct(flowersInt)
-- 	var flowersFloat = [Image(float, 3)].load(Format.JPEG, "flowers.jpeg")
-- 	[Image(float, 3).save(uint8)](&flowersFloat, Format.PNG, "flowersFloat.png")
-- 	m.destruct(flowersFloat)
-- end
-- test()


return
{
	-- Type = Type,
	Format = Format,
	Image = Image,
	__fiMemSentinel = __fiMemSentinel
}











