
-- MEM

local mem = terralib.require("mem")
local cstdio = terralib.includec("stdio.h")

local struct Foo
{
	bar : int,
	baz : double
}

terra Foo:__construct(i : int, d : double)
	self.bar = i
	self.baz = d
end

terra Foo:__destruct()
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
	mem.destruct(foo)
end

testmem()


-- VECTOR

local Vector = terralib.require("vector")

local terra printIntVector(v: &Vector(int))
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
	printIntVector(&vec)
	vec:set(0, 4)
	vec:set(3, 2)
	vec:push(7)
	printIntVector(&vec)
	vec:push(3)
	printIntVector(&vec)
	vec:pop()
	printIntVector(&vec)
	vec:insert(1, 10)
	printIntVector(&vec)
	vec:remove(4)
	printIntVector(&vec)
	vec:clear()
	printIntVector(&vec)
	mem.destruct(vec)

	var vec2 = [Vector(int)].stackAlloc():fill(1, 2, 3, 4, 5)
	printIntVector(&vec2)
	mem.destruct(vec2)
end

testvector()


-- TEMPLATIZE

local templatize = terralib.require("templatize")

local struct AddT
{
	val: int
}

AddT.metamethods.__add = terra(self: AddT, other: int)
	return AddT { self.val + other }
end

local add = templatize(function(T1, T2)
	return terra(a: T1, b: T2) : T1
		return a + b
	end
end).implicit

local terra testTemplateInferAndInvoke()
	cstdio.printf("-------\n")
	var a1 = 1
	var a2 = AddT { 2 }
	var b = 5
	var r1 = add(a1, b)
	var r2 = add(a2, b)
	cstdio.printf("r1: %d | r2: %d\n", r1, r2)
end

testTemplateInferAndInvoke()


-- INHERITANCE

local inheritance = terralib.require("inheritance")

local struct A
{
	foo: int
}

terra A:incrfoo()
	self.foo = self.foo + 1
end

local struct B
{
	bar: double
}

inheritance.extend(A, B)

local terra testInheritance()
	cstdio.printf("-------\n")
	var b = B { foo = 1, bar = 3.14 }
	b:incrfoo()
	cstdio.printf("b.foo: %d\n", b.foo)
	var a = [&A](&b)
	cstdio.printf("a.foo: %d\n", a.foo)
end

testInheritance()





