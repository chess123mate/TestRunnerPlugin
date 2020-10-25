-- TestSettings: A collection of test-related user settings. (Not called UserSettings because that's a Roblox class.)
local function varToEnglish(v)
	return v:sub(1,1):upper() .. v:sub(2):gsub("([A-Z])", " %1")
end
local function new(key, optionType, default, desc)
	return {
		Key = key,
		Name = varToEnglish(key),
		Validate = optionType.Validate,
		ValidateOrDefault = function(value)
			local success, value = optionType.Validate(value)
			if success then
				return value
			else
				return default
			end
		end,
		Type = optionType,
		Default = default,
		Desc = desc,
	}
end
local Bool = {
	Validate = function(value)
		if typeof(value) == "boolean" then
			return true, value
		end
	end,
}
local options = {
	new("preventRunWhileEditingScripts", Bool, true, "If true, tests will not be rerun while you are editing/viewing a being-tested-ModuleScript in Roblox Studio"),
	new("printStartOfTests", Bool, false, "If true, the start of all tests will be printed"),
	new("hideReport", Bool, false, "If true, the final report is not shown"),
	new("hideOneLineErrors", Bool, true, "(If report is enabled) Only display one-line errors in the final report."),
	new("putTracebackInReport", Bool, false, "Colourful errors will not appear and tracebacks will appear in the report"),
	new("hidePassedOnFailure", Bool, true, "(For reports) If true and at least one test fails, passing modules will be hidden (making it easier to read errors/output)"),
	new("alwaysShowTests", Bool, false, "(For reports) Always show a module's tests, even if all of them succeeded"),
	new("alwaysShowCases", Bool, false, "(For reports) Always show a test's cases, even if all of them succeeded"),
}
for _, option in ipairs(options) do
	options[option.Key] = option
end

local TestSettings = {
	Options = options, -- both a list<option> and key->option
}
local readProps = {
	HideOneLineErrors = function(self)
		return not self.hideReport and self.hideOneLineErrors
	end,
	ShowReport = function(self)
		return not self.hideReport
	end,
}
TestSettings.__index = function(self, key)
	local prop = readProps[key]
	if prop then
		return prop(self)
	end
	return TestSettings[key] or self:GetOne(options[key] and key or error(key .. " is not a valid key in TestSettings"))
end
function TestSettings.new(plugin)
	return setmetatable({
		plugin = plugin,
		changed = {},
		changedEvents = {},
	}, TestSettings)
end
function TestSettings:GetOne(key, settings) -- settings: for this file's use only
	settings = settings or self.plugin:GetSetting("settings") or {}
	return options[key].ValidateOrDefault(settings[key])
end
function TestSettings:Get()
	--	Gets the stored settings (without any keys from old versions)
	local t = {}
	local settings = self.plugin:GetSetting("settings")
	for _, option in ipairs(options) do
		t[option.Key] = self:GetOne(option.Key, settings)
	end
	return t
end
function TestSettings:SetOne(key, value, settings) -- settings: for this file's use only
	--	value expected to be validated
	local prev = self:GetOne(key)
	if prev == value then return end
	settings = settings or self:Get()
	settings[key] = value
	self.plugin:SetSetting("settings", settings)
	local changed = self.changed[key]
	if changed then
		changed:Fire()
	end
end
function TestSettings:Set(t)
	local settings = self:Get()
	for k, v in pairs(t) do
		self:SetOne(k, v, settings)
	end
end
function TestSettings:GetPropertyChangedSignal(key)
	local changedEvent = self.changedEvents[key]
	if not changedEvent then
		if not options[key] then
			error("TestSettings." .. tostring(key) .. " not a valid option")
		end
		local changed = Instance.new("BindableEvent")
		changedEvent = changed.Event
		self.changed[key] = changed
		self.changedEvents[key] = changedEvent
	end
	return changedEvent
end
function TestSettings:Destroy()
	for _, event in ipairs(self.changed) do
		event:Destroy()
	end
end

return TestSettings