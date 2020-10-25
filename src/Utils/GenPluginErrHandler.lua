-- GenPluginErrHandler - for simulating Roblox errors (but more concisely) while keeping plugin lines out of the traceback as appropriate
local TestService = game:GetService("TestService")
local function startTransform(traceback)
	--	will add an initial newline for easy searching
	return ("\n" .. traceback)
		:gsub("\nScript '(.*-)', Line (%d+)", "\n%1:%2") -- a bit more concise
		:gsub("\nTestService%.", "\n") -- The line will always start with TestService anyway
		--	The error msg line may not in the report, but I think this is okay
end
local function keepPluginLines(traceback)
	return startTransform(traceback)
		:gsub("\n[^\n]*(TestRunnerPlugin%.)", "\n%1") -- get rid of "cloud_" prefix (starting on new line only)
		:gsub("^\n+", "") -- get rid of all initial newlines
		:gsub("\n+$", "") -- and all ending newlines
end
local function removePluginLines(traceback)
	return startTransform(traceback)
		:gsub("\n[^\n]*TestRunnerPlugin%.[^\n]+", "\n")
		:gsub("^\n+", "") -- get rid of all initial newlines
		--	This also means that we don't show '...' for TestRunnerPlugin code (ex comparisons)
		:gsub("\n+$", "") -- prevent showing '...' at the end
		:gsub("\n\n+", "\n...\n") -- 2+ newlines only occurs when removing plugin lines, so replace with '...'
end

local function GenPluginErrHandler(onError, intro, hideOneLiner, hideAll)
	--	onError(niceErrMsg, msg, traceback, originalErrMsg) -- optional
	--		msg is what was actually output (except for 'intro')
	--		niceErrMsg is rearranged so that the problem shows up first, then the path & line number
	--		traceback is what was shown to the user (can be the empty string)
	--	intro (optional) is the initial text for any error message emitted to the Output window
	--	hideOneLiner: if true and there is no traceback, the error is not printed
	return function(origMsg)
		local traceback = debug.traceback("", 2) -- no message, depth 2 to ignore this error handler
		local msg = keepPluginLines(tostring(origMsg))
		-- User code can make the 'msg' refer to the plugin by setting the error depth high enough,
		--	so don't trust 'msg' for determining if the error came from this plugin
		local errorFromPlugin = traceback:find("^[^\n]*TestRunnerPlugin%.")
		if errorFromPlugin then
			traceback = keepPluginLines(traceback)
		else
			traceback = removePluginLines(traceback)
		end
		local niceErr do
			local path, line, txt = msg:match("^(.-):(%d+): (.*)$")
			niceErr = path and ("%s - %s:%s"):format(txt, path, line) or msg
			-- The previous match would get incorrect results if someone
			--	named their script something like ":123: "
		end
		if not hideAll and (not hideOneLiner or traceback:find("\n") or not msg:find(traceback)) then
			if intro then
				TestService:Error(tostring(intro) .. msg)
			else
				TestService:Error(msg)
			end
			local first = true
			for line in string.gmatch(traceback, "[^\n]+") do
				if first then -- don't show the error message as the first line in the traceback
					first = false
					if msg:find(line) then
						continue
					end
				end
				TestService:Message(line)
			end
		end
		if onError then onError(niceErr, msg, traceback, origMsg) end
	end
end
return GenPluginErrHandler