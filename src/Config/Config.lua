local EnsureDictionary = require(script.Parent.Parent.Utils.EnsureDictionary)

local Config = {}
-- __index defined below
function Config.new(config)
	return setmetatable(config or {}, Config)
end

local ConfigType = {}
ConfigType.__index = ConfigType
function ConfigType.new(valueType, desc)
	return setmetatable({
		Validate = function(value)
			--	Returns success, msg or value
			--		msg is a format string that can receive the name of the thing this is validating
			if not value or typeof(value) == valueType then
				return true, value
			else
				return false, ("'%%s' must be a %s or nil"):format(desc or valueType)
			end
		end,
	}, ConfigType)
end
function ConfigType.ValueToString(value)
	return tostring(value)
end
local List = ConfigType.new("table", "list")
local base = List.Validate
function List.Validate(value)
	if type(value) == "string" then return true, {[value] = true} end
	local goodSoFar, value = base(value)
	if not goodSoFar then return goodSoFar, value end
	return true, EnsureDictionary(value)
end
function List.ValueToString(value)
	if value and #value > 0 then error("Not supported") end
	return "{}"
end
local Number = ConfigType.new("number")
local Bool = ConfigType.new("boolean")
local function new(name, configType, default, doc)
	return {
		Name = name,
		Type = configType,
		Default = default,
		Doc = doc,
	}
end
local function Function(defaultFunc, defaultToString)
	local Function = ConfigType.new("function")
	function Function.ValueToString(value)
		return value == defaultFunc and defaultToString or error("Not supported")
	end
	return Function
end
local function newFunc(name, doc)
	local module = script.Parent["Default" .. name]
	local default = require(module)
	return {
		Name = name,
		Type = Function(default, module.Source:sub(8)), -- :sub(8) skips "return "
		Default = default,
		Doc = doc,
	}
end

local commonServiceNames = {
	"Workspace",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"TestService",
}
local defaultListenServiceNames = {
	"TestService",
}
local GetSearchArea = newFunc("GetSearchArea", "(For TestService.TestConfig only) If provided, must return the list of service names to search through for tests. It is provided as argument a list of the service names that scripts are usually stored in.")
local base = GetSearchArea.Type.Validate
function GetSearchArea.Type.Validate(value)
	local success, problem = base(value)
	if not success then return problem end
	local problem = Config.ProblemsWithUserSearchArea(value(commonServiceNames))
	if problem then
		return false, "GetSearchArea(): " .. problem
	end
	return true, value
end
local configOptions = {
	new("requireTimeout", Number, 0.5, "A module times out if it hasn't returned from its require after this many seconds"),
			--"Seconds for a test module to return from its initial require before timing out"),
	new("initTimeout", Number, 0.5, "A module times out if it hasn't returned from its tests setup after this many seconds"),
			--"Seconds for a test module to register all its tests before timing out"),
	new("timeout", Number, 2, "Seconds for a test to complete before timing out"),
	new("skip", List, nil, "The list of test module names to skip over. You can specify the module path (up to but *not* including TestService) as well."),
	new("focus", List, nil, "If any test module names (or paths) are in this list, only they are run, regardless of what Skip contains."),
	GetSearchArea,
	newFunc("SearchShouldRecurse", "(For TestService.TestConfig only) If provided, must return the list of service names to search through for tests. It is provided as argument a list of the service names that scripts are usually stored in."),
	newFunc("MayBeTest", "(For TestService.TestConfig only) Given a module script, return true if it could be a test script. Use this to filter scripts based on their name."),
	newFunc("GetSetupFunc", "(For TestService.TestConfig only) Given a module script and its required value, return either the setup function or a falsy value if it is not a test.")
}
local default = {}
for _, o in ipairs(configOptions) do
	default[o.Name] = o.Default
end
Config.__index = function(self, key)
	local v = Config[key] or default[key]
	if v == nil then error(("'%s' is not a valid config option"):format(tostring(key)), 2) end
	return v
end
Config.Default = default
Config.IsDefault = function(config, key)
	return config[key] == default[key]
