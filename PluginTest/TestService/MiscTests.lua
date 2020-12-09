--wait()
--do return true end
return function(tests, t)
--	wait()
	tests.skip = {"NestedMulti"}
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
	function tests.NestedMulti()
		t.multi("Outer", function(m)
			m.multi("Inner", function(m)
				m.equals("one", 1, 2)
				m.equals("three", 3, 3)
			end)
			m.equals("two", 2, 2)
			m.equals("four", 4, 4)
		end)
	end
end