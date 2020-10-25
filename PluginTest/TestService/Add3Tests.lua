local Add3 = require(game.ServerScriptService.Add3)
return function(tests, t)

tests.Simple = function()
	t.equals(Add3(1, 2, 3), 6)
end
tests.NoArgs = function()
	t.equals(Add3(), 0)
end
tests.OneArg = function()
	t.equals(Add3(5), 5)
end

end