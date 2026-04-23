--[[ BloodyHub main logic v2
- Выставляет _G.BloodyHub_API для ui.lua
- В конце подгружает ui.lua через loadstring
]]
local UI_URL = "https://raw.githubusercontent.com/convenctions-hub/BloodyHub/main/ui.lua"

local HttpService   = game:GetService("HttpService")
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputSvc  = game:GetService("UserInputService")
local VirtualUser   = game:GetService("VirtualUser")
local CoreGui       = game:GetService("CoreGui")
local LocalPlayer   = Players.LocalPlayer

-- ==================== GLOBAL DEFAULTS ====================
_G.AutoQuest_Enabled   = _G.AutoQuest_Enabled  or false
_G.ESP_Enabled         = _G.ESP_Enabled         or false
_G.AutoDialog_Enabled  = _G.AutoQuest_Enabled
_G.FlySpeed            = 120
_G.BS_Dead             = false
_G.QuestSessionId      = _G.QuestSessionId      or 0
_G.AttackDelay         = 0.08
_G.KillSnapDepth       = _G.KillSnapDepth        or 5

-- Auto Raid globals
_G.AutoRaid_Enabled    = false
_G.AutoRaid_Retry      = false
_G.AutoRaid_Return     = false
_G.AutoRaid_Selected   = nil   -- строка вида "Muhammad Avdol Raid"
_G.RaidSessionId       = _G.RaidSessionId or 0

-- Чистим старый лог
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
LogFrame.BackgroundColor3 = Color3.new(0,0,0)
LogFrame.Position = UDim2.new(1,-310,0,70)
LogFrame.Size = UDim2.new(0,300,0,250)
LogFrame.BorderSizePixel = 0
local lfCorner = Instance.new("UICorner")
lfCorner.CornerRadius = UDim.new(0,6)
lfCorner.Parent = LogFrame

local LogContainer = Instance.new("Frame")
LogContainer.Parent = LogFrame
LogContainer.Size = UDim2.new(1,-10,1,-10)
LogContainer.Position = UDim2.new(0,5,0,5)
LogContainer.BackgroundTransparency = 1
local lcLayout = Instance.new("UIListLayout")
lcLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
lcLayout.Parent = LogContainer

local function Log(msg, color)
    if _G.BS_Dead then return end
    local t = Instance.new("TextLabel")
    t.Parent = LogContainer
    t.Size = UDim2.new(1,0,0,16)
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.Code
    t.TextColor3 = color or Color3.fromRGB(0,255,150)
    t.TextSize = 10
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Text = "["..os.date("%X").."] "..tostring(msg)
    local ch = LogContainer:GetChildren()
    if #ch > 18 then ch[2]:Destroy() end
end

-- ==================== RAID NPC TABLE ====================
-- bossName  = имя объекта в workspace.Live для поиска цели рейда
-- npcName   = имя NPC (по billboard) в основном мире для начала рейда
-- ПОЗИЦИИ NPC — заполни после того как скинешь координаты
local RAID_DATA = {
    ["Muhammad Avdol Raid"] = {
        bossName = "Muhammad Avdol",
        npcName  = "Avdol",        -- уточни имя NPC в основном мире
        npcPos   = nil,            -- Vector3.new(X,Y,Z) — добавь позицию
    },
    ["Jotaro Kujo Raid"] = {
        bossName = "Jotaro Kujo",
        npcName  = "Jotaro",
        npcPos   = nil,
    },
    ["Kira Yoshikage Raid"] = {
        bossName = "Yoshikage Kira",
        npcName  = "Kira",
        npcPos   = nil,
    },
    ["Dio Brando Raid"] = {
        bossName = "Dio Brando",
        npcName  = "Dio",
        npcPos   = nil,
    },
    ["Prison Escape Raid"] = {
        bossName = "Prison Guard",
        npcName  = "Prison Warden",
        npcPos   = nil,
    },
    ["Death 13 Raid"] = {
        bossName = "Death 13",
        npcName  = "Death 13",
        npcPos   = nil,
    },
    ["Twoh Raid"] = {
        bossName = "DIO Over Heaven",
        npcName  = "Dio Over Heaven",
        npcPos   = nil,
    },
}

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
                needed  = info.Needed  or info.needed  or 1
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
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
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

