local Testing = script.Parent
local modules = Testing.Parent
local Comparisons = require(Testing.Comparisons)
local Results = require(modules.Results)
local Descriptions = require(modules.Descriptions)
local Describe, GetModuleName = Descriptions.Describe, Descriptions.GetModuleName
local function newT(testSettings, expectedFirst, moduleScript)
	local t, genComparisonHandler
	local comparisons = Comparisons.GetComparisons(expectedFirst)
	local function genComparisonHandler(comparison) -- defined local above. Expected to error.
		return function(...)
			local msg = comparison(...)
			if msg then
				error(msg, 2)
			end
		end
	end
	local tKeys = {}
	function tKeys.multi(name, func) -- multiValueTest; name optional
		if not func and type(name) == "function" then
			func = name
			name = nil
		end
		if type(func) ~= "function" then error("t.multi requires a function argument", 2) end
		local self = {}
		local list = {} -- list of tests descriptions/output
		local anythingFailed = false
		local header = name and ("Multitest '%s' failed"):format(name) or "Multitest failed"
		local function addToResults(desc, key, func, ...)
			local result = func(...)
			local args = {...}
			for i = 1, select("#", ...) do args[i] = Describe(args[i]) end
			-- Since the whole point of multi is that you want to test multiple things at once,
			--	we make sure to let the user see all the values they've input into the multi, whether it passed or failed
			--	ex use case: if you wanted to do an equality check on X, Y, and Z of a Vector3 using 3 different t.equals comparisons.
			--	(You don't need a multi for Vector3, but custom user objects might need it.)
			if result then
				anythingFailed = true
				list[#list + 1] = (">>> %s%s(%s) <<<    %s"):format(desc, key and (": %s"):format(key) or "", table.concat(args, ", "), result)
			else
				-- This many spaces roughly lines up with after ">>> " in both error text and report text
				list[#list + 1] = ("        %s%s(%s)"):format(desc, key and (": %s"):format(key) or "", table.concat(args, ", "))
			end
		end
		function self.test(desc, func, ...) -- func returns string describing problem or nil; ... are args to send to func
			t.type(desc, "string", "desc")
			t.type(func, "function", "func")
			return addToResults(desc, nil, func, ...)
		end
		function self._fail(msg)
			anythingFailed = true
			list[#list + 1] = ">>> " .. msg
		end
		function self.finish()
			local msg = self.report()
			if msg then
				error(msg)
			end
		end
		function self.report() -- won't error; safe for nested multi-testing
			return anythingFailed and ("%s:\n\t%s\t\t"):format(header, table.concat(list, "\n\t"))
		end
		setmetatable(self, {
			__index = function(self, key)
				local k = tKeys[key]
				if k then return k end
				local c = comparisons[key]
				if not c then return end
				return function(desc, ...)
					if type(desc) ~= "string" then
						error("Multitests must be named", 2)
					elseif select("#", ...) < (Comparisons.MinArgs[key] or Comparisons.MinArgsDefault) then
						--print(key, ":", select("#", ...), Comparisons.MinArgs[key] or Comparisons.MinArgsDefault, "|", ...)
						error(("Insufficient args to multitest.%s. (Multitest assertions must be named - did you miss the first argument?)"):format(key), 2)
					end
					addToResults(desc, key, c, ...)
				end
			end,
			__newindex = function() error("Cannot assign to a multi object", 2) end,
		})
		func(self)
		self.finish()
	end
	local genCleanup = {
		Instance = function(obj) return function() obj:Destroy() end end,
		RBXScriptConnection = function(obj) return function() obj:Disconnect() end end,
		["function"] = function(obj) return obj end,
		table = function(obj)
			return obj.Destroy and function() obj:Destroy() end
				or obj.Disconnect and function() obj:Disconnect() end
				or error("Cannot cleanup a table without .Destroy or .Disconnect", 3)
		end,
	}
	local miscCleanups = {}
	function tKeys.cleanup(obj)
		--	Automatically clean up 'obj' and return it
		--	'obj' can be an Instance, event connection, cleanup function, or table with .Destroy or .Disconnect defined on it
		--	All cleanup functions are expected to run without yielding
		--	If a cleanup function errors, note that this will not be reflected on the test
		--	Performance: if you have hundreds or thousands of objects to clean up, try to group them up into a single cleanup call
		local gen = genCleanup[typeof(obj)] or error("Cannot cleanup obj: " .. tostring(obj))
		miscCleanups[gen(obj)] = debug.traceback("", 2)
		return obj
	end
	local moduleName = GetModuleName(moduleScript)
	local function runMiscCleanups()
		local problems = 0
		for cleanup, traceback in pairs(miscCleanups) do
			local co = coroutine.create(function()
				cleanup()
				miscCleanups[cleanup] = nil
			end)
			local success, msg = coroutine.resume(co)
			if not success then
				print(moduleName, "cleanup failed:", msg, "| registered at:", traceback)
				miscCleanups[cleanup] = nil
				problems += 1
			end
		end
		for cleanup, traceback in pairs(miscCleanups) do
			print("Cleanup failed to complete immediately | registered at:", traceback:match(".*%S"))
			problems += 1
		end
		return problems > 0 and problems or nil
	end
	local cache = {}
	t = setmetatable({}, {
		__index = function(t, key)
			local v = tKeys[key] or cache[key]
			if v then return v end
			local c = comparisons[key]
			if c then
				v = genComparisonHandler(c)
				cache[key] = v
				return v
			end
		end
	})
	return t, runMiscCleanups
end
return newT