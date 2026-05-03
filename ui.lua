--[[ AnimeCrusadersHub UI v1.0
Layout (по эскизу):
  Top bar: лого + Record/Stop кнопка + close/min
  Left (red panel)   — текущий макро при playback (steps + map name + Pause/Stop)
  Right (green panel)— community macros (заглушка, кнопка Refresh)
  Bottom (blue panel)— локальные макросы (двойной клик = play)
]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputSvc = game:GetService("UserInputService")
local CoreGui      = game:GetService("CoreGui")
local LocalPlayer  = Players.LocalPlayer

local API = _G.ACH_API or {}
local function safeCall(fn, ...) if type(fn) == "function" then return select(2, pcall(fn, ...)) end end

for _, g in ipairs(CoreGui:GetChildren()) do
	if g.Name == "AnimeCrusadersHub" then pcall(function() g:Destroy() end) end
end

local THEME = {
	BG        = Color3.fromRGB(12, 10, 18),
	PANEL     = Color3.fromRGB(18, 14, 26),
	PANEL_ALT = Color3.fromRGB(24, 20, 34),
	ACCENT    = Color3.fromRGB(190, 80, 230),
	ACCENT_DK = Color3.fromRGB(90, 30, 130),
	RED       = Color3.fromRGB(220, 60, 80),
	RED_DK    = Color3.fromRGB(120, 20, 30),
	GREEN     = Color3.fromRGB(60, 200, 110),
	GREEN_DK  = Color3.fromRGB(30, 90, 50),
	BLUE      = Color3.fromRGB(80, 140, 230),
	BLUE_DK   = Color3.fromRGB(30, 60, 120),
	TEXT      = Color3.fromRGB(235, 235, 240),
	TEXT_DIM  = Color3.fromRGB(150, 145, 165),
	TEXT_FAINT= Color3.fromRGB(90, 88, 110),
}
local FONT     = Enum.Font.GothamBold
local FONT_REG = Enum.Font.Gotham

local function new(class, props, children)
	local ok, o = pcall(Instance.new, class)
	if not ok or not o then return Instance.new("Frame") end
	for k, v in pairs(props or {}) do pcall(function() o[k] = v end) end
	for _, c in ipairs(children or {}) do if c then pcall(function() c.Parent = o end) end end
	return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end
local function stroke(col, t, trans)
	return new("UIStroke", { Color = col or THEME.ACCENT_DK, Thickness = t or 1, Transparency = trans or 0 })
end
local function tween(o, t, p, st, di)
	local tw = TweenService:Create(o, TweenInfo.new(t, st or Enum.EasingStyle.Quad, di or Enum.EasingDirection.Out), p)
	tw:Play(); return tw
end

local ScreenGui = new("ScreenGui", {
	Name = "AnimeCrusadersHub", ResetOnSpawn = false,
	IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local mountOk = pcall(function() ScreenGui.Parent = CoreGui end)
if not mountOk then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

-- ==================== MAIN WINDOW ====================
local WIN_W, WIN_H = 720, 520
local Main = new("Frame", {
	Parent = ScreenGui, Name = "Main",
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = THEME.BG,
	BorderSizePixel = 0, ClipsDescendants = true,
}, { corner(8), stroke(THEME.ACCENT_DK, 1) })

-- ==================== TOP BAR ====================
local TopBar = new("Frame", {
	Parent = Main, Size = UDim2.new(1, 0, 0, 44),
	BackgroundColor3 = THEME.PANEL, BorderSizePixel = 0,
}, { corner(8) })

new("Frame", { Parent = TopBar, BorderSizePixel = 0, BackgroundColor3 = THEME.PANEL,
	Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12) })

new("TextLabel", {
	Parent = TopBar, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(220, 44),
	Font = FONT, TextSize = 18, RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	Text = '<font color="rgb(220,120,255)">Anime</font><font color="rgb(240,240,240)">CrusadersHub</font>',
	TextColor3 = THEME.TEXT,
})

-- Window buttons
local function winBtn(txt, xoff, cb)
	local b = new("TextButton", {
		Parent = TopBar, BackgroundTransparency = 1, Text = txt,
		Font = FONT, TextSize = 22, TextColor3 = THEME.TEXT_DIM,
		Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, xoff, 0.5, -15),
		AutoButtonColor = false,
	})
	b.MouseEnter:Connect(function() tween(b, 0.15, { TextColor3 = THEME.ACCENT }) end)
	b.MouseLeave:Connect(function() tween(b, 0.15, { TextColor3 = THEME.TEXT_DIM }) end)
	b.MouseButton1Click:Connect(cb)
	return b
end
local minimized = false
local origSize = UDim2.fromOffset(WIN_W, WIN_H)
winBtn("—", -70, function()
	minimized = not minimized
	tween(Main, 0.25, { Size = minimized and UDim2.fromOffset(WIN_W, 44) or origSize })
end)
winBtn("✕", -36, function()
	tween(Main, 0.2, { BackgroundTransparency = 1 })
	task.delay(0.25, function() Main.Visible = false; Main.BackgroundTransparency = 0 end)
end)

-- Drag
do
	local dragging, startPos, startInput
	TopBar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
			or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; startInput = i.Position; startPos = Main.Position
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
			or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
end

-- ==================== RECORD / STOP BUTTON (top-left under bar) ====================
local RecordBtn = new("TextButton", {
	Parent = Main, AutoButtonColor = false,
	Position = UDim2.fromOffset(14, 56),
	Size = UDim2.fromOffset(110, 36),
	BackgroundColor3 = THEME.RED_DK, BorderSizePixel = 0,
	Font = FONT, TextSize = 14, TextColor3 = THEME.TEXT,
	Text = "● Record",
}, { corner(6), stroke(THEME.RED, 1, 0.4) })

local SaveBtn = new("TextButton", {
	Parent = Main, AutoButtonColor = false,
	Position = UDim2.fromOffset(132, 56),
	Size = UDim2.fromOffset(120, 36),
	BackgroundColor3 = THEME.ACCENT_DK, BorderSizePixel = 0,
	Font = FONT, TextSize = 13, TextColor3 = THEME.TEXT,
	Text = "💾 Save current", Visible = false,
}, { corner(6), stroke(THEME.ACCENT, 1, 0.4) })

local NameBox = new("TextBox", {
	Parent = Main, BackgroundColor3 = THEME.PANEL_ALT, BorderSizePixel = 0,
	Position = UDim2.fromOffset(260, 56), Size = UDim2.fromOffset(200, 36),
	Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT,
	PlaceholderText = "Macro name (optional)", PlaceholderColor3 = THEME.TEXT_DIM,
	ClearTextOnFocus = false, Text = "", Visible = false,
}, { corner(6), stroke(THEME.ACCENT_DK, 1, 0.5) })

-- Status pill (top-right under bar)
local StatusPill = new("TextLabel", {
	Parent = Main, BackgroundColor3 = THEME.PANEL_ALT,
	Position = UDim2.new(1, -180, 0, 56),
	Size = UDim2.fromOffset(166, 36),
	BackgroundTransparency = 0.2, BorderSizePixel = 0,
	Font = FONT_REG, TextSize = 12, TextColor3 = THEME.TEXT_DIM,
	Text = "  ● idle",
	TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
}, { corner(6), stroke(THEME.ACCENT_DK, 1, 0.5) })

-- ==================== LAYOUT: red (left) + green (right) ====================
local CONTENT_TOP = 104
local CONTENT_H_TOP = 280

-- RED panel (current macro)
local RedPanel = new("Frame", {
	Parent = Main, Position = UDim2.fromOffset(14, CONTENT_TOP),
	Size = UDim2.new(0, 380, 0, CONTENT_H_TOP),
	BackgroundColor3 = THEME.PANEL, BorderSizePixel = 0,
}, { corner(6), stroke(THEME.RED, 1, 0.55) })

new("TextLabel", {
	Parent = RedPanel, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -12, 0, 18),
	Font = FONT, TextSize = 13, TextColor3 = THEME.RED,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "CURRENT MACRO",
})

