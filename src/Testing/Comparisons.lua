local Comparisons = {
	MinArgsDefault = 2,
	MinArgs = {
		errors = 1,
		fail = 1,
		truthy = 1,
		falsy = 1,
	},
}
local comparisonsObj = script.Parent.ComparisonsCode
local source = comparisonsObj.Source
local ComparisonsCode = require(comparisonsObj)
local threshold = 0.00001 -- difference at which numbers are considered unequal
local comparisonsExpectedFirst = ComparisonsCode(true, threshold)
local comparisonsExpectedSecond = ComparisonsCode(false, threshold)
function Comparisons.GetComparisons(expectedFirst)
	return expectedFirst and comparisonsExpectedFirst or comparisonsExpectedSecond
end
function Comparisons.GetDocs(header)
	local s = {
		header("Available Assertions"), [=[

In the below functions, 'a' and 'b' are for 'actual' and 'expected'.
By default, 'actual' comes first, but this can be changed by having 'expectedFirst = true' in the relevant TestConfig.
]=]}
	local startedAliases = false
	local allowNewlines = false -- don't allow blank lines until we have at least 1 line of content
	for line in source:gmatch("(.-)\n") do -- note: won't get last line (but we don't need it)
		local name, args, comment = line:match("^\t(%w+) = function(%([^)]+%))[ \t]*(%-?%-?[^\n]*)$")
		if name then
			if comment:sub(1, 2) ~= "--" then comment = nil end
			s[#s + 1] = ("t.%s%s%s"):format(name, args, comment and " " .. comment or "")
			allowNewlines = true
		elseif line:match("^%s*$") then
			if allowNewlines then
				s[#s + 1] = "" -- adds a newline (due to concat below)
			end
		else
			comment = line:match("^\t\t%-%-\t(.*)")
			if comment then
				s[#s + 1] = "\t-- " .. comment
			else
				local alias, fullName = line:match("^c%.(%w+) = c%.(%w+)")
				if alias then
					if not startedAliases then
						startedAliases = true
						s[#s + 1] = "\nAliases:" -- newline
					end
					s[#s + 1] = ("\t%s == %s"):format(alias, fullName)
				end
			end
		end
	end
	for i = #s, 1, -1 do -- Remove trailing blank lines
		if s[i] == "" then
			s[i] = nil
		else
			break
		end
	end
	return table.concat(s, "\n")
end
return Comparisons