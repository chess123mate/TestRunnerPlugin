local function ExploreServices(names, handleDescendant, gameOverride)
	--	handleDescendant(obj):true if should recurse
	--	returns connection cleanup function
	local game = gameOverride or game
	local cleanups = {}
	local function explore(obj)
		if handleDescendant(obj) then
			for _, c in obj:GetChildren() do
				explore(c)
			end
			local cons
			local function cleanup()
				for _, con in cons do
					con:Disconnect()
				end
				cleanups[cleanup] = nil
			end
			cons = {
				obj.ChildAdded:Connect(explore),
				obj.AncestryChanged:Connect(function(child, parent)
					if not parent then
						cleanup()
					end
				end),
			}
			cleanups[cleanup] = true
		end
	end
	for i, name in names do
		explore(game:GetService(name))
	end
	return function()
		for cleanup in cleanups do
			cleanup()
		end
	end
end
return ExploreServices