local CurrentBody = new("Frame", {
	Parent = RedPanel, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 26),
	Size = UDim2.new(1, -24, 1, -64),
})

local StepLabel = new("TextLabel", {
	Parent = CurrentBody, BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 22),
	Font = FONT, TextSize = 14, TextColor3 = THEME.TEXT,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "- step - -",
})
local UnitLabel = new("TextLabel", {
	Parent = CurrentBody, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 18),
	Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT_DIM,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "unit name: —",
})
local PosLabel = new("TextLabel", {
	Parent = CurrentBody, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 18),
	Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT_DIM,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "position: —",
})
local StatusLabel = new("TextLabel", {
	Parent = CurrentBody, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 18),
	Font = FONT_REG, TextSize = 13, TextColor3 = THEME.TEXT_DIM,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "status: —",
})

local MapLabel = new("TextLabel", {
	Parent = RedPanel, BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 1, -52), Size = UDim2.new(1, -24, 0, 16),
	Font = FONT_REG, TextSize = 11, TextColor3 = THEME.TEXT_FAINT,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "",
})

-- Pause / Stop buttons (visible during playback)
local PauseBtn = new("TextButton", {
	Parent = RedPanel, AutoButtonColor = false,
	Position = UDim2.new(0, 12, 1, -32),
	Size = UDim2.fromOffset(80, 24),
	BackgroundColor3 = THEME.PANEL_ALT, BorderSizePixel = 0,
	Font = FONT, TextSize = 12, TextColor3 = THEME.TEXT,
	Text = "❚❚ Pause", Visible = false,
}, { corner(4), stroke(THEME.ACCENT, 1, 0.5) })

