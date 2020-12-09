--[[TestTree monitors all module scripts for testing purposes.
It runs tests on startup and whenever any of the following change:
	testSettings (user settings)
	testConfigTree (any TestConfig ModuleScript)
	moduleScript.Source for any test or dependency
When a test is run, a report is printed automatically.
]]

local modules = script.Parent
local GetModuleName = require(modules.Descriptions).GetModuleName
local Results = require(modules.Results)
local RequireTracker = require(modules.RequireTracker)
local SystemRun = require(modules.SystemRun)
local Config = require(modules.Config.Config)
local baseShouldRecurse = require(modules.Config.BaseSearchShouldRecurse)
local TestConfigTree = require(modules.Config.TestConfigTree)
local TestSettingsMonitor = require(modules.Settings.TestSettingsMonitor)
local Variant = require(modules.Variant)
local Utils = modules.Utils
local ExploreServices = require(Utils.ExploreServices)
local Freezer = require(Utils.Freezer)
local TestService = game:GetService("TestService")
local testRunner = TestService.TestRunner
local StudioService = game:GetService("StudioService")
local stepped = game:GetService("RunService").Stepped

local TestTree = {}
TestTree.__index = TestTree

local allServiceNames = { -- that show up in explorer where you could add ModuleScripts
	"Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedScriptService", "ReplicatedStorage",
	"ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Teams", "SoundService",
	"Chat", "LocalizationService", "TestService"
}

