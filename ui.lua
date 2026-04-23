--[[ BloodyHub UI v1
- Строит главное окно с вкладками
- Кнопки вызывают _G.BloodyHub_API.*
- В конце прячет loading screen
]]
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputSvc = game:GetService("UserInputService")
local CoreGui      = game:GetService("CoreGui")
local LocalPlayer  = Players.LocalPlayer

local API = _G.BloodyHub_API or {}
local function safeCall(fn, ...) if type(fn) == "function" then pcall(fn, ...) end end

-- Чистим старое окно, если осталось
for _, g in ipairs(CoreGui:GetChildren()) do          -- ИСПРАВЛЕНО: * → _
    if g.Name == "BloodyHub" then pcall(function() g:Destroy() end) end
end

local THEME = {
    BG         = Color3.fromRGB(10, 10, 10),
    PANEL      = Color3.fromRGB(16, 16, 16),
    PANEL_ALT  = Color3.fromRGB(22, 22, 22),
    STROKE     = Color3.fromRGB(74, 0, 0),
    RED        = Color3.fromRGB(255, 30, 30),
    RED_DEEP   = Color3.fromRGB(120, 0, 0),
    TEXT       = Color3.fromRGB(235, 235, 235),
    TEXT_DIM   = Color3.fromRGB(150, 150, 150),
    TOGGLE_OFF = Color3.fromRGB(60, 60, 60),
}
local FONT     = Enum.Font.GothamBold
local FONT_REG = Enum.Font.Gotham

local function new(class, props, children)
    local ok, o = pcall(Instance.new, class)
    if not ok or not o then return Instance.new("Frame") end
    for k, v in pairs(props or {}) do pcall(function() o[k] = v end) end
    for _, c in ipairs(children or {}) do          -- ИСПРАВЛЕНО: пропущенный _
        if c and typeof(c) ~= "table" then pcall(function() c.Parent = o end) end
    end
    return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end
