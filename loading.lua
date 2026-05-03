--[[ AnimeCrusadersHub loading screen
Экспорт: _G.ACH_Loading = { ScreenGui, Dismiss() }
]]
local CoreGui      = game:GetService("CoreGui")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local LocalPlayer  = Players.LocalPlayer

for _, g in ipairs(CoreGui:GetChildren()) do
	if g.Name == "ACHLoading" then pcall(function() g:Destroy() end) end
end

local THEME = {
	BG     = Color3.fromRGB(10, 10, 14),
	STROKE = Color3.fromRGB(80, 0, 80),
	ACCENT = Color3.fromRGB(200, 60, 220),
}

local function new(class, props, children)
	local ok, o = pcall(Instance.new, class)
	if not ok or not o then return Instance.new("Frame") end
	for k, v in pairs(props or {}) do pcall(function() o[k] = v end) end
	for _, c in ipairs(children or {}) do
		if c then pcall(function() c.Parent = o end) end
	end
	return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end
local function stroke(col, t, trans)
	return new("UIStroke", {
		Color = col or THEME.STROKE, Thickness = t or 1, Transparency = trans or 0,
	})
end
local function tween(obj, time, props)
	local t = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad), props)
	t:Play(); return t
end

local ScreenGui = new("ScreenGui", {
	Name = "ACHLoading", ResetOnSpawn = false,
	IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local okMount = pcall(function() ScreenGui.Parent = CoreGui end)
if not okMount then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local Loading = new("Frame", {
	Parent = ScreenGui, Name = "Loading",
	Size = UDim2.fromOffset(380, 200),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = THEME.BG,
	BorderSizePixel = 0,
}, {
	corner(8),
	stroke(THEME.STROKE, 1),
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 0, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 0, 14)),
		}),
	}),
})

new("Frame", {
	Parent = Loading, BorderSizePixel = 0,
	BackgroundColor3 = THEME.ACCENT,
	Size = UDim2.new(1, 0, 0, 12),
})

new("TextLabel", {
	Parent = Loading, BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 28),
	Position = UDim2.fromOffset(0, 45),
	Font = Enum.Font.GothamBold, TextSize = 20,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "AnimeCrusadersHub is loading",
})

local spinner = new("Frame", {
	Parent = Loading, BackgroundColor3 = THEME.ACCENT,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(40, 40),
	Position = UDim2.new(0.5, -20, 0, 105),
	AnchorPoint = Vector2.new(0, 0),
}, { corner(20) })

local spinning = true
task.spawn(function()
	local rot = 0
	while spinning do
		rot = (rot + 6) % 360
		if spinner and spinner.Parent then spinner.Rotation = rot end
		RunService.RenderStepped:Wait()
	end
end)

local dismissed = false
local function Dismiss()
	if dismissed then return end
	dismissed = true; spinning = false
	pcall(function()
		tween(Loading, 0.4, { BackgroundTransparency = 1 })
		for _, d in ipairs(Loading:GetDescendants()) do
			if d:IsA("TextLabel") then tween(d, 0.4, { TextTransparency = 1 }) end
			if d:IsA("Frame")     then tween(d, 0.4, { BackgroundTransparency = 1 }) end
			if d:IsA("UIStroke")  then tween(d, 0.4, { Transparency = 1 }) end
		end
	end)
	task.wait(0.45)
	pcall(function() ScreenGui:Destroy() end)
end

_G.ACH_Loading = { ScreenGui = ScreenGui, Dismiss = Dismiss }
