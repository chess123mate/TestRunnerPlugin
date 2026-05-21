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
local	GetModuleName = Descriptions.GetModuleName
local ErrorCoroutines = require(modules.Testing.ErrorCoroutines)
local Utils = modules.Utils
local NewTry = require(Utils.NewTry)
local PluginErrHandler = require(Utils.PluginErrHandler)
local Event = require(Utils.Event)
local IsErrorFromPlugin = require(modules.IsErrorFromPlugin)
local pluginName = require(modules.PluginConfig).PluginName

local TestService = game:GetService("TestService")

local Variant = {}
Variant.__index = Variant

local variantCode = "return function(script, require) %s\nend" -- must have 'end' on new line in case there's a comment on the last line

local tsFullName = "ReplicatedStorage.rbxts_include.RuntimeLib"
local tsVariantCode = [[return function(script, require, addDep)
local function main()
%s`end
local TS = main()
local base = TS.import
function TS.import(context, module, ...)
	for i = 1, select("#", ...) do
		module = module:WaitForChild((select(i, ...)))
	end
	if module.ClassName == "ModuleScript" then
		addDep(context, module)
	end
	return base(context, module)
end
return TS

end]]
tsVariantCode = tsVariantCode:gsub("\n+", " "):gsub("`", "\n") -- ensure that line numbers align

local VariantStorage = {}
Variant.Storage = VariantStorage
VariantStorage.__index = VariantStorage
local variantStorageIsTemporaryScript = {} -- VariantStorage -> isTemporaryScript
local never = function() end
function VariantStorage.new(storage, isTemporaryScript)
	--	You can perform `for moduleScript, variant in storage.main do` on this class
	--	isTemporaryScript:function(moduleScript)->true if the script is temporary and should not invalidate other scripts
	--		It is assumed that a script can become non-temporary and so it is invoked as needed for each module script
	--		It defaults to assuming that scripts are never temporary
	local self = setmetatable({
		main = storage or {}, -- moduleScript -> Variant
	}, VariantStorage)
	variantStorageIsTemporaryScript[self] = isTemporaryScript or never
	return self
end
function VariantStorage:IsTSScript(fullName)
	return fullName == tsFullName
	-- return fullName == tsFullName or fullName == "TestService.TSStyle.TS" -- this line should only be enabled while testing dependencies for TS-style imports
end
function VariantStorage:Get(moduleScript)
	local main = self.main
	local variant = main[moduleScript]
	if not variant then
		variant = Variant.new(self, moduleScript)
		main[moduleScript] = variant
	end
	return variant
end
function VariantStorage:Remove(moduleScript) -- Should only be called by Variant:Destroy()
	self.main[moduleScript] = nil
end
function VariantStorage:Destroy()
	for _, variant in self.main do
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
		moduleScript = moduleScript or error("moduleScript mandatory", 2),
		required = false,
		-- variant:ModuleScript
		-- requireFinished:Event (only exists while requiring)
		-- requiredValue
		-- destroyed -- used to prevent Require from calling performRequire after destruction
		dependencies = {}, -- variant required by this one -> Invalidated connection
		dependentInvalidated = Event.new(), -- Normally ignored unless a Variant has ConnectAlwaysRefresh called on it
		-- alwaysRefreshCon: Connection,
		version = 0, -- increases whenever the variant changes
		Invalidated = Event.new(),
		SourceChanged = Event.new(),
	}, Variant)
	self.cons = {
		moduleScript:GetPropertyChangedSignal("Source"):Connect(function()
			self.SourceChanged:Fire()
			self:Invalidate()
		end),
		moduleScript.AncestryChanged:Connect(function(_, parent)
			if not parent then
				self:Destroy()
			else
				self:Invalidate()
			end
		end),
	}
	self.dependentInvalidated:Connect(function()
		-- This connection allows AlwaysRefresh scripts to invalidate themselves
		for variant in self.dependencies do
			variant:markDependentInvalidated()
		end
	end)
	return self
end
function Variant:Invalidate()
	if self.required or self.requireFinished then
		self.version += 1
		self.required = false
		self.requiredError = nil
		self.requiredErrorDuringRequire = nil
		self.incomingRequireError = nil
		if self.requireFinished then
			self.requireFinished:Destroy()
			self.requireFinished = nil
		end
		self:markDependentInvalidated()
		self:resetAllDependencies()
		table.clear(self.dependencies)
		self.Invalidated:Fire()
	end
