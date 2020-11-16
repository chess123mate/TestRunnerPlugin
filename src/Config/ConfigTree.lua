-- ConfigTree: manages a configuration for values when one value's config can override the config of another
local ConfigTree = {}
ConfigTree.__index = ConfigTree
function ConfigTree.new(default, getParent)
	local self = setmetatable({
		default = default
			and (type(default) == "table" and default or error("default config must be a table"))
			or {},
		valueToConfig = {},
		getParent = getParent or function(value) return value.Parent end,
	}, ConfigTree)
	return self
end
function ConfigTree:GetFor(value)
	local valueToConfig = self.valueToConfig
	local configs = {}
	local n = 0
	while value do
		local config = valueToConfig[value]
		if config then
			n += 1
			configs[n] = config
		end
		value = self.getParent(value)
	end
	n += 1
	configs[n] = self.default
	-- now compile configs
	local e = {} -- effective config
	for i = n, 1, -1 do
		for k, v in pairs(configs[i]) do
			e[k] = v
		end
	end
	return e
end
function ConfigTree:GetOriginatingValueForKey(value, key)
	--	Returns the value that is associated with the config that provided the specified key for "value"'s config (returns nil if it came from the default)
	local valueToConfig = self.valueToConfig
	while value do
		local config = valueToConfig[value]
		if config and config[key] then
			return value
		end
		value = self.getParent(value)
	end
	return nil
end
function ConfigTree:SetConfig(value, config)
	self.valueToConfig[value] = config
end
return ConfigTree