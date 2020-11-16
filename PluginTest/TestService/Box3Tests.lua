local Box3 = require(game.ServerScriptService.Box3)
return function(tests, t)

--tests.focus = {"Simple"}
tests.Simple = function()
	local b = Box3.new(1, 2, 3)
	t.equals(b.Sum, 6)
end
tests.NoArgs = function()
	local b = Box3.new()
	t.equals(b.Sum, 0)
end
tests.UpdateAllNums = function()
	local b = Box3.new()
	b:SetNums(10, 5, -4)
	t.equals(b.Sum, 11)
end
local function failNow()
	t.fail("now")
end
tests.UpdateOneNum = function()
	local b = Box3.new(1, 2, 3)
	b:SetNums(nil, nil, 30)
	--failNow()
	t.equals(b.Sum, 33)
end

end