local function stroke(col, t, trans)
    return new("UIStroke", {
        Color = col or THEME.STROKE,
        Thickness = t or 1,
        Transparency = trans or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end
local function tween(obj, time, props, style, dir)
    local t = TweenService:Create(obj, TweenInfo.new(time,
        style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local ScreenGui = new("ScreenGui", {
    Name = "BloodyHub",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local mountOk = pcall(function() ScreenGui.Parent = CoreGui end)
if not mountOk then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

-- ==================== MAIN WINDOW ====================
local WIN_W, WIN_H = 640, 420
local Main = new("Frame", {
    Parent = ScreenGui, Name = "Main",
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = THEME.BG,
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
}, {
    corner(8), stroke(THEME.STROKE, 1),
})

new("ImageLabel", {
    Parent = Main, BackgroundTransparency = 1,
    Image = "rbxassetid://5028857084",
    ImageColor3 = Color3.fromRGB(130, 0, 0),
    ImageTransparency = 0.35,
    ScaleType = Enum.ScaleType.Tile,
    TileSize = UDim2.fromOffset(128, 128),
    Size = UDim2.fromScale(1, 1),
    ZIndex = 0,
})

local TopBar = new("Frame", {
    Parent = Main,
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = THEME.PANEL,
    BorderSizePixel = 0,
}, { corner(8) })
new("Frame", {
    Parent = TopBar, BorderSizePixel = 0,
    BackgroundColor3 = THEME.PANEL,
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
})
new("Frame", {
    Parent = TopBar, BorderSizePixel = 0,
    BackgroundColor3 = Color3.fromRGB(140, 0, 0),
    Size = UDim2.new(1, 0, 0, 4),
}, {
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(0.4, 0),
            NumberSequenceKeypoint.new(0.7, 0.4),
            NumberSequenceKeypoint.new(1, 0.2),
        }),
    }),
})
new("TextLabel", {
    Parent = TopBar, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(0, 200, 1, 0),
    Font = FONT, TextSize = 20,
    TextXAlignment = Enum.TextXAlignment.Left,
    RichText = true,
    Text = '<font color="rgb(255,40,40)">Bloody</font><font color="rgb(240,240,240)">Hub</font>',
    TextColor3 = Color3.new(1, 1, 1),
})

local function winBtn(txt, xoff, cb)
    local b = new("TextButton", {
        Parent = TopBar, BackgroundTransparency = 1,
        Text = txt, Font = FONT, TextSize = 22,
        TextColor3 = THEME.TEXT_DIM,
        Size = UDim2.fromOffset(30, 30),
        Position = UDim2.new(1, xoff, 0.5, -15),
        AutoButtonColor = false,
    })
    b.MouseEnter:Connect(function() tween(b, 0.15, { TextColor3 = THEME.RED }) end)
    b.MouseLeave:Connect(function() tween(b, 0.15, { TextColor3 = THEME.TEXT_DIM }) end)
    b.MouseButton1Down:Connect(function() tween(b, 0.08, { Size = UDim2.fromOffset(26, 26) }) end)
    b.MouseButton1Up:Connect(function() tween(b, 0.1, { Size = UDim2.fromOffset(30, 30) }) end)
    b.MouseButton1Click:Connect(cb)
    return b
end

local minimized = false
local origSize = UDim2.fromOffset(WIN_W, WIN_H)

winBtn("—", -70, function()
    minimized = not minimized
    if minimized then
        tween(Main, 0.25, { Size = UDim2.fromOffset(WIN_W, 40) })
    else
        tween(Main, 0.25, { Size = origSize })
    end
end)

winBtn("✕", -36, function()
    tween(Main, 0.2, { BackgroundTransparency = 1 })
    task.delay(0.25, function()          -- ИСПРАВЛЕНО: task.wait внутри коннекта → task.delay
        Main.Visible = false
        Main.BackgroundTransparency = 0.05
    end)
end)

do
    local dragging, startPos, startInput
    TopBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startInput = i.Position
            startPos = Main.Position
        end
    end)
    UserInputSvc.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputSvc.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local Sidebar = new("Frame", {
    Parent = Main,
    Position = UDim2.fromOffset(0, 40),
    Size = UDim2.new(0, 150, 1, -70),
    BackgroundColor3 = THEME.PANEL,
    BorderSizePixel = 0,
    BackgroundTransparency = 0.15,
})
new("UIListLayout", {
    Parent = Sidebar, Padding = UDim.new(0, 4),
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
})
new("UIPadding", {
    Parent = Sidebar,
    PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
})

local Content = new("Frame", {
    Parent = Main,
    Position = UDim2.fromOffset(150, 40),
    Size = UDim2.new(1, -150, 1, -70),
    BackgroundTransparency = 1,
})

local Bottom = new("Frame", {
    Parent = Main,
    Size = UDim2.new(1, 0, 0, 30),
    Position = UDim2.new(0, 0, 1, -30),
    BackgroundColor3 = THEME.PANEL,
    BorderSizePixel = 0,
    BackgroundTransparency = 0.2,
}, { corner(8) })
new("Frame", { Parent = Bottom, BorderSizePixel = 0,
    BackgroundColor3 = THEME.PANEL,
    Size = UDim2.new(1, 0, 0, 12) })
new("Frame", { Parent = Bottom, BorderSizePixel = 0,
    BackgroundColor3 = THEME.RED_DEEP, BackgroundTransparency = 0.6,
    Size = UDim2.new(1, 0, 0, 1) })
new("TextLabel", {
    Parent = Bottom, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, 0, 1, 0),
    Font = FONT_REG, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = THEME.TEXT_DIM, RichText = true,
    Text = 'Welcome back, <font color="rgb(255,40,40)">' .. (LocalPlayer.DisplayName or LocalPlayer.Name) .. '</font>!',
})
new("TextLabel", {
    Parent = Bottom, BackgroundTransparency = 1,
    Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, -14, 1, 0),
    Font = FONT_REG, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
    TextColor3 = THEME.TEXT_DIM, RichText = true,
    Text = 'Version 1.0.0 <font color="rgb(255,40,40)">|</font> BloodyHub',
})

-- ==================== TAB / ELEMENT FACTORIES ====================
local BloodyHub = {}
local Tabs = {}
local ActiveTab = nil

