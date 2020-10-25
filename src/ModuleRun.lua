-- ModuleRun -- handles the processing & running of tests in a module

local modules = script.Parent
local Results = require(modules.Results)
local Testing = modules.Testing
local TestDetails = require(Testing.TestDetails)
local TestsHolder = require(Testing.TestsHolder)
local NewT = require(Testing.NewT)
local GetModuleName = require(modules.Descriptions).GetModuleName

local Utils = modules.Utils
local Coroutines = require(Utils.Coroutines)
local GenPluginErrHandler = require(Utils.GenPluginErrHandler)
local NewTry = require(Utils.NewTry)

local function genShouldTest(focus, skip)
	return focus and function(testName) return focus[testName] end
		or skip and function(testName) return not skip[testName] end
		or function(testName) return true end
end

local ModuleRun = {}
ModuleRun.__index = ModuleRun
function ModuleRun.new(testSettings, config, variant, loadingModuleCOs, processingModuleCOs, onFinish)
	--	Will start the running of tests (returning immediately)
	--	Will add a coroutine to loadingModuleCOs and possibly processingModuleCOs; once those are done, onFinish will be called
	--	Note: this .new function does not return anything
	--	onFinish:function(result from Results)
	local moduleScript = variant:GetModuleScript()
	local t, runMiscCleanups = NewT(testSettings, config.expectedFirst, moduleScript)
	local self = setmetatable({
		t = t,
		testSettings = testSettings,
		config = config,
		moduleScript = moduleScript,
		variant = variant,
		loadingModuleCOs = loadingModuleCOs, -- when attempting to run the test setup (`function(tests, t)`)
		processingModuleCOs = processingModuleCOs, -- when running the tests
		testResults = {},
		onFinish = function(result)
			local start = os.clock()
			local problems = runMiscCleanups()
			if result.dt then
				result.dt += os.clock() - start
			end
			if problems then
				local newResult = Results.Failed.new(("%d cleanups failed"):format(problems))
				for k, v in pairs(result) do -- transfer dt/name/etc
					newResult[k] = v
				end
				result = newResult
			end
			onFinish(result)
		end,
	}, ModuleRun)
	self:getTests()
end
function ModuleRun:getTests()
	self.testsHolder = TestsHolder.new()
	local func = self.variant:GetRequiredValue() -- this won't error because every time a variant changes we have to check if it's still a testModule (ie that it returns a function)
	NewTry(function(try)
		try
			:onAsyncStartEnd(
				function(co) self.loadingModuleCOs:Add(co) end,
				function(co) self.loadingModuleCOs:Remove(co) end)
			:onSuccess(function()
				self.processingModuleCOs:Add(self:runTests()) end)
			:onTimeout(self.config.initTimeout, function()
				local msg = "module didn't finish tests setup within " .. self.config.initTimeout .. " seconds"
				if not self.testSettings.hideOneLineErrors then
					warn(GetModuleName(self.moduleScript) .. " " .. msg)
				end
				self.onFinish(Results.Errored.new(msg)) end)
			:onError(self:genPluginErrHandler(function(msg)
				self.onFinish(Results.Errored.new("errored on init", msg))
			end), nil)
	end, func, self.testsHolder:GetTests(), self.t)
end
function ModuleRun:genPluginErrHandler(onError, intro)
	return GenPluginErrHandler(onError, intro, 
		self.testSettings.hideOneLineErrors,
		self.testSettings.putTracebackInReport)
