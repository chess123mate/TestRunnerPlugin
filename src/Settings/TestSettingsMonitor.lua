local TestSettingsMonitor = {} -- calls appropriate functions on a TestTree when testSettings changes
TestSettingsMonitor.__index = TestSettingsMonitor
function TestSettingsMonitor.new(testSettings, testTree)
	local cons = {}
	local function new(prop, action)
		cons[#cons + 1] = testSettings:GetPropertyChangedSignal(prop):Connect(action)
	end
	local function reprintReportIfShown()
		if testSettings.ShowReport then
			testTree:ReprintReport()
		end
	end
	new("printStartOfTests", function() testTree:RunAllTests() end)
	new("hideReport", reprintReportIfShown)
	new("putTracebackInReport", reprintReportIfShown)
	new("hidePassedOnFailure", reprintReportIfShown)
	new("alwaysShowTests", reprintReportIfShown)
	new("alwaysShowCases", reprintReportIfShown)
	return setmetatable({
		cons = cons
	}, TestSettingsMonitor)
end
function TestSettingsMonitor:Destroy()
	for _, con in ipairs(self.cons) do
		con:Disconnect()
	end
end
return TestSettingsMonitor