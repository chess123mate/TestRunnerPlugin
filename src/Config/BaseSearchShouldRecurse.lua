return function(instance, ignoreOtherModulesToo)
	return (instance.Name ~= "TestRunner" or instance.Parent.ClassName ~= "TestService")
		and (not ignoreOtherModulesToo or ((instance.Name ~= "PlayerModule" and instance.Name ~= "ChatScript") or instance.Parent.ClassName ~= "StarterPlayerScripts"))
end