end
function ModuleRun:runTests()
	local testsHolder = self.testsHolder
	local testFocus, testSkip = testsHolder:GetFocusSkip()
	local shouldTest = genShouldTest(testFocus, testSkip)
	local cos = Coroutines.new()
	local nameToTestResults = {}
	local function recordTestResult(name, result)
		nameToTestResults[name] = result:WithName(name)
	end
	testsHolder:ForEachTest(function(name, data)
		if shouldTest(name) then
			local function callback(result)
				recordTestResult(name, result)
			end
			if type(data) == "function" then
				cos:Add(self:runTest(name, {test=data}, callback))
			else
				local valid, msg = TestDetails.HasValidKeys(data)
				if valid then
					cos:Add(self:runTest(name, data, callback))
				else
					msg = msg:format(GetModuleName(self.moduleScript), name)
					warn(msg)
					recordTestResult(name, Results.Errored.new("Invalid test configuration", msg))
				end
			end
		else
			recordTestResult(name, Results.Skipped.new())
		end
	end)
	return cos:OnCompleteCallbackThread(function()
		local testResults = {}
		testsHolder:ForEachTest(function(name, data)
			testResults[#testResults + 1] = nameToTestResults[name]
		end)
		self.onFinish(Results.Completed.new(testResults))
	end)
end


function ModuleRun:handlePrintStartOfTest(moduleScript, testCaseDesc)
	if self.testSettings.printStartOfTests then
		print(("---%s.%s---"):format(moduleScript.Name, testCaseDesc))
	end
end

local Case = {}
Case.__index = Case
function Case.new(name, desc)
	return setmetatable({
		name = name, -- note: can be nil for a test without cases, in which case 'desc' is the test name
		desc = desc,
		-- start (assigned externally)
		-- result (assigned cooperatively)
	}, Case)
end
function Case:SetResult(result, suppressPrint)
	self.result = result:WithDT(os.clock() - self.start)
end

function ModuleRun:runTest(testName, data, onFinish)
	--	returns the coroutine to wait on for the results to be in
	local setup, cleanup = data.setup, data.cleanup
	local testFunc = data.test

	local cos = Coroutines.new()
	local unrunCleanups = {}
	local function testCleanup()
		for cleanup, case in pairs(unrunCleanups) do
			NewTry(function(try)
				-- We don't need to store the error because this test has already failed
				try:onError(self:genPluginErrHandler(nil, ("[%s.%s cleanup]"):format(GetModuleName(self.moduleScript), case.desc)))
			end, cleanup)
		end
	end
	local allCases = {}
	local function performCase(case, ...)
		self:handlePrintStartOfTest(self.moduleScript, case.desc)
		case.start = os.clock()
		if setup then
			local obj = setup(...)
			local caseCleanup
			if cleanup then
				local args = {obj, ...}
				caseCleanup = function() cleanup(unpack(args)) end
				unrunCleanups[caseCleanup] = case
			end
			testFunc(obj, ...)
			if cleanup then
				unrunCleanups[caseCleanup] = nil
				caseCleanup()
			end
		else
			testFunc(...)
		end
		case:SetResult(Results.Passed.new())
	end
	local function runCase(case, ...)
		--	Run a case (or if a test has no cases, the test itself is a case)
		--	'...' are the args to send
		allCases[#allCases + 1] = case
		local co
		local newFunc = function(...)
			co = coroutine.running()
			performCase(case, ...)
		end
		local timedOut
		NewTry(function(try)
			try
				:onTimeout(self.config.timeout or 0.2, function()
					print(("Test %s.%s timed out"):format(GetModuleName(self.moduleScript), case.desc))
					timedOut = true
					case:SetResult(Results.Failed.new("Timed out"), true) end)
				:onAsyncStartEnd(
					function() cos:Add(co) end,
					function() cos:Remove(co) end)
				:onError(self:genPluginErrHandler(function(niceMsg, msg, traceback)
					case:SetResult(Results.Failed.new(niceMsg, traceback))
				end, ("[%s.%s] "):format(GetModuleName(self.moduleScript), case.desc)))
		end, newFunc, ...)
	end
	local function getCaseDesc(caseName)
		--return caseName and ("%s.%s"):format(testName, caseName) or testName
		return caseName and ("%s, Case %s"):format(testName, caseName) or testName
	end
	local function newCase(caseName)
		return Case.new(caseName, getCaseDesc(caseName))
	end
	local function runCases(cases, caseNamePrefix, needUnpack)
		--	Returns true if it ran at least one case
		if not cases then return end
		local ran = {}
		local adjustedRunCase = needUnpack
			and function(case, args) return runCase(case, unpack(args)) end
			or runCase
		for i, case in ipairs(cases) do
			ran[i] = true
			local caseName = type(case) == "table" and (case.name or case.Name) or (caseNamePrefix .. i)
			adjustedRunCase(newCase(caseName), case)
		end	
		for name, case in pairs(cases) do
			if not ran[name] then -- else already ran above
				adjustedRunCase(newCase(name), case)
			end
		end
		return next(cases) ~= nil
	end
	-- run all cases
	local a = runCases(data.args, "Arg #", false)
	local b = runCases(data.argsLists, "ArgsList #", true)
	if not a and not b then -- no cases so just run 'func' as-is
		runCase(newCase())
	end
	return cos:OnCompleteCallbackThread(function()
		testCleanup()
		local caseResults = {}
		if #allCases == 1 and not allCases[1].name then -- Test without cases
			onFinish(allCases[1].result)
		else
			for i, case in ipairs(allCases) do
				caseResults[i] = case.result:WithName(case.name)
			end
			onFinish(Results.Completed.new(caseResults))
		end
	end)
end

return ModuleRun