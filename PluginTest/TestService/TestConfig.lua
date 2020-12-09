return {
	-- GetSearchArea = function(commonServiceNames) return commonServiceNames end,
	-- SearchShouldRecurse = function(instance, base)
	-- 	return base(instance) and not instance.Name:find("TestRunnerPlugin")
	-- end,
	-- MayBeTest = function() return true end,
	-- GetSetupFunc = function(moduleScript, requireValue)
	-- 	return type(requireValue) == "function" and requireValue
	-- end,
	-- requireTimeout = 0,
	-- initTimeout = 0,
	timeout = 0.01,
	--focus = {"ModuleScript"}
}