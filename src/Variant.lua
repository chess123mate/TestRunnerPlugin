--[[Variant ModuleScript
Creates a variant of a ModuleScript that allows tracking dependencies.
When the source of the target ModuleScript changes, this variant becomes invalidated,
along with all Variants that required this one.
Main API:
	.Invalidated:Event() -- fired when source changes, script is moved, or a dependency is invalidated
	.SourceChanged:Event()
	:Require()
	:Destroy() -- does not destroy the target ModuleScript
]]

local modules = script.Parent
local Descriptions = require(modules.Descriptions)
local GetModuleName = Descriptions.GetModuleName
local Utils = modules.Utils
local NewTry = require(Utils.NewTry)
local PluginErrHandler = require(Utils.PluginErrHandler)
local TestService = game:GetService("TestService")

local Variant = {}
Variant.__index = Variant

local variantCode = "return function(script, require) %s\nend" -- must have 'end' on new line in case there's a comment on the last line

local VariantStorage = {}
Variant.Storage = VariantStorage
VariantStorage.__index = VariantStorage
local variantStorageIsTemporaryScript = {} -- VariantStorage -> isTemporaryScript
local never = function() end
function VariantStorage.new(storage, isTemporaryScript)
	--	You can perform `for moduleScript, varaint in pairs(storage) do` on this class
	--	isTemporaryScript:function(moduleScript)->true if the script is temporary and should not invalidate other scripts
	--		It is assumed that a script can become non-temporary and so it is invoked as needed for each module script
	--		It defaults to assuming that scripts are never temporary
	local self = setmetatable(storage or {}, VariantStorage)
	variantStorageIsTemporaryScript[self] = isTemporaryScript or never
	return self
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
	variantStorageIsTemporaryScript[self] = nil
end

local moduleScriptToVariant = {}
function Variant.new(variantStorage, moduleScript)
	--	Note: A variant destroys itself if AncestryChanged to nil ancestor
	--	You will know this has happened if :IsDestroyed() is true after an .Invalidated event
	--	Note: Prefer to create a storage via Variant.Storage.new and use its :Get() function instead.
	local self = setmetatable({
		variantStorage = variantStorage or error("variantStorage mandatory", 2),
		moduleScript = moduleScript,
		required = false,
		-- variant:ModuleScript
		-- requireFinished:BindableEvent (only exists while requiring)
		-- requiredValue
		-- destroyed -- used to prevent Require from calling performRequire after destruction
		dependencies = {}, -- variant ModuleScript required by this one -> Invalidated connection
		version = 0, -- increases whenever the variant changes
	}, Variant)
	self.invalidated = Instance.new("BindableEvent")
	self.Invalidated = self.invalidated.Event
	self.sourceChanged = Instance.new("BindableEvent")
	self.SourceChanged = self.sourceChanged.Event
	function self.invalidate()
		if self.required or self.requireFinished then
			self.version += 1
			self.required = false
			self.requiredError = nil
			self.requiredErrorDuringRequire = nil
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
		moduleScript:GetPropertyChangedSignal("Source"):Connect(function()
			self.sourceChanged:Fire()
			self.invalidate()
		end),
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
function Variant:isTemporary()
	return variantStorageIsTemporaryScript[self.variantStorage](self.moduleScript)
end
function Variant:addDependencyAndRequire(moduleScript)
	local variant = self.variantStorage:Get(moduleScript)
	if variant ~= self and not self.dependencies[variant] then -- either condition could occur with circular requires
		self.dependencies[variant] = variant.Invalidated:Connect(function()
			if not variant:isTemporary() then
				self.invalidate()
			end
		end)
	end
	return variant:Require(nil, self)
end
--[[
For example, let's say there's A,B,C and C requires B requires A, but A is just `error("a")`.
The traceback is just going to be A:1
So it turns out that we can't use `error({})` -- only string values
	so we have to store this elsewhere
So we error(compressedError({msg = "a", traceback = "A:1"})) -- which assigns metatable for good __tostring
Then B's require 
so now we have msg "a" with traceback

local compressedErrorMT = {
	__tostring = function(self) return self.msg .. "\n" .. self.traceback end
}
error(setmetatable({msg = "a", traceback = "A:1"}, compressedErrorMT))

]]
local pluginErrHandlerDepth3 = PluginErrHandler.Gen(nil, nil, nil, nil, 3)
function Variant:Require(timeout, requiringVariant)
	--	requiringVariant: for a require nested inside another require
	local success, value = self:tryRequire(timeout, requiringVariant)
	if success then
		return value
	else
		error(value, 2)
	end
