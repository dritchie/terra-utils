local C = terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>

#ifndef _WIN32
#include <sys/time.h>
double __currentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}
#else
#include <time.h>
double __currentTimeInSeconds() {
	return time(NULL);
}
#endif
]]


local U = {}

-- Cross platform
terra U.currentTimeInSeconds()
	return C.__currentTimeInSeconds()
end

function U.copytable(tab)
	local ret = {}
	for k,v in pairs(tab) do
		ret[k] = v
	end
	return ret
end

function U.concattables(...)
	local tab1 = (select(1,...))
	local t = U.copytable(tab1)
	for i=2,select("#",...) do
		local tab2 = (select(i,...))
		for _,e in ipairs(tab2) do
			table.insert(t, e)
		end
	end
	return t
end

function U.joinTables(...)
	local tab1 = (select(1,...))
	local t = U.copytable(tab1)
	for i=2,select("#",...) do
		local tab2 = (select(i,...))
		for k,v in pairs(tab2) do
			t[k] = v
		end
	end
	return t
end

function U.index(tbl, indices)
	local ret = {}
	for i,index in ipairs(indices) do
		table.insert(ret, tbl[index])
	end
	return ret
end

function U.inline(terrafn)
	local defs = terrafn:getdefinitions()
	for i,d in ipairs(defs) do
		d:setinlined(true)
	end
	return terrafn
end

function U.istype(typ) return macro(function(x) return x:gettype() == typ end) end
function U.assertIsType(type, msg)
	return macro(function(x)
		U.luaAssertWithTrace(x:gettype() == type, msg)
		return quote end
	end)
end

U.getTypeAsString = macro(function(x) return tostring(x:gettype()) end)

function U.wait(procstr)
	return io.popen(procstr):read("*a")
end

function string:split(sep)
        local sep, fields = sep or " ", {}
        local pattern = string.format("([^%s]+)", sep)
        self:gsub(pattern, function(c) fields[#fields+1] = c end)
        return fields
end

function U.foreach(iterator, codeblock)
	return quote
		while not [iterator]:done() do
			[codeblock]
			[iterator]:next()
		end
	end
end

function U.openModule(ns)
	for n,v in pairs(ns) do
		rawset(_G, n, v)
	end
end

function U.stringify(...)
	local str = ""
	for i=1,select("#", ...) do
		local t = (select(i, ...))
		local typ = type(t)
		if typ ~= "table" and typ ~= "function" then
			str = string.format("%s%s,", str, tostring(t))
		else
			-- Use the raw tostring metamethod to get the
			-- memory address of this table/function
			local tostr = nil
			if typ == "table" then
				tostr = t.__tostring
				if getmetatable(t) then getmetatable(t).__tostring = nil end
			end
			local mystr = tostring(t):gsub(string.format("%s: ", typ), "")
			if typ == "table" then
				if getmetatable(t) then getmetatable(t).__tostring = tostr end
			end
			str = string.format("%s%s,", str, mystr)
		end
	end
	return str
end

function U.osName()
	return U.wait("uname")
end

function U.isPosix()
	local uname = U.wait("uname")
	return (uname == "Darwin" or uname == "Linux")
end

-- Call fn(...) to generate code if flag is true.
-- Otherwise, return an empty quote
function U.optionally(flag, fn, ...)
	if flag then return fn(...)
	else return quote end end
end

-- Cross platform
U.fatalError = macro(function(...)
	local args = {...}
	return quote
		C.printf("[Fatal Error] ")
		C.printf([args])
		-- Traceback only supported on POSIX systems
		[U.isPosix() and quote terralib.traceback(nil) end or quote end]
		C.exit(1)
	end
end)

U.assert = macro(function(condition, ...)
	local args = {...}
	return quote
		if not condition then
			C.printf("[Assertion Failed] ")
			[U.optionally(#args > 0, function() return quote
				C.printf([args])
			end end)]
			-- Traceback only supported on POSIX systems
			[U.isPosix() and quote terralib.traceback(nil) end or quote end]
			C.exit(1)
		end
	end
end)

function U.luaAssertWithTrace(condition, msg)
	if not condition then
		print(debug.traceback())
		assert(condition, msg)
	end
end

function U.findDefWithParamTypes(terrafn, paramTypes)
	for _,d in ipairs(terrafn:getdefinitions()) do
		local ptypes = d:gettype().parameters
		if #ptypes == #paramTypes then
			local typesMatch = true
			for i=1,#ptypes do
				if ptypes[i] ~= paramTypes[i] then
					typesMatch = false
					break
				end
			end
			if typesMatch then
				return d
			end
		end
	end
	-- Couldn't find a matching definition
	return nil
end

-- Wrap a function with another that accepts a table of
--    named arguments. For arguments not present in the table,
--    fetch the default value from argdefs.
-- argdefs is specified as a list of {name, default} tuples.
function U.fnWithDefaultArgs(fn, argdefs)
	return function(args)
		args = args or {}
		local arglist = {}
		for _,argdef in ipairs(argdefs) do
			local argname = argdef[1]
			local argdefault = argdef[2]
			local argval = args[argname]
			if argval == nil then argval = argdefault end
			table.insert(arglist, argval)
		end
		return fn(unpack(arglist))
	end
end

function U.includec_path(filename)
	local cpath = os.getenv("C_INCLUDE_PATH") or "."
	return terralib.includec(filename, "-I", cpath)
end

function U.includecstring_path(str)
	local cpath = os.getenv("C_INCLUDE_PATH") or "."
	return terralib.includecstring(str, "-I", cpath)
end

return U





