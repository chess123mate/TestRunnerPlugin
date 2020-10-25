--[[Mocks for simulating Roblox game/hierarchy

Returns a table with:
	[className] = MockClass
		ex, MInstance, ModuleScript, etc
		Game also works in addition to a game's actual class DataModel
	require:function() -- can be used on any mock ModuleScript
]]

local function List_Reverse(t)
	--	't' is a list whose elements are to be reversed in place
	local n = #t
	local n1 = n + 1
	local m = n1 / 2
	-- ex, if n = 5 (1 2 3 4 5), we want to ignore the '3' in the middle
	-- if n = 6, we want to include the '3'; the middle is 3.5
	-- so, we can subtract 0.1 to ensure it works in all cases
	for i = 1, m - 0.1 do
		t[i], t[n1 - i] = t[n1 - i], t[i]
	end
	return t
end

local modules = game.ServerStorage.TestRunnerPlugin
local Event = require(modules.Utils.Event)

local MInstance = {ClassName = "Instance"}
local function genIndex(class)
	return function(self, key)
		local p = class.props[key]
		if p then
			return p[1](self)
		else
			local v = class[key]
			if v ~= nil then
				return v
			end
			v = self.nameToChildren[key]
			if v then return v[1] end
			-- Roblox would error but for convenience we'll ignore lower case keys (assumed to be private variables)
			if type(key) == "string" then
				local c = key:sub(1, 1)
				if c:lower() == c then
					return nil
				end
			end
			error(('%s is not a valid member of test %s "%s"'):format(tostring(key), class.ClassName, self.name), 2)
		end
	end
end
local function __newindex(self, key, value)
	local p = self.props[key]
	if p then
		p[2](self, value)
	else
		rawset(self, key, value)
	end
end
local function __tostring(self) return self.name end
MInstance.__index = MInstance -- for classes
local MInstanceMt = { -- for instances
	__index = genIndex(MInstance),
	__newindex = __newindex,
	__tostring = __tostring,
}
local function genOnChangedProp(private, public, default)
	return {
		default
			and function(self) return self[private] or default end
			or function(self) return self[private] end,
		function(self, value)
			if value == self[private] then return end
			self[private] = value
			self:changed(public)
		end,
	}
end
MInstance.classNames = {MInstance=true}
MInstance.props = {
	Name = genOnChangedProp("name", "Name"),
	Parent = {
		function(self) return self.parent end,
		function(self, value)
			local oldParent = self.parent
			if oldParent == value then return end
			if self == value then
				error(("Attempt to set %s as its own parent"):format(self:GetFullName()), 2)
			elseif self:IsAncestorOf(value) then
				error(("Attempt to set parent of %s to %s would result in circular reference"):format(self:GetFullName(), value:GetFullName()), 2)
			end
			if oldParent then
				self.parent = nil
				oldParent:removeChild(self)
			end
			if value then
				self.parent = value
				value:addChild(self)
			end
			self:changed("Parent")
			self.AncestryChanged:Fire(self, value)
		end
	},
}
local Mocks = {Instance = MInstance}
function MInstance.new(className)
	--	derived classes should *not* provide className - that's for the public function
	if className then
		return (Mocks[className] or error("No class with name " .. className, 2)).new()
	else
		local self = setmetatable({
			name = "Instance",
			children = {},
			nameToChildren = {}, -- name->List<children>
			events = {}, -- name -> event for all events (for easy cleanup on Destroy)
		}, MInstanceMt)
		for _, name in ipairs({"AncestryChanged", "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving"}) do
			self:addEvent(name)
		end
		return self
	end
end
function MInstance.safeNew(className)
	--	Same as .new but creates 'className' if it doesn't exist
	local class = Mocks[className]
	if not class then
		class = MInstance:Extend(className)
		Mocks[className] = class
	end
	return class.new()
end
function MInstance:addEvent(name)
	local e = Event()
	self.events[name] = e
	self[name] = e
	return e
end
function MInstance:replAncestryChanged(child, parent)
	self.AncestryChanged:Fire(child, parent)
	for _, child in ipairs(self.children) do
		child:replAncestryChanged(child, parent)
	end
