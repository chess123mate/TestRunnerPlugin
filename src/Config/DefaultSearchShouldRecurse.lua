return function(instance, baseShouldRecurse)
	return (instance.Name ~= "TestRunner" or instance.Parent.ClassName ~= "TestService") -- baseShouldRecurse only checks for this unless you pass it 'true', ex baseShouldRecurse(instance, true)
		and ((instance.Name ~= "PlayerModule" and instance.Name ~= "ChatScript") or instance.Parent.ClassName ~= "StarterPlayerScripts")
end