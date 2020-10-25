-- Track ongoing requires so that they can be waited for before starting a test run
local RequireTracker = {}
RequireTracker.__index = RequireTracker
function RequireTracker.new()
	return setmetatable({
		threads = {}, -- moduleScript -> latest coroutine to start requiring
		finished = Instance.new("BindableEvent"),
		any = Instance.new("BindableEvent"),
	}, RequireTracker)
end
function RequireTracker:remove(moduleScript)
	self.threads[moduleScript] = nil
	self.any:Fire(moduleScript)
	if not next(self.threads) then
		self.finished:Fire()
	end
end
function RequireTracker:Start(moduleScript)
	self.threads[moduleScript] = coroutine.running()
end
function RequireTracker:Finish(moduleScript, coroutineThatCalledStart)
	--	Must be called on same thread that called Start, or else provide it via 'coroutineThatCalledStart'
	if self.threads[moduleScript] == (coroutineThatCalledStart or coroutine.running()) then
		self:remove(moduleScript)
	end
end
function RequireTracker:RemoveModuleScript(moduleScript)
	--	ex, call this if the moduleScript is removed from the game
	if self.threads[moduleScript] then
		self:remove(moduleScript)
	end
end
function RequireTracker:Wait()
	--	Returns true if waited
	if next(self.threads) then
		self.finished.Event:Wait()
		return true
	end
end
function RequireTracker:WaitOnList(moduleScripts, cancelFunc)
	--	cancelFunc():true if should cancel the wait (only evaluated sometimes)
	--	Returns true if waited
	local threads = self.threads
	local waited = false
	while next(threads) do
		local found = false
		for _, obj in ipairs(moduleScripts) do
			if threads[obj] then
				found = true
				while self.any.Event:Wait() ~= obj do end
				waited = true
			end
		end
		if not found or cancelFunc() then break end
	end
	return waited
end
function RequireTracker:Destroy()
	self.any:Destroy()
	self.finished:Destroy()
end
return RequireTracker