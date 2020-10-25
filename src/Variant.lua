--[[Variant ModuleScript
Creates a variant of a ModuleScript that allows tracking dependencies.
When the source of the target ModuleScript changes, this variant becomes invalidated,
along with all Variants that required this one.
Main API:
	.Invalidated:Event()
	:Require()
	:Destroy() -- does not destroy the target ModuleScript
]]

local modules = script.Parent
local GetModuleName = require(modules.Descriptions).GetModuleName
local Utils = modules.Utils
local NewTry = require(Utils.NewTry)
local GenPluginErrHandler = require(Utils.GenPluginErrHandler)
local TestService = game:GetService("TestService")

local Variant = {}
Variant.__index = Variant

local variantCode = "return function(script, require) %s end"

local VariantStorage = {}
Variant.Storage = VariantStorage
VariantStorage.__index = VariantStorage
function VariantStorage.new(storage)
	--	You can perform `for moduleScript, varaint in pairs(storage) do` on this class
	return setmetatable(storage or {}, VariantStorage)
end
function VariantStorage:Get(moduleScript)
	local variant = self[moduleScript]
	if not variant then
		variant = Variant.new(self, moduleScript)
		self[moduleScript] = variant
	end
	return variant
end
function VariantStorage:Remove(moduleScript) -- Should only be called by Variant:Destroy()
	self[moduleScript] = nil
end
function VariantStorage:Destroy()
	for _, variant in pairs(self) do
		variant:Destroy()
	end
end

local moduleScriptToVariant = {}
function Variant.new(variantStorage, moduleScript)
	--	Note: A variant destroys itself if AncestryChanged to nil ancestor
	--	You will know this has happened if :IsDestroyed() is true after an .Invalidated event
	--	Note: Prefer to create a storage via Variant.Storage.new and use its :Get() function instead.
	local self = setmetatable({
		variantStorage = assert(variantStorage),
		moduleScript = moduleScript,
		required = false,
		-- variant:ModuleScript
		-- requireFinished:BindableEvent (only exists while requiring)
		-- requiredValue
		-- destroyed -- used to prevent Require from calling performRequire after destruction
		dependencies = {}, -- variant ModuleScript required by this one -> Invalidated connection
	}, Variant)
	self.invalidated = Instance.new("BindableEvent")
	self.Invalidated = self.invalidated.Event
	function self.invalidate()
		if self.required or self.requireFinished then
			self.required = false
			self.requiredError = nil
			if self.requireFinished then
				self.requireFinished:Destroy()
				self.requireFinished = nil
			end
			for _, con in pairs(self.dependencies) do
				con:Disconnect()
			end
			self.dependencies = {}
			self.invalidated:Fire()
		end
	end
	self.cons = {
		moduleScript:GetPropertyChangedSignal("Source"):Connect(self.invalidate),
		moduleScript.AncestryChanged:Connect(function(_, parent)
			if not parent then
				self:Destroy()
			else
				self.invalidate()
			end
		end),
	}
	return self
end
function Variant:PrintDependencies(seen, depth)
	seen = seen or {}
	local id = seen[self]
	if not id then
		id = (seen.next or 1)
		seen.next = id + 1
	end
	depth = depth or 0
	local char = string.rep("  ", depth)
	local format = seen[self] and "(%s)" or "%s"
	print(("%s%s%s%s"):format(
		char,
		seen[self] and "" or ("%d) "):format(id),
		depth == 0 and self.moduleScript:GetFullName() or self.moduleScript.Name,
		seen[self] and (" (%d)"):format(seen[self]) or ""))
	if not seen[self] then
		seen[self] = id
		for variant, _ in pairs(self.dependencies) do
			variant:PrintDependencies(seen, depth + 1)
		end
	end
end
function Variant:GetModuleScript() return self.moduleScript end
function Variant:IsRequired()
	return self.required
