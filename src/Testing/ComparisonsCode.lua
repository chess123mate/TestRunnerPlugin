return function(expectedFirst, threshold)
assert(expectedFirst ~= nil and threshold ~= nil, "Missing arguments")

local describe = require(script.Parent.Parent.Descriptions).Describe
local function appendMsg(msg, ...)
	local n = select("#", ...)
	if n == 0 then return msg end
	local args = {...}
	for i = 1, n do
		args[i] = tostring(args[i])
	end
	return ("%s | %s"):format(msg, table.concat(args, " "))
end

local actual = expectedFirst and "expected" or "actual"
local expected = expectedFirst and "actual" or "expected"
local function actualNotExpected(a, op, b, ...)
	return appendMsg(string.format("(%s) %s %s %s (%s)", actual, describe(a), op, describe(b), expected), ...)
end

local c; c = { -- each comparison should return error msg if something is wrong, else nil/false
	describe = describe,
	actualNotExpected = actualNotExpected,
	type = function(value, theType, prefixMsg) -- Most comparisons have "..." that are appended to the error message to describe what the test is about
		return type(theType) ~= "string" and ("2nd argument to t.type must be value string; received %s"):format(tostring(theType))
			or type(value) ~= theType and ("%s%s%s (type '%s') is not of type '%s'"):format(prefixMsg or "", prefixMsg and " " or "", describe(value), type(value), theType)
	end,
	typeof = function(value, theType, ...)
		return c.type(theType, "string") or typeof(value) ~= theType and appendMsg(("%s (typeof '%s') is not typeof '%s'"):format(describe(value), type(value), theType), ...)
	end,
	equals = function(a, b, ...) return a ~= b and actualNotExpected(a, "~=", b, ...) end,
	notEquals = function(a, b, ...) return a == b and actualNotExpected(a, "==", b, ...) end,
	approxEquals = function(a, b, ...) return c.type(a, "number") or c.type(b, "number") or math.abs(a - b) >= threshold and actualNotExpected(a, "~~=", b, ...) end,
	truthy = function(value, ...) return (not value) and appendMsg(tostring(value) .. " not truthy", ...) end,
	falsy = function(value, ...) return value and appendMsg(describe(value) .. " not falsy", ...) end,
	truthyEquals = function(a, b, ...) return not a ~= not b and actualNotExpected(a, "~=", b, "(truthy equals)", ...) end,
	greaterThan = function(a, b, ...) return a <= b and actualNotExpected(a, "<=", b, ...) end,
	lessThan = function(a, b, ...) return a >= b and actualNotExpected(a, ">=", b, ...) end,
	lessThanEqual = function(a, b, ...) return a > b and actualNotExpected(a, ">", b, ...) end,
	greaterThanEqual = function(a, b, ...) return a < b and actualNotExpected(a, "<", b, ...) end,
	
	listContains = function(list, value, ...)
		return c.type(list, "table", "1st argument")
			or not table.find(list, value) and appendMsg(("List '%s' (length %d) does not contain '%s'"):format(describe(list), #list, describe(value)), ...)
	end,
	listLength = function(list, length, ...)
		return c.type(list, "table", "1st argument") or c.type(length, "number", "2nd argument") or #list ~= length and appendMsg(("Length of %s is %d instead of %s"):format(describe(list), #list, describe(length)), ...)
	end,
	listsSameLength = function(a, b, ...)
		return c.type(a, "table", "1st argument") or c.type(b, "table", "2nd argument")
			or #a ~= #b and appendMsg(("Unequal table lengths: %s for %s and %s respectively"):format(actualNotExpected(#a, "~=", #b), describe(a), describe(b)), ...)
	end,
	listsEqual = function(a, b, ...)
		local v = c.listsSameLength(a, b, ...)
		if v then return v end
		for i = 1, #a do
			if a[i] ~= b[i] then
				return appendMsg(("Item %d in actual %s unequal to %s (%s ~= %s)"):format(i, describe(a), describe(b), describe(a[i]), describe(b[i])), ...)
			end
		end
	end,
	containsKey = function(theTable, key, ...)
		return c.type(theTable, "table", "1st argument") or theTable[key] == nil and appendMsg(("%s does not contain key %s"):format(describe(theTable), describe(key)), ...)
	end,
	tablesEqual = function(a, b, ...) -- not recursive
		local v = c.listsSameLength(a, b, ...)
		if v then return v end
		for k, v in pairs(a) do
			if b[k] ~= v then return appendMsg(("(%s) %s[%s] = %s, unlike (%s) %s[%s] = %s"):format(actual, describe(a), describe(k), describe(v), expected, describe(b), describe(k), describe(b[k])), ...) end
		end
		for k, v in pairs(b) do
			if a[k] ~= v then return appendMsg(("(%s) %s[%s] = %s, unlike (%s) %s[%s] = %s"):format(actual, describe(a), describe(k), describe(a[k]), expected, describe(b), describe(k), describe(v)), ...) end
		end
	end,
	tablesEqualRecursive = function(a, b, ...) -- recursive (ignores tables it's already seen before during recursion to avoid infinite loops). Does not consider two keys to be the same if they are different tables, regardless of content.
		local v = c.type(a, "table", "1st argument") or c.type(b, "table", "2nd argument")
		if v then return v end
		local compare
		local tablesSeen = {}
		function compare(a, b) -- returns keyChain:string, va, vb
			tablesSeen[a] = true
			tablesSeen[b] = true
			for k, v in pairs(a) do
				local result
				if type(v) == "table" and type(b[k]) == "table" then
					if not tablesSeen[v] and not tablesSeen[b[k]] then
						local keyChain, va, vb = compare(v, b[k])
						if keyChain then return ("[%s]%s"):format(describe(k), keyChain or ""), va, vb end
					end
				elseif b[k] ~= v then
					return ("[%s]"):format(describe(k)), v, b[k]
				end
			end
			for k, v in pairs(b) do
				local result
				if a[k] == nil then return ("[%s]"):format(describe(k)), nil, v end
			end
		end
		local keyChain, va, vb = compare(a, b)
		if keyChain then return appendMsg(("For tables %s and %s, %s equals %s (%s) and %s (%s) respectively (but should be the same)"):format(describe(a), describe(b), keyChain, describe(va), actual, describe(vb), expected), ...) end
	end,
	isTrue = function(value, func, desc, ...)
		--	passes if func(value) is a truthy value
		--	desc optional; grammatically "is not {desc}"
		--		ex if value is 3 and desc is "between 5 and 10",
		--		the error message will say "3 is not between 5 and 10"
		return c.type(func, "function", "2nd argument") or not func(value) and appendMsg(("%s is not %s"):format(describe(value), desc and desc or "as expected"), ...) or nil
	end,
	is = function(value, className, ...)
		return (type(value) ~= "table" or type(value.Is) ~= "function" or not value:Is(className)) and appendMsg(('%s Is not %s'):format(describe(value), describe(className)), ...) or nil
	end,
	isA = function(value, className, ...)
		return (typeof(value) ~= "Instance" or value:IsA(className)) and appendMsg(("%s not IsA %s"):format(describe(value), describe(className)), ...)
	end,

	errors = function(func, ...) -- Note: for error functions, the '...' are passed to 'func'; they are not descriptions
		return c.type(func, "function", "Argument to 'errors'") or (pcall(func, ...) and "Function failed to error" or nil)
	end,
	errorsWith = function(errMsgSubstring, func, ...)
		local v = c.type(errMsgSubstring, "string", "1st argument") or c.type(func, "function", "2nd argument")
		if v then return v end
		local status, msg = pcall(func, ...)
		return status and "Function failed to error" or c.type(msg, "string", "Error returned by the function")
			or (not msg:find(errMsgSubstring) and ("Function did not error with substring '%s'"):format(errMsgSubstring))
	end,
	errorIs = function(errChecker, func, ...)
		local v = c.type(errChecker, "function", "1st argument") or c.type(func, "function", "2nd argument")
		if v then return v end
		local status, msg = pcall(func, ...)
		return status and "Function failed to error"
			or (not errChecker(msg) and "Function did not error as expected")
	end,
	fail = function(msg, ...) return appendMsg(msg, ...) or "Test failed" end, -- note that an equivalent 'pass' function is not needed as it is assumed from a lack of failure
}
c.gt = c.greaterThan
c.gte = c.greaterThanEqual
c.lt = c.lessThan
c.lte = c.lessThanEqual

return c
end