return function(tests, t)

tests.EnsureSpawnPartNotRun = function()
	wait()
	t.falsy(workspace:FindFirstChild("Should not be seen"), "Disabled script run by Test Runner")
	t.falsy(workspace:FindFirstChild("Should not be seen2"), "Non-test ModuleScript run by TestRunner")
end

end