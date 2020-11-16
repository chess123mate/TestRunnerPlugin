return function(moduleScript, requiredValue)
	return type(requiredValue) == "function" and requiredValue
end