-- SystemRun runs test modules (as configurations allow) and returns their test results

local modules = script.Parent
local ModuleRun = require(modules.ModuleRun)
local Results = require(modules.Results)
local GetModuleName = require(modules.Descriptions).GetModuleName
local Utils = modules.Utils
local Coroutines = require(Utils.Coroutines)

local function findWholeWord(input, word)
	return string.find(input, "%f[%w_]" .. word .. "%f[^%w_]")
end
local function shouldTestModule(config, moduleScript)
	local focus, skip = config.focus, config.skip
	local name = moduleScript.Name
	local name2 = GetModuleName(moduleScript)
	if focus then
		if focus[name] then return true end
		-- NOTE: This won't find it if the name provided is "TestService.Test" since GetModuleName excludes TestService
		for focusName in pairs(focus) do
			if findWholeWord(name2, focusName) then return true end
		end
		return false
	elseif skip then
		if skip[name] or skip[name2] then return false end
		for skipName in pairs(skip) do
			if findWholeWord(name2, skipName) then return false end
		end
	end
	return true
end

local SystemRun = {}
SystemRun.__index = SystemRun
function SystemRun.new(testSettings)
	return setmetatable({
		testSettings = testSettings,
		loadingModuleCOs = Coroutines.new(),
		processingModuleCOs = Coroutines.new(),
		moduleResults = {}, -- [variant] = Result
		order = {}, -- List<Variant>
	}, SystemRun)
end
function SystemRun:GetTestSettings() return self.testSettings end
function SystemRun:AddTest(config, variant)
	self.order[#self.order + 1] = variant
	local function onFinish(result)
		self.moduleResults[variant] = result:WithModuleScript(variant:GetModuleScript())
	end
	if shouldTestModule(config, variant:GetModuleScript()) then
		ModuleRun.new(self.testSettings, config, variant, self.loadingModuleCOs, self.processingModuleCOs, onFinish)
	else
		onFinish(Results.Skipped.new())
	end
end
function SystemRun:WaitForLoadingComplete()
	self.loadingModuleCOs:WaitForComplete()
end
function SystemRun:WaitForTestsComplete()
	self.processingModuleCOs:WaitForComplete()
end
function SystemRun:GetResults()
	local results = {}
	local moduleResults = self.moduleResults
	for i, variant in ipairs(self.order) do
		results[i] = moduleResults[variant] or error("No result for " .. variant:GetModuleScript():GetFullName())
	end
	return Results.new(results)
end
return SystemRun