-- Test run types:
--local NOT_QUEUED = false
local QUEUED_TESTS = 1
local ALL_TESTS = 2
function TestTree.new(testSettings, Report, reInit)
	local self = setmetatable({
		testSettings = testSettings,
		queue = {}, -- list (and set) of moduleScripts that need to be retested
		-- queued:false/a constant above, representing the type of testing that is currently queued
		-- lastResults = nil
		-- lastReport = nil
		moduleScriptCons = {},
		testVariants = {}, -- moduleScript -> variant for valid tests only (ie they return a function without erroring)
		testSetupFunc = {}, -- moduleScript -> setup function (for tests only)
		Report = Report,
		requireTracker = RequireTracker.new(),
		testRunNum = 0,
		allowFreezer = false, -- We disable the freezer until all tests/configs have been required for the first time
		--	We need to do this in case the user is looking at a script when they press Run (allowing configs to be read correctly)
		freezer = Freezer.new(false),
	}, TestTree)
	self.moduleScriptToVariant = Variant.Storage.new(nil, function(moduleScript)
		return self:isModuleScriptTemporary(moduleScript)
	end)
	self.testSettingsMonitor = TestSettingsMonitor.new(testSettings, self)
	local function updateFreezer()
		self.freezer:SetEnabled(self.allowFreezer and testSettings.preventRunWhileEditingScripts)
	end
	self.testSettingsCon = testSettings:GetPropertyChangedSignal("preventRunWhileEditingScripts"):Connect(updateFreezer)
	local testConfigTree
	local MayBeTest
	local function sourceChanged(moduleScript, variant) -- also works for name changes
		--	May yield
		-- Require might yield. As it yields, we don't want it to be considered a test.
		self:notATest(moduleScript)
		if moduleScript.Name == "TestConfig" or not MayBeTest(moduleScript) then return end
		local config = testConfigTree:GetFor(moduleScript)
		self.requireTracker:Start(moduleScript)
		local success, value = variant:TryRequire(config.requireTimeout)
		if success then
			local configScript = testConfigTree:GetConfigScriptFor(moduleScript, "GetSetupFunc")
			success, value = pcall(function() return config.GetSetupFunc(moduleScript, value) end)
			local function problem(msg)
				if configScript then
					warn(configScript:GetFullName() .. msg)
				else
					self.requireTracker:Finish(moduleScript)
					error("Default config" .. msg)
				end
			end
			if not success then
				problem((".GetSetupFunc(%s, requiredValue) errored with: %s"):format(
					GetModuleName(moduleScript), value))
			elseif value then
				if type(value) ~= "function" then
					problem((".GetSetupFunc(%s, requiredValue) returned '%s' instead of the setup function"):format(
						GetModuleName(moduleScript), tostring(value)))
				else
					self:thisIsATest(moduleScript, value)
				end
			end
		end -- otherwise, variant:TryRequire will have already emitted the problem via PluginErrHandler
		self.requireTracker:Finish(moduleScript)
	end
	-- Create testConfigTree
	local function onConfigChange(testConfig, old, new)
		-- could do: if Config.AnyTimeoutChanged
		local shouldFreeze = self.freezer:ShouldFreeze()
		local function analyze()
			if testConfig.Parent == TestService then
				local function mayHaveChanged(key)
					return not Config.IsDefault(old, key) or not Config.IsDefault(new, key)
				end
				if mayHaveChanged("SearchShouldRecurse") then
					reInit()
					return
				elseif mayHaveChanged("GetSearchArea") then
					local a = Config.GetSearchArea(old)
					local b = Config.GetSearchAreaFromModule(testConfig)
					local same = #a == #b
					if same then
						for i, v in ipairs(a) do
							if v ~= b[i] then
								same = false
								break
							end
						end
					end
					if not same then
						reInit()
						return
					end
				end
				if mayHaveChanged("GetSetupFunc") or mayHaveChanged("MayBeTest")  then
					-- We need to re-analyze all scripts as if their source changed
					MayBeTest = new.MayBeTest
					for moduleScript, variant in pairs(self.moduleScriptToVariant) do
						sourceChanged(moduleScript, variant)
					end
				end
			end
			self:considerStartTestRun(ALL_TESTS, shouldFreeze)
		end
		if shouldFreeze then
			self.freezer:Freeze("TestConfigChanged", analyze)
		else
			analyze()
		end
		--[[In response to each config change, could do...
		timeout - run all*
		skip/focus
			- anything added to focus that wasn't run before? run it.
			- everything removed from focus? run all*
		* run all that this config affects
		]]
	end
	local topLevelConfig = Config.GetConfigFromModule(TestService:FindFirstChild("TestConfig"))
	local listenServiceNames = Config.GetSearchArea(topLevelConfig)
	testConfigTree = TestConfigTree.new(listenServiceNames, topLevelConfig.SearchShouldRecurse, Config, onConfigChange, self.freezer)
	self.testConfigTree = testConfigTree
	-- Setup connections
	MayBeTest = topLevelConfig.MayBeTest
	local SearchShouldRecurse = topLevelConfig.SearchShouldRecurse
	self.serviceConCleanup = ExploreServices(listenServiceNames, function(obj)
		if obj:IsA("ModuleScript") and not obj:IsDescendantOf(testRunner) and MayBeTest(obj) then
			local variant = self:GetVariant(obj)
			coroutine.wrap(sourceChanged)(obj, variant)
			variant.Invalidated:Connect(function()
				if self.destroyed then return end -- variants can invalidate each other before they are destroyed
				if variant:IsDestroyed() then
					self:notATest(obj)
					self.requireTracker:RemoveModuleScript(obj)
				elseif self:isModuleScriptTemporary(obj) then
					return
				elseif self.freezer:ShouldFreeze() then
					self.freezer:Freeze(obj, function() sourceChanged(obj, variant) end)
				else
					sourceChanged(obj, variant)
				end
			end)
			variant.SourceChanged:Connect(function()
				-- Promote this to a non-temporary script
				if self.moduleScriptsAtStartOfRun then
					self.moduleScriptsAtStartOfRun[obj] = true
				end
			end)
		end
		return SearchShouldRecurse(obj, baseShouldRecurse)
	end)
	local moduleScriptExists = {}
	self.moduleScriptExists = moduleScriptExists
	self.moduleScriptCleanup = ExploreServices(allServiceNames, function(obj)
		if obj:IsA("ModuleScript") then
			local con
			local function cleanup()
				con:Disconnect()
				moduleScriptExists[obj] = nil
			end
			con = obj.AncestryChanged:Connect(function(child, parent)
				if not parent then
					cleanup()
				end
			end)
			moduleScriptExists[obj] = cleanup
		end
		return true
	end)
	self:considerStartTestRun(ALL_TESTS)
	return self
