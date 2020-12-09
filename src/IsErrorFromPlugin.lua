local pluginName = require(script.Parent.PluginConfig).PluginName
local s1 = "^\n?[^\n]*" .. pluginName .. "%."
local s2 = "^\n?[^\n]*" .. pluginName .. "%.Testing%.NewT" -- multitests error in this file and aren't the plugin's fault
local s3 = "^\n?[^\n]*" .. pluginName .. "%.Variant:%d+ function performRequire" -- require doesn't use pcall so stack looks like plugin's fault from PluginErrHandler's perspective
local function IsErrorFromPlugin(traceback)
	return traceback:find(s1)
		and not traceback:find(s2)
		and not traceback:find(s3)
end
return IsErrorFromPlugin