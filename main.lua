--[[ AnimeCrusadersHub main v1.1 ]]

local UI_URL = "https://raw.githubusercontent.com/convenctions-hub/BloodyHub/main/ui.lua"

-- ============================================================== --
--                          СЕРВИСЫ                                --
-- ============================================================== --
local HttpService        = game:GetService("HttpService")
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local CoreGui            = game:GetService("CoreGui")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalPlayer        = Players.LocalPlayer

-- ============================================================== --
-- 1) CONFIG
-- ============================================================== --
local CONFIG = {
    BaseFolder      = "AnimeCrusadersHub",
    MacroFolder     = "AnimeCrusadersHub/Macros",
    PlayTick        = 0.15,
    NotifLifetime   = 2.5,
    CashTimeoutSec  = 240,
}

-- ============================================================== --
-- 2) STATE
-- ============================================================== --
local STATE = {
    Dead          = false,
    Recording     = false,
    Playing       = false,
    Paused        = false,
    RecordSession = 0,
    PlaySession   = 0,
    CurrentMacro  = nil,
    LiveSteps     = {},
    RecordStartT  = 0,
    CurrentStep   = 0,
    CurrentStatus = "idle",
    CurrentNeed   = 0,
}

-- ============================================================== --
-- 3) FILES / FOLDERS
-- ============================================================== --
local HAS_FS = (writefile and readfile and isfile and isfolder and listfiles) and true or false

local function ensureFolders()
    if not HAS_FS then return end
    if not isfolder(CONFIG.BaseFolder)  then pcall(makefolder, CONFIG.BaseFolder) end
    if not isfolder(CONFIG.MacroFolder) then pcall(makefolder, CONFIG.MacroFolder) end
end
ensureFolders()

-- ============================================================== --
-- 4) UTIL
-- ============================================================== --
local function safeName(s)
    s = tostring(s or "macro")
    s = s:gsub('[\\/:*?"<>|]', "_")
    return s
end

local function getMapName()
    local ok, name = pcall(function()
        for _, n in ipairs({"Map","CurrentMap","_Map","ActiveMap","MapFolder"}) do
            local m = workspace:FindFirstChild(n)
            if m then
                local sv = m:FindFirstChild("MapName") or m:FindFirstChild("DisplayName")
                if sv and sv:IsA("StringValue") then return sv.Value end
                local kids = m:GetChildren()
                if #kids == 1 and kids[1]:IsA("Model") then return kids[1].Name end
                return m.Name
            end
        end
        for _, n in ipairs({"CurrentMap","MapName","ActiveMap"}) do
            local v = ReplicatedStorage:FindFirstChild(n)
            if v and v:IsA("StringValue") then return v.Value end
        end
        local pd = LocalPlayer:FindFirstChild("PlayerData") or LocalPlayer:FindFirstChild("Data")
        if pd then
            for _, n in ipairs({"Map","CurrentMap","MapName"}) do
                local v = pd:FindFirstChild(n)
                if v and v.Value and v.Value ~= "" then return tostring(v.Value) end
            end
        end
        return nil
    end)
    if ok and name and name ~= "" then return name end
    local ok2, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
    if ok2 and info and info.Name then return info.Name end
    return "Unknown Map"
end

local function getCash()
    local sources = {
        LocalPlayer:FindFirstChild("PlayerData"),
        LocalPlayer:FindFirstChild("Data"),
        LocalPlayer:FindFirstChild("leaderstats"),
        LocalPlayer:FindFirstChild("Stats"),
    }
    for _, src in ipairs(sources) do
        if src then
            for _, n in ipairs({"Cash","Money","Coins","Yen","Gold","Currency","Gems"}) do
                local v = src:FindFirstChild(n)
                if v then
                    local ok, val = pcall(function() return v.Value end)
                    if ok then
                        local num = tonumber(val)
                        if num then return num end
                    end
                end
            end
        end
    end
    return 0
end