end
-- local runAllList = {"requireTimeout", "initTimeout", "timeout"}
-- function Config.OnConfigChange(testConfig, old, new, testConfigTree, actions)
--	-- (In future, *could* go through runAllList, then analyze skip/focus to help determine what to rerun)
-- 	for _, name in ipairs(runAllList) do
--		local option = 
-- 		if old[option.Name] ~= new[option.Name] then
-- 	end
--	-- etc
-- end

function Config.GetSearchAreaFromModule(moduleScript)
	--	moduleScript can be nil
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local success, config = pcall(require, moduleScript:Clone())
		if success then
			return Config.GetSearchArea(config, moduleScript)
		else
			warn(moduleScript:GetFullName(), "errored with:", config)
		end
	end
	return defaultListenServiceNames
end
function Config.GetSearchArea(config, moduleScript)
	--	moduleScript: for warning purposes. Provide nil to silence the warning.
	if type(config) ~= "table" then
		if moduleScript then warn(moduleScript:GetFullName(), "did not return a config table") end
	else
		local func = config.GetSearchArea
		if type(func) ~= "function" then
			if func ~= nil and moduleScript then warn(moduleScript:GetFullName() .. ".GetSearchArea is not a function") end
		else
			local success, value = pcall(config.GetSearchArea, commonServiceNames)
			if success then
				local problem = Config.ProblemsWithUserSearchArea(value)
				if problem then
					if moduleScript then warn(moduleScript:GetFullName() .. ".GetSearchArea(commonServiceNames) returned '" .. tostring(value) .. "', but", problem) end
				else
					return value
				end
			else
				if moduleScript then warn(moduleScript:GetFullName() .. ".GetSearchArea(commonServiceNames) failed:", value) end
			end
		end
	end
	return defaultListenServiceNames
end
function Config.ProblemsWithUserSearchArea(searchArea)
	--	Returns a problem string if there's something wrong, else nil
	if type(searchArea) ~= "table" then
		return "it must return a table"
	elseif #searchArea == 0 then
		return "it is empty"
	else
		for i, v in ipairs(searchArea) do
			if type(v) ~= "string" then
				return ("[%d] = %s instead of a string"):format(i, v)
			end
			if not pcall(game.GetService, game, v) then
				return v .. " is not a valid service"
			end
		end
	end
end

function Config.GetDocs(header)
	--	Get the documentation for the configuration options
	--	The returned value is a string containing a Lua table
	local configDocs = {
		header("Configuration"), [=[

You can configure this system using a TestConfig ModuleScript (its parent should be TestService).
It must return a table with any of the following fields (all optional; the values below are the defaults):

return {]=]
	}
	for _, details in ipairs(configOptions) do
		local name, Type, default, doc = details.Name, details.Type, details.Default, details.Doc
		configDocs[#configDocs + 1] = ("\t%s = %s,%s"):format(name, Type.ValueToString(default), doc and (" -- %s"):format(doc) or "")
	end
	configDocs[#configDocs + 1] = "}"
	return table.concat(configDocs, "\n")
end

function Config.Validate(config)
	--	Returns issues:string (potentially multiline) or nil, newConfig
	if type(config) ~= "table" then
		return "Config must be a table", nil
	end
	local problems = {} --{"Config failed to validate:"} -- not necessary (see TestConfigTree's setConfig)
	local newConfig = Config.new()
	local keysAnalyzed = {}
	for _, details in ipairs(configOptions) do
		local name, Type = details.Name, details.Type
		if config[name] ~= nil then
			local success, msg = Type.Validate(config[name])
			if success then
				newConfig[name] = msg
			else
				problems[#problems + 1] = msg:format(name)
			end
		end
		keysAnalyzed[name] = true
	end
	for k, v in pairs(config) do
		if not keysAnalyzed[k] then
			problems[#problems + 1] = ("Unrecognized key '%s'"):format(k)
		end
	end
	return #problems > 1 and table.concat(problems, "\n    - ") or nil, newConfig
end
function Config.GetConfigFromModule(moduleScript)
	--	moduleScript can be nil
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local success, config = pcall(require, moduleScript:Clone())
		if success then
			local problems, config = Config.Validate(config)
			if problems then
				warn(moduleScript:GetFullName(), "is invalid:", problems)
			end
			return config
		-- else -- As of Nov 2020, the error is being displayed despite being in a pcall
		-- 	warn(moduleScript:GetFullName(), "errored with:", config)
		end
	end
	return Config.new()
end

return Config