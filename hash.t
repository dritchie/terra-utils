local fasthash = terralib.includec("fasthash.h").SuperFastHash
local templatize = terralib.require("templatize")
local util = terralib.require("util")

-- We can provide a 'default' hash for aggregates that can be
--    easily adopted but is not present unless explicity asked for.
local function getDefaultHash(typ)
	local fn = terra(val: typ)
		return fasthash([&int8](&val), sizeof(typ))
	end
	util.inline(fn)
	return fn
end

local hash = templatize(function(T)
	return getDefaultHash(T)
end)

hash.rawhash = fasthash

return hash