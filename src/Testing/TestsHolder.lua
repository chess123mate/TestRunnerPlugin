-- TestsHolder - holds a 'tests' object

local modules = script.Parent.Parent
local Utils = modules.Utils
local EnsureDictionary = require(Utils.EnsureDictionary)

local specialKeys = { -- If these keys show up in tests's "__order", ignore them
	focus = true,
	skip = true,
}
local testsMT = {
	__newindex = function(self, key, value)
		self.__order[#self.__order + 1] = key
		rawset(self, key, value)
	end
}
local function newTests()
	return setmetatable({
		__unfinishedMultis = {},
		__order = {},
		focus = {},
		skip = {},
	}, testsMT)
end

local function containsTrueValues(dict)
	for k, v in pairs(dict) do
		if v then return true end
	end
	return false
end

local TestsHolder = {}
TestsHolder.__index = TestsHolder
function TestsHolder.new(args)
	return setmetatable({
		tests = newTests()
	}, TestsHolder)
end
function TestsHolder:GetTests() return self.tests end
function TestsHolder:ForEachTest(func)
	--	func(name, data)
	local tests = self.tests
	for _, name in ipairs(tests.__order) do
		if not specialKeys[name] then
			func(name, tests[name])
		end
	end
end
function TestsHolder:GetFocusSkip()
	--	returns focus, skip (either a set<testName:string> or nil)
	local tests = self.tests
	local testFocus = EnsureDictionary(tests.focus or {})
	local testSkip = EnsureDictionary(tests.skip or {})
	self:ForEachTest(function(name, data)
		if type(data) == "table" then
			if data.focus then
				testFocus[name] = true
			end
			if data.skip then
				testSkip[name] = true
			end
		end
	end)
	if not containsTrueValues(testFocus) then testFocus = nil end
	if not containsTrueValues(testSkip) then testSkip = nil end
	return testFocus, testSkip
end
return TestsHolder