end
function TestTree:Destroy()
	self.destroyed = true
	self.freezer:Destroy()
	self.testConfigTree:Destroy()
	self.serviceConCleanup()
	if self.queuedCon then
		self.queuedCon:Disconnect()
	end
	self.testRunNum += 1
	self.moduleScriptToVariant:Destroy()
	self.requireTracker:Destroy()
	self.testSettingsMonitor:Destroy()
	self.moduleScriptCleanup()
	for _, cleanup in pairs(self.moduleScriptExists) do
		cleanup()
	end
end
function TestTree:GetVariant(moduleScript)
	return self.moduleScriptToVariant:Get(moduleScript)
end
function TestTree:isModuleScriptTemporary(moduleScript)
	-- It's temporary if we're in a run and the moduleScript didn't exist before the run started
	-- Note that it's removed from moduleScriptsAtStartOfRun if its source changes, even during a run
	return self.moduleScriptsAtStartOfRun and not self.moduleScriptsAtStartOfRun[moduleScript]
end
function TestTree:notATest(moduleScript)
	self.testVariants[moduleScript] = nil
	self.testSetupFunc[moduleScript] = nil
	self:removeFromQueue(moduleScript)
end
function TestTree:thisIsATest(moduleScript, setupFunc)
	if self.testVariants[moduleScript] then return end -- already known to be a test
	self.testVariants[moduleScript] = self.moduleScriptToVariant[moduleScript]
	self.testSetupFunc[moduleScript] = setupFunc
	self:addToQueue(moduleScript)
