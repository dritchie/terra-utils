local C = terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>
]]


local U = {}

function U.copytable(tab)
	local ret = {}
	for k,v in pairs(tab) do
		ret[k] = v
	end
	return ret
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

function U.wait(procstr)
	return io.popen(procstr):read("*a")
end

function string:split(sep)
        local sep, fields = sep or " ", {}
        local pattern = string.format("([^%s]+)", sep)
        self:gsub(pattern, function(c) fields[#fields+1] = c end)
        return fields
end

U.foreach = macro(function(iterator, codeblock)
	return quote
		while not iterator:done() do
			[codeblock]
			iterator:next()
		end
	end
end)

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

U.fatalError = macro(function(...)
	local args = {...}
	return quote
		C.printf("[Fatal Error] ")
		C.printf([args])
		terralib.traceback(nil)
		C.exit(1)
	end
end)

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

return U