local function findUnitCost(unitName)
    if not unitName or unitName == "" then return nil end
    local roots = {
        ReplicatedStorage:FindFirstChild("Units"),
        ReplicatedStorage:FindFirstChild("Towers"),
        ReplicatedStorage:FindFirstChild("UnitData"),
        ReplicatedStorage:FindFirstChild("Modules"),
        ReplicatedStorage:FindFirstChild("Data"),
    }
    for _, root in ipairs(roots) do
        if root then
            local u = root:FindFirstChild(unitName)
            if u then
                for _, n in ipairs({"Cost","Price","Placement","PlacementCost","DeployCost"}) do
                    local v = u:FindFirstChild(n)
                    if v then
                        local ok, val = pcall(function() return v.Value end)
                        if ok then
                            local num = tonumber(val)
                            if num then return num end
                        end
                    end
                end
                if u:IsA("ModuleScript") then
                    local ok, mod = pcall(require, u)
                    if ok and type(mod) == "table" then
                        return tonumber(mod.Cost) or tonumber(mod.Price)
                            or tonumber(mod.PlacementCost) or tonumber(mod.DeployCost)
                    end
                end
            end
        end
    end
    return nil
end

local function fullPath(inst)
    if not inst then return nil end
    local segs = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(segs, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(segs, "/")
end

local function resolvePath(path)
    if not path then return nil end
    local cur = game
    for seg in path:gmatch("[^/]+") do
        if not cur then return nil end
        cur = cur:FindFirstChild(seg)
    end
    return cur
end

local function encodeArg(v)
    local tv = typeof(v)
    if tv == "CFrame" then
        local x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22 = v:GetComponents()
        return { __t = "CFrame", v = {x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22} }
    elseif tv == "Vector3" then
        return { __t = "Vector3", v = {v.X, v.Y, v.Z} }
    elseif tv == "Vector2" then
        return { __t = "Vector2", v = {v.X, v.Y} }
    elseif tv == "Color3" then
        return { __t = "Color3", v = {v.R, v.G, v.B} }
    elseif tv == "Instance" then
        return { __t = "Instance", v = fullPath(v) }
    elseif tv == "table" then
        local out = {}
        for k, sub in pairs(v) do out[k] = encodeArg(sub) end
        return { __t = "table", v = out }
    elseif tv == "string" or tv == "number" or tv == "boolean" then
        return v
    elseif v == nil then
        return { __t = "nil" }
    else
        return { __t = "raw", v = tostring(v) }
    end
end

local function decodeArg(v)
    if type(v) ~= "table" then return v end
    local t = v.__t
    if t == "CFrame" then
        local a = v.v
        return CFrame.new(a[1],a[2],a[3], a[4],a[5],a[6], a[7],a[8],a[9], a[10],a[11],a[12])
    elseif t == "Vector3"  then return Vector3.new(v.v[1], v.v[2], v.v[3])
    elseif t == "Vector2"  then return Vector2.new(v.v[1], v.v[2])
    elseif t == "Color3"   then return Color3.new(v.v[1], v.v[2], v.v[3])
    elseif t == "Instance" then return resolvePath(v.v)
    elseif t == "nil"      then return nil
    elseif t == "table" then
        local out = {}
        for k, sub in pairs(v.v) do out[k] = decodeArg(sub) end
        return out
    elseif t == "raw" then return v.v
    end
    local out = {}
    for k, sub in pairs(v) do out[k] = decodeArg(sub) end
    return out
end

local function classifyPlacement(args, argc)
    local unit, pos
    for i = 1, argc do
        local v = args[i]; local tv = typeof(v)
        if tv == "CFrame" then pos = pos or v.Position
        elseif tv == "Vector3" then pos = pos or v
        elseif tv == "string" then
            if not unit and #v > 0 and #v <= 64 then unit = v end
        end
    end
    if unit and pos then return unit, pos end
    return nil
end

-- ============================================================== --
-- 5) NOTIFICATIONS GUI
-- ============================================================== --
pcall(function()
    for _, g in ipairs(CoreGui:GetChildren()) do
        if g.Name == "ACHNotif" then pcall(function() g:Destroy() end) end
    end
end)

local NotifGui = Instance.new("ScreenGui")
NotifGui.Name = "ACHNotif"
NotifGui.ResetOnSpawn = false
NotifGui.IgnoreGuiInset = true
NotifGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() NotifGui.Parent = CoreGui end)
if not NotifGui.Parent then NotifGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local NotifContainer = Instance.new("Frame")
NotifContainer.Parent = NotifGui
NotifContainer.BackgroundTransparency = 1
NotifContainer.Position = UDim2.new(1, -320, 0, 20)
NotifContainer.Size = UDim2.new(0, 300, 1, -40)
local lst = Instance.new("UIListLayout")
lst.Parent = NotifContainer
lst.Padding = UDim.new(0, 6)
lst.SortOrder = Enum.SortOrder.LayoutOrder
lst.HorizontalAlignment = Enum.HorizontalAlignment.Right