end
function TestTree:addToQueue(moduleScript)
	if self.queued == ALL_TESTS then return end
	local queue = self.queue
	if not queue[moduleScript] then
		queue[moduleScript] = true
		queue[#queue + 1] = moduleScript
		self:considerStartTestRun(QUEUED_TESTS)
	end
end
function TestTree:removeFromQueue(moduleScript)
	local queue = self.queue
	if queue[moduleScript] then
		queue[moduleScript] = nil
		table.remove(queue, table.find(queue, moduleScript))
	end
end
function TestTree:considerStartTestRun(level, suppressMandatoryWait)
	--	Guaranteed to not yield
	if not self.queued then
		self.testRunNum += 1
	elseif level <= self.queued then -- nothing to be done
		return
	end
	local wasQueued = self.queued
	self.queued = level
	-- We often want to wait at least a moment before running tests to allow all script edits to be registered
	if wasQueued then return end -- we already have a thread in continueQueue
	if level == ALL_TESTS and next(self.queue) then -- reset queue since we'll be testing all of them
		self.queue = {}
	end
	if suppressMandatoryWait then
		coroutine.wrap(self.waitForTests)(self)
	else
		self.queuedCon = stepped:Connect(function()
			self.queuedCon:Disconnect()
			self.queuedCon = nil
			self:waitForTests()
		end)
	end
end
function TestTree:waitForTests()
	--	Wait until the tests that we want to run have finished being required
	while self.queued == QUEUED_TESTS and self.requireTracker:WaitOnList(self.queue, function() return self.queue ~= QUEUED_TESTS end) do
		-- WaitOnList returns whether we waited, so we keep waiting on 'queue' in case more are added over time
		--	We provide a cancel function for WaitOnList so that if we switch to ALL_TESTS, we can just use the :Wait() function (which is more efficient)
	end
	-- self.queued could be upgraded during WaitOnList
	if self.queued == ALL_TESTS then
		self.requireTracker:Wait()
	end
	local queued = self.queued
	self.queued = false
	if queued == ALL_TESTS then
		self:runAllTests()
	else
		self:runQueuedTests()
	end
end
function TestTree:runAllTests()
	self:performRun(function(addTest)
		for moduleScript, variant in pairs(self.testVariants) do
			addTest(moduleScript)
		end
	end)
end

function TestTree:runQueuedTests()
	local queue = self.queue
	self.queue = {}
	self:performRun(function(addTest)
		for _, moduleScript in ipairs(queue) do
			addTest(moduleScript)
		end
	end)
end

function TestTree:startTest(moduleScript)
	self.currentRun:AddTest(
		self.testConfigTree:GetFor(moduleScript),
		self:GetVariant(moduleScript))
end
local function cloneMSE(t)
	local new = {}
	for k, con in pairs(t) do
		new[k] = true
	end
	return new
end
local function filterResultsForNonTests(results, testVariants)
	local new = Results.new()
	local n = 0
	for _, m in ipairs(results) do
		if testVariants[m.moduleScript] then -- Only keep it if it's still a valid test
			n += 1
			new[n] = m
		end
	end
	return new
end
local function newLastResults(lastResults, results, testVariants)
	if lastResults then -- Merge results into lastResults
		local new = Results.new()
		local n = 0
		local moduleScriptToResult = {}
		-- Store results in moduleScriptToResult
		-- Then use that to update the "new" lastResults
		-- Remove it from moduleScriptToResult if it's been dealt with
		-- Add any remaining moduleScriptToResult to "new" in the order they appear in results
		for _, m in ipairs(results) do
			moduleScriptToResult[m.moduleScript] = m
		end
		for _, m in ipairs(lastResults) do
			if testVariants[m.moduleScript] then -- Only keep it if it's still a valid test
				n += 1
				local updated = moduleScriptToResult[m.moduleScript]
				if updated then
					new[n] = updated
					moduleScriptToResult[m.moduleScript] = nil
				else
					new[n] = m
				end
			end
		end
		for _, m in ipairs(results) do
			if moduleScriptToResult[m.moduleScript] then
				n += 1
				new[n] = m
			end
		end
		return new
	else
		return results
	end
end
function TestTree:performRun(setupTests)
	if self.destroyed then return end
	local num = self.testRunNum
	print("\n-----------Starting Tests-----------")
	self.allowFreezer = true -- see allowFreezer initialization for explanation
	local start = os.clock()
	self.moduleScriptsAtStartOfRun = cloneMSE(self.moduleScriptExists)
	local currentRun = SystemRun.new(self.testSettings)
	self.currentRun = currentRun
	local testConfigTree = self.testConfigTree
	setupTests(function(moduleScript)
		currentRun:AddTest(testConfigTree:GetFor(moduleScript), self:GetVariant(moduleScript))
	end)
	local requiringTime = os.clock() - start
	local s = os.clock()
	currentRun:WaitForLoadingComplete()
	local setupTime = os.clock() - s
	s = os.clock()
	currentRun:WaitForTestsComplete()
	local runTime = os.clock() - s
	if num ~= self.testRunNum then return end -- Already queueing for or running new test run, so don't print the results of this run
	local results = currentRun:GetResults()
	local lastResults = self.lastResults
	if lastResults then
		lastResults = filterResultsForNonTests(lastResults, self.testVariants)
	end
	local report = self.Report.new(self.testSettings,
		results,
		lastResults,
		requiringTime,
		setupTime,
		runTime,
		os.clock() - start)
	report:FullPrint()
	self.lastReport = report
	self.lastResults = newLastResults(lastResults, results, self.testVariants)
	self.currentRun = nil
	self.moduleScriptsAtStartOfRun = nil
end
function TestTree:RunAllTests()
	self:considerStartTestRun(ALL_TESTS, true)
end
function TestTree:ReprintReport()
	if self.lastReport then
		self.lastReport:FullPrint()
	elseif not self.currentRun then
		self:considerStartTestRun(ALL_TESTS, true)
	end -- else first report will print soon
end
-- function TestTree:RunTests(moduleScripts) -- commented out because not used
-- 	for _, moduleScript in ipairs(moduleScripts) do
-- 		if self.testVariants[moduleScript] then
-- 			self:addToQueue(moduleScript)
-- 		end
-- 	end
-- end
function TestTree:PrintDependencyTree() -- TODO Add a button to print this out?
	--[[TODO Could do better tree analysis
	ex: a>b, b>c, c>d
	say we start at b>c, then we see c>d, but later we find a>b
	so since 'a' is not a descendant of 'b', we can add it as a parent and merge the trees
	
	What if we see c>d first, then we see a>b>c?
		at this point, we could say "hey, we saw 'c' before"
		Then we ask "was a/b a descendant of c?"
		Since no, we connect them (otherwise they would already have been connected)
		> similarly we can ask if there was any overlap
		Is it possible that only one overlaps but others still need to be connected?
	]]
	print("\nDependency Tree")
	local seen = {}
	for _, v in pairs(self.moduleScriptToVariant) do
		v:PrintDependencies(seen)
	end
end
return TestTree