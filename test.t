
local mem = terralib.require("mem")

local struct Foo
{
	bar : int,
	baz : double
}

local cstdio = terralib.includec("stdio.h")

local terra test()
	var fooptr = mem.new(Foo)
	fooptr.bar = 1
	fooptr.baz = 42.0
	cstdio.printf("%d, %g\n", fooptr.bar, fooptr.baz)
	mem.delete(fooptr)
end

test()