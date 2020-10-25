local Descriptions = {}
function Descriptions.Describe(x) -- Describe an arbitrary object is a bit nicer format than tostring
	local t = typeof(x)
	if t == "string" then
		return ('"%s"'):format(x)
	elseif t == "table" then
		-- roblox outputs "table: " then 16 hex digits; only last 8 are remotely useful in most cases
		local mt = getmetatable(x)
		return mt and mt.__tostring and tostring(x) or ("'table %s'"):format(tostring(x):sub(-8))
	elseif t == "Instance" then
		return ("'Instance %s'"):format(x:GetFullName())
	else
		return tostring(x)
	end
end
local stopAtClassNames = {
	TestService = true,
	DataModel = true,
}
function Descriptions.GetModuleName(m) -- Variant of :GetFullName()
	local path = {m}
	local parent = m.Parent
	while parent and not stopAtClassNames[parent.ClassName] do
		path[#path + 1] = parent
		parent = parent.Parent
	end
	local name = {}
	for i = #path, 1, -1 do
		name[#name + 1] = path[i].Name
	end
	return table.concat(name, ".")
end
return Descriptions