local _notifOrder = 0
local function Notify(title, body, color)
    if STATE.Dead then return end
    _notifOrder = _notifOrder + 1
    local frame = Instance.new("Frame")
    frame.Parent = NotifContainer
    frame.LayoutOrder = _notifOrder
    frame.BackgroundColor3 = Color3.fromRGB(20, 16, 26)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 0, 0)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = frame
    local s = Instance.new("UIStroke"); s.Color = color or Color3.fromRGB(180, 60, 220); s.Thickness = 1; s.Parent = frame
    local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0,8); pad.PaddingBottom = UDim.new(0,8)
    pad.PaddingLeft = UDim.new(0,10); pad.PaddingRight = UDim.new(0,10); pad.Parent = frame
    local lyt = Instance.new("UIListLayout"); lyt.Padding = UDim.new(0,2); lyt.Parent = frame

    local t = Instance.new("TextLabel")
    t.Parent = frame; t.BackgroundTransparency = 1
    t.Size = UDim2.new(1, 0, 0, 18)
    t.Font = Enum.Font.GothamBold; t.TextSize = 13
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextColor3 = color or Color3.fromRGB(220, 120, 255)
    t.Text = tostring(title or "")

    local b = Instance.new("TextLabel")
    b.Parent = frame; b.BackgroundTransparency = 1
    b.Size = UDim2.new(1, 0, 0, 0)
    b.AutomaticSize = Enum.AutomaticSize.Y
    b.Font = Enum.Font.Gotham; b.TextSize = 12
    b.TextWrapped = true
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextColor3 = Color3.fromRGB(220, 220, 220)
    b.Text = tostring(body or "")

    frame.BackgroundTransparency = 1
    t.TextTransparency = 1; b.TextTransparency = 1; s.Transparency = 1
    local TweenService = game:GetService("TweenService")
    local function tw(o, time, props)
        TweenService:Create(o, TweenInfo.new(time, Enum.EasingStyle.Quad), props):Play()
    end
    tw(frame, 0.2, { BackgroundTransparency = 0.05 })
    tw(t, 0.2, { TextTransparency = 0 })
    tw(b, 0.2, { TextTransparency = 0 })
    tw(s, 0.2, { Transparency = 0 })

    task.delay(CONFIG.NotifLifetime, function()
        tw(frame, 0.4, { BackgroundTransparency = 1 })
        tw(t, 0.4, { TextTransparency = 1 })
        tw(b, 0.4, { TextTransparency = 1 })
        tw(s, 0.4, { Transparency = 1 })
        task.wait(0.45)
        pcall(function() frame:Destroy() end)
    end)
end

-- ============================================================== --
-- 6) REMOTE HOOK
-- ИСПРАВЛЕНО: аргументы пакуются ДО любого pcall через table.pack,
-- обработка записи выполняется в task.defer (асинхронно),
-- oldNamecall вызывается сразу и синхронно с оригинальными аргументами.
-- ============================================================== --
local _onPlacement = nil
local hookInstalled = false

local function installHook()
    if hookInstalled then return end
    if not (hookmetamethod and newcclosure and getnamecallmethod) then
        warn("[ACH] Executor lacks hookmetamethod — recording disabled")
        return
    end
    local oldNamecall
    local ok, err = pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            -- Сначала проверяем метод — никаких аллокаций если не нужно
            local ok_m, method = pcall(getnamecallmethod)
            if not ok_m then
                return oldNamecall(self, ...)
            end

            -- Перехватываем только если идёт запись И это FireServer/InvokeServer
            if STATE.Recording
                and (method == "FireServer" or method == "InvokeServer")
                and typeof(self) == "Instance"
                and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction"))
            then
                -- ВАЖНО: пакуем аргументы ДО вызова оригинала
                -- table.pack сохраняет точное количество аргументов включая nil
                local packed = table.pack(...)
                local remotePath = fullPath(self)

                -- Обработку записи делаем АСИНХРОННО через task.defer
                -- чтобы не задерживать оригинальный вызов ни на такт
                task.defer(function()
                    pcall(function()
                        local unit, pos = classifyPlacement(packed, packed.n)
                        if unit and pos and _onPlacement then
                            _onPlacement(unit, pos, remotePath, packed, packed.n)
                        end
                    end)
                end)
            end

            -- Оригинальный вызов — всегда, синхронно, без изменений
            return oldNamecall(self, ...)
        end))
    end)
    if ok then
        hookInstalled = true
    else
        warn("[ACH] hook FAILED: " .. tostring(err))
    end
