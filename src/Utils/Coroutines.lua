-- Multiple coroutine tracking - can be used to wait for multiple coroutines to complete
local stepped = game:GetService("RunService").Stepped
local Coroutines = {}
Coroutines.__index = Coroutines
function Coroutines.new(...)
	local self = setmetatable({}, Coroutines)
	self:Add(...)
	return self
end
function Coroutines:Add(...)
	for _, co in ipairs({...}) do
		if coroutine.status(co) ~= "dead" then
			self[co] = true
		end
	end
	return ...
end
function Coroutines:Remove(...)
	for _, co in ipairs({...}) do
		self[co] = nil
	end
end
function Coroutines:WaitForComplete(timeout)
	--	Yields until all coroutines are complete (dead), then returns true
	--	Returns false if timeout is reached before this happens
	timeout = timeout or math.huge
	local start = os.clock()
	while true do
		for co in pairs(self) do
			if coroutine.status(co) == "dead" then
				self[co] = nil
			end
		end
		if not next(self) then return true end
		if os.clock() - start >= timeout then return false end
		stepped:Wait()
	end
end
function Coroutines:OnCompleteCallbackThread(callback, ...)
	--	calls callback(unpack(args)) when all coroutines in this collection are complete (dead)
	--	returns a new coroutine if any coroutines are still alive; you can wait for it to die as an alternative to listening to the callback
	--	if all coroutines are already dead, returns nothing
	if not next(self) then
		if callback then
			callback(...)
		end
		return
	end
	local newCo = coroutine.create(function(...)
		self:WaitForComplete()
		if callback then
			callback(...)
		end
	end)
	assert(coroutine.resume(newCo, ...))
	return newCo
end
return Coroutines