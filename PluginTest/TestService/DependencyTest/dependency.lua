-- local module2 = require(script.Parent.dependency2) -- enable for example of recursive require (which should have a dedicated error message)
local module = {}
local v = 0
local ver = 1 -- modifying this (to 1) makes the unit tests pass
function module.GetValue() return v end
function module.SetValue(value) v = value end
function module.GetVersion() return ver end
return module