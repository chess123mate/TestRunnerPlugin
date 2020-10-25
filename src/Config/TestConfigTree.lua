-- TestConfigTree: manages TestConfigs for a game
local Config = script.Parent
local ConfigTree = require(Config.ConfigTree)
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
function TestConfigTree.new(listenServiceNames, Config, onConfigChange, freezer, gameOverride, requireOverride)
	--	Config:
	--		.Default:config
	--		.Validate(config):issues/nil, newConfig/nil
	--	onConfigChange:function(testConfig:ModuleScript, oldConfig, newConfig)
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
	local function treeSetConfig(obj, config)
		local value = getValueFromInstance(obj)
		local old = tree:GetFor(value)
		tree:SetConfig(value, config)
		local new = tree:GetFor(value)
		onConfigChange(obj, old, new)
	end
	local function setConfig(obj)
		local success, result = pcall(require, obj:Clone()) -- we don't use the variant since we want to be safe (ie this is a simple solution)
		if success then
			local issues, config = Config.Validate(result)
			if issues then
				warn("Invalid configuration in", obj:GetFullName() .. ":", issues)
				print(obj.Source)
			end
			if config then
				treeSetConfig(obj, config)
			end
		else
			warn("Invalid configuration in", obj:GetFullName()) -- don't need to output result because we're requiring it to demo error + traceback
			require(obj)
		end
	end
	local function setNoLongerConfig(obj)
		treeSetConfig(obj, nil)
	end
	local function cleanup(...)
		for _, con in ipairs({...}) do
			con:Disconnect()
			self.cons[con] = nil
		end
	end
	self.serviceConsCleanup = ExploreServices(listenServiceNames, function(obj)
		if not obj:IsA("ModuleScript") or obj:IsDescendantOf(testRunner) then return end
		local sourceChangedCon
		local function freezerSetConfig()
			freezer:RunWhenNotFreezing(obj, setConfig)
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
				setNoLongerConfig(obj)
			end
		end
		if obj.Name == "TestConfig" then
			objIsConfig(obj)
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
				cleanup(sourceChangedCon, nameCon, ancestryCon)
			end
		end)
		self.cons[ancestryCon] = true
	end, game)
	return self
end
function TestConfigTree:GetFor(obj)
	--	Get the effective configuration table for 'obj' (can be any Instance in the hierarchy)
	return self.tree:GetFor(obj)
end
function TestConfigTree:Destroy()
	self.serviceConsCleanup()
	for con, _ in pairs(self.cons) do
		con:Disconnect()
	end
end
return TestConfigTree