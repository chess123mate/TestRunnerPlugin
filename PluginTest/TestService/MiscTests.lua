wait()
return function(tests, t)
	wait()
	--tests.skip = {"My Test"}
	tests["My Test"] = {
		setup = function(a, b)
			--print(a, b)
			--error("setup")
			return true
		end,
		cleanup = function(obj, a, b)
			--print(obj, a, b)
			--error("cleanup")
		end,
		test = function(obj, a, b)
			--error("in test")
			--t.equals(a, b)
		end,
		argsLists = {
			{name="first", 1, 1},
			{2, 3},
			{name="third", 5, 9},
			{5,5},
		}
	}
	--[[
	function tests.yo()
		wait(6)
	end
	--]]
end