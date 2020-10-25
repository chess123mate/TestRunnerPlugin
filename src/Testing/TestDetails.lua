-- TestDetails: functionality regarding a single table test in a 'tests' object
local TestDetails = {}
local validTestKeys = {
	setup = "function",
	cleanup = "function",
	test = "function",
	args = "table",
	argsLists = "table",
	skip = "boolean",
	focus = "boolean",
}
function TestDetails.HasValidKeys(details)
	--	returns valid, msg with "%s.%s" at the beginning (expecting module path/name & test)
	for k, v in pairs(details) do
		local reqType = validTestKeys[k]
		if not reqType then
			return false, ("%%s.%%s invalid test configuration: %s is not a valid key"):format(k)
		elseif type(v) ~= reqType then
			return false, ("%%s.%%s invalid test configuration: %s must be of type %s (not %s)"):format(k, reqType, type(v))
		end
	end
	if not details.test then
		return false, "%s.%s invalid test configuration: missing the test function"
	end
	if details.cleanup and not details.setup then
		return false, "%s.%s invalid test configuration: missing 'setup' (required due to presence of 'cleanup')"
	end
	return true
end
return TestDetails