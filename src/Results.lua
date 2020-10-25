--[[Results
Results as a class is a list of module results
	which may have test results
	which may have case results
Each individual result is also a Result, which you can create with
	Results.Passed.new()
	or any similar class.
]]

local Count = require(script.Parent.Count)

local ModuleTestCaseCount = {}
ModuleTestCaseCount.__index = ModuleTestCaseCount
function ModuleTestCaseCount.new(moduleCount, testCount, caseCount)
	return setmetatable({
		moduleCount = moduleCount,
		testCount = testCount,
		caseCount = caseCount,
	}, ModuleTestCaseCount)
end
function ModuleTestCaseCount:Add(other)
	self.moduleCount:Add(other.moduleCount)
	self.testCount:Add(other.testCount)
	self.caseCount:Add(other.caseCount)
	return self
end
function ModuleTestCaseCount:Clone()
	local t = {}
	for k, v in pairs(self) do
		t[k] = v:Clone()
	end
	return setmetatable(t, ModuleTestCaseCount)
end

local Results = {}
Results.__index = Results
function Results.new(results) -- A list of module results
	--	You may use a Results as a regular list, though it should only contain module results
	return setmetatable(results or {}, Results)
end
function Results:GetModuleTestCaseCount()
	local moduleCount = Count.For(self)
	local testCount, caseCount = Count.new(), Count.new()
	for _, module in ipairs(self) do
		if module.subResults then
			testCount:Add(module:GetSubResultsCount())
			for _, test in ipairs(module.subResults) do
				if test.subResults then
					caseCount:Add(test:GetSubResultsCount())
				end
			end
		end
	end
	return ModuleTestCaseCount.new(moduleCount, testCount, caseCount)
end
function Results:GetModuleTestCaseCountCache()
	--	Caching is not the default behaviour since the results list could be modified
	local cache = self.mtcCountCache
	if not cache then
		cache = self:GetModuleTestCaseCount()
		self.mtcCountCache = cache
	end
	return cache
end

local BaseResult = {}
BaseResult.__index = BaseResult
local function no() return false end
local function yes() return true end
-- Note: You should call the following with ":", ex result:Skipped()
BaseResult.Skipped = no
BaseResult.Errored = no -- special type of failure where it didn't even run (ex due to config problems)
BaseResult.Completed = no
BaseResult.Failed = no
BaseResult.Passed = no
function BaseResult:WithModuleScript(moduleScript)
	self.moduleScript = moduleScript
	return self
end
function BaseResult:WithName(name)
	self.name = name
	return self
end
function BaseResult:HasChildren()
	return self.subResults and #self.subResults > 0
end

local Skipped = setmetatable({}, BaseResult)
Skipped.__index = Skipped
Results.Skipped = Skipped
function Skipped.new() return setmetatable({}, Skipped) end
Skipped.Skipped = yes
function Skipped:UpdateCount(count) count.skipped += 1 end

local DTResult = setmetatable({}, BaseResult)
DTResult.__index = DTResult
function DTResult:WithDT(dt)
	self.dt = dt
	return self
end

local Errored = setmetatable({}, DTResult)
Errored.__index = Errored
Results.Errored = Errored
function Errored.new(reason, msg)
	return setmetatable({
		reason = reason,
		msg = msg,
	}, Errored)
end
Errored.Errored = yes
Errored.Failed = yes
function Errored:UpdateCount(count) count.errored += 1 end

-- Failed and Passed are for single results (ex test cases); Completed is for a collection of cases or tests
local Failed = setmetatable({}, DTResult)
Failed.__index = Failed
Results.Failed = Failed
function Failed.new(msg, traceback)
	return setmetatable({
		msg = msg,
		traceback = traceback,
	}, Failed)
end
Failed.Failed = yes
function Failed:UpdateCount(count) count.failed += 1 end

local Passed = setmetatable({}, DTResult)
Passed.__index = Passed
Results.Passed = Passed
function Passed.new()
	return setmetatable({}, Passed)
end
Passed.Passed = yes
function Passed:UpdateCount(count) count.passed += 1 end

local Completed = setmetatable({}, DTResult)
Completed.__index = Completed
Results.Completed = Completed
function Completed.new(subResults)
	--	subResults: for modules, list of test results. For tests, list of case results.
	local count = Count.For(subResults)
	local dt = 0
	for _, r in ipairs(subResults) do
		if r.dt then
			dt += r.dt
		end
	end
	return setmetatable({
		subResults = subResults,
		count = count,
		dt = dt,
		-- If there are no tests/cases, this was configured wrong
		-- Otherwise, this result is a pass if all of the children are passed/skipped
		passed = count.failed == 0 and count.errored == 0 and (count.passed > 0 or count.skipped > 0)
	}, Completed)
end
Completed.Completed = yes
function Completed:GetSubResults() return self.subResults end
function Completed:GetSubResultsCount() return self.count end
function Completed:Passed()
	return self.passed
end
function Completed:Failed()
	return not self.passed
end
function Completed:UpdateCount(count)
	if self.passed then
		count.passed += 1
	else
		count.failed += 1
	end
end

-- -- In the below we could simplify with "Entry(name, dt, result, children)" (or call it Node)
-- local Module = {}
-- Module.__index = Module
-- Results.Module = Module
-- function Module.new(m, dt, result, testCases)
-- 	return setmetatable({
-- 		m = m,
-- 		dt = dt,
-- 		result = result,
-- 		testCases = testCases,
-- 	}, Module)
-- end

-- local Test = {}
-- Test.__index = Test
-- Results.Test = Test
-- function Test.new(name, dt, result, caseResults)
-- 	return setmetatable({
-- 		name = name,
-- 		dt = dt,
-- 		result = result,
-- 		caseResults = caseResults,
-- 	}, Test)
-- end

-- local Case = {}
-- Case.__index = Case
-- Results.Case = Case
-- function Case.new(name, dt, result)
-- 	return setmetatable({
-- 		name = name,
-- 		dt = dt,
-- 		result = result,
-- 	}, Case)
-- end


return Results