end
function Variant:neverReturn()
	-- We want to stop the current thread, so we'll yield in the hopes that it's forgotten
	coroutine.yield() -- Note: Roblox's thread scheduler no longer resumes this
	-- The yield could return if something was referencing the coroutine and resumed it
	error("(Thread attempted to require an expired variant of " .. self.moduleScript:GetFullName() .. "; the thread was resumed by something)")
end
function Variant:addDependencyAndRequire(moduleScript)
	local variant = self.variantStorage:Get(moduleScript)
	if variant ~= self and not self.dependencies[variant] then -- either condition could occur with circular requires
		self.dependencies[variant] = variant.Invalidated:Connect(self.invalidate)
	end
	return variant:Require()
end
function Variant:performRequire()
	if self.variant then
		self.variant:Destroy()
	end
	local variant = Instance.new("ModuleScript")
	self.variant = variant
	variant.Name = self.moduleScript:GetFullName()
	variant.Source = variantCode:format(self.moduleScript.Source)
	local function newRequire(what)
		if self.destroyed or self.variant ~= variant then
			self:neverReturn()
		end
		if typeof(what) == "Instance" and what:IsA("ModuleScript") then
			return self:addDependencyAndRequire(what)
		else -- can occur if another script has modified the function environment
			return require(what)
		end
	end
	return require(self.variant)(self.moduleScript, newRequire)
end
local function nonTry(name)
	local tryName = "Try" .. name
	Variant[name] = function(self, ...)
		local success, value = self[tryName](self, ...)
		if not success then
			error(value)
		end
		return value
	end
end
nonTry("Require")
nonTry("GetRequiredValue")
function Variant:TryRequire(timeout) -- require it (waiting as necessary)
	--	returns success, value
	if not self.required then
		if self.requireFinished then
			self.requireFinished.Event:Wait()
		elseif self.destroyed then
			error(("Attempt to require %s, which has been destroyed"):format(self.moduleScript:GetFullName()))
		else
			local requireFinished = Instance.new("BindableEvent")
			self.requireFinished = requireFinished
			NewTry(function(try)
				try
					:onSuccess(function(value)
						if self.requireFinished == requireFinished then
							self.requiredValue = value
						else -- script has been invalidated or destroyed since we started
							-- In this case, cleanup is unnecessary (it should already have been done)
							self:neverReturn()
						end
					end)
					:onError(GenPluginErrHandler(function(msg)
						if self.requireFinished == requireFinished then
							self.requiredError = msg
						end
					end))
					:finally(function()
						if self.requireFinished == requireFinished then
							self.required = true
							requireFinished:Fire()
							requireFinished:Destroy()
							requireFinished = nil
							self.requireFinished = nil
						else -- same as in onSuccess case
							self:neverReturn()
						end
					end)
				if timeout then
					try:onTimeout(timeout, function()
						if self.requireFinished == requireFinished then
							self.requiredError = ("%s failed to return from require in %s seconds"):format(GetModuleName(self.moduleScript), tostring(timeout))
							TestService:Error(self.requiredError)
						end
					end)
				end
			end, self.performRequire, self)
			if requireFinished then
				requireFinished.Event:Wait()
			end
		end
	end
	return self:TryGetRequiredValue()
end
function Variant:TryGetRequiredValue()
	--	returns success, value
	if not self.required then
		error("Cannot TryGetRequiredValue " .. self.moduleScript:GetFullName() .. " if script not :Require()'d", 2)
	elseif self.requiredError then
		return false, GetModuleName(self.moduleScript) .. " encountered an error while requiring: " .. self.requiredError
	else
		return true, self.requiredValue
	end
end
function Variant:IsDestroyed()
	return self.destroyed
end
function Variant:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.variantStorage:Remove(self.moduleScript)
	if self.required then
		self:invalidate()
	end
	if self.requireFinished then
		self.requireFinished:Destroy()
		self.requireFinished = nil
	end
	if self.variant then
		self.variant:Destroy()
	end
	self.invalidated:Destroy()
	for _, con in pairs(self.dependencies) do
		con:Disconnect()
	end
	for _, con in ipairs(self.cons) do
		con:Disconnect()
	end
end
return Variant