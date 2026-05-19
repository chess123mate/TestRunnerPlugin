local Count = {}
Count.__index = Count
function Count.new()
	return setmetatable({
		passed = 0,
		failed = 0,
		skipped = 0,
		errored = 0,
	}, Count)
end
function Count.For(list)
	return Count.new():Increase(list)
end
function Count:Increase(list)
	for _, obj in list do
		obj:UpdateCount(self)
	end
	return self
end
function Count:NumCompleted()
	return self.passed + self.failed
end
function Count:NumWentWrong()
	return self.failed + self.errored
end
function Count:NumAttempted()
	return self.passed + self.failed + self.errored
end
function Count:NumTotal()
	return self.passed + self.failed + self.skipped + self.errored
end
function Count:Clone()
	local nc = {}
	for k, v in self do
		nc[k] = v
	end
	return setmetatable(nc, Count)
end
function Count:Add(other) -- other:Count
	for k, v in other do
		self[k] += v
	end
end
return Count