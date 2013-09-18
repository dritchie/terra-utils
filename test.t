local cstdio = terralib.includec("stdio.h")



-- MEM

local mem = terralib.require("mem")

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
	cstdio.printf("------- TEST: mem.t -------\n")
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
	cstdio.printf("------- TEST: vector.t -------\n")

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

	var vec2 = [Vector(int)].stackAlloc():fill(4, 10, 0, 0, 0, 7)
	printIntVector(&vec2)
	var eq = vec == vec2
	cstdio.printf("%d\n", eq)

	mem.destruct(vec)
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
	cstdio.printf("------- TEST: templatize.t -------\n")
	var a1 = 1
	var a2 = AddT { 2 }
	var b = 5
	var r1 = add(a1, b)
	var r2 = add(a2, b)
	cstdio.printf("r1: %d | r2: %d\n", r1, r2)
end

testTemplateInferAndInvoke()


-- INHERITANCE (STATIC)

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

inheritance.staticExtend(A, B)

local terra testStaticInheritance()
	cstdio.printf("------- TEST: inheritance.t (static) -------\n")
	var b = B { foo = 1, bar = 3.14 }
	b:incrfoo()
	cstdio.printf("b.foo: %d\n", b.foo)
	var a = [&A](&b)
	cstdio.printf("a.foo: %d\n", a.foo)
end

testStaticInheritance()


-- INHERITANCE (DYNAMIC)

local struct C
{
	foo: int
}

terra C:__construct(f: int)
	self.foo = f
end

terra C:incrfoo()
	self.foo = self.foo + 1
end

terra C:tell() : {}
	cstdio.printf("C\n")
end
inheritance.virtual(C.methods.tell)

mem.addConstructors(C)

local struct D
{
	bar: double
}

terra D:__construct(f: int, b: double)
	C.__construct(self, f)
	self.bar = b
end

terra D:tell() : {}
	cstdio.printf("D\n")
end
inheritance.virtual(D.methods.tell)

mem.addConstructors(D)

inheritance.dynamicExtend(C, D)

local terra expectD(d: &D)
	cstdio.printf("got D\n")
end

local terra testDynamicInheritance()
	cstdio.printf("------- TEST: inheritance.t (dynamic) -------\n")
	var d = D.stackAlloc(1, 3.14)
	d:incrfoo()
	cstdio.printf("d.foo: %d\n", d.foo)
	var c = [&C](&d)
	cstdio.printf("c.foo: %d\n", c.foo)
	var c2 = C.stackAlloc(2)
	c2:tell()
	d:tell()
	c:tell()
	--expectD(&c2)
end

testDynamicInheritance()


-- HASHMAP

local HashMap = terralib.require("hashmap")

local struct Thing { val: int }
terra Thing:__construct(v: int)
	self.val = v
end
Thing.metamethods.__eq = terra(self: &Thing, t: Thing)
	return self.val == t.val
end
Thing.methods.__hash = HashMap.defaultHash(Thing)
mem.addConstructors(Thing)

local terra testHashMap()
	cstdio.printf("------- TEST: hashmap.t -------\n")

	var map = [HashMap(int, int)].stackAlloc()
	cstdio.printf("get(42) == nil: %d\n", map:getPointer(42) == nil)
	map:put(42, 10)
	cstdio.printf("get(42): %d\n", @map:getPointer(42))
	map:remove(42)
	cstdio.printf("get(42) == nil: %d\n", map:getPointer(42) == nil)
	map:put(34, 1)
	map:put(47, 2)
	map:put(19, 3)
	map:put(3949, 4)
	map:put(174, 5)
	var it = map:iterator()
	while not it:done() do
		var key, val = it:keyval()
		cstdio.printf("(%d -> %d), ", key, val)
		it:next()
	end
	cstdio.printf("\n")
	mem.destruct(map)

	var map2 = [HashMap(Thing, Thing)].stackAlloc()
	var t42 = Thing.stackAlloc(42)
	var t1 = Thing.stackAlloc(1)
	map2:put(t42, t1)
	var tget : Thing
	map2:get(t42, &tget)
	cstdio.printf("get(t42): %d\n", tget.val)
	map2:remove(t42)
	mem.destruct(map2)
end

testHashMap()










