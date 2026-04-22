--[[ BloodyHub loading screen
     Экспорт: _G.BloodyHub_Loading = { ScreenGui, Dismiss() }
]]
local CoreGui      = game:GetService("CoreGui")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local LocalPlayer  = Players.LocalPlayer

-- Чистим старый лоадер, если остался
for _, g in ipairs(CoreGui:GetChildren()) do
    if g.Name == "BloodyHubLoading" then pcall(function() g:Destroy() end) end
end

local THEME = {
    BG     = Color3.fromRGB(10, 10, 10),
    STROKE = Color3.fromRGB(74, 0, 0),
}

local function new(class, props, children)
    local ok, o = pcall(Instance.new, class)
    if not ok or not o then return Instance.new("Frame") end
    for k, v in pairs(props or {}) do pcall(function() o[k] = v end) end
    for _, c in ipairs(children or {}) do
        if c and typeof(c) ~= "table" then pcall(function() c.Parent = o end) end
    end
    return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end
local function stroke(col, t, trans)
    return new("UIStroke", {
        Color = col or THEME.STROKE, Thickness = t or 1, Transparency = trans or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end
local function tween(obj, time, props)
    local t = TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad), props)
    t:Play()
    return t
end

local ScreenGui = new("ScreenGui", {
    Name = "BloodyHubLoading",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
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
            ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 0, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 0, 0)),
        }),
    }),
})

new("Frame", {
    Parent = Loading, BorderSizePixel = 0,
    BackgroundColor3 = Color3.fromRGB(140, 0, 0),
    Size = UDim2.new(1, 0, 0, 12),
}, {
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.25, 0),
            NumberSequenceKeypoint.new(0.5, 0.5),
            NumberSequenceKeypoint.new(0.75, 0),
            NumberSequenceKeypoint.new(1, 0.2),
        }),
    }),
})

new("TextLabel", {
    Parent = Loading, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 28),
    Position = UDim2.fromOffset(0, 45),
    Font = Enum.Font.GothamBold, TextSize = 20,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Text = "BloodyHub is loading",
})

local knife = new("ImageLabel", {
    Parent = Loading, BackgroundTransparency = 1,
    Size = UDim2.fromOffset(60, 60),
    Position = UDim2.new(0.5, -30, 0, 100),
    Image = "rbxassetid://6031075938",
    ImageColor3 = Color3.fromRGB(255, 60, 60),
})

local trails = {}
for i = 1, 3 do
    local t = knife:Clone()
    t.Parent = Loading
    t.ImageTransparency = 0.4 + i * 0.15
    t.ZIndex = knife.ZIndex - i
    table.insert(trails, t)
end

local spinning = true
task.spawn(function()
    local rot = 0
    while spinning do
        rot = (rot + 6) % 360
        if knife and knife.Parent then knife.Rotation = rot end
        for i, t in ipairs(trails) do
            if t and t.Parent then t.Rotation = rot - i * 14 end
        end
        RunService.RenderStepped:Wait()
    end
end)

local dismissed = false
local function Dismiss()
    if dismissed then return end
    dismissed = true
    spinning = false
    pcall(function()
        tween(Loading, 0.5, { BackgroundTransparency = 1 })
        for _, d in ipairs(Loading:GetDescendants()) do
            if d:IsA("TextLabel") then tween(d, 0.5, { TextTransparency = 1 }) end
            if d:IsA("ImageLabel") then tween(d, 0.5, { ImageTransparency = 1 }) end
            if d:IsA("Frame") then tween(d, 0.5, { BackgroundTransparency = 1 }) end
            if d:IsA("UIStroke") then tween(d, 0.5, { Transparency = 1 }) end
        end
    end)
    task.wait(0.5)
    pcall(function() ScreenGui:Destroy() end)
end

_G.BloodyHub_Loading = {
    ScreenGui = ScreenGui,
    Dismiss   = Dismiss,
}