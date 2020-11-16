-- TestConfigTree: manages TestConfigs for a game
local Config = script.Parent
local ConfigTree = require(Config.ConfigTree)
local baseShouldRecurse = require(Config.BaseSearchShouldRecurse)
local modules = Config.Parent
local Utils = modules.Utils
local ExploreServices = require(Utils.ExploreServices)
local TestConfigTree = {}
TestConfigTree.__index = TestConfigTree
local testRunner = game:GetService("TestService").TestRunner
local function assertIs(v, t, varName)
	if typeof(v) ~= t then
		error(("%s must be a '%s', received '%s'"):format(varName or "Value", t, tostring(v)), 3)
	end
	return v
end
function TestConfigTree.new(listenServiceNames, searchShouldRecurse, Config, onConfigChange, freezer, gameOverride, requireOverride)
	--	Config:
	--		.Default:config
	--		.Validate(config):issues/nil, newConfig/nil
	--	onConfigChange:function(testConfig:ModuleScript, oldConfig, newConfig)
	--		will not fire when the config is first loaded (during TestConfigTree.new)
	--	Does not take ownership of freezer
	local default = Config.Default
	if default == nil then error("Config.Default must exist", 2) end
	assertIs(Config.Validate, "function", "Config.Validate")
	local cons = {}
	local tree = ConfigTree.new(default)
	local self = setmetatable({
		tree = tree,
		cons = cons,
	}, TestConfigTree)
	local game = gameOverride or game
	local require = requireOverride or require
	local TestService = game:GetService("TestService")
	local function getValueFromInstance(obj)
		obj = obj.Parent
		return obj == TestService and game or obj
	end
	function self.getInstanceFromValue(value)
		return value and (value == game and TestService.TestConfig or value.TestConfig) or nil
	end
	local finishedInit
	local function treeSetConfig(obj, config, valueOverride)
		local value = valueOverride or getValueFromInstance(obj)
		local old = tree:GetFor(value)
		tree:SetConfig(value, config)
		local new = tree:GetFor(value)
		if finishedInit then
			onConfigChange(obj, old, new)
		end
	end
	local function setConfig(obj)
		local success, result = pcall(require, obj:Clone()) -- we don't use the variant since we want to be safe (ie this is a simple solution)
		if success then
			local issues, config = Config.Validate(result)
			if issues then
				warn("Invalid configuration in", obj:GetFullName() .. ":", issues)
			end
			if config then
				treeSetConfig(obj, config)
			end
		-- else -- As of Nov 2020, the error is being displayed despite being in a pcall
		-- 	warn("Invalid configuration in", obj:GetFullName()) -- don't need to output result because we're requiring it to demo error + traceback
			--coroutine.wrap(require)(obj:Clone())
		end
	end
	local function cleanup(...)
		for _, con in ipairs({...}) do
			con:Disconnect()
			self.cons[con] = nil
		end
	end
	self.serviceConsCleanup = ExploreServices(listenServiceNames, function(obj)
		if obj:IsA("ModuleScript") and not obj:IsDescendantOf(testRunner) then
			local sourceChangedCon
			local prevValue -- must keep track of this for if the obj is removed since the value depends on the parent
			local function setObjIsConfig()
				setConfig(obj)
				prevValue = getValueFromInstance(obj)
			end
			local function freezerSetConfig()
				freezer:RunWhenNotFreezing(obj, setObjIsConfig)
			end
			local function objIsConfig()
				if not sourceChangedCon then
					sourceChangedCon = obj:GetPropertyChangedSignal("Source"):Connect(freezerSetConfig)
					self.cons[sourceChangedCon] = true
					freezerSetConfig()
				end
			end
			local function objIsNotConfig()
				if sourceChangedCon then
					cleanup(sourceChangedCon)
					sourceChangedCon = nil
					if prevValue then
						treeSetConfig(obj, nil, prevValue)
					end
				end
			end
			if obj.Name == "TestConfig" then
				objIsConfig()
			end
			local nameCon = obj:GetPropertyChangedSignal("Name"):Connect(function()
				if sourceChangedCon then -- was config, so is no longer
					objIsNotConfig()
				elseif obj.Name == "TestConfig" then
					objIsConfig()
				end
			end)
			self.cons[nameCon] = true
			local ancestryCon; ancestryCon = obj.AncestryChanged:Connect(function(child, parent)
				if not parent then
					objIsNotConfig() -- cleans up sourceChangedCon
					cleanup(nameCon, ancestryCon)
				end
			end)
			self.cons[ancestryCon] = true
		end
		return searchShouldRecurse(obj, baseShouldRecurse)
	end, game)
	finishedInit = true
	return self
end
function TestConfigTree:GetFor(obj)
	--	Get the effective configuration table for 'obj' (can be any Instance in the hierarchy)
	return self.tree:GetFor(obj)
end
function TestConfigTree:GetConfigScriptFor(moduleScript, key)
	return self.getInstanceFromValue(self.tree:GetOriginatingValueForKey(moduleScript, key))
end
function TestConfigTree:Destroy()
	self.serviceConsCleanup()
	for con, _ in pairs(self.cons) do
		con:Disconnect()
	end
end
return TestConfigTree