-- ==================== SNAP UNDER MOB ====================
local function makeUnderCFrame(npcHRP)
    local p = npcHRP.Position
    return CFrame.new(p.X, p.Y - (_G.KillSnapDepth or 5), p.Z)
        * CFrame.Angles(math.pi / 2, 0, 0)
end

local function startSnapLoop(hrp, npcHRP)
    if not hrp or not npcHRP then return function() end end
    local active = true
    setGhost(true)
    hrp.Anchored = true
    hrp.CFrame = makeUnderCFrame(npcHRP)
    Log(string.format("SNAP: depth=%.1f", _G.KillSnapDepth or 5), Color3.fromRGB(0,255,200))
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
        Log("SNAP STOP", Color3.fromRGB(180,180,180))
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
        if _G.BS_Dead then done = true; return end
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
        local step   = math.min(_G.FlySpeed * dt, dist)
        local newPos = cur + delta.Unit * step
        local flatDir = Vector3.new(delta.X, 0, delta.Z)
        if flatDir.Magnitude > 0.05 then
            hrp.CFrame = CFrame.new(newPos, newPos + flatDir)
        else
            hrp.CFrame = CFrame.new(newPos)
        end
    end)
    local t0 = os.clock()
    while not done and not _G.BS_Dead do
        if os.clock() - t0 > 30 then Log("FLY TIMEOUT", Color3.fromRGB(255,120,0)); break end
        task.wait()
    end
    conn:Disconnect()
    return true
end

-- ==================== FIRE ALL PROXIMITY PROMPTS NEAR NPC ====================
local function fireAllPromptsNear(npcHRP, radius)
    radius = radius or 12
    local fired = 0
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("ProximityPrompt") and v.Enabled then
            local part = v.Parent
            if part and part:IsA("BasePart")
                and (part.Position - npcHRP.Position).Magnitude < radius then
                v.HoldDuration = 0
                pcall(function() fireproximityprompt(v) end)
                Log("PROMPT fired: "..part.Name, Color3.fromRGB(255,255,0))
                fired = fired + 1
            end
        end
    end
    return fired > 0
end

-- ==================== DIALOG CLICK (улучшенный polling) ====================
-- Ищет первую кнопку варианта 1 в PlayerGui (GUI-диалоги игры)
local function clickDialogOption()
    -- Стратегия 1: Roblox Dialog/DialogChoice через RemoteEvent
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Dialog") and v.InUse then
            local choices = {}
            for _, c in ipairs(v:GetChildren()) do
                if c:IsA("DialogChoice") then table.insert(choices, c) end
            end
            table.sort(choices, function(a,b)
                return (a.ResponseOrder or 0) < (b.ResponseOrder or 0)
            end)
            for _, c in ipairs(choices) do
                for _, re in ipairs(v:GetDescendants()) do
                    if re:IsA("RemoteEvent") then pcall(function() re:FireServer(c) end) end
                end
                pcall(function() firesignal(c.GoodbyeChoiceSelected) end)
                Log("DIALOG CHOICE (native)", Color3.fromRGB(0,255,200))
                return true
            end
        end
    end

    -- Стратегия 2: GUI-кнопки в PlayerGui
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end

    local best = nil
    local bestPrio = 999
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui:IsA("TextButton") and gui.Visible and gui.Active then
            local name = gui:GetFullName()
            if not name:find("BloodyHub") and not name:find("BSLog") then
                local text = (gui.Text or ""):lower()
                local prio = 999
                if text:match("^%s*1[%.]")                     then prio = 1
                elseif text:match("^%s*yes")                   then prio = 2
                elseif text:match("^%s*accept")                then prio = 3
                elseif text:match("^%s*sure")                  then prio = 4
                elseif text:match("^%s*ok%s*$")               then prio = 5
                end
                if prio < bestPrio then bestPrio = prio; best = gui end
            end
        end
    end
    if best then
        pcall(function()
            for _, c in ipairs(getconnections(best.MouseButton1Click)) do c:Fire() end
        end)
        pcall(function() firesignal(best.MouseButton1Click) end)
        pcall(function() firesignal(best.Activated) end)
        Log("GUI BTN clicked: "..(best.Text or "?"), Color3.fromRGB(0,255,200))
        return true
    end
    return false
