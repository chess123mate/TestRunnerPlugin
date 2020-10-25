local Module = {Add = function(a, b) return (a or error("Missing first argument")) + (b or error("Missing second argument")) end}
return function(tests, t)

function tests.simpleTest()
	t.equals(Module.Add(1, 1), 2)
end

tests.complexTest = { -- Tests can be a table with the following fields (all optional except 'test'):
	test = function(a, b, expected)
		t.equals(Module.Add(a, b), expected)
	end,
	argsLists = {
		{name="simple", 1, 2, 3},
		{name="negatives", 1, -2, -1},
		{name="zero", 0, 0, 0},
	},
}

tests.ensureErrorsWhenMissingArgs = {
	test = function(a, b)
		t.errorsWith("Missing ", function()
			Module.Add(a, b)
		end)
	end,
	argsLists = {
		{false, 3}, -- Note: best to avoid using 'nil' in these lists
		{3},
		{},
	}
}

end