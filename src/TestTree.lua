--[[TestTree monitors all module scripts for testing purposes.
It runs tests on startup and whenever any of the following change:
	testSettings (user settings)
	testConfigTree (any TestConfig ModuleScript)
	moduleScript.Source for any test or dependency
When a test is run, a report is printed automatically.
]]

local modules = script.Parent
local Results = require(modules.Results)
local RequireTracker = require(modules.RequireTracker)
local SystemRun = require(modules.SystemRun)
local TestConfigTree = require(modules.Config.TestConfigTree)
local TestSettingsMonitor = require(modules.Settings.TestSettingsMonitor)
local Variant = require(modules.Variant)
local Utils = modules.Utils
local ExploreServices = require(Utils.ExploreServices)
local Freezer = require(Utils.Freezer)
local testRunner = game:GetService("TestService").TestRunner
local StudioService = game:GetService("StudioService")
local stepped = game:GetService("RunService").Stepped

local TestTree = {}
TestTree.__index = TestTree

-- Test run types:
--local NOT_QUEUED = false
local QUEUED_TESTS = 1
local ALL_TESTS = 2
function TestTree.new(testSettings, listenServiceNames, Config, Report)
	local self = setmetatable({
		testSettings = testSettings,
		queue = {}, -- list (and set) of moduleScripts that need to be retested
		-- queued:false/a constant above, representing the type of testing that is currently queued
		-- lastResults = nil
		-- lastReport = nil
		moduleScriptCons = {},
		testVariants = {}, -- moduleScript -> variant for valid tests only (ie they return a function without erroring)
		Report = Report,
		moduleScriptToVariant = Variant.Storage.new(),
		requireTracker = RequireTracker.new(),
		testRunNum = 0,
		allowFreezer = false, -- We disable the freezer until all tests/configs have been required for the first time
		--	We need to do this in case the user is looking at a script when they press Run (allowing configs to be read correctly)
		freezer = Freezer.new(false),
	}, TestTree)
	self.testSettingsMonitor = TestSettingsMonitor.new(testSettings, self)
	local function updateFreezer()
		self.freezer:SetEnabled(self.allowFreezer and testSettings.preventRunWhileEditingScripts)
	end
	self.testSettingsCon = testSettings:GetPropertyChangedSignal("preventRunWhileEditingScripts"):Connect(updateFreezer)
	-- Create testConfigTree
	local function onConfigChange(testConfig, old, new)
		-- could do: if Config.AnyTimeoutChanged
		if self.freezer:ShouldFreeze() then
			self.freezer:Freeze("RunAllTests", function()
				self:considerStartTestRun(ALL_TESTS, true)
			end)
		else
			self:considerStartTestRun(ALL_TESTS)
		end
		--[[In response to each config change, could do...
		timeout - run all*
		skip/focus
			- anything added to focus that wasn't run before? run it.
			- everything removed from focus? run all*
		* run all that this config affects
		]]
	end
	local testConfigTree = TestConfigTree.new(listenServiceNames, Config, onConfigChange, self.freezer)
	self.testConfigTree = testConfigTree
	-- Setup connections
	local function sourceChanged(moduleScript, variant)
		--	May yield
		-- Require might yield. As it yields, we don't want it to be considered a test.
		self:notATest(moduleScript)
		local config = testConfigTree:GetFor(moduleScript)

		self.requireTracker:Start(moduleScript)
		local success, value = variant:TryRequire(config.requireTimeout)
		if success and type(value) == "function" then
			self:thisIsATest(moduleScript)
		end -- otherwise, variant:TryRequire will have already emitted the problem via GenPluginErrHandler
		self.requireTracker:Finish(moduleScript)
	end
	self.serviceConCleanup = ExploreServices(listenServiceNames, function(obj)
		if not obj:IsA("ModuleScript") or obj:IsDescendantOf(testRunner) then return end
		local variant = self:GetVariant(obj)
		coroutine.wrap(sourceChanged)(obj, variant)
		variant.Invalidated:Connect(function()
			if variant:IsDestroyed() then
				self:notATest(obj)
				self.requireTracker:RemoveModuleScript(obj)
			elseif self.freezer:ShouldFreeze() then
				self.freezer:Freeze(obj, function() sourceChanged(obj, variant) end)
			else
				sourceChanged(obj, variant)
			end
		end)
	end)
	self:considerStartTestRun(ALL_TESTS)
	return self
end
function TestTree:Destroy()
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
end
function TestTree:GetVariant(moduleScript)
	return self.moduleScriptToVariant:Get(moduleScript)
end
function TestTree:notATest(moduleScript)
	self.testVariants[moduleScript] = nil
	self:removeFromQueue(moduleScript)
end
function TestTree:thisIsATest(moduleScript)
	if self.testVariants[moduleScript] then return end -- already known to be a test
	self.testVariants[moduleScript] = self.moduleScriptToVariant[moduleScript]
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
function TestTree:performRun(setupTests)
	local num = self.testRunNum
	print("\n-----------Starting Tests-----------")
	self.allowFreezer = true -- see allowFreezer initialization for explanation
	local start = os.clock()
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
	local report = self.Report.new(self.testSettings,
		results,
		self.lastResults,
		requiringTime,
		setupTime,
		runTime,
		os.clock() - start)
	report:FullPrint()
	self.lastReport = report
	local lastResults = self.lastResults
	if lastResults then
		local n = 0
		local new = Results.new()
		local moduleScriptToResult = {}
		-- Store results in moduleScriptToResult
		-- Then use that to update the "new" lastResults
		-- Remove it from moduleScriptToResult if it's been dealt with
		-- Add any remaining moduleScriptToResult to "new" in the order they appear in results
		for _, m in ipairs(results) do
			moduleScriptToResult[m.moduleScript] = m
		end
		local testVariants = self.testVariants
		for _, m in ipairs(lastResults) do
			if testVariants[m.moduleScript] then -- Don't keep it if it's no longer a test
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
		self.lastResults = new
	else
		self.lastResults = results
	end
	self.currentRun = nil
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