end
pcall(installHook)

-- ============================================================== --
-- 7) MACRO RECORDER
-- ============================================================== --
local Recorder = {}

function Recorder.Start()
    if STATE.Recording then return end
    if STATE.Playing then Notify("Recorder", "Stop playback first", Color3.fromRGB(255,80,80)); return end
    STATE.Recording = true
    STATE.RecordSession = STATE.RecordSession + 1
    STATE.LiveSteps = {}
    STATE.RecordStartT = os.clock()
    local mapName = getMapName()
    STATE.CurrentMacro = { mapName = mapName, steps = STATE.LiveSteps, version = 1 }
    Notify("REC ●", "Recording started on map: " .. mapName, Color3.fromRGB(255, 60, 100))
    if _G.ACH_UI and _G.ACH_UI.OnRecordStateChanged then
        pcall(_G.ACH_UI.OnRecordStateChanged, true)
    end
end

function Recorder.Stop()
    if not STATE.Recording then return nil end
    STATE.Recording = false
    local macro = STATE.CurrentMacro
    Notify("REC ■", ("Recorded %d steps"):format(#(macro and macro.steps or {})), Color3.fromRGB(120, 220, 120))
    if _G.ACH_UI and _G.ACH_UI.OnRecordStateChanged then
        pcall(_G.ACH_UI.OnRecordStateChanged, false)
    end
    return macro
end

-- ИСПРАВЛЕНО: classifyPlacement теперь принимает table.pack результат (поле .n)
_onPlacement = function(unit, pos, remotePath, packed, argc)
    local cost = findUnitCost(unit)
    local step = {
        unit       = unit,
        position   = { pos.X, pos.Y, pos.Z },
        cost       = cost,
        remotePath = remotePath,
        t          = os.clock() - STATE.RecordStartT,
        args       = {},
        argc       = argc,
    }
    for i = 1, argc do step.args[i] = encodeArg(packed[i]) end
    table.insert(STATE.LiveSteps, step)
    local stepNum = #STATE.LiveSteps
    local posStr = ("%d, %d, %d"):format(math.floor(pos.X), math.floor(pos.Y), math.floor(pos.Z))
    Notify("step " .. stepNum,
        ("unit name: %s\nposition: %s\nstatus: placing unit"):format(unit, posStr),
        Color3.fromRGB(120, 200, 255))
    if _G.ACH_UI and _G.ACH_UI.OnRecordStep then
        pcall(_G.ACH_UI.OnRecordStep, stepNum, step)
    end
end

-- ============================================================== --
-- 8) MACRO PLAYER
-- ============================================================== --
local Player = {}

local function setStatus(stat, need)
    STATE.CurrentStatus = stat
    STATE.CurrentNeed = need or 0
    if _G.ACH_UI and _G.ACH_UI.OnPlayerStatus then
        pcall(_G.ACH_UI.OnPlayerStatus, STATE.CurrentStep, stat, need)
    end
end

function Player.Start(macro)
    if STATE.Playing then return end
    if STATE.Recording then Notify("Player", "Stop recording first", Color3.fromRGB(255,80,80)); return end
    if not macro or type(macro) ~= "table" or not macro.steps or #macro.steps == 0 then
        Notify("Player", "Empty / invalid macro", Color3.fromRGB(255,80,80)); return
    end
    STATE.Playing = true; STATE.Paused = false
    STATE.PlaySession = STATE.PlaySession + 1
    STATE.CurrentMacro = macro
    STATE.CurrentStep = 0
    local sid = STATE.PlaySession
    Notify("PLAY ▶", ("Map: %s | %d steps"):format(macro.mapName or "?", #macro.steps), Color3.fromRGB(120, 220, 220))
    if _G.ACH_UI and _G.ACH_UI.OnPlayStateChanged then
        pcall(_G.ACH_UI.OnPlayStateChanged, true, macro)
    end
    task.spawn(function()
        for i, step in ipairs(macro.steps) do
            if STATE.PlaySession ~= sid or not STATE.Playing then break end
            STATE.CurrentStep = i
            local cost = step.cost
            local waitedT = 0
            if cost and cost > 0 then
                while STATE.PlaySession == sid and STATE.Playing do
                    while STATE.Paused and STATE.Playing and STATE.PlaySession == sid do task.wait(0.1) end
                    if not STATE.Playing or STATE.PlaySession ~= sid then break end
                    local cash = getCash()
                    local need = math.max(0, cost - cash)
                    if need <= 0 then break end
                    setStatus("waiting", need)
                    task.wait(CONFIG.PlayTick)
                    waitedT = waitedT + CONFIG.PlayTick
                    if waitedT > CONFIG.CashTimeoutSec then
                        setStatus("error", need)
                        Notify("step " .. i, "Cash timeout, skipping", Color3.fromRGB(255,80,80))
                        break
                    end
                end
            end
            if not STATE.Playing or STATE.PlaySession ~= sid then break end
            while STATE.Paused and STATE.Playing and STATE.PlaySession == sid do task.wait(0.1) end
            setStatus("placing", 0)
            local re = resolvePath(step.remotePath)
            if re and (re:IsA("RemoteEvent") or re:IsA("RemoteFunction")) then
                local decoded = {}
                for j = 1, (step.argc or #step.args) do decoded[j] = decodeArg(step.args[j]) end
                local ok = pcall(function()
                    if re:IsA("RemoteEvent") then
                        re:FireServer(table.unpack(decoded, 1, step.argc or #step.args))
                    else
                        re:InvokeServer(table.unpack(decoded, 1, step.argc or #step.args))
                    end
                end)
                if not ok then setStatus("error", 0) end
            else
                setStatus("error", 0)
                Notify("step " .. i, "Remote not found: " .. tostring(step.remotePath), Color3.fromRGB(255,80,80))
            end
            task.wait(0.25)
        end
        if STATE.PlaySession == sid then
            STATE.Playing = false; STATE.Paused = false
            setStatus("idle", 0)
            Notify("PLAY ■", "Macro finished", Color3.fromRGB(120,220,120))
            if _G.ACH_UI and _G.ACH_UI.OnPlayStateChanged then
                pcall(_G.ACH_UI.OnPlayStateChanged, false, macro)
            end
        end
    end)
end

function Player.Pause(v)
    if not STATE.Playing then return end
    STATE.Paused = v and true or false
    if _G.ACH_UI and _G.ACH_UI.OnPlayPaused then
        pcall(_G.ACH_UI.OnPlayPaused, STATE.Paused)
    end
end

function Player.Stop()
    if not STATE.Playing then return end
    STATE.Playing = false; STATE.Paused = false
    STATE.PlaySession = STATE.PlaySession + 1
    setStatus("idle", 0)
    Notify("PLAY ■", "Stopped by user", Color3.fromRGB(255, 180, 80))
    -- ИСПРАВЛЕНО: было G.ACH_UI (глобальная переменная без _), теперь _G.ACH_UI
    if _G.ACH_UI and _G.ACH_UI.OnPlayStateChanged then
        pcall(_G.ACH_UI.OnPlayStateChanged, false, STATE.CurrentMacro)
    end
end

-- ============================================================== --
-- 9) FILE I/O
-- ============================================================== --
local Files = {}

function Files.SaveCurrent(nameOpt)
    if not HAS_FS then Notify("Files", "Executor lacks filesystem", Color3.fromRGB(255,80,80)); return nil end
    local macro = STATE.CurrentMacro
    if not macro or not macro.steps or #macro.steps == 0 then
        Notify("Files", "Nothing to save", Color3.fromRGB(255,80,80)); return nil
    end
    ensureFolders()
    local name = safeName(nameOpt or (macro.mapName or "macro") .. "_" .. os.date("%Y%m%d%H%M%S"))
    local path = CONFIG.MacroFolder .. "/" .. name .. ".json"
    local ok, json = pcall(function() return HttpService:JSONEncode(macro) end)
    if not ok then Notify("Files", "Encode failed", Color3.fromRGB(255,80,80)); return nil end
    local okW = pcall(writefile, path, json)
    if okW then
        Notify("Saved", path, Color3.fromRGB(120,220,120))
        if _G.ACH_UI and _G.ACH_UI.OnLibraryChanged then pcall(_G.ACH_UI.OnLibraryChanged) end
        return path
    else
        Notify("Files", "Write failed", Color3.fromRGB(255,80,80))
    end
end

function Files.List()
    if not HAS_FS then return {} end
    ensureFolders()
    local out = {}
    local ok, items = pcall(listfiles, CONFIG.MacroFolder)
    if not ok or not items then return out end
    for _, f in ipairs(items) do
        if type(f) == "string" and f:lower():sub(-5) == ".json" then
            local nm = f:match("[^/\\]+$") or f
            table.insert(out, { path = f, name = nm:gsub("%.json$", "") })
        end
    end
    return out
end

function Files.Load(path)
    if not HAS_FS then return nil end
    local ok, src = pcall(readfile, path)
    if not ok or not src then Notify("Files", "Read failed", Color3.fromRGB(255,80,80)); return nil end
    local okJ, macro = pcall(function() return HttpService:JSONDecode(src) end)
    if not okJ or type(macro) ~= "table" then
        Notify("Files", "Bad JSON: " .. path, Color3.fromRGB(255,80,80)); return nil
    end
    Notify("Loaded", (macro.mapName or "?") .. " / " .. tostring(#(macro.steps or {})) .. " steps",
        Color3.fromRGB(120,220,220))
    return macro
end

function Files.Delete(path)
    if not HAS_FS then return end
    local okD = pcall(delfile, path)
    if okD and _G.ACH_UI and _G.ACH_UI.OnLibraryChanged then pcall(_G.ACH_UI.OnLibraryChanged) end
end

-- ============================================================== --
-- 10) PUBLIC API
-- ============================================================== --
_G.ACH_API = {
    StartRecord  = Recorder.Start,
    StopRecord   = Recorder.Stop,
    IsRecording  = function() return STATE.Recording end,
    GetLiveSteps = function() return STATE.LiveSteps end,

    Play     = function(macro) Player.Start(macro) end,
    PlayFile = function(path) local m = Files.Load(path); if m then Player.Start(m) end end,
    StopPlay = Player.Stop,
    SetPause = Player.Pause,
    IsPlaying = function() return STATE.Playing end,
    IsPaused  = function() return STATE.Paused end,
    GetPlayState = function()
        return {
            playing = STATE.Playing,
            paused  = STATE.Paused,
            step    = STATE.CurrentStep,
            status  = STATE.CurrentStatus,
            need    = STATE.CurrentNeed,
            macro   = STATE.CurrentMacro,
        }
    end,

    SaveCurrent = Files.SaveCurrent,
    ListLibrary = Files.List,
    LoadFile    = Files.Load,
    DeleteFile  = Files.Delete,

    GetMapName  = getMapName,
    GetCash     = getCash,
    GetCurrent  = function() return STATE.CurrentMacro end,
    Notify      = Notify,

    Destroy = function()
        STATE.Dead = true
        STATE.Recording = false; STATE.Playing = false
        pcall(function() NotifGui:Destroy() end)
        if _G.ACH_UI and _G.ACH_UI.ScreenGui then
            pcall(function() _G.ACH_UI.ScreenGui:Destroy() end)
        end
    end,
}

Notify("AnimeCrusadersHub", "v1.1 loaded — macro recorder ready", Color3.fromRGB(180, 120, 255))

-- ============================================================== --
-- 11) UI LOADER (с защитой от 404)
-- ============================================================== --
local function looksLikeHttpError(src)
    if type(src) ~= "string" or src == "" then return true end
    local head = src:sub(1, 256)
    if head:match("^%s*%d%d%d%s*:%s*") then return true end
    if head:lower():find("not found", 1, true) then return true end
    if head:lower():find("rate limit", 1, true) then return true end
    if head:match("^%s*<!DOCTYPE") or head:match("^%s*<html") then return true end
    return false
end

local ok, src = pcall(function() return game:HttpGet(UI_URL, true) end)
if not ok then
    warn("[ACH] ui.lua HTTP error: " .. tostring(src))
elseif looksLikeHttpError(src) then
    warn(("[ACH] ui.lua: сервер вернул не-Lua ответ (вероятно 404). Первые 120 символов: %q")
        :format(tostring(src):sub(1, 120)))
else
    local fn, lerr = loadstring(src, "=ui.lua")
    if fn then
        local okR, rerr = pcall(fn)
        if not okR then warn("[ACH] ui.lua runtime: " .. tostring(rerr)) end
    else
        warn("[ACH] ui.lua compile: " .. tostring(lerr))
    end
end
