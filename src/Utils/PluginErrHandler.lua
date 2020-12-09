-- PluginErrHandler - for simulating Roblox errors (but more concisely) while keeping plugin lines out of the traceback as appropriate
local TestService = game:GetService("TestService")
local PluginErrHandler = {}
local function startTransform(traceback)
	--	will add an initial newline for easy searching
	return ("\n" .. traceback)
		:gsub("\nScript '(.*-)', Line (%d+)", "\n%1:%2") -- a bit more concise
		:gsub("\nTestService%.", "\n") -- The line will always start with TestService anyway
		:gsub("\nStarterPlayer%.StarterPlayerScripts%.", "\nStarterPlayerScripts.")
		:gsub("\nStarterPlayer%.StarterCharacterScripts%.", "\nStarterCharacterScripts.")
		--	The error msg line may not be in the report, but I think this is okay
end
local function genKeepPluginLines(pluginName)
	local s = "\n[^\n]*(" .. pluginName .. "%.)"
	return function(traceback)
		return startTransform(traceback)
			:gsub(s, "\n%1") -- get rid of "cloud_" prefix (starting on new line only)
			:gsub("^\n+", "") -- get rid of all initial newlines
			:gsub("\n+$", "") -- and all ending newlines
	end
end
local function genRemovePluginLines(pluginName)
	local s = "\n[^\n]*" .. pluginName .. "%.[^\n]+"
	return function(traceback)
		return startTransform(traceback)
			:gsub(s, "\n")
			:gsub("^\n+", "") -- get rid of all initial newlines
			:gsub("\n+$", "") -- and all ending newlines
			:gsub("\n+", "\n") -- remove consecutive newlines (occurs when removing plugin lines)
	end
end
function PluginErrHandler.GenContinueUserErrorAddTraceback(pluginName)
	local removePluginLines = genRemovePluginLines(pluginName)
	return function(traceback)
		for line in string.gmatch(removePluginLines(traceback), "[^\n]+") do
			TestService:Message(line)
		end
	end
end
PluginErrHandler.GenClean = genRemovePluginLines
local function getScriptAndLineNum(line)
	return line:match("%w+:%d+%f[%D]")
end
function PluginErrHandler.GenIsErrorFromPlugin(pluginName)
	local s = "^\n?[^\n]*" .. pluginName .. "%."
	return function(traceback)
		return traceback:find(s)
	end
end

function PluginErrHandler.Gen(pluginName, onError, intro, hideOneLiner, hideAll, depth, isErrorFromPlugin)
	--	onError(niceErrMsg, msg, traceback) -- optional
	--		msg is what was actually output (except for 'intro')
	--		niceErrMsg is rearranged so that the problem shows up first, then the path & line number
	--		traceback is roughly what was shown to the user (can be the empty string)
	--	intro (optional) is the initial text for any error message emitted to the Output window
	--	hideOneLiner: if true and there is no traceback, the error is not printed
	--	isErrorFromPlugin(traceback):bool (optional) - if it returns true, plugin related traceback lines will not be removed
	isErrorFromPlugin = isErrorFromPlugin or PluginErrHandler.GenIsErrorFromPlugin(pluginName)
	local keepPluginLines = genKeepPluginLines(pluginName)
	local removePluginLines = genRemovePluginLines(pluginName)
	return function(origMsg, notPluginsFault)
		--	notPluginsFault guarantees that plugin related traceback lines will be removed
		local traceback = debug.traceback("", depth or 2) -- no message, depth 2 to ignore this error handler
		local msg = keepPluginLines(tostring(origMsg))
		-- User code can make the 'msg' refer to the plugin by setting the error depth high enough,
		--	so don't trust 'msg' for determining if the error came from this plugin
		local errorFromPlugin = not notPluginsFault and isErrorFromPlugin(traceback)
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
		if not hideAll and (not hideOneLiner or traceback:find("\n") or getScriptAndLineNum(msg) ~= getScriptAndLineNum(traceback)) then
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
return PluginErrHandler