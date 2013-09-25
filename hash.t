local thisfile = debug.getinfo(1, "S").source:gsub("@", "")

local fasthash = terralib.includec(thisfile:gsub("hash.t", "fasthash.h")).SuperFastHash
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

function hash.gethashfn(typ)
	if typ:isprimitive() or typ:ispointer() then
		return hash(typ)
	elseif typ:isstruct() and typ:getmethod("__hash") then
		return macro(function(val) return `val:__hash() end)
	else
		error(string.format("No __hash method for aggregate type '%s'", tostring(K)))
	end
end

return hash