local StopPlayBtn = new("TextButton", {
	Parent = RedPanel, AutoButtonColor = false,
	Position = UDim2.new(0, 100, 1, -32),
	Size = UDim2.fromOffset(80, 24),
	BackgroundColor3 = THEME.RED_DK, BorderSizePixel = 0,
	Font = FONT, TextSize = 12, TextColor3 = THEME.TEXT,
	Text = "■ Stop", Visible = false,
}, { corner(4), stroke(THEME.RED, 1, 0.5) })

local IdleHint = new("TextLabel", {
	Parent = RedPanel, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 30),
	Font = FONT_REG, TextSize = 12, TextColor3 = THEME.TEXT_FAINT,
	TextXAlignment = Enum.TextXAlignment.Center,
	Text = "Press Record to start, or double-click a saved macro below.",
})

-- GREEN panel (community)
local GreenPanel = new("Frame", {
	Parent = Main, Position = UDim2.new(0, 408, 0, CONTENT_TOP),
	Size = UDim2.new(1, -422, 0, CONTENT_H_TOP),
	BackgroundColor3 = THEME.PANEL, BorderSizePixel = 0,
}, { corner(6), stroke(THEME.GREEN, 1, 0.55) })
new("TextLabel", {
	Parent = GreenPanel, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -12, 0, 18),
	Font = FONT, TextSize = 13, TextColor3 = THEME.GREEN,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "COMMUNITY MACROS",
})
new("TextLabel", {
	Parent = GreenPanel, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -24, 0, 36),
	Font = FONT_REG, TextSize = 11, TextColor3 = THEME.TEXT_FAINT,
	TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
	Text = "Скоро: загрузка макросов из репозитория сообщества прямо в твой ПК.",
})
local GreenList = new("ScrollingFrame", {
	Parent = GreenPanel, BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(8, 70), Size = UDim2.new(1, -16, 1, -78),
	ScrollBarThickness = 2, ScrollBarImageColor3 = THEME.GREEN,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
new("UIListLayout", { Parent = GreenList, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder })
new("TextLabel", {
	Parent = GreenList, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24),
	Font = FONT_REG, TextSize = 12, TextColor3 = THEME.TEXT_FAINT,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "  (no community macros yet)",
})

-- BLUE panel (local exports) — bottom
local BluePanel = new("Frame", {
	Parent = Main, Position = UDim2.new(0, 14, 0, CONTENT_TOP + CONTENT_H_TOP + 10),
	Size = UDim2.new(1, -28, 1, -(CONTENT_TOP + CONTENT_H_TOP + 24)),
	BackgroundColor3 = THEME.PANEL, BorderSizePixel = 0,
}, { corner(6), stroke(THEME.BLUE, 1, 0.55) })
new("TextLabel", {
	Parent = BluePanel, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -120, 0, 18),
	Font = FONT, TextSize = 13, TextColor3 = THEME.BLUE,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "YOUR EXPORTED MACROS  (double-click to play)",
})
local RefreshBtn = new("TextButton", {
	Parent = BluePanel, AutoButtonColor = false,
	Position = UDim2.new(1, -84, 0, 4), Size = UDim2.fromOffset(72, 22),
	BackgroundColor3 = THEME.BLUE_DK, BorderSizePixel = 0,
	Font = FONT, TextSize = 11, TextColor3 = THEME.TEXT, Text = "⟳ Refresh",
}, { corner(4), stroke(THEME.BLUE, 1, 0.5) })

