local function ExploreServices(names, handleDescendant, gameOverride)
	--	returns connection cleanup function
	local game = gameOverride or game
	local cons = {}
	for i, name in ipairs(names) do
		local instance = game:GetService(name)
		cons[i] = instance.DescendantAdded:Connect(handleDescendant)
		for _, obj in ipairs(instance:GetDescendants()) do
			handleDescendant(obj)
		end
	end
	return function()
		for _, con in ipairs(cons) do
			con:Disconnect()
		end
	end
end
return ExploreServices