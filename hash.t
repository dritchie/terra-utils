local thisfile = debug.getinfo(1, "S").source:gsub("@", "")

local util = require("util")
local fasthash = util.includec_path(thisfile:gsub("hash.t", "fasthash.h")).SuperFastHash
local templatize = require("templatize")

local C = terralib.includecstring [[
#include <string.h>
]]

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

-- Simple wrapper around rawstring that allows for hashing
local struct HashableString { str: rawstring }
terra HashableString:__hash()
	return fasthash(self.str, C.strlen(self.str))
end
HashableString.metamethods.__eq = terra(hs1: HashableString, hs2: HashableString)
	return C.strcmp(hs1.str, hs2.str) == 0
end
hash.HashableString = HashableString

return hash
