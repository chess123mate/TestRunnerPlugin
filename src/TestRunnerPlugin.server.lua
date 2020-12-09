local TestService = game:GetService("TestService")
local modules = script.Parent
local testRunnerScript = TestService:FindFirstChild("TestRunner")

local function checkScriptInjectionError(msg)
	if not msg:find("script injection") then
		error(msg, 3)
	end
end

local function isInstalled()
	return testRunnerScript and testRunnerScript.Parent
end
local UpdateTestRunnerScript
local function startupWhenInstalled()
	TestService.ExecuteWithStudioRun = true
	TestService.Timeout = 1e8
	UpdateTestRunnerScript = UpdateTestRunnerScript or require(modules.UpdateTestRunnerScript)
	xpcall(UpdateTestRunnerScript, checkScriptInjectionError) -- we remain silent unless it errors about something other than script injection
end
local function install()
	testRunnerScript = Instance.new("Script")
	testRunnerScript.Name = "TestRunner"
	testRunnerScript.Parent = TestService
	for _, c in ipairs(modules.UserDocumentation:GetChildren()) do
		c:Clone().Parent = testRunnerScript
	end
	startupWhenInstalled()
	print("TestRunner successfully installed! Click Install again to select and open the TestRunner script (includes documentation).")
end
local function onAlreadyInstalled()
	local signal = testRunnerScript:FindFirstChild("Running")
	if signal then
		signal:Destroy()
	end
	startupWhenInstalled()
end

local function reRunTests() -- overwritten later if tests are running
	print("Cannot run tests: TestRunner only runs in Run mode (no clients)")
end

local testSettings = require(modules.Settings.TestSettings).new(plugin)
local setupToolbar, setupRunningToolbar, guiCleanup do
	local pluginToolbar
	local function create(text, tooltip, action)
		local button = pluginToolbar:CreateButton(text, tooltip or "", "")
		button.ClickableWhenViewportHidden = true
		return button, action and button.Click:Connect(action)
	end
	local function createNoActive(text, tooltip, action)
		--	Create a button that does not stay active after being clicked
		local button, con
		local function action2()
			button:SetActive(false)
			if action then action() end
		end
		button, con = create(text, tooltip, action2)
		return button, con
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
	--[[
when NOT running:
	install (if needed)
	settings
when RUNNING (if installed):
	run
	settings
	]]
	local function setupMainToolbar()
		pluginToolbar = plugin:CreateToolbar("TestRunner")
	end
	local function setupInstallButton()
		createNoActive("Install", "Install TestRunner into this place", function()
			if isInstalled() then
				game.Selection:Set({testRunnerScript})
				plugin:OpenScript(testRunnerScript)
			else
				xpcall(install, function(msg)
					checkScriptInjectionError(msg)
					local alreadyDenied = not (msg:find("prompted") or not msg:find("grant"))
					print("--------------------------------")
					print("The Test Runner Plugin requires script injection permission to create TestService.TestRunner scripts.")
					if alreadyDenied then
						print("If you'd like automatic installation, you can grant this permission in the Plugin Manager.")
					else
						print("If you'd like automatic installation, you can click \"Allow\" on Roblox's popup.")
					end
					print("You can disable this permission after the installation is complete - you'll only miss out on automatic updates to the TestRunner script.")
					print("Alternatively, look up the manual installation instructions (this plugin is open source).")
					print()
					warn("***DENY ANY REQUEST FOR ACCESS TO THE INTERNET FROM THIS PLUGIN*** unless you are 100% sure that your test scripts are responsible!")
					print("This plugin does not use HttpService, but if it finds a potential test script that attempts to use it, you will see the request open up when you enter Run mode.")
					print("Granting this request could allow a malicious script to steal a copy of your place!")
					print("--------------------------------")
				end)
			end
			-- Note: we can't destroy the button or the toolbar
		end)
	end
	local function setupRunButton()
		createNoActive("Run", "Rerun all tests", function()
			reRunTests()
		end)
	end
	local function setupSettingsButton()
		settingsButton = create("Settings", "Customize Test Runner User Settings", toggleTestSettingsGui)
	end
	function setupToolbar()
		setupMainToolbar()
		if not isInstalled() then
			setupInstallButton()
		end
		setupSettingsButton()
	end
	function setupRunningToolbar()
		setupMainToolbar()
		setupRunButton()
		setupSettingsButton()
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
setupRunningToolbar()
-- We can now wait for TestRunner script to signal that it's running
--	since RunService doesn't tell us the difference between Run mode and Server mode [as of October 2020]
local signal = testRunnerScript:WaitForChild("Running", 60)
if not signal then return end

function reRunTests()
	-- Do nothing since tests will be loading momentarily
end

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
function reRunTests()
	testTree:RunAllTests()
end