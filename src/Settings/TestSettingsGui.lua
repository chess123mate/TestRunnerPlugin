local function create(class, props, ...)
	local x = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			x[k] = v
		end
	end
	for _, child in ipairs({...}) do
		child.Parent = x
	end
	return x
end
local function createText(class, props, ...)
	--	same as create but sets the font to SourceSans since Legacy is the default for some reason
	props = props or {}
	props.Font = props.Font or Enum.Font.SourceSans
	return create(class, props, ...)
end
local u2 = UDim2.new
--local function square(p) return u2(0, p, 0, p) end
local function offset(x, y) return u2(0, x, 0, y) end

local studio = settings().Studio
local function connectCallUpdateTheme(func)
	local conFunc = function()
		func(studio.Theme)
	end
	conFunc()
	return studio.ThemeChanged:Connect(conFunc)
end

local function listLayout(fillDir, props)
	--	all arguments optional
	--	you can also call listLayout(props)
	if type(fillDir) == "table" then props = fillDir; fillDir = nil end -- shift args
	props = props or {}
	props.FillDirection = props.FillDirection or fillDir -- defaults to Vertical
	props.SortOrder = props.SortOrder or "LayoutOrder"
	return create("UIListLayout", props)
end
local labelPaddingUDim = UDim.new(0, 3)
local labelPadding = create("UIPadding", {
	PaddingBottom = labelPaddingUDim,
	PaddingLeft = labelPaddingUDim,
	PaddingRight = labelPaddingUDim,
	PaddingTop = labelPaddingUDim,
})

local Checkbox = {}
Checkbox.__index = Checkbox
function Checkbox.new(value, height, checkboxHeight, descContent) -- desc, value, height, checkboxHeight)
	--	descContent must have :GetInstance and :Destroy. It must update its own theme if needed.
	--		It should have a size of UDim2.new(1, -height, 0, height)
	height = height or 25
	checkboxHeight = checkboxHeight or height
	local instance = createText("TextButton", {
		Text = "",
		Size = u2(1, 0, 0, height),
	},
		listLayout("Horizontal", {VerticalAlignment = "Center"}),
		createText("TextLabel", {
			Size = offset(checkboxHeight, checkboxHeight),
			Text = value and "X" or "",
			TextScaled = true,
		}),
		descContent:GetInstance())
	local box = instance.TextLabel
	local boxNormal, boxSelected
	local function updateBoxBG()
		box.BackgroundColor3 = box.Text == "X" and boxSelected or boxNormal
	end
	instance.MouseButton1Click:Connect(function()
		box.Text = box.Text == "X" and "" or "X"
		updateBoxBG()
	end)
	return setmetatable({
		instance = instance,
		box = box,
		ValueChanged = box:GetPropertyChangedSignal("Text"),
		descContent = descContent,
		con = connectCallUpdateTheme(function(theme)
			-- The below theme colours are consistent with what the Properties window uses
			instance.BackgroundColor3 = theme:GetColor("TableItem")
			instance.BorderColor3 = theme:GetColor("Border")
			boxNormal = theme:GetColor("CheckedFieldBackground")
			boxSelected = theme:GetColor("CheckedFieldBackground", "Selected")
			updateBoxBG()
			box.BorderColor3 = theme:GetColor("CheckedFieldBorder")
			box.TextColor3 = theme:GetColor("CheckedFieldIndicator")
		end),
		updateBoxBG = updateBoxBG,
	}, Checkbox)
end
function Checkbox:Destroy()
	self.instance:Destroy()
	self.descContent:Destroy()
	self.con:Disconnect()
end
function Checkbox:GetInstance()
	return self.instance
end
function Checkbox:GetValue()
	return self.box.Text == "X"
end
function Checkbox:SetValue(value)
	self.box.Text = value and "X" or ""
	self.updateBoxBG()
end

