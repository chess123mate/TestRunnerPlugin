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

local configOptions = {
	new("requireTimeout", Number, 0.5, "A module times out if it hasn't returned from its require after this many seconds"),
			--"Seconds for a test module to return from its initial require before timing out"),
	new("initTimeout", Number, 0.5, "A module times out if it hasn't returned from its tests setup after this many seconds"),
			--"Seconds for a test module to register all its tests before timing out"),
	new("timeout", Number, 2, "Seconds for a test to complete before timing out"),
	new("skip", List, nil, "The list of test module names to skip over. You can specify the module path (up to but *not* including TestService) as well."),
	new("focus", List, nil, "If any test module names (or paths) are in this list, only they are run, regardless of what Skip contains."),
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
-- local runAllList = {"requireTimeout", "initTimeout", "timeout"}
-- function Config.OnConfigChange(testConfig, old, new, testConfigTree, actions)
--	-- (In future, *could* go through runAllList, then analyze skip/focus to help determine what to rerun)
-- 	for _, name in ipairs(runAllList) do
--		local option = 
-- 		if old[option.Name] ~= new[option.Name] then
-- 	end
--	-- etc
-- end

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

return Config