end
local function addToDictList(t, key, value)
	local list = t[key]
	if not list then
		list = {}
		t[key] = list
	end
	list[#list + 1] = value
end
local function removeFromDictList(t, key, value)
	local list = t[key]
	if #list == 1 then
		t[key] = nil
	else
		table.remove(list, table.find(list, value))
	end
end
function MInstance:addChild(c)
	self.children[#self.children + 1] = c
	addToDictList(self.nameToChildren, c.Name, c)
	self.ChildAdded:Fire(c)
	local obj = self
	repeat
		obj.DescendantAdded:Fire(c)
		obj = obj.parent
	until not obj
end
function MInstance:removeChild(c)
	local obj = self
	repeat
		obj.DescendantRemoving:Fire(c)
		obj = obj.parent
	until not obj
	table.remove(self.children, table.find(self.children, c))
	removeFromDictList(self.nameToChildren, c.Name, c)
	self.ChildRemoved:Fire(c)
end
function MInstance:GetChildren() return {unpack(self.children)} end
function MInstance:GetDescendants(t)
	t = t or {}
	for _, c in ipairs(self.children) do
		t[#t + 1] = c
		c:GetDescendants(t)
	end
	return t
end
function MInstance:IsA(className)
	return self.classNames[className] or false
end
function MInstance:IsAncestorOf(value)
	value = value.Parent
	while value do
		if self == value then
			return true
		end
		value = value.Parent
	end
	return false
end
function MInstance:FindFirstChild(name)
	local list = self.nameToChildren[name]
	return list and list[1] or nil
end
function MInstance:IsDescendantOf(value)
	local parent = self.Parent
	while parent do
		if parent == value then
			return true
		end
		parent = parent.Parent
	end
	return false
end
function MInstance:Clone()
	local new = MInstance.new(self.ClassName)
	for k, p in pairs(self.props) do
		if k ~= "Parent" then
			new.props[k][2](new, p[1](self))
		end
	end
	return new
end
function MInstance:GetFullName()
	local names = {}
	local obj = self
	repeat
		names[#names + 1] = obj.name
		obj = obj.parent
	until not obj or obj:IsA("DataModel")
	List_Reverse(names)
	return table.concat(names, ".")
end
function MInstance:GetPropertyChangedSignal(prop)
	local event = self.events[prop]
	if not event then
		event = Instance.new("BindableEvent")
		self.events[prop] = event
	end
	return event.Event
end
function MInstance:changed(prop)
	local event = self.events[prop]
	if event then
		event:Fire()
	end
	self.Changed:Fire(prop)
end
function MInstance:Destroy()
	-- We recurse on children first. This minimizes AncestryChanged activity
	--	and ensures that DescendantRemoving works correctly.
	for _, child in ipairs(self.children) do
		child:Destroy()
	end
	self.Parent = nil
	for _, event in pairs(self.events) do
		event:Destroy()
	end
end
local function clone(t)
	local new = {}
	for k, v in pairs(t) do
		new[k] = v
	end
	return new
end
function MInstance.Extend(baseClass, name) -- ie MInstance:Extend("Part")
	local classNames = clone(baseClass.classNames)
	classNames[name] = true
	local class = setmetatable({
		ClassName = name,
		classNames = classNames,
		props = clone(baseClass.props), -- :Clone needs all props so don't bother using a metatable here
	}, baseClass)
	class.__index = class
	Mocks[name] = class
	local mt = {
		__index = genIndex(class),
		__newindex = __newindex,
		__tostring = __tostring,
	}
	function class.new()
		local self = setmetatable(baseClass.new(), mt)
		self.name = name
		return self
	end
	return class
end

local Game = MInstance:Extend("DataModel")
Mocks.Game = Game -- special case since you expect Game not DataModel
local base = Game.new
function Game.new()
	local self = base()
	local services = {}
	self.services = services
	for _, name in ipairs({"Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "SoundService", "Chat", "LocalizationService", "TestService", "Teams"}) do
		local obj = MInstance.safeNew(name)
		services[name] = obj
		obj.Parent = self
	end
	return self
end
function Game:GetService(name)
	return self.services[name] or error("No service with name " .. tostring(name), 2)
end

local ScriptContainer = MInstance:Extend("LuaSourceContainer")
-- Note: Roblox's LuaSourceContainer does *not* contain Source, since CoreScript does not
--	But we'll include it for simplicity
ScriptContainer.props.Source = genOnChangedProp("source", "Source", "")
local String = {}
function String.Trim(s) -- Is trim6 from http://lua-users.org/wiki/StringTrim.
	return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
end
local ModuleScript = ScriptContainer:Extend("ModuleScript")
function ModuleScript:Require()
	if self.requiring then
		self.requiring.Event:Wait()
	end
	if not self.required or self.requiredSource ~= self.source then
		self.requiring = Instance.new("BindableEvent")
		local m = Instance.new("ModuleScript")
		m.Name = self.name
		m.Source = self.source
		local traceback = ""
		local success, result = xpcall(require, function()
			traceback = "\n" .. String.Trim(debug.traceback())
		end, m)
		if self.realModule then
			self.realModule:Destroy()
		end
		self.realModule = m
		self.required = true
		if success then
			self.requiredValue = result
			self.requiredError = nil
		else
			self.requiredError = result .. traceback
			self.requiredValue = nil
		end
		self.requiring:Fire()
		self.requiring:Destroy()
		self.requiring = nil
		self.requiredSource = self.source
	end
	if self.requiredError then
		error(self:GetFullName() .. " encountered an error on require: " .. self.requiredError)
	else
		return self.requiredValue
	end
end
local base = ModuleScript.Destroy
function ModuleScript:Destroy()
	base(self)
	if self.realModule then
		self.realModule:Destroy()
	end
	if self.requiring then
		self.requiring:Destroy()
	end
end

function Mocks.Require(moduleScript)
	if type(moduleScript) ~= "table" or not moduleScript:IsA("ModuleScript") then
		error(
			("Mock require must receive a mock ModuleScript; received '%s' (a %s)"):format(
				tostring(moduleScript),
				typeof(moduleScript) == "table" and ("test " .. moduleScript.ClassName or "table") or typeof(moduleScript)),
			2)
	end
	return moduleScript:Require()
end
Mocks.require = Mocks.Require

return Mocks