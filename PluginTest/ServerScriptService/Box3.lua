local Add3 = require(script.Parent.Add3)

local Box3 = {}
Box3.__index = Box3
function Box3.new(a, b, c)
	local self = setmetatable({
		-- Sum:number
		a = a,
		b = b,
		c = c,
	}, Box3)
	self:updateSum()
	return self
end
function Box3:updateSum()
	self.Sum = Add3(self.a, self.b, self.c)
end
function Box3:SetNums(newA, newB, newC)
	self.a = newA or self.a
	self.b = newB or self.b
	self.c = newC or self.c
	self:updateSum()
end

return Box3