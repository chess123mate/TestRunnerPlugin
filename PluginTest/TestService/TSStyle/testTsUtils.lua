local tsUtils = require(script.Parent.TS).import(script, script.Parent.tsUtils)
return function(tests, t)

function tests.add()
	t.equals(tsUtils.add(1, 2), 3)
end


end