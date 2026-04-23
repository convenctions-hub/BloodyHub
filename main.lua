--[[ BloodyHub main logic v1
     - Выставляет _G.BloodyHub_API для ui.lua
     - В конце подгружает ui.lua через loadstring
]]
local UI_URL = "https://raw.githubusercontent.com/conventions-hub/BloodyHub/main/ui.lua"

local HttpService   = game:GetService("HttpService")
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputSvc  = game:GetService("UserInputService")
local VirtualUser   = game:GetService("VirtualUser")
local CoreGui       = game:GetService("CoreGui")
local LocalPlayer   = Players.LocalPlayer

-- ==================== GLOBAL DEFAULTS ====================
_G.AutoQuest_Enabled   = _G.AutoQuest_Enabled   or false
_G.ESP_Enabled         = _G.ESP_Enabled         or false
_G.AutoDialog_Enabled  = (_G.AutoDialog_Enabled ~= false)
_G.FlySpeed            = _G.FlySpeed            or 120
_G.BS_Dead             = false
_G.QuestSessionId      = _G.QuestSessionId      or 0
_G.KillAura            = true
_G.AutoAttack          = true
_G.SkillSpam           = false
_G.AttackDelay         = 0.15
_G.TargetMethod        = "Nearest"
_G.TargetDistance      = 20
_G.AntiStun            = true
_G.AutoBlock           = true
_G.HitboxExtender      = false
_G.NoCooldown          = true
_G.HitboxSize          = 3

-- Чистим старый лог, если есть
for _, g in ipairs(CoreGui:GetChildren()) do
    if g.Name == "BSLog" then pcall(function() g:Destroy() end) end
end

-- ==================== DEBUG LOGGER ====================
local DebugGui = Instance.new("ScreenGui")
DebugGui.Name = "BSLog"
pcall(function() DebugGui.Parent = CoreGui end)
if not DebugGui.Parent then DebugGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local LogFrame = Instance.new("Frame")
LogFrame.Parent = DebugGui
LogFrame.BackgroundTransparency = 0.5
LogFrame.BackgroundColor3 = Color3.new(0, 0, 0)
LogFrame.Position = UDim2.new(1, -310, 0, 70)
LogFrame.Size = UDim2.new(0, 300, 0, 250)
LogFrame.BorderSizePixel = 0
local lfCorner = Instance.new("UICorner")
lfCorner.CornerRadius = UDim.new(0, 6)
lfCorner.Parent = LogFrame

local LogContainer = Instance.new("Frame")
LogContainer.Parent = LogFrame
LogContainer.Size = UDim2.new(1, -10, 1, -10)
LogContainer.Position = UDim2.new(0, 5, 0, 5)
LogContainer.BackgroundTransparency = 1
local lcLayout = Instance.new("UIListLayout")
lcLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
lcLayout.Parent = LogContainer

local function Log(msg, color)
    if _G.BS_Dead then return end
    local t = Instance.new("TextLabel")
    t.Parent = LogContainer
    t.Size = UDim2.new(1, 0, 0, 16)
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.Code
    t.TextColor3 = color or Color3.fromRGB(0, 255, 150)
    t.TextSize = 10
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Text = "[" .. os.date("%X") .. "] " .. tostring(msg)
    local ch = LogContainer:GetChildren()
    if #ch > 18 then ch[2]:Destroy() end
end

