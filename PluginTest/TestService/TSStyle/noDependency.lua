local TS = require(script.Parent.TS)
return function(tests, t)

function tests.noDependency()
	t.falsy(script:GetAttribute("run"), "This test should only run once, even when changing files imported through TS (ignore this test if not testing for TS dependency - see IsTSScript)")
	script:SetAttribute("run", true)
end

end