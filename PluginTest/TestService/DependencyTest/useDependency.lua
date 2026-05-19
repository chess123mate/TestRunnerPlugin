local module = require(script.Parent.dependency)
local module2 = require(script.Parent.dependency2)

return function(tests, t)


function tests.ver()
	t.equals(module.GetVersion(), 1)
end
function tests.ver10()
	t.equals(module2.GetVersion10(), 10)
end
function tests.valueShouldBe1()
	t.equals(module.GetValue(), 1)
	t.equals(module2.GetValue10(), 10)
end


end