local function setActiveTab(tab)
    if ActiveTab == tab then return end
    if ActiveTab then
        ActiveTab.Page.Visible = false
        tween(ActiveTab.Button, 0.2, { BackgroundTransparency = 1 })
        ActiveTab.Stroke.Transparency = 1
        ActiveTab.Label.TextColor3 = THEME.TEXT_DIM
        ActiveTab.Icon.TextColor3 = THEME.TEXT_DIM
    end
    ActiveTab = tab
    tab.Page.Visible = true
    tween(tab.Button, 0.2, { BackgroundTransparency = 0.5 })
    tab.Button.BackgroundColor3 = THEME.RED_DEEP
    tab.Stroke.Transparency = 0
    tab.Label.TextColor3 = THEME.TEXT
    tab.Icon.TextColor3 = THEME.RED
end

local function makeHeader(parent, title)
    new("TextLabel", {
        Parent = parent, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 4),
        Size = UDim2.new(1, -14, 0, 26),
        Font = FONT, TextSize = 20,
        TextColor3 = THEME.TEXT,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = title,
    })
end

function BloodyHub:MakeTab(name, iconGlyph)
    local btn = new("TextButton", {
        Parent = Sidebar,
        Size = UDim2.new(1, -16, 0, 34),
        BackgroundColor3 = THEME.RED_DEEP,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
    }, { corner(6) })
    local s = stroke(THEME.RED, 1, 1)
    s.Parent = btn
    local icon = new("TextLabel", {
        Parent = btn, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(20, 34),
        Font = FONT, TextSize = 14, TextColor3 = THEME.TEXT_DIM,
        Text = iconGlyph or "•",
    })
    local lbl = new("TextLabel", {
        Parent = btn, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -36, 1, 0),
        Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT_DIM,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = name,
    })
    local page = new("ScrollingFrame", {
        Parent = Content, Visible = false,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.RED,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    })
    new("UIPadding", { Parent = page,
        PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 0),  PaddingBottom = UDim.new(0, 12) })
    makeHeader(page, name)
    local body = new("Frame", {
        Parent = page, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 36),
        Size = UDim2.new(1, 0, 1, -36),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    local tab = { Button = btn, Label = lbl, Icon = icon, Stroke = s, Page = page, Body = body, Sections = {} }
    btn.MouseButton1Click:Connect(function() setActiveTab(tab) end)
    table.insert(Tabs, tab)
    if #Tabs == 1 then setActiveTab(tab) end

    local function makeSectionRaw(self, title, col)
        local section = new("Frame", {
            Parent = body,
            Size = UDim2.new(col or 0.5, -6, 0, 40),
            BackgroundColor3 = THEME.PANEL_ALT,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = #self.Sections + 1,
        }, { corner(6), stroke(THEME.STROKE, 1, 0.2) })
        new("UIListLayout", {
            Parent = section, Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        new("UIPadding", { Parent = section,
            PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
        new("TextLabel", {
            Parent = section, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 20),
            Font = FONT, TextSize = 14, TextColor3 = THEME.TEXT,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = title, LayoutOrder = 0,
        })
        table.insert(self.Sections, section)
        local sec = {}

        function sec:MakeLabel(text, richText)
            new("TextLabel", {
                Parent = section, BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Font = FONT_REG, TextSize = 12,
                TextColor3 = THEME.TEXT_DIM,
                TextWrapped = true, RichText = richText or false,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                Text = text,
                LayoutOrder = #section:GetChildren(),
            })
        end

        function sec:MakeKeybind(name, onTriggered)
            local listening = false
            local boundKey  = nil
            local row = new("Frame", {
                Parent = section, BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 28),
                LayoutOrder = #section:GetChildren(),
            })
            new("TextLabel", {
                Parent = row, BackgroundTransparency = 1,
                Size = UDim2.new(1, -110, 1, 0),
                Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = name,
            })
            local bindBtn = new("TextButton", {
                Parent = row, AutoButtonColor = false,
                Position = UDim2.new(1, -105, 0.5, -11),
                Size = UDim2.fromOffset(100, 22),
                BackgroundColor3 = THEME.PANEL,
                BorderSizePixel = 0,
                Font = FONT_REG, TextSize = 12,
                TextColor3 = THEME.TEXT_DIM,
                Text = "[ None ]",
            }, { corner(4), stroke(THEME.STROKE, 1, 0.3) })

            bindBtn.MouseButton1Click:Connect(function()
                if listening then return end
                listening = true
                bindBtn.Text = "..."
                bindBtn.TextColor3 = THEME.RED
                local conn
                conn = UserInputSvc.InputBegan:Connect(function(input, gpe)
                    if gpe then return end
                    if input.UserInputType == Enum.UserInputType.Keyboard then
                        boundKey = input.KeyCode
                        bindBtn.Text = "[ " .. input.KeyCode.Name .. " ]"
                        bindBtn.TextColor3 = THEME.TEXT
                        listening = false
                        conn:Disconnect()
                    end
                end)
            end)

            UserInputSvc.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                if not listening and boundKey and input.KeyCode == boundKey then
                    if onTriggered then pcall(onTriggered) end
                end
            end)

            return { GetKey = function() return boundKey end }
        end

        function sec:MakeToggle(name, default, callback)
            local row = new("Frame", {
                Parent = section, BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 28),
                LayoutOrder = #section:GetChildren(),
            })
            new("TextLabel", {
                Parent = row, BackgroundTransparency = 1,
                Size = UDim2.new(1, -50, 1, 0),
                Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT,
                TextXAlignment = Enum.TextXAlignment.Left, Text = name,
            })
            local tog = new("TextButton", {
                Parent = row, Text = "", AutoButtonColor = false,
                Size = UDim2.fromOffset(38, 20),
                Position = UDim2.new(1, -38, 0.5, -10),
                BackgroundColor3 = default and THEME.RED or THEME.TOGGLE_OFF,
                BorderSizePixel = 0,
            }, { corner(10) })
            local knob = new("Frame", {
                Parent = tog, BorderSizePixel = 0,
                BackgroundColor3 = Color3.new(1, 1, 1),
                Size = UDim2.fromOffset(14, 14),
                Position = UDim2.new(default and 1 or 0,
                    default and -17 or 3, 0.5, -7),
            }, { corner(7) })
            local state = default and true or false
            local function apply()
                tween(tog, 0.18, { BackgroundColor3 = state and THEME.RED or THEME.TOGGLE_OFF })
                tween(knob, 0.18, { Position = UDim2.new(state and 1 or 0,
                    state and -17 or 3, 0.5, -7) })
                if callback then pcall(callback, state) end
            end
            tog.MouseButton1Click:Connect(function()
                state = not state
                apply()
            end)
            return {
                Set = function(_, v) state = v and true or false; apply() end,  -- ИСПРАВЛЕНО
                Get = function() return state end,
            }
        end

        function sec:MakeSlider(name, min, max, default, decimals, callback)
            decimals = decimals or 2
            local row = new("Frame", {
                Parent = section, BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 40),
                LayoutOrder = #section:GetChildren(),
            })
            new("TextLabel", {
                Parent = row, BackgroundTransparency = 1,
                Size = UDim2.new(1, -60, 0, 18),
                Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT,
                TextXAlignment = Enum.TextXAlignment.Left, Text = name,
            })
            local val = new("TextLabel", {
                Parent = row, BackgroundTransparency = 1,
                Position = UDim2.new(1, -60, 0, 0),
                Size = UDim2.fromOffset(60, 18),
                Font = FONT, TextSize = 13, TextColor3 = THEME.RED,
                TextXAlignment = Enum.TextXAlignment.Right,
                Text = tostring(default),
            })
            local bar = new("Frame", {
                Parent = row, BorderSizePixel = 0,
                BackgroundColor3 = THEME.TOGGLE_OFF,
                Position = UDim2.fromOffset(0, 24),
                Size = UDim2.new(1, 0, 0, 6),
            }, { corner(3) })
            local fill = new("Frame", {
                Parent = bar, BorderSizePixel = 0,
                BackgroundColor3 = THEME.RED,
                Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
            }, { corner(3) })
            local handle = new("Frame", {
                Parent = bar, BorderSizePixel = 0,
                BackgroundColor3 = Color3.new(1, 1, 1),
                Size = UDim2.fromOffset(12, 12),
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
            }, { corner(6) })
            local current = default
            local function setFromX(px)
                local rel = math.clamp((px - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                current = min + (max - min) * rel
                local mult = 10 ^ decimals
                current = math.floor(current * mult + 0.5) / mult
                rel = (current - min) / (max - min)
                fill.Size = UDim2.new(rel, 0, 1, 0)
                handle.Position = UDim2.new(rel, 0, 0.5, 0)
                val.Text = tostring(current)
                if callback then pcall(callback, current) end
            end
            local sliding = false
            bar.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                    sliding = true
                    setFromX(i.Position.X)
                end
            end)
            UserInputSvc.InputChanged:Connect(function(i)
                if sliding and (i.UserInputType == Enum.UserInputType.MouseMovement
                    or i.UserInputType == Enum.UserInputType.Touch) then
                    setFromX(i.Position.X)
                end
            end)
            UserInputSvc.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                    sliding = false
                end
            end)
            return {
                Get = function() return current end,
                Set = function(_, v) current = v; setFromX(bar.AbsolutePosition.X + bar.AbsoluteSize.X * ((v - min) / (max - min))) end,  -- ИСПРАВЛЕНО
            }
        end

        function sec:MakeDropdown(name, options, default, callback)
            local row = new("Frame", {
                Parent = section, BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 28),
                LayoutOrder = #section:GetChildren(),
            })
            new("TextLabel", {
                Parent = row, BackgroundTransparency = 1,
                Size = UDim2.new(0.5, 0, 1, 0),
                Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT,
                TextXAlignment = Enum.TextXAlignment.Left, Text = name,
            })
            local btn2 = new("TextButton", {
                Parent = row, AutoButtonColor = false,
                Position = UDim2.new(0.5, 0, 0, 0),
                Size = UDim2.new(0.5, 0, 1, 0),
                BackgroundColor3 = THEME.PANEL,
                BorderSizePixel = 0,
                Font = FONT_REG, TextSize = 13,
                TextColor3 = THEME.TEXT,
                Text = default .. "  ▾",
            }, { corner(4), stroke(THEME.STROKE, 1, 0.3) })
            local list = new("Frame", {
                Parent = row, Visible = false,
                Position = UDim2.new(0.5, 0, 1, 4),
                Size = UDim2.new(0.5, 0, 0, #options * 24),
                BackgroundColor3 = THEME.PANEL,
                BorderSizePixel = 0, ZIndex = 10,
            }, { corner(4), stroke(THEME.STROKE, 1, 0.3) })
            new("UIListLayout", { Parent = list })
            local current = default
            for _, opt in ipairs(options) do
                local b = new("TextButton", {
                    Parent = list, AutoButtonColor = false,
                    Size = UDim2.new(1, 0, 0, 24),
                    BackgroundTransparency = 1,
                    Font = FONT_REG, TextSize = 12,
                    TextColor3 = THEME.TEXT, Text = opt, ZIndex = 11,
                })
                b.MouseEnter:Connect(function() b.TextColor3 = THEME.RED end)
                b.MouseLeave:Connect(function() b.TextColor3 = THEME.TEXT end)
                b.MouseButton1Click:Connect(function()
                    current = opt
                    btn2.Text = opt .. "  ▾"
                    list.Visible = false
                    if callback then pcall(callback, opt) end
                end)
            end
            btn2.MouseButton1Click:Connect(function() list.Visible = not list.Visible end)
            return { Get = function() return current end }
        end

        function sec:MakeButton(name, callback)
            local b = new("TextButton", {
                Parent = section, AutoButtonColor = false,
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundColor3 = THEME.RED_DEEP,
                BorderSizePixel = 0,
                Font = FONT, TextSize = 13,
                TextColor3 = THEME.TEXT, Text = name,
                LayoutOrder = #section:GetChildren(),
            }, { corner(4), stroke(THEME.RED, 1, 0.5) })
            b.MouseEnter:Connect(function() tween(b, 0.15, { BackgroundColor3 = THEME.RED }) end)
            b.MouseLeave:Connect(function() tween(b, 0.15, { BackgroundColor3 = THEME.RED_DEEP }) end)
            b.MouseButton1Click:Connect(function() pcall(callback) end)
            return b
        end

        return sec
    end

    new("UIListLayout", {
        Parent = body, Padding = UDim.new(0, 12),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    body.AutomaticSize = Enum.AutomaticSize.Y

    local pendingRow
    function tab:MakeSection(title)
        if not pendingRow or (pendingRow:GetAttribute("count") or 0) >= 2 then
            pendingRow = new("Frame", {
                Parent = body, BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 10),
                AutomaticSize = Enum.AutomaticSize.Y,
                LayoutOrder = #body:GetChildren(),
            })
            new("UIListLayout", {
                Parent = pendingRow, FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, 12),
                VerticalAlignment = Enum.VerticalAlignment.Top,
            })
            pendingRow:SetAttribute("count", 0)
        end
        pendingRow:SetAttribute("count", (pendingRow:GetAttribute("count") or 0) + 1)
        local sec = makeSectionRaw(self, title)
        local section = self.Sections[#self.Sections]
        section.Parent = pendingRow
        section.Size = UDim2.new(0.5, -6, 0, 0)
        return sec
    end

    return tab
end

-- ==================== BUILD TABS ====================
local TabCombat   = BloodyHub:MakeTab("Combat",    "⚔")
local TabAutoFarm = BloodyHub:MakeTab("Auto Farm", "◉")
local TabVisuals  = BloodyHub:MakeTab("Visuals",   "◎")
local TabPlayer   = BloodyHub:MakeTab("Player",    "☺")
local TabSession  = BloodyHub:MakeTab("Session",   "✖")
local TabMisc     = BloodyHub:MakeTab("Misc",      "✦")
local TabSettings = BloodyHub:MakeTab("Settings",  "⚙")
local TabCredits  = BloodyHub:MakeTab("Credits",   "★")

-- AUTO FARM
local secFarm = TabAutoFarm:MakeSection("Quests")
secFarm:MakeToggle("Master Auto Quest", false, function(v)
    safeCall(API.SetAutoQuest, v)
end)
secFarm:MakeToggle("Auto Dialog (option 1)", true, function(v)
    safeCall(API.SetAutoDialog, v)
end)

-- VISUALS
local secVis = TabVisuals:MakeSection("ESP")
secVis:MakeToggle("Player ESP", false, function(v)
    safeCall(API.SetESP, v)
end)

-- SESSION
local secSess = TabSession:MakeSection("Session")
secSess:MakeButton("⛔ Destroy Session", function()
    safeCall(API.DestroySession)
end)

-- SETTINGS
local secSets = TabSettings:MakeSection("Interface")
secSets:MakeKeybind("Script Appearance Keybind", function()
    if not Main.Visible then
        Main.Visible = true
        Main.BackgroundTransparency = 1
        Main.Size = UDim2.fromOffset(WIN_W * 0.8, WIN_H * 0.8)
        tween(Main, 0.3, { Size = origSize, BackgroundTransparency = 0.05 }, Enum.EasingStyle.Back)
    end
end)

-- CREDITS
local secCred = TabCredits:MakeSection("About")
secCred:MakeLabel(
    'BloodyHub v1.0.0\nCustom UI, no Rayfield.\n© 2026\n\nCreator: bloodytears',
    false
)

-- ==================== EXPOSE UI + DISMISS LOADING ====================
_G.BloodyHub_UI = {
    ScreenGui = ScreenGui,
    Main      = Main,
    Show = function()
        Main.Visible = true
        Main.BackgroundTransparency = 1
        Main.Size = UDim2.fromOffset(WIN_W * 0.8, WIN_H * 0.8)
        tween(Main, 0.35, { Size = origSize, BackgroundTransparency = 0.05 },
            Enum.EasingStyle.Back)
    end,
    Hide = function()
        Main.Visible = false
    end,
}

-- Спрятать лоадер и показать окно
task.spawn(function()
    if _G.BloodyHub_Loading and _G.BloodyHub_Loading.Dismiss then
        _G.BloodyHub_Loading.Dismiss()
    end
    _G.BloodyHub_UI.Show()
end)
