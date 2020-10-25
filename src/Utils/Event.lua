-- from Event.lua's Event.NoNil
local function Event()
	--	Supports complex table arguments and recursively triggering the event, but doesn't support nil arguments
	local self = {}
	local fireNumber = 0
	local args = {} -- Dict<fireNumber, argTable>
	local e = Instance.new("BindableEvent")
	local e_Event = e.Event
	function self:Connect(func)
		if type(func) ~= "function" then error("'func' must be a function; received " .. tostring(func)) end
		return e_Event:Connect(function(fireNumber)
			func(unpack(args[fireNumber]))
		end)
	end
	function self:Fire(...)
		fireNumber = fireNumber + 1
		local n = fireNumber
		args[n] = {...}
		e:Fire(n)
		args[n] = nil
	end
	function self:Wait()
		local n = e_Event:Wait()
		return unpack(args[n])
	end
	function self:Destroy()
		e:Destroy() -- Note: BindableEvent stops any in-progress event:Fire()s on Destroy
		args = nil
	end
	return self
end
return Event