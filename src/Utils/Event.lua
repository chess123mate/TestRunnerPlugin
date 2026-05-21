--------------------------------------------------------------------------------
--               Batched Yield-Safe Event Implementation                     --
-- This is a Event class which has effectively identical behavior to a       --
-- normal RBXScriptSignal, with the only difference being a couple extra      --
-- stack frames at the bottom of the stack trace when an error is thrown.     --
-- This implementation caches runner coroutines, so the ability to yield in   --
-- the signal handlers comes at minimal extra cost over a naive signal        --
-- implementation that either always or never spawns a thread.                --
--                                                                            --
-- API:                                                                       --
--   local Event = require(THIS MODULE)                                      --
--   local sig = Event.new()                                                 --
--   local connection = sig:Connect(function(arg1, arg2, ...) ... end)        --
--   sig:Fire(arg1, arg2, ...)                                                --
--   connection:Disconnect()                                                  --
--   sig:DisconnectAll()                                                      --
--   local arg1, arg2, ... = sig:Wait()                                       --
--                                                                            --
-- Licence:                                                                   --
--   Licenced under the MIT licence.                                          --
--                                                                            --
-- Authors:                                                                   --
--   stravant - July 31st, 2021 - Created the file.                           --
--   chess123mate - see Changes below
--
-- Changes:
--   Using pull request: https://github.com/stravant/goodsignal/pull/3
--   DisconnectAll -> Destroy
--   Allow a Connection to be disconnected 2+ times
--   Remove "strict" mode metatables that error on __index and __newindex
--   Private variable names '_' character removed
--   Added init/deinit arguments (and modified Wait to work with an init that calls Fire)
--   On destroy, if an event is mid-fire, the remaining handlers are cancelled
--   Added Once
--   Updated .Connected for all connections belonging to an event that has Clear called on it
--------------------------------------------------------------------------------

--!native

-- The currently idle thread to run the next handler on
local freeRunnerThread = nil

-- Function which acquires the currently idle handler runner thread, runs the
-- function fn on it, and then releases the thread, returning it to being the
-- currently idle one.
-- If there was a currently idle runner thread already, that's okay, that old
-- one will just get thrown and eventually GCed.
local function acquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	freeRunnerThread = acquiredRunnerThread
end

-- Coroutine runner that we create coroutines of. The coroutine can be
-- repeatedly resumed with functions to run followed by the argument to run
-- them with.
local function runEventHandlerInFreeThread()
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local Connection = {}
Connection.__index = Connection
function Connection.new(signal, fn)
	return setmetatable({
		Connected = true,
		signal = signal,
		fn = fn,
		next = false,
	}, Connection)
end

function Connection:Disconnect()
	if not self.Connected then return end
	self.Connected = false

	-- Unhook the node, but DON'T clear it. That way any fire calls that are
	-- currently sitting on this node will be able to iterate forwards off of
	-- it, but any subsequent fire calls will not hit it, and it will be GCed
	-- when no more fire calls are sitting on it.
	if self.signal.handlerListHead == self then
		if self.next then
			self.signal.handlerListHead = self.next
		else
			local signal = self.signal
			signal.handlerListHead = false
			if signal.deinit then
				if not freeRunnerThread then
					freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
					task.spawn(freeRunnerThread)
				end
				local value = signal.initReturn
				signal.initReturn = nil
				task.spawn(freeRunnerThread, signal.deinit, signal, value)
			end
		end
	else
		local prev = self.signal.handlerListHead
		while prev and prev.next ~= self do
			prev = prev.next
		end
		if prev then
			prev.next = self.next
		end
	end
end
Connection.Destroy = Connection.Disconnect

local Event = {}
Event.__index = Event

local function runInit(self)
	self.initReturn = self:init()
end

function Event.new(init, deinit)
	--	init (optional) : function(signal) -> initValue -- called whenever a connection is made when no connections existed
	--	deinit (optional) : function(signal, initValue) is called whenever no connections are left; initValue is whatever 'init' returned
	return setmetatable({
		handlerListHead = false,
		init = init,
		deinit = deinit,
	}, Event)
end

function Event:Connect(fn)
	local connection = Connection.new(self, fn)
	if self.handlerListHead then
		connection.next = self.handlerListHead
		self.handlerListHead = connection
	else
		self.handlerListHead = connection
		if self.init then
			if not freeRunnerThread then
				freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
				task.spawn(freeRunnerThread)
			end
			task.spawn(freeRunnerThread, runInit, self)
		end
	end
	return connection
end
function Event:ConnectCall(fn, ...)
	if not freeRunnerThread then
		freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
		task.spawn(freeRunnerThread)
	end
	task.spawn(freeRunnerThread, fn, ...)
	return self:Connect(fn)
end

-- Disconnect all handlers.
function Event:Destroy()
	local hadCons = self.handlerListHead
	self.handlerListHead = false
	if hadCons then
		repeat
			hadCons.Connected = false
			hadCons = hadCons.next
		until not hadCons
		if self.deinit then
			if not freeRunnerThread then
				freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
				task.spawn(freeRunnerThread)
			end
			local value = self.initReturn
			self.initReturn = nil
			task.spawn(freeRunnerThread, self.deinit, self, value)
		end
	end
end
Event.Clear = Event.Destroy -- function(self)

-- Event:Fire(...) implemented by running the handler functions on the
-- coRunnerThread, and any time the resulting thread yielded without returning
-- to us, that means that it yielded to the Roblox scheduler and has been taken
-- over by Roblox scheduling, meaning we have to make a new coroutine runner.
function Event:Fire(...)
	local item = self.handlerListHead
	while item do
		if item.Connected then
			if not freeRunnerThread then
				freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
				task.spawn(freeRunnerThread)
			end
			task.spawn(freeRunnerThread, item.fn, ...)
			if not self.handlerListHead then break end -- Support :Destroy() mid-Fire
		end
		item = item.next
	end
end
function Event:HasConnections()
	return self.handlerListHead ~= false
end

function Event:Wait()
	local waitingCoroutine
	local con
	local immediate
	con = self:Once(function(...)
		if con then
			task.spawn(waitingCoroutine, ...)
		else -- the act of Connecting caused the event to fire (via a signal's init function)
			immediate = {...}
		end
	end)
	if immediate then
		return unpack(immediate)
	else
		waitingCoroutine = coroutine.running()
		return coroutine.yield()
	end
end

function Event:Once(fn)
	local con; con = self:Connect(function(...)
		con:Disconnect()
		fn(...)
	end)
	return con
end

Event.Event = Event -- typescript support
Event.newEventTuple = Event.new -- typescript support
return Event