end
function Variant:performRequire()
	--	Returns alreadyErrored, value -- but is likely to error (ex if the required script does)
	--		value is either the error message (if alreadyErrored) or the value required
	--		alreadyErrored can be the string "require" if the error happened during a require
	--	Note: call this function in a 'try' and handle requireFinished:
	--		on finally: fire it (if it exists) and destroy & remove it (assuming self.version is unchanged)
	if self.required or self.requireFinished then
		if self.requireFinished then
			self.requireFinished.Event:Wait()
		end
		if self.requiredError then
			return self.requiredErrorDuringRequire and "require" or true, self.requiredError
		end
		return false, self.requiredValue
	else
		self.requireFinished = Instance.new("BindableEvent")
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
			else
				error("TestRunnerPlugin does not support non-ModuleScript requires", 2)
			end
		end
		return false, require(self.variant)(self.moduleScript, newRequire)
	end
end
function Variant:tryRequire(timeout, --[[onDestroyed,]] requiringVariant)
	if self.destroyed then -- Note: Roblox doesn't error if you require a destroyed ModuleScript, but we don't want to keep testing it
		self:neverReturn()
	end
	local v = self.version
	local errMsg -- set to what error message to return (if something goes wrong)
	NewTry(function(try)
		try
			:onSuccess(function(alreadyErrored, value)
				if v ~= self.version then self:neverReturn() end
				if alreadyErrored then
					errMsg = string.format("%s%s encountered an error while %s: %s",
						requiringVariant and "(While determining if it's a test) " or "",
						alreadyErrored == "require" and GetModuleName(self.moduleScript) or self.moduleScript.Name, -- We don't need to use GetModuleName because self.requiredError (stored in value) is likely to specify that already
						alreadyErrored == "require" and "requiring" or "loading",
						value)
					if requiringVariant then
						requiringVariant.incomingRequireError = value
					end
					pluginErrHandlerDepth3(errMsg)
				else
					self.requiredValue = value
				end
			end)
			:onError(function(msg)
				if v ~= self.version then self:neverReturn() end
				-- As variants require each other, incomingRequireError will be nil for the first "top level" error, then true just long enough to pass the error backwards through the chain without emitting more red text
				if self.incomingRequireError then
					self.incomingRequireError = nil
					PluginErrHandler.ContinueUserErrorAddTraceback(debug.traceback("", 2))
					errMsg = msg
						:gsub("^.-TestRunnerPlugin%.Variant:[^:]-:%s*(.*)", "%1")
						:gsub("StarterPlayer%.StarterPlayerScripts%.", "StarterPlayerScripts.")
						:gsub("StarterPlayer%.StarterCharacterScripts%.", "StarterCharacterScripts.")
					self.requiredError = errMsg
					self.requiredErrorDuringRequire = true
				else -- top level error
					PluginErrHandler.Gen(function(msg, b, c, d)
						self.requiredError = msg
						errMsg = msg
					end, nil, nil, nil, 3)(msg)
				end
				if requiringVariant then
					requiringVariant.incomingRequireError = errMsg
				end
			end)
			:finally(function()
				if v ~= self.version then self:neverReturn() end
				self.required = true
				local requireFinished = self.requireFinished
				if requireFinished then
					self.requireFinished = nil
					requireFinished:Fire()
					requireFinished:Destroy()
				end
			end)
		if timeout then
			try:onTimeout(timeout, function()
				if v ~= self.version then self:neverReturn() end
				errMsg = ("%s failed to return from require in %s seconds"):format(GetModuleName(self.moduleScript), tostring(timeout))
				self.requiredError = errMsg
				TestService:Error(errMsg)
			end)
		end
	end, self.performRequire, self)
	if self.requireFinished then self.requireFinished.Event:Wait() end
	if errMsg then
		return false, errMsg
	else
		return true, self.requiredValue
	end
end
function Variant:TryRequire(timeout) -- require it (waiting as necessary)
	--	returns success, value
	return self:tryRequire(timeout)
end
-- function Variant:tryGetRequiredValue()
-- 	--	returns success, value, requireAlreadyErrored
-- 	if not self.required then
-- 		error("Cannot tryGetRequiredValue " .. self.moduleScript:GetFullName() .. " if script not :Require()'d", 2)
-- 	elseif self.requiredError then
-- 		-- We don't need to use GetModuleName because self.requiredError is likely to specific that already
-- 		return false, self.moduleScript.Name .. " encountered an error while loading: " .. self.requiredError, true
-- 	else
-- 		return true, self.requiredValue
-- 	end
-- end
function Variant:GetRequiredValue()
	if not self.required then
		error("Cannot GetRequiredValue " .. self.moduleScript:GetFullName() .. " if script not :Require()'d", 2)
	elseif self.requiredError then
		error("Cannot GetRequiredValue " .. self.moduleScript:GetFullName() .. " if script errored", 2)
	else
		return self.requiredValue
	end
end
function Variant:IsDestroyed()
	return self.destroyed
end
function Variant:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.variantStorage:Remove(self.moduleScript)
	self:invalidate() -- this changes version and destroys requireFinished as needed
	if self.variant then
		self.variant:Destroy()
	end
	self.invalidated:Destroy()
	self.sourceChanged:Destroy()
	for _, con in pairs(self.dependencies) do
		con:Disconnect()
	end
	for _, con in ipairs(self.cons) do
		con:Disconnect()
	end
end
return Variant