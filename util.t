
local Vector = terralib.require("vector")

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

U.Array = macro(function(...)
	local T = (select(1,...)):gettype()
	local args = {}
	for i=1,select("#",...) do
		table.insert(args, (select(i,...)))
	end
	return `[Vector(T)].stackAlloc():fill([args])
end)

return U