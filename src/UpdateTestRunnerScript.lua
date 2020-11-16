local modules = script.Parent
local testRunnerScript = game:GetService("TestService").TestRunner
local function header(s)
	local line = string.rep("-", #s + 4)
	return ("%s\n--%s--\n%s"):format(line, s, line)
end
testRunnerScript.Source = table.concat({
	"--[[Note: changes to this file are overwritten\n",
	header("TestRunner Testing Framework"), [=[

Designed to allow rapid development and verification of tests.
- Automatically runs tests when you enter Run mode (ie with no clients)
	This prevents tests from damaging your game (ex by mutating the workspace).
- Tests are rerun when their dependencies (direct or indirect) have been changed
	If you use script syncing software (such as Rojo), this enables you to have your script changes tested within a second of hitting Ctrl+s!
- Uses the Output so that test output Designed to give you just the information you need to fix broken tests
- Though it is not best practice, the system supports asynchronous tests - all test cases are run at the same time.
	(Better practice is to use mocks so that you can simulate waits instead of having to wait in real time.)

Limitations:
- The testing system does not track created coroutines, so tests will not reflect errors that occur in them
- You can't click on error output to jump to a ModuleScript's source
- Error output will always have "TestService:" at the beginning of every line, unless it came from an untracked coroutine
	On the plus side, the error output and traceback is more concise and includes which test the error occurred in
- The final report will include the ms it took to run the tests. This will be inflated dramatically if there are a lot of errors (or a ton of output) printed out, or if tests yield for a while.
- Roblox allows you to require destroyed ModuleScripts, but this system assumes that you will not rely on this behaviour.

]=], header("Creating Tests"), [=[

To create a test script, create a ModuleScript as a descendant of TestService with the following return format:

local Module = require(game.ServerScriptService.MyModule) -- it is fine to put requires later on as well
return function(tests, t) -- 't' stands for 'testThat'. For valid functions for 't', look at the Available Assertions section below

-- (I don't indent for this outermost function wrapper but you're welcome to)

-- Assign your tests directly to the 'tests' dictionary
function tests.simpleTest()
	t.equals(Module.Add(1, 1), 2) -- Note that the expected value should come 2nd unless you modify that in the config
end

tests.complexTest = { -- Tests can be a table with the following fields (all optional except 'test'):
	setup = function(...) return Obj.new() end, -- if setup is defined, what it returns becomes the first argument to the test (this is called for each test case)
	--	The '...' are any test arguments
	cleanup = function(obj, ...) obj:Destroy() end, -- if setup and cleanup are defined, the created object can be cleaned up here
	--	Note: cleanup is not guaranteed to be run right away
	--	Note: cleanup is only valid if setup is defined
	test = function(obj, a, b) -- the test function
		-- do something with obj/a/b; check values with 't', ex:
		t.equals(a, b)
		-- Note that you can error at any time to cause a test case to fail.
	end,
	args = {argTest1, argTest2}, -- each item in this list is a "case" to test; the value will be sent as the only argument (other than what is passed in by setup, if anything)
	argsLists = {{argsList1}, {etc}}, -- each item in this list will be unpacked and then sent to the function
	-- You can use string keys to name cases (for args and argsLists):
	args = {argTest1, namedCase = arg2},
	-- If you're naming your test cases and order is important, you can add 'name' or 'Name' to any list in argsLists:
	argsLists = {{argsList1, name="case name1"}, {argsList2, name="case name2"}},
	skip = true, -- indicates to skip this test
	focus = true, -- indicates to only run this test in this module
}

-- Instead of specifying skip/focus throughout the test file, it is recommended to have that configured at the top:
tests.skip = {"test1", "test2", -- and/or:
	test1 = true,
	test2 = true,
}
-- same for tests.focus. Note that 'focus' takes precedence over 'skip'

function tests.multiDemo()
	-- If you want certain assertions to complete before any of them raise an error, use 'multi':
	t.multi("Optional Name/Desc", function(m)
		-- You can use any function that you can with 't', except all functions take in a name/desc as their first argument
		m.equals("this won't error until after the function is done", 1, 2)
		m.equals("basic equality", 1+1, 2)
		-- m.multi has the same arguments as t.multi and allows nesting them
	end)
	-- In the event of a problem, all assertions will be output, one per line - those that failed will have ">>>" in front of them
end

-- Instead of specifying setup and cleanup, if you just want to make sure something gets cleaned up, use t.cleanup:
function tests.autoCleanup()
	local obj = t.cleanup(Instance.new("Part"))
	t.equals(obj.Name, "Part")
	-- Now, even if this thread errors, 'obj' will be destroyed
	-- t.cleanup can take instances, functions, event connections, and tables that have either Destroy or Disconnect defined on them
	-- Note: If you have thousands of things to clean up in a single test case, it is more efficient to register a single cleanup function.
end

function tests.otherAPI() -- In your tests, you can also use:
	t.describe(arg) -- describes 'arg' in a handy fashion (ex puts quotes around strings, shortens tables, uses GetFullName on instances)
	t.actualNotExpectedCore(a, op, b) -- generates "actual ~= expected" but using 'a', 'op', and 'b'. Switches based on whether 'actual' is expected to be first/second.
	t.actualNotExpected(a, op, b, ...) -- same as the Core variant but appends '...' to the message
end

end -- ends "return function(tests, t)"

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
return true