local Library = new("ScrollingFrame", {
	Parent = BluePanel, BackgroundTransparency = 1, BorderSizePixel = 0,
	Position = UDim2.fromOffset(8, 32), Size = UDim2.new(1, -16, 1, -40),
	ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.BLUE,
	CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
})
local libGrid = new("UIGridLayout", {
	Parent = Library, CellSize = UDim2.new(0, 200, 0, 36),
	CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder,
})

local function refreshLibrary()
	for _, c in ipairs(Library:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextButton") or c:IsA("TextLabel") then
			pcall(function() c:Destroy() end)
		end
	end
	local items = (API.ListLibrary and API.ListLibrary()) or {}
	if #items == 0 then
		local lbl = new("TextLabel", {
			Parent = Library, BackgroundTransparency = 1,
			Size = UDim2.fromOffset(400, 24),
			Font = FONT_REG, TextSize = 12, TextColor3 = THEME.TEXT_FAINT,
			TextXAlignment = Enum.TextXAlignment.Left, Text = "  (no macros saved yet)",
		})
		return
	end
	for _, item in ipairs(items) do
		local card = new("TextButton", {
			Parent = Library, AutoButtonColor = false,
			BackgroundColor3 = THEME.PANEL_ALT, BorderSizePixel = 0, Text = "",
		}, { corner(5), stroke(THEME.BLUE_DK, 1, 0.4) })
		new("TextLabel", {
			Parent = card, BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -42, 1, 0),
			Font = FONT_REG, TextSize = 12, TextColor3 = THEME.TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = item.name,
		})
		local del = new("TextButton", {
			Parent = card, AutoButtonColor = false,
			Position = UDim2.new(1, -28, 0.5, -10), Size = UDim2.fromOffset(22, 20),
			BackgroundColor3 = THEME.RED_DK, BorderSizePixel = 0,
			Font = FONT, TextSize = 12, TextColor3 = THEME.TEXT, Text = "✕",
		}, { corner(4) })
		del.MouseButton1Click:Connect(function()
			if API.DeleteFile then API.DeleteFile(item.path) end
			refreshLibrary()
		end)
		-- двойной клик = play
		local lastClick = 0
		card.MouseButton1Click:Connect(function()
			local now = os.clock()
			if now - lastClick < 0.4 then
				if API.PlayFile then API.PlayFile(item.path) end
			end
			lastClick = now
		end)
		card.MouseEnter:Connect(function() tween(card, 0.12, { BackgroundColor3 = THEME.BLUE_DK }) end)
		card.MouseLeave:Connect(function() tween(card, 0.12, { BackgroundColor3 = THEME.PANEL_ALT }) end)
	end
end

RefreshBtn.MouseButton1Click:Connect(refreshLibrary)

-- ==================== RECORD/STOP HANDLERS ====================
local recording = false
local function setRecordingUi(rec)
	recording = rec
	if rec then
		RecordBtn.Text = "■ Stop"
		RecordBtn.BackgroundColor3 = THEME.RED
		SaveBtn.Visible = false; NameBox.Visible = false
	else
		RecordBtn.Text = "● Record"
		RecordBtn.BackgroundColor3 = THEME.RED_DK
		local current = API.GetCurrent and API.GetCurrent()
		if current and current.steps and #current.steps > 0 then
			SaveBtn.Visible = true; NameBox.Visible = true
		end
	end
end

RecordBtn.MouseButton1Click:Connect(function()
	if recording then
		if API.StopRecord then API.StopRecord() end
	else
		if API.StartRecord then API.StartRecord() end
	end
end)

