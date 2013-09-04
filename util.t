
local U = {}

function U.copytable(tab)
	local ret = {}
	for k,v in pairs(tab)
		ret[k] = v
	end
	return ret
end

return U