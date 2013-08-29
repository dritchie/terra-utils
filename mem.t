
-- Functions for memory management

local cstdlib = terralib.includec("stdlib.h")


local new = macro(function(type)
	local t = type:astype()
	return `[&t](cstdlib.malloc(sizeof(t)))
end)

local delete = macro(function(ptr)
	return `cstdlib.free([ptr])
end)

return
{
	new = new,
	delete = delete
}