end

-- Ждёт появления кнопки диалога и кликает, timeout в секундах
local function waitAndClickDialog(timeoutSecs)
    local t0 = os.clock()
    while os.clock() - t0 < timeoutSecs do
        if clickDialogOption() then return true end
        task.wait(0.15)
    end
    return false
end

-- ==================== TALK LOGIC (ПОЛНЫЙ БЛОК ДО ЗАВЕРШЕНИЯ ДИАЛОГА) ====================
local Talking, Killing = false, false
local CurrentTarget = nil

local function doTalkQuest(targetName, sessionId)
    if Talking then return end
    Talking = true
    local ok, err = pcall(function()
        local pd  = LocalPlayer:FindFirstChild("PlayerData")
        local sd  = pd and pd:FindFirstChild("SlotData")
        local cq  = sd and sd:FindFirstChild("CurrentQuests")
        local oldValue = cq and cq.Value or ""

        local _, npcObj = findNpcByBillboard(targetName)
        if not npcObj then
            Log("NPC NOT FOUND: ["..targetName.."]", Color3.fromRGB(255,50,50))
            return
        end
        local npcHRP = getNpcHRP(npcObj)
        if not npcHRP then
            Log("HRP NOT FOUND: ["..targetName.."]", Color3.fromRGB(255,50,50))
            return
        end
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        Log("TALK -> "..targetName, Color3.fromRGB(0,200,255))

        -- Летим к NPC
        flyTo(function()
            if not npcHRP or not npcHRP.Parent then return nil end
            return npcHRP.Position
        end, 6, function() return _G.QuestSessionId ~= sessionId end)
        forceUnlock()
        if _G.QuestSessionId ~= sessionId then return end

        -- ======= ЦИКЛ: жмём proximity prompt и ждём диалог, повторяем пока квест не обновится =======
        local questDone = false
        local attemptMax = 5
        for attempt = 1, attemptMax do
            if _G.QuestSessionId ~= sessionId or _G.BS_Dead then break end

            -- Снова подлетаем вплотную (на случай дрейфа)
            flyTo(function()
                if not npcHRP or not npcHRP.Parent then return nil end
                return npcHRP.Position
            end, 5, function() return _G.QuestSessionId ~= sessionId end)
            forceUnlock()
            if _G.QuestSessionId ~= sessionId then break end

            task.wait(0.25)

            -- Жмём все ProximityPrompt рядом с NPC
            local fired = fireAllPromptsNear(npcHRP, 12)
            if not fired then
                Log("NO PROMPT (attempt "..attempt..")", Color3.fromRGB(255,150,0))
            end

            -- Ждём появления диалога и кликаем (до 4 секунд)
            local clicked = waitAndClickDialog(4)
            if clicked then
                -- После клика может быть цепочка диалогов — кликаем ещё 2 раза с паузами
                task.wait(0.4)
                if _G.QuestSessionId == sessionId then clickDialogOption() end
                task.wait(0.4)
                if _G.QuestSessionId == sessionId then clickDialogOption() end
                task.wait(0.4)
                if _G.QuestSessionId == sessionId then clickDialogOption() end
            end

            -- Ждём обновления квеста (до 5 секунд)
            local t0 = os.clock()
            while os.clock() - t0 < 5 do
                if cq and cq.Value ~= oldValue then
                    Log("QUEST UPDATED ✓", Color3.fromRGB(0,255,150))
                    questDone = true
                    break
                end
                task.wait(0.1)
            end

            if questDone then break end
            Log("RETRY DIALOG "..attempt.."/"..attemptMax, Color3.fromRGB(255,200,0))
            task.wait(0.5)
        end

        if not questDone then
            Log("DIALOG TIMEOUT — продолжаем", Color3.fromRGB(255,100,0))
        end
    end)
    Talking = false
    if not ok then
        Log("TALK ERR: "..tostring(err), Color3.fromRGB(255,0,0))
        forceUnlock()
    end
