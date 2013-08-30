
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

local terra testmem()
	var fooptr = Foo.heapAlloc(1, 42.0)
	cstdio.printf("%d, %g\n", fooptr.bar, fooptr.baz)
	mem.delete(fooptr)

	var foo = Foo.stackAlloc(2, 36.0)
	cstdio.printf("%d, %g\n", foo.bar, foo.baz)
	foo:destruct()
end

testmem()


-- VECTOR

local Vector = terralib.require("vector")

local terra testvector()
	var vec = [Vector(int)].stackAlloc(5, 0)	
	cstdio.printf("capacity: %u, size: %u\n", vec.__capacity, vec.size)
	vec:set(0, 4)
	vec:set(3, 2)
	vec:push(7)
	cstdio.printf("capacity: %u, size: %u\n", vec.__capacity, vec.size)
	vec:push(3)
	cstdio.printf("capacity: %u, size: %u\n", vec.__capacity, vec.size)
	vec:pop()
	cstdio.printf("capacity: %u, size: %u\n", vec.__capacity, vec.size)
	for i=0,vec.size do
		cstdio.printf("%d ", vec:get(i))
	end
	cstdio.printf("\n")
	vec:clear()
	cstdio.printf("capacity: %u, size: %u\n", vec.__capacity, vec.size)
	vec:destruct()

	var vec2 = [Vector(Foo)].stackAlloc()
	cstdio.printf("capacity: %u, size: %u\n", vec2.__capacity, vec2.size)
	vec2:push(Foo.stackAlloc(1, 1))
	cstdio.printf("capacity: %u, size: %u\n", vec2.__capacity, vec2.size)
	vec2:push(Foo.stackAlloc(2, 2))
	cstdio.printf("capacity: %u, size: %u\n", vec2.__capacity, vec2.size)
	vec2:push(Foo.stackAlloc(3, 3))
	cstdio.printf("capacity: %u, size: %u\n", vec2.__capacity, vec2.size)
	vec2:set(1, Foo.stackAlloc(42, 42))
	vec2:pop()
	cstdio.printf("capacity: %u, size: %u\n", vec2.__capacity, vec2.size)
	for i=0,vec2.size do
		cstdio.printf("%d ", vec2:get(i).bar)
	end
	cstdio.printf("\n")
	vec2:destruct()
end

testvector()