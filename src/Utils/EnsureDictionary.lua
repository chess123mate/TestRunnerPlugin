return function(t)
	--	't' may be a list, dictionary, or blend of both (or a single value to turn into a table)
	--	Converts all integer keys into t[value] = true.
	-- Don't add keys while iterating, so store in different list first
	if type(t) ~= "table" then
		if t == nil then error("Missing argument 't' to EnsureDictionary") end
		return {[t] = true}
	end
	local n = #t
	if n == 0 then return t end
	local t2 = {}
	for i = 1, n do
		t2[i] = t[i]
		t[i] = nil
	end
	for i = 1, n do
		t[t2[i]] = true
	end
	return t
end