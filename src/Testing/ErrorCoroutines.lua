-- ErrorCoroutines keeps track of coroutines that are currently expecting errors. Modules that error during requires should do so silently. This set must be cleared at the end of tests.
local errorCoroutines = {}
return {
	pcallError = function(...)
		local co = coroutine.running()
		errorCoroutines[co] = true
		local function handleReturn(...)
			errorCoroutines[co] = nil
			return ...
		end
		return handleReturn(pcall(...))
	end,
	shouldIgnoreErrors = function(co)
		return errorCoroutines[co or coroutine.running()]
	end,
	clear = function()
		table.clear(errorCoroutines)
	end,
}