local SettingsCheckboxDesc = {}
SettingsCheckboxDesc.__index = SettingsCheckboxDesc
function SettingsCheckboxDesc.new(name, desc, checkboxWidth, height, maxDescTextSize)
	local padding = labelPadding:Clone()
	padding.PaddingLeft = UDim.new(0, labelPaddingUDim.Offset * 2)
	local instance = createText("TextLabel", {
		Size = u2(1, -(checkboxWidth or 25), 0, height),
		BackgroundTransparency = 1,
		Text = ("%s - %s"):format(name, desc),
		TextXAlignment = "Left",
		TextScaled = true,
	},
		padding,
		create("UITextSizeConstraint", {MaxTextSize = maxDescTextSize})
	)
	return setmetatable({
		instance = instance,
		con = connectCallUpdateTheme(function(theme)
			-- BrightText is what the Properties window uses
			instance.TextColor3 = theme:GetColor("BrightText")
		end),
	}, SettingsCheckboxDesc)
end
function SettingsCheckboxDesc:Destroy()
	self.instance:Destroy()
	self.con:Disconnect()
end
function SettingsCheckboxDesc:GetInstance() return self.instance end

local TestSettingsGui = {}
TestSettingsGui.__index = TestSettingsGui
function TestSettingsGui.new(testSettings)
	local rowHeight = 60
	local maxDescTextSize = 20
	--local titleHeight = 30
	local checkboxSize = 25
	local rowPadding = 0

	local rows = {}
	local optionKeyToCheckbox = {}
	for i, option in ipairs(testSettings.Options) do
		local desc = SettingsCheckboxDesc.new(option.Name, option.Desc, checkboxSize, rowHeight, maxDescTextSize)
		local cb = Checkbox.new(nil, rowHeight, checkboxSize, desc)
		local row = cb:GetInstance()
		rows[i] = row
		row.BorderSizePixel = 0
		create("UIPadding", {PaddingLeft = UDim.new(0, labelPaddingUDim.Offset * 2)}).Parent = row
		optionKeyToCheckbox[option.Key] = cb
		cb.ValueChanged:Connect(function()
			testSettings:SetOne(option.Key, cb:GetValue())
		end)
	end
	
	local padding = labelPadding:Clone()
	padding.PaddingLeft = UDim.new(0, labelPaddingUDim.Offset * 2)
	local instance = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, 0), -- -titleHeight),
		CanvasSize = UDim2.new(0, 0, 0, #rows * (rowHeight + rowPadding) - rowPadding + labelPaddingUDim.Offset * 2),
		VerticalScrollBarInset = "ScrollBar",
	},
		create("Frame", {
			Size = UDim2.new(1, 0, 1, 0),
			BorderSizePixel = 0,
		},
			listLayout({Padding = UDim.new(0, rowPadding)}),
			padding,
			unpack(rows)
		)
	)
	-- local instance = create("Frame", {
	-- 	Size = UDim2.new(1, 0, 1, 0),
	-- },
	-- 	listLayout(),
	-- 	createText("TextLabel", {
	-- 		Text = "Test Runner User Settings",
	-- 		Size = UDim2.new(1, 0, 0, titleHeight),
	-- 		TextScaled = true,
	-- 		BackgroundTransparency = 1
	-- 	}, labelPadding:Clone()),
	-- 	-- sf
	-- )
	local self = setmetatable({
		testSettings = testSettings,
		instance = instance,
		optionKeyToCheckbox = optionKeyToCheckbox,
		con = connectCallUpdateTheme(function(theme)
			instance.BackgroundColor3 = theme:GetColor("ScrollBarBackground")
			instance.BorderColor3 = theme:GetColor("Border")
			instance.ScrollBarImageColor3 = theme:GetColor("ScrollBar")
			instance.Frame.BackgroundColor3 = theme:GetColor("MainBackground")
		end)
	}, TestSettingsGui)
	self:Update()
	return self
end
function TestSettingsGui:Destroy()
	self.instance:Destroy()
	for _, cb in pairs(self.optionKeyToCheckbox) do
		cb:Destroy()
	end
	self.con:Disconnect()
end
function TestSettingsGui:GetInstance() return self.instance end
function TestSettingsGui:Update()
	local testSettings = self.testSettings:Get()
	local optionKeyToCheckbox = self.optionKeyToCheckbox
	for key, value in pairs(testSettings) do
		optionKeyToCheckbox[key]:SetValue(value)
	end
end

return TestSettingsGui