end

-- ==================== KILL LOGIC ====================
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
                    Log("TARGET: "..mob.Name.." ("..math.floor(dist).."m)", Color3.fromRGB(255,100,100))
                else
                    Log("SEARCHING: "..targetName, Color3.fromRGB(255,150,0))
                    task.wait(1); continue
                end
            end
            local quest = getQuestInfo()
            if not quest or quest.type ~= "kill"
                or quest.target:lower() ~= targetName:lower() then
                Log("KILL DONE ✓", Color3.fromRGB(0,255,150)); break
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
                local stopSnap = startSnapLoop(hrp, mobHRP)
                local attackStart = os.clock()
                while _G.AutoQuest_Enabled and _G.QuestSessionId == sessionId
                    and not _G.BS_Dead and mob and mob.Parent do
                    local mh = mob:FindFirstChildOfClass("Humanoid")
                    if not mh or mh.Health <= 0 then break end
                    local hr = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not hr then break end
                    if (hr.Position - mobHRP.Position).Magnitude > 8 then break end
                    doM1()
                    task.wait(_G.AttackDelay or 0.08)
                    if os.clock() - attackStart > 60 then
                        Log("ATTACK TIMEOUT", Color3.fromRGB(255,100,0))
                        CurrentTarget = nil; break
                    end
                end
                stopSnap()
                forceUnlock()
            end
        end
    end)
    Killing = false
    CurrentTarget = nil
    forceUnlock()
    if not ok then Log("KILL ERR: "..tostring(err), Color3.fromRGB(255,0,0)) end
end

-- ==================== MAIN QUEST LOOP ====================
task.spawn(function()
    local lastQuestType, lastQuestTarget = nil, nil
    local lastActivityTime = os.clock()
    while task.wait(0.5) do
        if _G.BS_Dead then break end
        if not _G.AutoQuest_Enabled then
            lastQuestType = nil; lastQuestTarget = nil; continue
        end
        if Killing or Talking then
            if os.clock() - lastActivityTime > 35 then
                Log("WATCHDOG: reset", Color3.fromRGB(255,200,0))
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
                Log("NO QUEST — idle", Color3.fromRGB(180,180,180))
                lastQuestType = nil; lastQuestTarget = nil
            end
            CurrentTarget = nil; continue
        end
        if quest.type ~= lastQuestType or quest.target ~= lastQuestTarget then
            lastQuestType = quest.type; lastQuestTarget = quest.target
            Talking = false; Killing = false; CurrentTarget = nil
            lastActivityTime = os.clock()
            Log("QUEST ["..quest.type:upper().."]: "..quest.target, Color3.fromRGB(0,220,255))
        end
        local sid = _G.QuestSessionId
        if quest.type == "talk" and not Talking then
            task.spawn(function() doTalkQuest(quest.target, sid) end)
        elseif quest.type == "kill" and not Killing then
            task.spawn(function() doKillLoop(quest.target, sid) end)
        end
    end
end)

-- ==================== AUTO RAID ====================

