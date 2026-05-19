local module = require(script.Parent.dependency)
local module2 = {}
function module2.GetVersion10() return module.GetVersion() * 10 end
function module2.GetValue10() return module.GetValue() * 10 end
module.SetValue(module.GetValue() + 1)
return module2