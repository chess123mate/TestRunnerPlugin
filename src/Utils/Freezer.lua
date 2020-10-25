-- Freezer: Freezes arbitrary actions while the user is looking at a script
--	Used to prevent a test the user is editing from requiring after every key-press
local StudioService = game:GetService("StudioService")
local stepped = game:GetService("RunService").Stepped
local Freezer = {}
Freezer.__index = Freezer
function Freezer.new(enabled)
	--	enabled defaults to true
	return setmetatable({
		enabled = enabled ~= nil,
	}, Freezer)
end
function Freezer:Disable()
	self.enabled = false
	if self.freezeCon then
		self:reEvalFreeze()
	end
end
function Freezer:Enable()
	self.enabled = true
end
function Freezer:SetEnabled(enabled)
	if self.enabled == enabled then return end
	self.enabled = enabled
	if not enabled and self.freezeCon then
		self:reEvalFreeze()
	end
end
function Freezer:ShouldFreeze()
	if self.enabled then
		local active = StudioService.ActiveScript
		return active and active:IsA("ModuleScript")
	end
	return false
end
function Freezer:RunWhenNotFreezing(key, func)
	if self:ShouldFreeze() then
		self:Freeze(key, func)
	else
		func(key)
	end
end
function Freezer:Freeze(key, func)
	local t = self.freezeTable
	if not t then
		t = {}
		self.freezeTable = t
	end
	t[key] = func
	if not self.freezeCon then
		self.freezeCon = stepped:Connect(function()
			self:reEvalFreeze()
		end)
	end
end
function Freezer:reEvalFreeze()
	if not self:ShouldFreeze() then
		self.freezeCon:Disconnect()
		self.freezeCon = nil
		local t = self.freezeTable
		self.freezeTable = {}
		for key, func in pairs(t) do
			func(key)
		end
	end
end
function Freezer:Destroy()
	if self.freezeCon then
		self.freezeCon:Disconnect()
	end
end
return Freezer