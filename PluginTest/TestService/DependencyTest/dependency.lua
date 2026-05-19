local module = {}
local v = 0
local ver = 1
function module.GetValue() return v end
function module.SetValue(value) v = value end
function module.GetVersion() return ver end
return module