-- ==================== QUEST PARSING ====================
local function getQuestInfo()
    local pd = LocalPlayer:FindFirstChild("PlayerData")
    local sd = pd and pd:FindFirstChild("SlotData")
    local cq = sd and sd:FindFirstChild("CurrentQuests")
    if not cq or cq.Value == "" or cq.Value == "[]" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(cq.Value) end)
    if not ok or not data or not data[1] then return nil end
    local quest = data[1]
    if type(quest.Talk) == "table" then
        for npcName, done in pairs(quest.Talk) do
            if done == false or done == 0 then
                return { type = "talk", target = tostring(npcName) }
            end
        end
    end
    if type(quest.Kills) == "table" then
        for name, info in pairs(quest.Kills) do
            local needed, current
            if type(info) == "table" then
                needed = info.Needed or info.needed or 1
                current = info.Current or info.current or 0
            elseif type(info) == "number" then
                needed = math.huge; current = info
            else
                needed = 1; current = 0
            end
            if current < needed then
                return { type = "kill", target = tostring(name) }
            end
        end
    end
    if quest.TalkTo then return { type = "talk", target = tostring(quest.TalkTo) } end
    if quest.NPC    then return { type = "talk", target = tostring(quest.NPC) } end
    if type(quest.Objective) == "string" then
        local npc = quest.Objective:match("[Tt]alk to:?%s*(.+)")
        if npc then return { type = "talk", target = npc } end
    end
    return nil
end

