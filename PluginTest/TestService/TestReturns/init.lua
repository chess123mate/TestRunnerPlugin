return function(tests, t)
	function tests.returnNilWorks()
		t.falsy(require(script.ReturnNil))
	end
	function tests.returnNothingErrors()
		t.errors(function()
			require(script.ReturnNothing :: Instance)
		end)
	end
end