-- TestConfigTree Tests (without using Testing Framework)
return {function() -- wrap the function in a table to avoid detection by the TestRunnerPlugin
local progress = "startup"
spawn(function()
	if not progress then
		print("TestConfigTree tests successful")
	elseif progress ~= -1 then
		error("TestConfigTree tests got stuck at progress " .. tostring(progress))
	end
end)
local function assertEquals(name, a, b)
	if a ~= b then
		progress = -1
		error(("%s: %s ~= %s"):format(name, tostring(a), tostring(b)), 2)
	end
end
local function assertTableEquals(name, a, b)
	if a ~= b then
		for k, v in pairs(a) do
			if b[k] ~= v then
				progress = -1
				error(("%s: key '%s': %s ~= %s"):format(name, tostring(k), tostring(v), tostring(b[k])), 2)
			end
		end
		for k, v in pairs(b) do
			if a[k] ~= v then
				progress = -1
				error(("%s: key '%s': %s ~= %s"):format(name, tostring(k), tostring(a[k]), tostring(v)), 2)
			end
		end
	end
end

local T = require(script.Parent.Mocks)
local tGame = T.Game.new()
local tRequire = T.Require

local modules = game.ServerStorage.TestRunnerPlugin
local TestConfigTree = require(modules.Config.TestConfigTree)
local function newConfig(parent, s)
	--if s and typeof(s) ~= "string" then parent = s; s = nil end
	local x = T.Instance.new("ModuleScript")
	x.Name = "TestConfig"
	x.Source = ("return {%s}"):format(s or "")
	x.Parent = parent
	return x
end

progress = 1

local defaultConfig = {a=1, b=2, c=true}
local function override(t, ...)
	local new = {}
	for k, v in pairs(t) do
		new[k] = v
	end
	for _, t2 in ipairs({...}) do
		for k, v in pairs(t2) do
			new[k] = v
		end
	end
	return new
end

local listenServiceNames = {"TestService"}
local Config = {
	Default = defaultConfig,
	Validate = function(config)
		-- returns issues, newConfig
		return nil, config
	end,
}
local function configChanged() end
local freezer = {
	ShouldFreeze = function() return false end,
	RunWhenNotFreezing = function(_, key, func) func(key) end,
	Freeze = function() error("Shouldn't be calling Freeze") end,
}
local tree = TestConfigTree.new(listenServiceNames, Config, configChanged, freezer, tGame, tRequire)
progress = 2
local service = tGame.TestService
local result = tree:GetFor(service)
assertTableEquals("No config == default", result, defaultConfig)

progress = 3
local serviceConfig = newConfig(service, "a=2, c=false")
local effectiveConfig = {a=2,b=2,c=false}
assertTableEquals("Adding TestConfig overrides default", tree:GetFor(service), effectiveConfig)

progress = 4
local function create(class, name, parent)
	local obj = T.Instance.safeNew(class)
	obj.Name = name
	obj.Parent = parent
	return obj
end
local folder1 = create("Folder", "Folder1", service)
local folder2 = create("Folder", "Folder2", folder1)

progress = 5
local thirdConfig = newConfig(folder2)
assertTableEquals("Child of service uses service's config", tree:GetFor(folder1), effectiveConfig)
assertTableEquals("Descendant of service uses service's config", tree:GetFor(folder2), effectiveConfig)

progress = 6
local configF2 = newConfig(folder2, "f2=true")
assertTableEquals("Child of service still uses service's config", tree:GetFor(folder1), effectiveConfig)
local effectiveConfigF2NoF1 = {a=2,b=2,c=false,f2=true}
assertTableEquals("Folder2's config works", tree:GetFor(folder2), effectiveConfigF2NoF1)

progress = 7
local configF1 = newConfig(folder1, "f1=true, f2=false")
local effectiveConfigF1 = {a=2,b=2,c=false,f1=true,f2=false}
local effectiveConfigF2WithF1 = {a=2,b=2,c=false,f1=true,f2=true}
assertTableEquals("Folder1's config updated by config change", tree:GetFor(folder1), effectiveConfigF1)
assertTableEquals("Folder2's config updated by parent config change", tree:GetFor(folder2), effectiveConfigF2WithF1)

progress = 8
configF1.Name = "different name"
assertTableEquals("Folder1's config renamed; it should now inherit service", tree:GetFor(folder1), effectiveConfig)
assertTableEquals("Folder1's config renamed; folder2 should be as it was before", tree:GetFor(folder2), effectiveConfigF2NoF1)

progress = 9
configF1.Name = "TestConfig"
assertTableEquals("Folder1's config renamed back to TestConfig; folder1 working", tree:GetFor(folder1), effectiveConfigF1)
assertTableEquals("Folder2's config updated by parent config rename back to TestConfig change", tree:GetFor(folder2), effectiveConfigF2WithF1)

progress = 10
tree:Destroy()
progress = nil
end}