SaveBtn.MouseButton1Click:Connect(function()
	local name = NameBox.Text
	if name == "" then name = nil end
	if API.SaveCurrent then API.SaveCurrent(name) end
	SaveBtn.Visible = false; NameBox.Visible = false; NameBox.Text = ""
end)

-- ==================== UI HOOKS (called from main) ====================
local function setStatusPill(text, color)
	StatusPill.Text = "  " .. text
	StatusPill.TextColor3 = color or THEME.TEXT_DIM
end

local function showCurrentMacroIdle()
	StepLabel.Text = "- step - -"
	UnitLabel.Text = "unit name: —"
	PosLabel.Text  = "position: —"
	StatusLabel.Text = "status: —"
	MapLabel.Text = ""
	PauseBtn.Visible = false
	StopPlayBtn.Visible = false
	IdleHint.Visible = true
end
showCurrentMacroIdle()

local function showStep(stepIdx, step, statusText, statusColor)
	IdleHint.Visible = false
	StepLabel.Text = ("- step %d -"):format(stepIdx or 0)
	UnitLabel.Text = "unit name: " .. tostring(step and step.unit or "—")
	local p = step and step.position
	PosLabel.Text = p
		and ("position: %d, %d, %d"):format(math.floor(p[1]), math.floor(p[2]), math.floor(p[3]))
		or "position: —"
	StatusLabel.Text = "status: " .. (statusText or "—")
	StatusLabel.TextColor3 = statusColor or THEME.TEXT_DIM
end

local function statusToText(stat, need)
	if stat == "waiting" then
		return ("waiting for %d more cash"):format(need or 0), Color3.fromRGB(255, 200, 90)
	elseif stat == "placing" then
		return "placing unit", Color3.fromRGB(120, 220, 120)
	elseif stat == "error" then
		return "error", Color3.fromRGB(255, 80, 80)
	else
		return "idle", THEME.TEXT_DIM
	end
end

PauseBtn.MouseButton1Click:Connect(function()
	local isPaused = API.IsPaused and API.IsPaused()
	if API.SetPause then API.SetPause(not isPaused) end
end)
StopPlayBtn.MouseButton1Click:Connect(function()
	if API.StopPlay then API.StopPlay() end
end)

_G.ACH_UI = {
	ScreenGui = ScreenGui, Main = Main,
	Show = function() Main.Visible = true end,
	Hide = function() Main.Visible = false end,

	OnRecordStateChanged = function(rec)
		setRecordingUi(rec)
		if rec then
			setStatusPill("● recording", THEME.RED)
		else
			setStatusPill("● idle", THEME.TEXT_DIM)
		end
	end,

	OnRecordStep = function(stepNum, step)
		-- при записи в красном поле показываем последний шаг, но это опционально
		-- (по ТЗ при записи всё уходит в нотификации)
	end,

	OnPlayStateChanged = function(playing, macro)
		if playing then
			IdleHint.Visible = false
			PauseBtn.Visible = true; StopPlayBtn.Visible = true
			MapLabel.Text = "map: " .. tostring(macro and macro.mapName or "—")
			setStatusPill("▶ playing", THEME.GREEN)
		else
			PauseBtn.Visible = false; StopPlayBtn.Visible = false
			setStatusPill("● idle", THEME.TEXT_DIM)
			showCurrentMacroIdle()
		end
	end,

	OnPlayPaused = function(paused)
		PauseBtn.Text = paused and "▶ Resume" or "❚❚ Pause"
		setStatusPill(paused and "❚❚ paused" or "▶ playing",
			paused and Color3.fromRGB(255, 200, 90) or THEME.GREEN)
	end,

	OnPlayerStatus = function(stepIdx, stat, need)
		local macro = API.GetCurrent and API.GetCurrent()
		local step = macro and macro.steps and macro.steps[stepIdx]
		local text, color = statusToText(stat, need)
		showStep(stepIdx, step, text, color)
		if macro then MapLabel.Text = "map: " .. tostring(macro.mapName or "—") end
	end,

	OnLibraryChanged = function() refreshLibrary() end,
}

-- Initial fill
refreshLibrary()

-- Show after loader
task.spawn(function()
	if _G.ACH_Loading and _G.ACH_Loading.Dismiss then _G.ACH_Loading.Dismiss() end
end)
