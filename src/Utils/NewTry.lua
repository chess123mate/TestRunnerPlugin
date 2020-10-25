-- NewTry: try to run code (on a separate thread) with easy setup for what to do if it succeeds, fails, times out, etc.

local nothing = function() end
local function defaultErrorHandler(msg) return msg end
return function(setupTry, func, ...)
	--	setupTry:function(try)
	--	After setupTry returns, func(...) will be called on a separate thread.
	--	This function will return immediately
	--[[try has this api:
		onSuccess(f) -- f will be called with whatever 'func' returned, if it succeeds within any timeout specified
		onError(errHandler) -- will be called with the error msg; can use debug.traceback() (as it becomes the error handler in xpcall)
			-- Note: if the onError function errors, it will not be displayed anywhere!
		onTimeout(t, f) -- if 't' seconds go by, f() will be called
		onAsyncStartEnd(onStart, onEnd) -- onStart(co:coroutine) called if 'func' yields; onEnd(co:coroutine) called when the try completes/dies (before onSuccess/onTimeout trigger)
		finally(f) -- f() will be called after the try completes
			This will not run if any of the onSuccess/onTimeout/etc functions error or yield forever
	]]
	assert(type(func) == "function", "func must be the function to try")
	local self = {}
	local timeout
	local onSuccess, onTimeout, finally, onAsyncStart, onAsyncEnd = nothing, nothing, nothing, nothing, nothing
	local errorHandler = defaultErrorHandler
	function self:onSuccess(f) onSuccess = f return self end
	function self:onError(f) errorHandler = f return self end
	function self:onTimeout(t, f) timeout = t; onTimeout = f return self end
	function self:onAsyncStartEnd(onStart, onEnd) onAsyncStart = onStart or nothing; onAsyncEnd = onEnd or nothing return self end
	function self:finally(f) finally = f return self end
	setupTry(self)
	local co, async, completed -- completed becomes true if timed out or if completed naturally
	local function interpretResults(success, ...)
		if completed then return end
		completed = true
		if async then
			onAsyncEnd(co)
		end
		if success then
			onSuccess(...)
		end
		--(success and onSuccess or onFail)(...)
		finally()
	end
	-- Using coroutine.wrap allows Roblox to output errors if something goes wrong in user code
	coroutine.wrap(function(...)
		co = coroutine.running()
		interpretResults(xpcall(func, errorHandler, ...))
	end)(...)
	if coroutine.status(co) ~= "dead" then
		async = true
		coroutine.wrap(onAsyncStart)(co) -- guarantees the try returns immediately, as promised
		if timeout then
			delay(timeout, function()
				if completed then return end
				completed = true
				onAsyncEnd(co)
				onTimeout()
				finally()
			end)
		end
	end
end