-- Найти объект цели рейда в workspace.Live
local function findRaidTarget(bossName)
    local live = workspace:FindFirstChild("Live")
    if not live then return nil end
    local lower = bossName:lower()
    local hrp0 = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local best, bestDist = nil, math.huge
    for _, v in ipairs(live:GetDescendants()) do
        if v:IsA("Model") and not Players:GetPlayerFromCharacter(v) then
            local hum = v:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local matched = v.Name:lower():find(lower, 1, true)
                if not matched then
                    -- проверяем billboard
                    for _, child in ipairs(v:GetDescendants()) do
                        if child:IsA("TextLabel") and child.Text:lower():find(lower, 1, true) then
                            matched = true; break
                        end
                    end
                end
                if matched then
                    local root = v:FindFirstChild("HumanoidRootPart")
                    if root and hrp0 then
                        local d = (root.Position - hrp0.Position).Magnitude
                        if d < bestDist then best = v; bestDist = d end
                    elseif root then
                        best = v; bestDist = 0
                    end
                end
            end
        end
    end
    return best
end

-- Кликнуть кнопку пост-рейда (Auto Retry или Return to menu)
local function clickPostRaidButton(pattern)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui:IsA("TextButton") or gui:IsA("TextLabel") then
            local text = (gui.Text or ""):lower()
            if text:find(pattern:lower(), 1, true) then
                local fullName = gui:GetFullName()
                if not fullName:find("BloodyHub") and not fullName:find("BSLog") then
                    pcall(function()
                        for _, c in ipairs(getconnections(gui.MouseButton1Click)) do c:Fire() end
                    end)
                    pcall(function() firesignal(gui.MouseButton1Click) end)
                    pcall(function() firesignal(gui.Activated) end)
                    Log("POST-RAID BTN: "..gui.Text, Color3.fromRGB(0,255,200))
                    return true
                end
            end
        end
    end
    return false
end

-- Проверить, появилось ли пост-рейдовое окно
local function waitForPostRaidGui(timeoutSecs)
    local t0 = os.clock()
    while os.clock() - t0 < timeoutSecs do
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            for _, gui in ipairs(playerGui:GetDescendants()) do
                if (gui:IsA("TextButton") or gui:IsA("TextLabel")) and gui.Visible then
                    local text = (gui.Text or ""):lower()
                    if text:find("auto retry") or text:find("return to menu") then
                        return true
                    end
                end
            end
        end
        task.wait(0.3)
    end
    return false
end

local RaidRunning = false