-- ==================== UTILITIES ====================
local function getModelPosition(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    local hrp = obj:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.Position end
    if obj.PrimaryPart then return obj.PrimaryPart.Position end
    for _, p in ipairs(obj:GetDescendants()) do
        if p:IsA("BasePart") then return p.Position end
    end
    return nil
end

local function doM1() pcall(function() mouse1click() end) end

local function uprightLookAt(from, to)
    local flat = Vector3.new(to.X, from.Y, to.Z)
    if (flat - from).Magnitude < 0.01 then return CFrame.new(from) end
    return CFrame.lookAt(from, flat)
end

local savedCollide = {}
local function setGhost(on)
    local char = LocalPlayer.Character
    if not char then return end
    if on then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                if savedCollide[p] == nil then savedCollide[p] = p.CanCollide end
                p.CanCollide = false
            end
        end
    else
        for p, old in pairs(savedCollide) do
            if p and p.Parent then p.CanCollide = old end
        end
        savedCollide = {}
    end
end

local function forceUnlock()
    setGhost(false)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hrp then hrp.Anchored = false end
    if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
end

local function findNpcByBillboard(targetName)
    local lowerTarget = targetName:lower()
    for _, v in ipairs(workspace:GetDescendants()) do
        local text = nil
        if v:IsA("BillboardGui") then
            for _, child in ipairs(v:GetDescendants()) do
                if child:IsA("TextLabel") and child.Text ~= "" then
                    text = child.Text; break
                end
            end
        elseif v:IsA("TextLabel") and v.Text ~= "" then
            text = v.Text
        end
        if text and text:lower():find(lowerTarget, 1, true) then
            local part = v.Parent
            while part and part ~= workspace do
                if part:IsA("BasePart") then return part.Position, part end
                if part:IsA("Model") and not Players:GetPlayerFromCharacter(part) then
                    local pos = getModelPosition(part)
                    if pos then return pos, part end
                end
                part = part.Parent
            end
        end
    end
    return nil, nil
end

local function getNpcHRP(npcObj)
    if not npcObj or not npcObj.Parent then return nil end
    local model = npcObj
    if npcObj:IsA("BasePart") then model = npcObj.Parent end
    if model and model:IsA("Model") then
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp end
        if model.PrimaryPart then return model.PrimaryPart end
    end
    if npcObj:IsA("BasePart") then return npcObj end
    return nil
end

-- ==================== SNAP UNDER NPC ====================
local UNDER_OFFSET = 20
local function makeUnderCFrame(npcHRP)
    local p = npcHRP.Position
    return CFrame.new(p.X, p.Y - UNDER_OFFSET, p.Z)
        * CFrame.Angles(math.pi / 2, 0, 0)
end

local function startSnapLoop(hrp, npcHRP)
    if not hrp or not npcHRP then return function() end end
    local active = true
    setGhost(true)
    hrp.Anchored = true
    hrp.CFrame = makeUnderCFrame(npcHRP)
    Log(string.format("SNAP UNDER: Y=%.1f", npcHRP.Position.Y - UNDER_OFFSET),
        Color3.fromRGB(0, 255, 200))
    local conn = RunService.Heartbeat:Connect(function()
        if not active then return end
        if not hrp or not hrp.Parent then active = false; return end
        if npcHRP and npcHRP.Parent then
            hrp.Anchored = true
            hrp.CFrame = makeUnderCFrame(npcHRP)
        end
    end)
    return function()
        active = false
        conn:Disconnect()
        Log("SNAP STOP", Color3.fromRGB(180, 180, 180))
    end
end

local function findKillTarget(targetName)
    local lowerTarget = targetName:lower()
    local hrp0 = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local best, bestDist = nil, math.huge
    local npcFolder = workspace:FindFirstChild("Npcs")
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Model") and not Players:GetPlayerFromCharacter(v)
            and v:FindFirstChildOfClass("Humanoid")
            and v:FindFirstChildOfClass("Humanoid").Health > 0 then
            local isQuestGiver = false
            if npcFolder then
                local p = v.Parent
                while p and p ~= workspace do
                    if p == npcFolder then isQuestGiver = true; break end
                    p = p.Parent
                end
            end
            if not isQuestGiver then
                local matched = false
                for _, child in ipairs(v:GetDescendants()) do
                    if child:IsA("TextLabel") and child.Text ~= "" then
                        if child.Text:lower():find(lowerTarget, 1, true) then
                            matched = true; break
                        end
                    end
                end
                if not matched and v.Name:lower():find(lowerTarget, 1, true) then
                    matched = true
                end
                if matched then
                    local root = v:FindFirstChild("HumanoidRootPart")
                    if root and hrp0 then
                        local d = (root.Position - hrp0.Position).Magnitude
                        if d < bestDist then best = v; bestDist = d end
                    end
                end
            end
        end
    end
    return best, bestDist
end

local function flyTo(getTargetPos, arriveDist, isCancelled)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return false end
    setGhost(true)
    hrp.Anchored = true
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    local done = false
    local nilTargetSince = nil
    local conn = RunService.Heartbeat:Connect(function(dt)
        if _G.BS_Dead or not _G.AutoQuest_Enabled then done = true; return end
        if isCancelled and isCancelled() then done = true; return end
        if not hrp or not hrp.Parent then done = true; return end
        local targetPos = getTargetPos()
        if not targetPos then
            if not nilTargetSince then nilTargetSince = os.clock() end
            if os.clock() - nilTargetSince > 0.8 then done = true end
            return
        end
        nilTargetSince = nil
        local cur   = hrp.Position
        local delta = targetPos - cur
        local dist  = delta.Magnitude
        if dist <= arriveDist then done = true; return end
        local step    = math.min(_G.FlySpeed * dt, dist)
        local newPos  = cur + delta.Unit * step
        local flatDir = Vector3.new(delta.X, 0, delta.Z)
        if flatDir.Magnitude > 0.05 then
            hrp.CFrame = CFrame.new(newPos, newPos + flatDir)
        else
            hrp.CFrame = CFrame.new(newPos)
        end
    end)
    local t0 = os.clock()
    while not done and not _G.BS_Dead and _G.AutoQuest_Enabled do
        if os.clock() - t0 > 25 then Log("FLY TIMEOUT", Color3.fromRGB(255,120,0)); break end
        task.wait()
    end
    conn:Disconnect()
    return true
end

local function clickDialogOption()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui:IsA("TextButton") and gui.Visible then
            local text = gui.Text or ""
            if text:find("1%.") or text:find("Yes") or text:find("Accept") or text:find("Sure") then
                if gui:GetFullName():find("BloodyHub") or gui:GetFullName():find("BSLog") then continue end
                pcall(function()
                    for _, c in ipairs(getconnections(gui.MouseButton1Click)) do c:Fire() end
                end)
                pcall(function() firesignal(gui.MouseButton1Click) end)
                pcall(function() firesignal(gui.Activated) end)
                return true
            end
        end
    end
    return false
end

-- ==================== TALK / KILL LOGIC ====================
local Talking, Killing = false, false
local CurrentTarget = nil

local function doTalkQuest(targetName, sessionId)
    if Talking then return end
    Talking = true
    local stopSnap = nil
    local ok, err = pcall(function()
        local cq = LocalPlayer:FindFirstChild("PlayerData")
            and LocalPlayer.PlayerData:FindFirstChild("SlotData")
            and LocalPlayer.PlayerData.SlotData:FindFirstChild("CurrentQuests")
        local oldValue = cq and cq.Value or ""
        local _, npcObj = findNpcByBillboard(targetName)
        if not npcObj then
            Log("NPC NOT FOUND: [" .. targetName .. "]", Color3.fromRGB(255, 50, 50))
            return
        end
        local npcHRP = getNpcHRP(npcObj)
        if not npcHRP then
            Log("HRP NOT FOUND: [" .. targetName .. "]", Color3.fromRGB(255, 50, 50))
            return
        end
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        Log("TALK -> " .. targetName, Color3.fromRGB(0, 200, 255))
        stopSnap = startSnapLoop(hrp, npcHRP)
        task.wait(0.2)
        if _G.QuestSessionId ~= sessionId then return end
        local activated = false
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("ProximityPrompt") and v.Enabled then
                local part = v.Parent
                if part and part:IsA("BasePart")
                    and (part.Position - npcHRP.Position).Magnitude < 10 then
                    v.HoldDuration = 0
                    pcall(function() fireproximityprompt(v) end)
                    Log("PROMPT: " .. part.Name, Color3.fromRGB(255, 255, 0))
                    activated = true; break
                end
            end
        end
        if not activated then Log("NO PROMPT — dialog fallback", Color3.fromRGB(255,150,0)) end
        if _G.AutoDialog_Enabled then
            task.wait(0.5); clickDialogOption()
            task.wait(0.3); clickDialogOption()
            task.wait(0.3); clickDialogOption()
        end
        local t0 = os.clock()
        while os.clock() - t0 < 6 do
            if cq and cq.Value ~= oldValue then
                Log("QUEST UPDATED ✓", Color3.fromRGB(0,255,150)); break
            end
            task.wait(0.1)
        end
        if stopSnap then stopSnap(); stopSnap = nil end
        forceUnlock()
    end)
    Talking = false
    if stopSnap then pcall(stopSnap) end
    if not ok then
        Log("TALK ERR: " .. tostring(err), Color3.fromRGB(255, 0, 0))
        forceUnlock()
    end
end

local function doKillLoop(targetName, sessionId)
    if Killing then return end
    Killing = true
    local ok, err = pcall(function()
        while _G.AutoQuest_Enabled and _G.QuestSessionId == sessionId and not _G.BS_Dead do
            local mobHum = CurrentTarget and CurrentTarget:FindFirstChildOfClass("Humanoid")
            if not CurrentTarget or not CurrentTarget.Parent or not mobHum or mobHum.Health <= 0 then
                local mob, dist = findKillTarget(targetName)
                if mob then
                    CurrentTarget = mob
                    Log("TARGET: " .. mob.Name .. " (" .. math.floor(dist) .. "m)",
                        Color3.fromRGB(255, 100, 100))
                else
                    Log("SEARCHING: " .. targetName, Color3.fromRGB(255, 150, 0))
                    task.wait(1); continue
                end
            end
            local quest = getQuestInfo()
            if not quest or quest.type ~= "kill"
                or quest.target:lower() ~= targetName:lower() then
                Log("KILL DONE ✓", Color3.fromRGB(0, 255, 150)); break
            end
            local mob = CurrentTarget
            if not mob or not mob.Parent then CurrentTarget = nil; continue end
            local mobHRP = mob:FindFirstChild("HumanoidRootPart")
            if not mobHRP then CurrentTarget = nil; continue end
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(0.5); continue end
            local dist = (hrp.Position - mobHRP.Position).Magnitude
            if dist > 5 then
                flyTo(function()
                    if not mob or not mob.Parent then return nil end
                    local r = mob:FindFirstChild("HumanoidRootPart")
                    return r and r.Position or nil
                end, 5, function()
                    return not _G.AutoQuest_Enabled or _G.QuestSessionId ~= sessionId
                end)
                forceUnlock()
            else
                local attackStart = os.clock()
                while _G.AutoQuest_Enabled and _G.QuestSessionId == sessionId
                    and not _G.BS_Dead and mob and mob.Parent do
                    local mh = mob:FindFirstChildOfClass("Humanoid")
                    if not mh or mh.Health <= 0 then break end
                    local hr = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not hr then break end
                    if (hr.Position - mobHRP.Position).Magnitude > 8 then break end
                    hr.CFrame = uprightLookAt(hr.Position, mobHRP.Position)
                    doM1()
                    task.wait(_G.AttackDelay or 0.08)
                    if os.clock() - attackStart > 60 then
                        Log("ATTACK TIMEOUT", Color3.fromRGB(255, 100, 0))
                        CurrentTarget = nil; break
                    end
                end
            end
        end
    end)
    Killing = false
    CurrentTarget = nil
    forceUnlock()
    if not ok then Log("KILL ERR: " .. tostring(err), Color3.fromRGB(255, 0, 0)) end
end

-- ==================== MAIN QUEST LOOP + WATCHDOG ====================
task.spawn(function()
    local lastQuestType, lastQuestTarget = nil, nil
    local lastActivityTime = os.clock()
    while task.wait(0.5) do
        if _G.BS_Dead then break end
        if not _G.AutoQuest_Enabled then
            lastQuestType = nil; lastQuestTarget = nil; continue
        end
        if Killing or Talking then
            if os.clock() - lastActivityTime > 30 then
                Log("WATCHDOG: reset", Color3.fromRGB(255, 200, 0))
                Killing = false; Talking = false
                CurrentTarget = nil; forceUnlock()
                lastActivityTime = os.clock()
            end
        else
            lastActivityTime = os.clock()
        end
        local quest = getQuestInfo()
        if not quest then
            if lastQuestType ~= nil then
                Log("NO QUEST — idle", Color3.fromRGB(180, 180, 180))
                lastQuestType = nil; lastQuestTarget = nil
            end
            CurrentTarget = nil; continue
        end
        if quest.type ~= lastQuestType or quest.target ~= lastQuestTarget then
            lastQuestType = quest.type; lastQuestTarget = quest.target
            Talking = false; Killing = false; CurrentTarget = nil
            lastActivityTime = os.clock()
            Log("QUEST [" .. quest.type:upper() .. "]: " .. quest.target,
                Color3.fromRGB(0, 220, 255))
        end
        local sid = _G.QuestSessionId
        if quest.type == "talk" and not Talking then
            task.spawn(function() doTalkQuest(quest.target, sid) end)
        elseif quest.type == "kill" and not Killing then
            task.spawn(function() doKillLoop(quest.target, sid) end)
        end
    end
end)

-- ==================== ESP ====================
local espConnections = {}
local function CreateESP(p)
    if p == LocalPlayer then return end
    local function Setup(char)
        if not char then return end
        local head = char:WaitForChild("Head", 10)
        if not head then return end
        local bg = Instance.new("BillboardGui")
        bg.Parent = head
        bg.Name = "BS_ESP"; bg.AlwaysOnTop = true
        bg.Size = UDim2.new(0, 100, 0, 30)
        local tl = Instance.new("TextLabel")
        tl.Parent = bg
        tl.Size = UDim2.new(1, 0, 1, 0)
        tl.BackgroundTransparency = 1
        tl.TextColor3 = Color3.new(1, 1, 1)
        tl.Font = Enum.Font.GothamBold
        tl.TextSize = 13
        local highOk, high = pcall(Instance.new, "Highlight")
        if not highOk then high = nil end
        if high then
            high.Name = "BS_ESP"
            high.FillColor = Color3.fromRGB(255, 0, 50)
            high.Parent = char
        end
        local conn = RunService.Heartbeat:Connect(function()
            if _G.BS_Dead then bg:Destroy(); if high then high:Destroy() end; return end
            if _G.ESP_Enabled and char and char.Parent
                and LocalPlayer.Character
                and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local d = math.floor(
                    (LocalPlayer.Character.HumanoidRootPart.Position - head.Position).Magnitude)
                tl.Text = p.Name .. " [" .. d .. "m]"
                bg.Enabled = true
                if high then high.Enabled = true end
            else
                bg.Enabled = false
                if high then high.Enabled = false end
            end
        end)
        table.insert(espConnections, conn)
    end
    p.CharacterAdded:Connect(Setup)
    if p.Character then Setup(p.Character) end
end
for _, p in pairs(Players:GetPlayers()) do CreateESP(p) end
Players.PlayerAdded:Connect(CreateESP)

-- ==================== DESTROY SESSION ====================
_G.BS_DestroyFn = function()
    Log("DESTROYING...", Color3.fromRGB(255, 50, 50))
    _G.BS_Dead = true; _G.AutoQuest_Enabled = false; _G.ESP_Enabled = false
    Talking = false; Killing = false; CurrentTarget = nil
    forceUnlock()
    for _, c in ipairs(espConnections) do pcall(function() c:Disconnect() end) end
    espConnections = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character then
            for _, obj in ipairs(p.Character:GetDescendants()) do
                if obj.Name == "BS_ESP" then pcall(function() obj:Destroy() end) end
            end
        end
    end
    pcall(function() DebugGui:Destroy() end)
    if _G.BloodyHub_UI and _G.BloodyHub_UI.ScreenGui then
        pcall(function() _G.BloodyHub_UI.ScreenGui:Destroy() end)
    end
    if _G.BloodyHub_Loading and _G.BloodyHub_Loading.ScreenGui then
        pcall(function() _G.BloodyHub_Loading.ScreenGui:Destroy() end)
    end
end

LocalPlayer.Idled:Connect(function()
    if _G.BS_Dead then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    savedCollide = {}
    Talking = false; Killing = false; CurrentTarget = nil
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if hrp then hrp.Anchored = false end
    Log("RESPAWN — state reset", Color3.fromRGB(200, 200, 0))
end)

-- ==================== PUBLIC API FOR UI ====================
_G.BloodyHub_API = {
    Log = Log,

    -- Toggles (вызываются из ui.lua при клике)
    SetAutoQuest = function(v)
        _G.AutoQuest_Enabled = v and true or false
        if v then
            _G.QuestSessionId = _G.QuestSessionId + 1
        else
            Talking = false; Killing = false
        end
    end,
    SetAutoDialog = function(v) _G.AutoDialog_Enabled = v and true or false end,
    SetESP        = function(v) _G.ESP_Enabled = v and true or false end,

    -- Sliders / misc
    SetFlySpeed    = function(v) _G.FlySpeed = tonumber(v) or _G.FlySpeed end,
    SetAttackDelay = function(v) _G.AttackDelay = tonumber(v) or _G.AttackDelay end,

    -- Session
    DestroySession = function() if _G.BS_DestroyFn then _G.BS_DestroyFn() end end,
}

Log("BloodyHub v82 LOADED", Color3.fromRGB(0, 255, 255))

-- ==================== LOAD UI ====================
local ok, src = pcall(function() return game:HttpGet(UI_URL, true) end)
if ok and src and src ~= "" then
    local fn, err = loadstring(src)
    if fn then
        pcall(fn)
    else
        warn("[BloodyHub] ui.lua compile: " .. tostring(err))
    end
else
    warn("[BloodyHub] ui.lua fetch failed")
end
