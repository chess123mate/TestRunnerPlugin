-- Variant Tests (without using Testing Framework)
return {function() -- wrap the function in a table to avoid detection by the TestRunnerPlugin
local modules = game.ServerStorage.TestRunnerPlugin
local progress = 0
spawn(function()
	if not progress then
		print("Variant tests successful")
	elseif progress ~= -1 then
		error("Variant tests got stuck at progress " .. tostring(progress))
	end
end)
local function assertEquals(name, a, b)
	if a ~= b then
		progress = -1
		error(("%s: %s ~= %s"):format(name, tostring(a), tostring(b)), 2)
	end
end
local Variant = require(modules.Variant)
local x = Instance.new("ModuleScript")
x.Source = [[return {var=3}]]

progress = 1
local storage = Variant.Storage.new()
local variant = storage:Get(x)
assertEquals("Variant.Storage:Get same return", storage:Get(x), variant)
assertEquals("variant.variantStorage == storage", variant.variantStorage, storage)

progress = 2
local val = variant:Require()
assertEquals("Require correct", type(val), "table")
assertEquals("Require correct", val.var, 3)

-- 2nd require shouldn't hurt anything
progress = 3
assertEquals("2nd require consistent", variant:Require(), val)

local fired
variant.Invalidated:Connect(function()
	fired = true
end)

progress = 4
x.Source = [[return {var=4}]]
assertEquals("Invalidated fired", fired, true)
assertEquals("Source updating works", variant:Require().var, 4)

progress = 5
assertEquals("Variant not IsDestroyed", not variant:IsDestroyed(), true)
variant:Destroy()
assertEquals("Variant IsDestroyed after Destroy", variant:IsDestroyed(), true)
assertEquals("Variant.Storage does not contain destroyed variant", storage[x], nil)

progress = nil
end}