local function doRaidLoop(raidName, raidSid)
    if RaidRunning then return end
    RaidRunning = true
    local ok, err = pcall(function()
        local data = RAID_DATA[raidName]
        if not data then
            Log("RAID DATA NOT FOUND: "..tostring(raidName), Color3.fromRGB(255,0,0))
            return
        end
        Log("RAID START: "..raidName, Color3.fromRGB(255,180,0))

        -- === Шаг 1: Найти NPC в основном мире и поговорить ===
        -- (NPC запускает рейд через proximity prompt + option 1)
        local _, npcObj = findNpcByBillboard(data.npcName)

        -- Если позиция задана явно и NPC не найден по billboard — летим к позиции
        if not npcObj and data.npcPos then
            Log("NPC billboard not found, fly to npcPos", Color3.fromRGB(255,200,0))
            flyTo(function() return data.npcPos end, 8,
                function() return _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled end)
            forceUnlock()
            -- повторная попытка поиска после подлёта
            _, npcObj = findNpcByBillboard(data.npcName)
        end

        if not npcObj then
            Log("RAID NPC NOT FOUND: "..data.npcName, Color3.fromRGB(255,0,0))
            return
        end

        local npcHRP = getNpcHRP(npcObj)
        if not npcHRP then
            Log("RAID NPC HRP NOT FOUND", Color3.fromRGB(255,0,0))
            return
        end

        -- Летим к NPC
        flyTo(function()
            if not npcHRP or not npcHRP.Parent then return nil end
            return npcHRP.Position
        end, 6, function() return _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled end)
        forceUnlock()
        if _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled then return end

        task.wait(0.3)

        -- Жмём proximity prompt + диалог (до 5 попыток)
        for attempt = 1, 5 do
            if _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled then break end
            flyTo(function()
                if not npcHRP or not npcHRP.Parent then return nil end
                return npcHRP.Position
            end, 5, function() return _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled end)
            forceUnlock()
            task.wait(0.25)
            fireAllPromptsNear(npcHRP, 12)
            local clicked = waitAndClickDialog(4)
            if clicked then
                task.wait(0.4); clickDialogOption()
                task.wait(0.4); clickDialogOption()
                Log("RAID DIALOG CLICKED (attempt "..attempt..")", Color3.fromRGB(0,255,200))
                break
            end
            Log("RAID DIALOG RETRY "..attempt, Color3.fromRGB(255,200,0))
            task.wait(0.5)
        end

        -- === Шаг 2: Ждём телепорт в рейд (workspace.Live появляется с боссом) ===
        Log("WAITING FOR TELEPORT TO RAID...", Color3.fromRGB(255,200,0))
        local teleported = false
        local t0 = os.clock()
        while os.clock() - t0 < 25 do
            if not _G.AutoRaid_Enabled or _G.RaidSessionId ~= raidSid then return end
            local target = findRaidTarget(data.bossName)
            if target then
                teleported = true
                Log("IN RAID — target found: "..target.Name, Color3.fromRGB(0,255,100))
                break
            end
            task.wait(0.5)
        end
        if not teleported then
            Log("TELEPORT TIMEOUT", Color3.fromRGB(255,100,0))
            return
        end

        -- === Шаг 3: Убиваем всех мобов в workspace.Live по имени босса ===
        local raidKillStart = os.clock()
        while _G.AutoRaid_Enabled and _G.RaidSessionId == raidSid and not _G.BS_Dead do
            -- Таймаут рейда 10 минут
            if os.clock() - raidKillStart > 600 then
                Log("RAID KILL TIMEOUT", Color3.fromRGB(255,100,0)); break
            end

            local mob = findRaidTarget(data.bossName)
            if not mob then
                Log("RAID: no more targets — waiting for post-raid GUI", Color3.fromRGB(0,255,150))
                break
            end

            local mobHRP = mob:FindFirstChild("HumanoidRootPart")
            if not mobHRP then task.wait(0.5); continue end

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
                    return not _G.AutoRaid_Enabled or _G.RaidSessionId ~= raidSid
                end)
                forceUnlock()
            else
                local stopSnap = startSnapLoop(hrp, mobHRP)
                local attackStart = os.clock()
                while _G.AutoRaid_Enabled and _G.RaidSessionId == raidSid
                    and not _G.BS_Dead and mob and mob.Parent do
                    local mh = mob:FindFirstChildOfClass("Humanoid")
                    if not mh or mh.Health <= 0 then break end
                    local hr = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not hr then break end
                    if (hr.Position - mobHRP.Position).Magnitude > 8 then break end
                    doM1()
                    task.wait(_G.AttackDelay or 0.08)
                    if os.clock() - attackStart > 60 then
                        Log("RAID ATTACK TIMEOUT", Color3.fromRGB(255,100,0)); break
                    end
                end
                stopSnap()
                forceUnlock()
            end
        end

        -- === Шаг 4: Пост-рейд — Auto Retry / Auto Return ===
        if not _G.AutoRaid_Enabled or _G.RaidSessionId ~= raidSid then return end

        -- Ждём пост-рейдовое GUI
        Log("WAITING POST-RAID GUI...", Color3.fromRGB(200,200,0))
        local hasGui = waitForPostRaidGui(15)

        if _G.AutoRaid_Retry then
            local ok2 = clickPostRaidButton("auto retry")
            if ok2 then
                Log("AUTO RETRY triggered", Color3.fromRGB(0,255,100))
            else
                Log("AUTO RETRY btn not found", Color3.fromRGB(255,100,0))
            end
        elseif _G.AutoRaid_Return then
            local ok2 = clickPostRaidButton("return to menu")
            if ok2 then
                Log("AUTO RETURN triggered", Color3.fromRGB(0,255,100))
            else
                Log("AUTO RETURN btn not found", Color3.fromRGB(255,100,0))
            end
        end
    end)
    RaidRunning = false
    forceUnlock()
    if not ok then Log("RAID ERR: "..tostring(err), Color3.fromRGB(255,0,0)) end
