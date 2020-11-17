-- Let's make a Bucket class for testing.
--	It can have contents added to it and it has an event when it gets filled to capacity.
local Bucket = {}
Bucket.__index = Bucket
function Bucket.new(capacity)
	local filled = Instance.new("BindableEvent")
	return setmetatable({
		capacity = capacity or error("capacity required", 2),
		contents = 0,
		filled = filled,
		Filled = filled.Event,
	}, Bucket)
end
function Bucket:GetContents() return self.contents end
function Bucket:IsFull() return self.contents == self.capacity end
function Bucket:Add(amount)
	--	Returns amount added
	if amount < 0 then error("amount must not be negative", 2) end
	local room = self.capacity - self.contents
	amount = math.min(amount, room)
	if amount == 0 then return 0 end
	self.contents += amount
	if self.contents == self.capacity then
		self.filled:Fire()
	end
	return amount
end
function Bucket:EmptyAll()
	--	Returns amount emptied
	local contents = self.contents
	self.contents = 0
	return contents
end
function Bucket:Destroy()
	self.filled:Destroy()
end

-- Normally the Bucket class would be in a different module, so the test file would start after the following line (with the require line enabled).
-- Because of this, I skip the indent after "return function(tests, t)" (just remember to have an 'end' at the bottom of the file!)
-- Note: you may place your require lines after "return function(tests, t)", it won't make a difference.
-----------------------------------------
-- local Bucket = require(game.ReplicatedStorage.Bucket)
return function(tests, t)

-- Assign your tests directly to the 'tests' dictionary.
-- Use "t" (short for "test that") to make assertions.
--	See the TestRunner script for documentation on the available assertions.

function tests.addWorks()
	-- Let's create the bucket. Since it has a Destroy function, it's good practice to destroy it when we're done.
	--	But if we just call bucket:Destroy() at the end of our test, it won't get run if our test fails!
	-- 	We can use t.cleanup (but see setup & cleanup notes below) to ensure Destroy will definitely be called after the test is done.
	local bucket = t.cleanup(Bucket.new(5)) -- t.cleanup returns whatever is given to it
	-- t.cleanup can take instances, functions, event connections, and tables that have either Destroy or Disconnect defined on them.
	
	-- Now let's test the bucket.
	-- By default, the 'actual' value comes first, then the 'expected'. You can change this in a TestConfig with 'expectedFirst = true'.
	t.equals(bucket:Add(3), 3, "add returns amount filled") -- extra arguments to most comparisons are assumed to be descriptions (you can send more than one, like in a print statement)
	t.equals(bucket:Add(3), 2, "add does not fill past capacity")
	-- Note that you can also error at any time to cause a test case to fail.
end

tests["filled fired correctly"] = {
	-- Tests can be tables with the following fields (all optional except 'test'):
	setup = function() return Bucket.new(5) end,
	cleanup = function(bucket) bucket:Destroy() end,
	-- You can also use the arguments sent to 'test' in setup & cleanup:
	-- setup = function(amount, shouldBeFilled) return Bucket.new(5) end,
	-- cleanup = function(bucket, amount, shouldBeFilled) bucket:Destroy() end,
	--[[Notes:
		cleanup is not guaranteed to be run right away (but it is guaranteed to run if setup completes)
		cleanup is only valid if setup is defined
		Compared to t.cleanup, you should prefer to use setup & cleanup functions, as they run slightly faster and correctly fail the test if an error comes up.
	]]
	test = function(bucket, amount, shouldBeFilled) -- The first argument of a test is from setup (if setup is defined), the rest come from args/argsLists
		--	shouldBeFilled: nil or true
		local filled
		bucket.Filled:Connect(function()
			filled = true
		end)
		bucket:Add(amount)
		t.equals(filled, shouldBeFilled)
	end,
	-- 'args' is useful when you only need to send a single argument
	args = {0, 1, 2, 3, 4}, -- each item in 'args' is a different test case
	-- You can also name cases (though order is then not guaranteed)
	-- args = {emptyCase = 0, 1, 2, 3, almostFull = 4},
	
	-- 'argsLists' is useful for 2+ arguments or when you want to maintain order with named cases
	-- Each item must be the list of arguments to send to the test
	argsLists = {
		{5, true},
		-- You can name them with a 'name' or 'Name' key:
		{name = "over-full case", 6, true},
		notQuiteFull = {4.9},
		-- Note that you should avoid 'nil' values in the list, to ensure that none get lost
		-- ex, in {nil, 3}, the '3' might not be sent
	},
	-- skip = true, -- This would skip running this test
	-- focus = true, -- This would prevent non-focus tests in this module from running
}

-- Instead of specifying skip/focus throughout the test file, it is recommended to have that configured at the top.
-- For illustration, here's a test we want to skip:
function tests.testToSkip()
	error("Unfinished or problematic test")
end
tests.skip = {
	-- We can use either of these formats to skip it:
	"testToSkip",
	-- testToSkip = true,
}
-- tests.focus uses the same format and takes precedence over skipping.

-- Let's keep testing.
-- Since we need more tests with buckets, let's make a helper function:
local function newBucketTest(name, test)
	if type(test) == "function" then test = {test = test} end
	test.setup = function() return Bucket.new(5) end
	test.cleanup = function(bucket) bucket:Destroy() end
	tests[name] = test
end

newBucketTest("filledIgnoresExtraAdds", function(bucket)
	local filled = 0
	bucket.Filled:Connect(function()
		filled += 1
	end)
	bucket:Add(5)
	bucket:Add(5)
	t.equals(filled, 1)
end)

newBucketTest("filledWorksAfterEmptying", function(bucket)
	local filled = 0
	bucket.Filled:Connect(function()
		filled += 1
	end)
	bucket:Add(5)
	bucket:EmptyAll()
	bucket:Add(5)
	t.equals(filled, 2)
end)

newBucketTest("otherGetFunctionsWork", function(bucket)
	-- (Better testing practice would have these in different tests, but for illustration...)
	bucket:Add(5)
	-- Though it's unnecessary here, sometimes it's beneficial to test multiple aspects of something before erroring.
	-- You can do that with a "multi" test:
	t.multi("bucket is full", function(m)
		-- 'm' is identical to 't' except all comparisons must start with a name argument
		m.equals("IsFull", bucket:IsFull(), true)
		m.equals("GetContents", bucket:GetContents(), 5)
		-- If either of those tests fail, the report will include the values of "IsFull" and "GetContents", one per line (with ">>>" in front of those that failed).
		-- It is acceptable to nest multi-tests.
	end)
	t.equals(bucket:EmptyAll(), 5, "EmptyAll returns what was emptied")
	t.multi("empty bucket works", function(m)
		m.equals("IsFull", bucket:IsFull(), false)
		m.equals("GetContents", bucket:GetContents(), 0)
	end)
end)

function tests.constructorErrorsWhenMissingArgs()
	t.errorsWith("capacity", Bucket.new)
end

newBucketTest("addErrorsWithIncorrectArgs", function(bucket)
	t.errorsWith("amount", function()
		bucket:Add(-1)
	end)
end)

function tests.otherAvailableFunctions()
	-- In your tests, you can also use:
	-- t.describe(arg) -- returns a string description of 'arg' in a handy fashion (ex puts quotes around strings, shortens tables, uses GetFullName on instances)
	--	t.describe is often counter-productive if you use Roblox's Expressive Output Window
	-- t.actualNotExpected(a, op, b, ...) -- generates an "actual ~= expected" string but using 'a', 'op', and 'b'. Switches based on whether 'actual' is expected to be first/second (any '...' args are appended to the message)
end

end -- ends "return function(tests, t)"