end
function Variant:ForEachDependencyRecursive(fn, seen) -- fn also called on this Variant. fn can return true to break early. The whole function also returns true if `fn` does.
	seen = seen or {}
	seen[self] = true
	if fn(self) then return true end
	for variant in self.dependencies do
		if not seen[variant] then
			if variant:ForEachDependencyRecursive(fn, seen) then return true end
		end
	end
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
		for variant in self.dependencies do
			variant:PrintDependencies(seen, depth + 1)
		end
	end
end
function Variant:GetModuleScript() return self.moduleScript end
function Variant:IsRequired()
	return self.required
end
function Variant:neverReturn()
	-- We want to stop the current thread, so we'll yield and attempt to cancel it
	local co = coroutine.running()
	task.defer(task.cancel, co)
	coroutine.yield()
	-- The yield could return if something was referencing the coroutine and resumed it before it was cancelled
	error("(Thread attempted to require an expired variant of " .. self.moduleScript:GetFullName() .. "; the thread was resumed by something)")
end
function Variant:isTemporary()
	return variantStorageIsTemporaryScript[self.variantStorage](self.moduleScript)
end
function Variant:addDependency(moduleScript)
	local variant = self.variantStorage:Get(moduleScript)
	if variant ~= self --[[and not self.dependencies[variant] ]] then -- either condition could occur with circular requires
		-- Note: we actually want to support circular requires, and since calling Invalidate a 2nd time doesn't do anything, we can safely connect dependencies like this
		-- (If this was a problem, we would also want to check for longer circular require chains)
		self.dependencies[variant] = variant.Invalidated:Connect(function()
			if not variant:isTemporary() then
				self:Invalidate()
			end
		end)
	end
	return variant
end
function Variant:addDependencyAndRequire(moduleScript)
	local variant = self:addDependency(moduleScript)
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

local pluginErrHandlerDepth3 = PluginErrHandler.Gen(pluginName, nil, nil, nil, nil, 3, IsErrorFromPlugin)
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
	--		alreadyErrored can also be true if the ModuleScript doesn't return precisely 1 value
	--	Note: call this function in a 'try' and handle requireFinished:
	--		on finally: fire it (if it exists) and destroy & remove it (assuming self.version is unchanged)
	if self.required or self.requireFinished then
		if self.requireFinished then
			self.requireFinished:Wait()
		end
		if self.requiredError then
			return self.requiredErrorDuringRequire and "require" or true, self.requiredError
		end
		return false, self.requiredValue
	else
		self.requireFinished = Event.new()
		if self.variant then
			self.variant:Destroy()
		end
		local variant = Instance.new("ModuleScript")
		variant.Name = self.moduleScript:GetFullName()
		self.variant = variant
		local isTS = self.variantStorage:IsTSScript(variant.Name)
		if isTS then
			-- Disable the "multiple TS runtimes" check so we don't ever need to clear TS cache
			variant.Source = tsVariantCode:format((self.moduleScript.Source:gsub("if _G%[module%] then", "if false then")))
		else
			variant.Source = variantCode:format(self.moduleScript.Source)
		end
		local function handle(...)
			if select("#", ...) ~= 1 then
				self.requiredError = "Module code did not return exactly one value"
				return true, self.requiredError
			end
			return false, (...)
		end
		if isTS then
			local requiringVariant -- Set to a Variant in addDep, then cleared in the call to require. There should be 1 require call for every addDep (ignoring error cases).
			-- newRequire is identical to the standard case except that if requiringVariant, we want to *not* add dependencies
			local function newRequire(what)
				if self.destroyed or self.variant ~= variant then
					self:neverReturn()
				end
				if typeof(what) == "Instance" and what:IsA("ModuleScript") then
					if requiringVariant then
						local variant = self.variantStorage:Get(what)
						local val = requiringVariant
						requiringVariant = nil
						return variant:Require(nil, val)
					else
						return self:addDependencyAndRequire(what)
					end
				else
					error("TestRunnerPlugin does not support non-ModuleScript requires", 2)
				end
			end
			local function addDep(context, module)
				-- Because we pass in the moduleScript as script, context will be the real moduleScript
				requiringVariant = self.variantStorage:Get(context)
				requiringVariant:addDependency(module)
			end
			return handle(require(self.variant :: Instance)(self.moduleScript, newRequire, addDep))
		else
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
			return handle(require(self.variant :: Instance)(self.moduleScript, newRequire))
		end
	end
