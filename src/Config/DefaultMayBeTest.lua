return function(moduleScript)
	return (moduleScript.Name ~= "PlayerModule" and moduleScript.Name ~= "ChatScript") or moduleScript.Parent.ClassName ~= "StarterPlayerScripts"
end