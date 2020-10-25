local modules = script.Parent
local Count = require(modules.Count)
local Results = require(modules.Results)
local GetModuleName = require(modules.Descriptions).GetModuleName

local Report = {}
Report.__index = Report
local function filterOldResults(oldResults, results)
	--	Returns oldResults that do not contain any modules also listed in results
	--	Returns nil if it's an empty list
	if not oldResults then return nil end
	local inCur = {}
	for _, result in ipairs(results) do
		inCur[GetModuleName(result.moduleScript)] = true
	end
	local new = Results.new()
	for _, result in ipairs(oldResults) do
		if not inCur[GetModuleName(result.moduleScript)] then
			new[#new + 1] = result
		end
	end
	return #new > 0 and new or nil
end
function Report.new(testSettings, results, oldResults, requireTime, setupTime, runTime, totalTime)
	return setmetatable({
		testSettings = testSettings,
		results = results, -- List<Result> 
		oldResults = filterOldResults(oldResults, results),
		requireTime = requireTime,
		setupTime = setupTime,
		runTime = runTime,
		totalTime = totalTime,
	}, Report)
end
function Report:FullPrint()
	if not self.testSettings.hideReport then
		self:PrintReport()
	end
	self:PrintSummary()
end

function Report:tabChar(d)
	return d == 0 and ""
		or d == 1 and "  "
		or string.rep("  ", 2 * d - 1)
end
function Report:shouldPrintChildren(result, depth)
	if (depth == 1 and self.testSettings.alwaysShowTests) or (depth > 0 and self.testSettings.alwaysShowCases) then return true end
	for _, c in ipairs(result.subResults) do
		if c:Failed() then return true end
	end
	return false
end
function Report:willPrintChildren(result, depth)
	return result:HasChildren() and self:shouldPrintChildren(result, depth)
end
local newlineTab = "\n\t\t" .. string.rep(" ", 50)
function Report:appendReason(msg, reason, tabDepth, traceback)
	if traceback then
		if not self.testSettings.putTracebackInReport then
			traceback = nil
		else
			traceback = traceback:match("[^\n]*\n(.*)")
			if traceback then
				traceback = newlineTab .. traceback:gsub("\n", newlineTab)
			end
		end
	end
	return reason
		and string.format("%s%s\t - %s%s", msg, string.rep(" ", 50 - #msg - #self:tabChar(tabDepth)), reason, traceback or "") -- Note: the '50' came from experimenting (for one set of tests, 46-54 worked)
		or msg
end
local function dtToSBracket(dt) return (" (%dms)"):format(dt * 1000) end
local function getSummary(result)
	if result:Completed() then
		local count = result:GetSubResultsCount()
		local nonSkipped = count:NumAttempted()
		return nonSkipped + count.skipped == 0 and ""
			or (" (%s%s%s)"):format(
				nonSkipped > 0 and ("%d/%d passed"):format(count.passed, nonSkipped) or "",
				nonSkipped > 0 and count.skipped > 0 and " + " or "",
				count.skipped > 0 and count.skipped .. " skipped" or "")
	else -- Errored (note: result.msg dealt with below)
		return result.reason and (" - %s"):format(result.reason) or ""
	end
end
local reportFormats = {
	module = function(self, result, willPrintChildren) --[FAILED/Skipped/Passed/No Tests] Name Summary-if-failed-or-passed
		return self:appendReason(("[%s]%s %s%s%s"):format(
			result:Passed() and "Passed"
				or result:Errored() and "Errored"
				or result:Failed() and (#result.subResults == 0 and "FAILED - No Tests" or "FAILED")
				or "Skipped",
			result.dt and result.dt > 0 and dtToSBracket(result.dt) or "",
			GetModuleName(result.moduleScript),
			getSummary(result),
			willPrintChildren and ":" or ""), result.msg, 1)
	end,
	test = function(self, result, willPrintChildren)
		return self:appendReason(("[%s]%s %s%s%s"):format(
			result:Passed() and "Passed"
				or result:Failed() and "FAILED"
				or "Skipped",
			result.dt and dtToSBracket(result.dt) or "",
			result.name,
			getSummary(result),
			willPrintChildren and ":" or ""), result.msg or result.reason, 2, result.traceback)
	end,
	case = function(self, result)
		return self:appendReason(("[%s]%s Case %s"):format(
			result:Passed() and "Passed" or "FAILED",
			dtToSBracket(result.dt),
			result.name), result.msg, 3, result.traceback)
	end,
}
local depthToReportFormat = {reportFormats.module, reportFormats.test, reportFormats.case}
function Report:printReport(result, tabSoFar, depth)
	tabSoFar = tabSoFar or self:tabChar(1)
	depth = depth or 1
	local willPrintChildren = self:willPrintChildren(result, depth)
	print(tabSoFar .. depthToReportFormat[depth](self, result, willPrintChildren))
	if willPrintChildren then
		depth = depth + 1
		tabSoFar = self:tabChar(depth)
		for _, c in ipairs(result.subResults) do
			self:printReport(c, tabSoFar, depth)
		end
	end
end
function Report:PrintReport()
	--	Note: does not contain summary (which should be printed after)
	local results = self.results
	print() -- Spacing
	if #results == 0 then
		print("TestRunner: no modules detected")
		return
	end
	local oldResults = self.oldResults
	local hidePassedModules = self.testSettings.hidePassedOnFailure
	local curWentWrong, oldWentWrong, anyFailed
	if hidePassedModules then
		curWentWrong = results:GetModuleTestCaseCountCache().moduleCount:NumWentWrong() > 0
		oldWentWrong = oldResults and oldResults:GetModuleTestCaseCountCache().moduleCount:NumWentWrong() > 0
		anyFailed = curWentWrong or oldWentWrong
		if not anyFailed then
			hidePassedModules = false
		end
	end
	if oldResults then
		if not hidePassedModules or oldWentWrong then -- either all are printed or we have at least 1 failed
			print("Previous:")
			for _, module in ipairs(oldResults) do
				if not hidePassedModules or module:Failed() then
					self:printReport(module)
				end
			end
		end
		print("Latest:")
	else
		print("Report:")
	end
	-- at this point, if all new ones succeeded, disregard hidePassedModules
	if not curWentWrong then hidePassedModules = false end
	for _, module in ipairs(results) do
		if not hidePassedModules or module:Failed() then
			self:printReport(module)
		end
	end
end

local function getMSkipErrorStr(modulesSkipped, modulesErrored)
	return modulesSkipped == 0 and modulesErrored == 0 and ""
		or (" (%s%s%s)"):format(
			modulesSkipped > 0 and modulesSkipped .. " skipped" or "",
			modulesSkipped > 0 and modulesErrored > 0 and ", " or "",
			modulesErrored > 0 and modulesErrored .. " errored" or "")
end
local function latest(orig, latest) -- args are counts
	return orig:NumAttempted() == latest:NumAttempted() and ""
		or (" (%d/%d latest)"):format(latest.passed, latest:NumAttempted())
end
local function common(count, term, extra)
	local attempted = count:NumAttempted()
	return ("%d/%d %s%s passed%s"):format(count.passed, attempted, term, attempted == 1 and "" or "s", extra or "")
end
local function m(modules)
	return common(modules, "module", getMSkipErrorStr(modules.skipped, modules.errored))
end
local function t(tests)
	return common(tests, "test", tests.skipped > 0 and " + " .. tests.skipped .. " skipped" or "")
end
local function c(cases)
	return common(cases, "case")
end
function Report:moduleTestCaseCountToString(mtcTotal, mtcCur)
	--	only provide mtcCur if there was a previous one increasing the total
	if mtcCur then
		return ("%s%s | %s%s%s%s%s"):format(
			m(mtcTotal.moduleCount), latest(mtcTotal.moduleCount, mtcCur.moduleCount),
			t(mtcTotal.testCount), latest(mtcTotal.testCount, mtcCur.testCount),
			mtcTotal.caseCount:NumTotal() > 0 and " | " or "",
			mtcTotal.caseCount:NumTotal() > 0 and c(mtcTotal.caseCount) or "",
			mtcTotal.caseCount:NumTotal() > 0 -- if we printed new cases
				and latest(mtcTotal.caseCount, mtcCur.caseCount) -- extend with total
				or mtcCur.caseCount:NumTotal() > 0 -- else check if we printed any cases (and if so, do a variant on 'total')
					and ("(%d/%d latest cases)"):format(mtcCur.caseCount.passed, mtcCur.caseCount:NumAttempted())
					or "")
	else
		return ("%s | %s%s"):format(
			m(mtcTotal.moduleCount),
			t(mtcTotal.testCount),
			mtcTotal.caseCount:NumTotal() > 0 and " | " .. c(mtcTotal.caseCount) or "")
	end
end
function Report:PrintSummary()
	local curTotal = self.results:GetModuleTestCaseCountCache()
	local oldResults = self.oldResults
	local grandTotal = oldResults and curTotal:Clone():Add(oldResults:GetModuleTestCaseCountCache()) or curTotal
	print(("\n%s | %dms | (%dms require, %dms setup, %dms run)"):format(
		grandTotal.moduleCount:NumTotal() > 0
			and self:moduleTestCaseCountToString(grandTotal, oldResults and curTotal)
			or "No tests detected",
		self.totalTime * 1000,
		self.requireTime * 1000, self.setupTime * 1000, self.runTime * 1000))
end

return Report