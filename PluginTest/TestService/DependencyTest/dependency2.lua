local module = require(script.Parent.dependency)
local module2 = {
	m2Ver = 0 -- modifying this will cause the unit tests to fail since module's Value will increment
}
function module2.GetVersion10() return module.GetVersion() * 10 end
function module2.GetValue10() return module.GetValue() * 10 end
module.SetValue(module.GetValue() + 1)
return module2