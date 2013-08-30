
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
	cstdio.printf("-------\n")
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

local terra printIntVector(v: Vector(int))
	if v.size == 0 then
		cstdio.printf("<empty>\n")
	else
		for i=0,v.size do
			cstdio.printf("%d ", v:get(i))
		end
		cstdio.printf("\n")
		cstdio.printf("capacity: %u, size: %u\n", v.__capacity, v.size)
	end
end

local terra testvector()
	cstdio.printf("-------\n")

	var vec = [Vector(int)].stackAlloc(5, 0)	
	printIntVector(vec)
	vec:set(0, 4)
	vec:set(3, 2)
	vec:push(7)
	printIntVector(vec)
	vec:push(3)
	printIntVector(vec)
	vec:pop()
	printIntVector(vec)
	vec:insert(1, 10)
	printIntVector(vec)
	vec:remove(4)
	printIntVector(vec)
	vec:clear()
	printIntVector(vec)
	vec:destruct()
	
end

testvector()