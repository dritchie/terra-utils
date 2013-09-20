
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
	return io.popen(procstr):read("*all")
end

function string:split(sep)
        local sep, fields = sep or ":", {}
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

return U