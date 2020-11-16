local TestService = game:GetService("TestService")
local modules = script.Parent
local testRunnerScript = TestService:FindFirstChild("TestRunner")

local function isInstalled()
	return testRunnerScript and testRunnerScript.Parent
end
local function startupWhenInstalled()
	require(modules.UpdateTestRunnerScript)
	TestService.ExecuteWithStudioRun = true
	TestService.Timeout = 1e8
end
local function install()
	testRunnerScript = Instance.new("Script")
	testRunnerScript.Name = "TestRunner"
	testRunnerScript.Parent = TestService
	modules.UserDocumentation.ExampleTests:Clone().Parent = testRunnerScript
	startupWhenInstalled()
end
local function onAlreadyInstalled()
	local signal = testRunnerScript:FindFirstChild("Running")
	if signal then
		signal:Destroy()
	end
	startupWhenInstalled()
end

local testSettings = require(modules.Settings.TestSettings).new(plugin)
local setupToolbar, guiCleanup do
	local pluginToolbar
	local setupToolbarWhenInstalled
	local function create(text, tooltip, action)
		local button = pluginToolbar:CreateButton(text, tooltip or "", "")
		button.ClickableWhenViewportHidden = true
		return button, action and button.Click:Connect(action)
	end
	local TestSettingsGui = require(modules.Settings.TestSettingsGui)
	local testSettingsGui
	local settingsWidget
	local settingsButton
	local function toggleTestSettingsGui()
		if not settingsWidget then -- create
			settingsWidget = plugin:CreateDockWidgetPluginGui("TestRunnerSettings", DockWidgetPluginGuiInfo.new(
				Enum.InitialDockState.Float,
				true, -- enabled
				true, -- override previous enabled state
				600, -- default width
				400, -- default height
				400, -- min width
				100 -- min height
			))
			settingsWidget.Title = "Test Runner User Settings"
			settingsWidget.Name = settingsWidget.Title
			settingsWidget:BindToClose(function()
				toggleTestSettingsGui()
			end)
			testSettingsGui = TestSettingsGui.new(testSettings)
			testSettingsGui:GetInstance().Parent = settingsWidget
		elseif settingsWidget.Enabled then -- close
			settingsWidget.Enabled = false
		else -- open
			testSettingsGui:Update()
			settingsWidget.Enabled = true
		end
		settingsButton:SetActive(settingsWidget.Enabled)
	end
	function setupToolbar()
		pluginToolbar = plugin:CreateToolbar("TestRunner")
		if not isInstalled() then
			local installButton; installButton = create("Install", "Install TestRunner into this place", function()
				if isInstalled() then
					print("TestRunner is already installed in this place.")
				else
					install()
					print("TestRunner has been installed. You can read the documentation in TestService.TestRunner.")
				end
				-- Unfortunately we can't destroy the button or the toolbar
				installButton:SetActive(false)
				installButton.Enabled = false
			end)
		end
		settingsButton = create("Settings", "Customize Test Runner User Settings", toggleTestSettingsGui)
	end
	function guiCleanup()
		if testSettingsGui then
			testSettingsGui:Destroy()
		end
	end
end

local testVariants
local function tryRunningTests()
	local folder = game:GetService("ServerScriptService"):FindFirstChild("__TestRunnerPluginTests")
	if not folder then return end
	testVariants = testVariants or require(modules.Variant).Storage.new()
	for _, obj in ipairs(folder:GetChildren()) do
		if obj:IsA("ModuleScript") then
			local variant = testVariants:Get(obj)
			local success, value = variant:TryRequire()
			if success then
				local test = value[1]
				if type(test) == "function" then
					spawn(test) -- each test function can get its own stack trace this way
				end
			end
		end
	end
end

local testTree

plugin.Unloading:Connect(function()
	guiCleanup()
	if testVariants then
		testVariants:Destroy()
	end
	if testTree then
		testTree:Destroy()
	end
	testSettings:Destroy()
end)

local RunService = game:GetService("RunService")
if not RunService:IsRunning() then
	tryRunningTests()
	if isInstalled() then
		onAlreadyInstalled()
	end
	setupToolbar()
	return
elseif not RunService:IsRunMode() or not isInstalled() then
	-- We only want to run tests when installed & the game is running
	return
end
setupToolbar()
-- We can now wait for TestRunner script to signal that it's running
--	since RunService doesn't tell us the difference between Run mode and Server mode [as of October 2020]
local signal = testRunnerScript:WaitForChild("Running", 60)
if not signal then return end

local Report = require(modules.Report)
local TestTree = require(modules.TestTree)
local Config = require(modules.Config.Config)

local reInit
local function init()
	testTree = TestTree.new(testSettings, Report, reInit)
end
function reInit()
	testTree:Destroy()
	init()
end

do -- Give other scripts a chance to run so as to not impact the run time of the tests nor the TestRunner
	-- Experimenting discovered that a large surge of other scripts run during the 2nd wait, so always wait at least twice
	local start = os.clock()
	wait()
	for i = 1, 4 do
		local dt = wait()
		if dt < 0.1 then break end
	end
	print(("TestRunner waited %dms for other scripts"):format((os.clock()-start)*1000))
end
init()