end
local continueUserErrorAddTraceback = PluginErrHandler.GenContinueUserErrorAddTraceback(pluginName)
function Variant:tryRequire(timeout, requiringVariant)
	if self.destroyed then -- Note: Roblox doesn't error if you require a destroyed ModuleScript, but we don't want to keep testing it
		self:neverReturn()
	end
	local v = self.version
	local errMsg -- set to what error message to return (if something goes wrong)
	local co = coroutine.running()
	NewTry(function(try)
		try
			:onSuccess(function(alreadyErrored, value)
				if v ~= self.version then self:neverReturn() end
				if alreadyErrored then
					errMsg = string.format("%s%s encountered an error while %s: %s",
						requiringVariant and "" or "(While determining if it's a test) ",
						alreadyErrored == "require" and GetModuleName(self.moduleScript) or self.moduleScript.Name, -- We don't need to use GetModuleName because self.requiredError (stored in value) is likely to specify that already
						alreadyErrored == "require" and "requiring" or "loading",
						value)
					if requiringVariant then
						requiringVariant.incomingRequireError = value
					end
					if not ErrorCoroutines.shouldIgnoreErrors(co) then
						pluginErrHandlerDepth3(errMsg, true)
					end
				else
					self.requiredValue = value
				end
			end)
			:onError(function(msg)
				if v ~= self.version then self:neverReturn() end
				local show = not ErrorCoroutines.shouldIgnoreErrors(co)
				-- As variants require each other, incomingRequireError will be nil for the first "top level" error, then true just long enough to pass the error backwards through the chain without emitting more red text
				if self.incomingRequireError then
					self.incomingRequireError = nil
					if show then
						continueUserErrorAddTraceback(debug.traceback("", 2))
					end
					errMsg = msg
						:gsub("^.-TestRunnerPlugin%.Variant:[^:]-:%s*(.*)", "%1")
						:gsub("StarterPlayer%.StarterPlayerScripts%.", "StarterPlayerScripts.")
						:gsub("StarterPlayer%.StarterCharacterScripts%.", "StarterCharacterScripts.")
					self.requiredError = errMsg
					self.requiredErrorDuringRequire = true
				elseif show then -- top level error
					PluginErrHandler.Gen(pluginName, function(niceErrMsg, msg, traceback)
						self.requiredError = niceErrMsg
						errMsg = niceErrMsg
					end, nil, nil, nil, 3, IsErrorFromPlugin)(msg)
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
	if self.requireFinished then self.requireFinished:Wait() end
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

function Variant:ConnectAlwaysRefresh() -- returns true if already connected
	if self.alwaysRefreshCon then return true end -- already connected
	self.alwaysRefreshCon = self.dependentInvalidated:Connect(function()
		self:Invalidate()
	end)
end
function Variant:DisconnectAlwaysRefresh()
	if not self.alwaysRefreshCon then return true end
	self.alwaysRefreshCon:Disconnect()
	self.alwaysRefreshCon = nil
end
function Variant:markDependentInvalidated() -- will trigger dependentInvalidated on the entire tree of dependencies used by this variant
	if self.dependentInvalidatedRecently then return end
	self.dependentInvalidatedRecently = true
	task.defer(function()
		self.dependentInvalidatedRecently = false
	end)
	self.dependentInvalidated:Fire()
end

function Variant:resetAllDependencies()
	for variant, con in self.dependencies do
		con:Disconnect()
	end
end
function Variant:IsDestroyed()
	return self.destroyed
end
function Variant:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.variantStorage:Remove(self.moduleScript)
	self:Invalidate() -- this changes version and destroys requireFinished as needed
	if self.variant then
		self.variant:Destroy()
	end
	self.Invalidated:Destroy()
	self.SourceChanged:Destroy()
	self.dependentInvalidated:Destroy()
	self:resetAllDependencies()
	self:DisconnectAlwaysRefresh()
	for _, con in self.cons do
		con:Disconnect()
	end
end
return Variant