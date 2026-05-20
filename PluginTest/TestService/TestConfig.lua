local ignore = {
	NotATest = true,
	SomeScript = true,
	ReturnNothing = true,
}
return {
	-- GetSearchArea = function(commonServiceNames) return commonServiceNames end, -- Top level config only
	-- SearchShouldRecurse = function(instance, base)
	-- 	return base(instance) and not instance.Name:find("TestRunnerPlugin")
	-- end,
	-- MayBeTest = function(moduleScript) return true end,
	-- MayBeTest = function(moduleScript) -- only for debugging
	-- 	return not ignore[moduleScript.Name]
	-- end,
	-- GetSetupFunc = function(moduleScript, requireValue)
	-- 	return type(requireValue) == "function" and requireValue
	-- end,
	-- requireTimeout = 0,
	-- initTimeout = 0,
	timeout = 0.01,
	-- focus = {"ModuleScript"}
}