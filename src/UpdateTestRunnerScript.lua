local modules = script.Parent
local testRunnerScript = game:GetService("TestService").TestRunner
local function header(s)
	local line = string.rep("-", #s + 6)
	return ("%s\n-- %s --\n%s"):format(line, s, line)
end
local source = table.concat({
	"--[[",
	header("TestRunner Testing Framework"), [=[	Note: changes to this file are overwritten

Designed to allow rapid development and verification of tests:
- Automatically runs tests when you enter Run mode (ie with no clients)
	This prevents tests from damaging your game (ex by mutating the workspace).
- Tests are rerun when their dependencies (direct or indirect) have been changed
	If you use script syncing software (such as Rojo), this enables you to have your script changes tested within a second of hitting Ctrl+s!
- Prints reports to the Output Window; designed to give you just the information you need to fix broken tests
- The system supports asynchronous tests - all test cases are run at the same time.
	(Note that better practice is to use mocks so that you can simulate waits instead of having to wait in real time.)

Limitations:
- The testing system does not track created coroutines, so tests will not reflect errors that occur in them
- You can't click on error output to jump to a ModuleScript's source
- Error output will always have "TestService:" at the beginning of every line, unless it came from an untracked coroutine
	On the plus side, the error output and traceback is more concise and includes which test the error occurred in
- The final report will include the ms it took to run the tests. This will be inflated dramatically if there are a lot of errors (or a ton of output) printed out, or if tests yield for a while.
- Roblox allows you to require destroyed ModuleScripts, but this system assumes that you will not rely on this behaviour.

]=], header("Roblox Plugin Permissions"), [=[

Script Injection Permission:
	TestRunner only needs this permission for installation and automatic updating of the TestRunner script in TestService.
	If you follow the manual installation steps, you can deny this permission without affecting the operation of this plugin, except that the TestRunner script will not be automatically updated.
	Manual installation steps:
		1. Set TestService.ExecuteWithStudioRun to true
		2. Place a copy of this Script directly under TestService

Internet Access Permission:
	***DENY ANY REQUEST FOR INTERNET ACCESS PERMISSIONS FROM THIS PLUGIN*** unless you are 100% sure that one of your test scripts is responsible!

	TestRunner does not use this permission, but any script in your place that is considered a potential test script (based on your configuration) will be executed while in Run mode.
	If such a script attempts to send a web request, you will see a permission request for HttpService from the Test Runner Plugin!
	If you happen to have a malicious script in your place (in any location that tests are scanned for), they could use this permission to steal a copy of your place!

]=], header("Creating Tests"), [=[

To create a test script, create a ModuleScript as a descendant of TestService (this can be configured in TestConfig, see below) - just not as a descendant of this TestRunner script.
Any ModuleScript that returns a function is considered a test script (though this can also be configured).

See the ExampleTests ModuleScript (a child of this TestRunner script) for documentation while going over an example.
You can move it directly into TestService to experiment with it.

]=],
	require(modules.Config.Config).GetDocs(header),
	"\n", -- will be two spaces (for between sections)
	require(modules.Testing.Comparisons).GetDocs(header),
	"\n",
	header("Uninstallation"), [=[

Simply delete/rename the TestRunner script in TestService.

]]

if script.Disabled then return end
-- Tell plugin that this is Test mode so it can run
local running = Instance.new("Folder")
running.Name = "Running"
running.Archivable = false
running.Parent = script]=],
}, "\n")

return function()
	testRunnerScript.Source = source
end