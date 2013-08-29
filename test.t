
-- MEM

local mem = terralib.require("mem")
local cstdio = terralib.includec("stdio.h")

local struct Foo
{
	bar : int,
	baz : double
}

terra Foo:construct(i : int, d : double)
	self.bar = i
	self.baz = d
end

terra Foo:destruct()
	cstdio.printf("destructing!\n")
end

mem.addConstructors(Foo)



local terra test()
	var fooptr = Foo.newHeap(1, 42.0)
	cstdio.printf("%d, %g\n", fooptr.bar, fooptr.baz)
	mem.delete(fooptr)

	var foo = Foo.newStack(2, 36.0)
	cstdio.printf("%d, %g\n", foo.bar, foo.baz)
	foo:destruct()
end

test()