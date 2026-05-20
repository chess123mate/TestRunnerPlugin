local function ExploreServices(names, handleDescendant, gameOverride)
	--	handleDescendant(obj):true if should recurse
	--	returns connectionCleanupFunction, plausibleTests (set of Instances that could be tests -- note that this set may increase over time)
	local game = gameOverride or game
	local cleanups = {}
	local plausibleTests = {} -- set of objs that might be a test script
	local function explore(obj)
		plausibleTests[obj] = true
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
				plausibleTests[obj] = nil
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
	end, plausibleTests
end
return ExploreServices