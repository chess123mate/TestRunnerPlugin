return {function() -- wrap the function in a table to avoid detection by the TestRunnerPlugin
local modules = game.ServerStorage.TestRunnerPlugin
local NewTry = require(modules.Utils.NewTry)
local progress = "startup"
spawn(function()
	wait(); wait()
	if not progress then
		print("NewTry tests successful")
	elseif progress ~= -1 then
		error("NewTry tests got stuck at progress " .. tostring(progress))
	end
end)
local function assertEquals(name, a, b)
	if a ~= b then
		progress = -1
		error(("%s: %s ~= %s"):format(name, tostring(a), tostring(b)), 2)
	end
end
local function assertTableEquals(name, a, b)
	if a ~= b then
		for k, v in pairs(a) do
			if b[k] ~= v then
				progress = -1
				error(("%s: key '%s': %s ~= %s"):format(name, tostring(k), tostring(v), tostring(b[k])), 2)
			end
		end
		for k, v in pairs(b) do
			if a[k] ~= v then
				progress = -1
				error(("%s: key '%s': %s ~= %s"):format(name, tostring(k), tostring(a[k]), tostring(v)), 2)
			end
		end
	end
end
progress = 1
--[[try has this api:
	onSuccess(f) -- f will be called with whatever 'func' returned, if it succeeds within any timeout specified
	onError(f) -- will be called with the error msg; can use debug.traceback() since 'f' becomes the error handler in xpcall
	onTimeout(t, f) -- if 't' seconds go by, f() will be called
	onAsyncStartEnd(onStart, onEnd) -- onStart(co:coroutine) called if 'func' yields; onEnd(co:coroutine) called when the try completes/dies (before onSuccess/onTimeout trigger)
	finally(f) -- f() will be called after the try completes
		This will not run if any of the onSuccess/onTimeout/etc functions error or yield forever
]]

local function return1() return 1 end

local function no(try, ...)
	for _, name in ipairs({...}) do
		(try["on" .. name] or error("no try function on" .. name))(try, function() error("on" .. name .. " does not get called") end)
	end
	return try
end

local onSuccessCalled
NewTry(function(try)
	no(try, "Error", "AsyncStartEnd")
		:onSuccess(function(a, b)
			onSuccessCalled = true
			assertEquals("onSuccess returns what the function returns", a, 1)
			assertEquals("onSuccess does not return more args", b, nil)
		end)
		:finally(function()
			assertEquals("finally called after onSuccess", onSuccessCalled, true)
		end)
end, function() return 1 end)

local onErrorCalled
NewTry(function(try)
	no(try, "Success", "AsyncStartEnd")
		:onError(function(msg)
			onErrorCalled = true
			if not msg:find("HI") then
				progress = -1
				print("onError did not receive error. msg:", msg)
			end
		end)
		:finally(function()
			assertEquals("finally called after onError", onErrorCalled, true)
		end)
end, function() error("HI") end)
assertEquals("onErrorCalled immediately", onErrorCalled, true)

local test2
local p = 1
local function r(n, msg)
	assertEquals(msg, p, n)
	p += 1
	if p == 7 and progress ~= -1 then
		progress = 2
		test2()
	end
end
NewTry(function(try)
	no(try, "Error")
		:onAsyncStartEnd(function() r(1, "NewTry must call onAsyncStart") end, function() r(4, "onAsyncEnd called next") end)
		:onSuccess(function(a)
			r(5, "onSuccess after onAsyncEnd")
			assertEquals("onSuccess returns what the function returns", a, 1)
		end)
		:finally(function()
			r(6, "finally after onSuccess")
			assertEquals("finally called after onSuccess", onSuccessCalled, true)
		end)
end, function() wait() r(3, "NewTry must return without yielding") return 1 end)
r(2, "NewTry must return after onAsyncStart")

function test2()
	local hitTimeout
	NewTry(function(try)
		no(try, "Error", "Success")
			:onTimeout(0.001, function()
				hitTimeout = true
			end)
			:finally(function()
				assertEquals("hit timeout before finally", hitTimeout, true)
				progress = nil
			end)
	end, wait, 1)
end
end}