end

-- Рейд-цикл
task.spawn(function()
    while task.wait(1) do
        if _G.BS_Dead then break end
        if not _G.AutoRaid_Enabled then RaidRunning = false; continue end
        if RaidRunning then continue end
        if not _G.AutoRaid_Selected then
            Log("RAID: no raid selected", Color3.fromRGB(255,150,0))
            task.wait(3); continue
        end
        local sid = _G.RaidSessionId
        task.spawn(function() doRaidLoop(_G.AutoRaid_Selected, sid) end)
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
        bg.Size = UDim2.new(0,100,0,30)
        local tl = Instance.new("TextLabel")
        tl.Parent = bg
        tl.Size = UDim2.new(1,0,1,0)
        tl.BackgroundTransparency = 1
        tl.TextColor3 = Color3.new(1,1,1)
        tl.Font = Enum.Font.GothamBold
        tl.TextSize = 13
        local highOk, high = pcall(Instance.new, "Highlight")
        if not highOk then high = nil end
        if high then
            high.Name = "BS_ESP"
            high.FillColor = Color3.fromRGB(255,0,50)
            high.Parent = char
        end
        local conn = RunService.Heartbeat:Connect(function()
            if _G.BS_Dead then bg:Destroy(); if high then high:Destroy() end; return end
            if _G.ESP_Enabled and char and char.Parent
                and LocalPlayer.Character
                and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local d = math.floor(
                    (LocalPlayer.Character.HumanoidRootPart.Position - head.Position).Magnitude)
                tl.Text = p.Name.." ["..d.."m]"
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
    Log("DESTROYING...", Color3.fromRGB(255,50,50))
    _G.BS_Dead = true
    _G.AutoQuest_Enabled = false
    _G.AutoRaid_Enabled = false
    Talking = false; Killing = false; RaidRunning = false
    CurrentTarget = nil
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
    Talking = false; Killing = false; RaidRunning = false; CurrentTarget = nil
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if hrp then hrp.Anchored = false end
    Log("RESPAWN — state reset", Color3.fromRGB(200,200,0))
end)

-- ==================== PUBLIC API ====================
_G.BloodyHub_API = {
    Log = Log,

    SetAutoQuest = function(v)
        _G.AutoQuest_Enabled  = v and true or false
        _G.AutoDialog_Enabled = _G.AutoQuest_Enabled
        if v then
            _G.QuestSessionId = _G.QuestSessionId + 1
        else
            Talking = false; Killing = false
        end
    end,
    SetESP           = function(v) _G.ESP_Enabled = v and true or false end,
    SetKillSnapDepth = function(v) _G.KillSnapDepth = tonumber(v) or _G.KillSnapDepth end,

    -- Auto Raid
    SetAutoRaid = function(v)
        _G.AutoRaid_Enabled = v and true or false
        if v then
            _G.RaidSessionId = _G.RaidSessionId + 1
        else
            RaidRunning = false
        end
    end,
    SetAutoRaidRetry  = function(v) _G.AutoRaid_Retry  = v and true or false end,
    SetAutoRaidReturn = function(v) _G.AutoRaid_Return = v and true or false end,
    SetRaidSelected   = function(v) _G.AutoRaid_Selected = v end,

    -- Session
    DestroySession = function() if _G.BS_DestroyFn then _G.BS_DestroyFn() end end,
}

Log("BloodyHub v83 LOADED", Color3.fromRGB(0,255,255))

-- ==================== LOAD UI ====================
local ok, src = pcall(function() return game:HttpGet(UI_URL, true) end)
if ok and src and src ~= "" then
    local fn, lerr = loadstring(src)
    if fn then pcall(fn)
    else warn("[BloodyHub] ui.lua compile: "..tostring(lerr)) end
else
    warn("[BloodyHub] ui.lua fetch failed")
end
