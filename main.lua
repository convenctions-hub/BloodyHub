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
_G.AutoQuest_Enabled   = _G.AutoQuest_Enabled   or false
_G.ESP_Enabled         = _G.ESP_Enabled         or false
_G.AutoDialog_Enabled  = _G.AutoQuest_Enabled
_G.FlySpeed            = 120
_G.BS_Dead             = false
_G.QuestSessionId      = _G.QuestSessionId      or 0
_G.AttackDelay         = 0.08
_G.KillSnapDepth       = _G.KillSnapDepth       or 5

_G.CombatDepth           = _G.CombatDepth           or (_G.KillSnapDepth or 7)
_G.QuestForwardDist      = _G.QuestForwardDist      or 4
_G.QuestTeleThreshold    = _G.QuestTeleThreshold    or 3.5
_G.CombatTeleThreshold   = _G.CombatTeleThreshold   or 2.0
_G.MoveDebounce          = _G.MoveDebounce          or 0.12

-- Auto Raid globals
_G.AutoRaid_Enabled    = false
_G.AutoRaid_Retry      = false
_G.AutoRaid_Return     = false
_G.AutoRaid_Selected   = nil
_G.RaidSessionId       = _G.RaidSessionId or 0

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
local RAID_DATA = {
    ["Muhammad Avdol Raid"] = { bossName = "Muhammad Avdol", npcName = "Avdol",           npcPos = nil },
    ["Jotaro Kujo Raid"]    = { bossName = "Jotaro Kujo",    npcName = "Jotaro",          npcPos = nil },
    ["Kira Yoshikage Raid"] = { bossName = "Yoshikage Kira", npcName = "Kira",            npcPos = nil },
    ["Dio Brando Raid"]     = { bossName = "Dio Brando",     npcName = "Dio",             npcPos = nil },
    ["Prison Escape Raid"]  = { bossName = "Prison Guard",   npcName = "Prison Warden",   npcPos = nil },
    ["Death 13 Raid"]       = { bossName = "Death 13",       npcName = "Death 13",        npcPos = nil },
    ["Twoh Raid"]           = { bossName = "DIO Over Heaven",npcName = "Dio Over Heaven", npcPos = nil },
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
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
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

-- ==================== ПОЗИЦИОНИРОВАНИЕ: ОБЩИЕ ХЕЛПЕРЫ ====================
local function prepBody()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp then return nil, nil end
    setGhost(true)
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
    hrp.Anchored = true
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    return hrp, hum
end

-- ==================== QUEST MODE: MoveToNPC ====================
local _lastQuestMove = 0
local function MoveToNPC(npcHRP, opts)
    opts = opts or {}
    if not npcHRP or not npcHRP.Parent then return false end
    local now = os.clock()
    if not opts.force and (now - _lastQuestMove) < (_G.MoveDebounce or 0.12) then
        return false
    end

    local hrp = prepBody()
    if not hrp then return false end

    local forwardDist = opts.forwardDist or _G.QuestForwardDist or 4
    local npcCF = npcHRP.CFrame
    local targetCF = npcCF * CFrame.new(0, 0, -forwardDist)

    local threshold = opts.threshold or _G.QuestTeleThreshold or 3.5
    if not opts.force and (hrp.Position - targetCF.Position).Magnitude <= threshold then
        return false
    end

    local myPos = targetCF.Position
    local lookAt = Vector3.new(npcHRP.Position.X, myPos.Y, npcHRP.Position.Z)
    hrp.CFrame = CFrame.new(myPos, lookAt)

    _lastQuestMove = now
    Log(string.format("MoveToNPC: forward=%.1f", forwardDist), Color3.fromRGB(0,200,255))
    return true
end

-- ==================== COMBAT MODE: MoveToEnemy ====================
local _lastCombatMove = 0
local function makeCombatCFrame(enemyHRP, depth)
    local targetCF = enemyHRP.CFrame * CFrame.new(0, -(depth or _G.CombatDepth or 7), 0)
    local myPos = targetCF.Position
    local ep = enemyHRP.Position
    local lookAt = Vector3.new(ep.X, myPos.Y, ep.Z + 0.001)
    return CFrame.new(myPos, lookAt)
end

local function MoveToEnemy(enemyHRP, opts)
    opts = opts or {}
    if not enemyHRP or not enemyHRP.Parent then return false end
    local now = os.clock()
    if not opts.force and (now - _lastCombatMove) < (_G.MoveDebounce or 0.12) then
        return false
    end

    local hrp = prepBody()
    if not hrp then return false end

    local depth = opts.depth or _G.CombatDepth or _G.KillSnapDepth or 7
    local wantCF = makeCombatCFrame(enemyHRP, depth)

    local threshold = opts.threshold or _G.CombatTeleThreshold or 2.0
    if not opts.force and (hrp.Position - wantCF.Position).Magnitude <= threshold then
        return false
    end

    hrp.CFrame = wantCF
    _lastCombatMove = now
    return true
end

-- ==================== ОБЩИЙ ГОРИЗОНТАЛЬНЫЙ ТЕЛЕПОРТ ====================
local function teleportTo(getTargetPos, arriveDist, isCancelled)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp then return false end
    if isCancelled and isCancelled() then return false end
    local targetPos = getTargetPos()
    if not targetPos then return false end
    if _G.BS_Dead then return false end

    setGhost(true)
    hrp.Anchored = true

    local dist = (hrp.Position - targetPos).Magnitude
    if dist > (arriveDist or 5) then
        local dir = (hrp.Position - targetPos)
        local offset = dir.Magnitude > 0.1
            and dir.Unit * (arriveDist or 5)
            or Vector3.new(0, 0, arriveDist or 5)
        local myPos = targetPos + offset
        hrp.CFrame = CFrame.new(myPos, Vector3.new(targetPos.X, myPos.Y, targetPos.Z))
    end

    task.wait(0.05)
    pcall(function()
        if hum then
            hum.PlatformStand = false
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
    return true
end

-- ==================== COMBAT SNAP: ПОЗИЦИЯ ФИКСИРУЕТСЯ ОДИН РАЗ ====================
-- ИСПРАВЛЕНИЕ: CFrame устанавливается ОДИН РАЗ при вызове.
-- Heartbeat только удерживает Anchored и гасит скорость — без пересчёта CFrame.
-- Это устраняет дёргание вверх/вниз каждый кадр.
local function startCombatSnapLoop(hrp, enemyHRP)
    if not hrp or not enemyHRP then return function() end end
    local active = true

    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")

    setGhost(true)
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end

    hrp.Anchored = true
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)

    -- Телепорт под моба — ОДИН РАЗ
    local depth = _G.CombatDepth or _G.KillSnapDepth or 7
    hrp.CFrame = makeCombatCFrame(enemyHRP, depth)
    Log(string.format("COMBAT SNAP (once): depth=%.1f", depth), Color3.fromRGB(0,255,200))

    -- Heartbeat: только удерживаем позицию (Anchored + velocity = 0)
    -- CFrame НЕ обновляется — это ключевое исправление
    local conn = RunService.Heartbeat:Connect(function()
        if not active then return end
        if not hrp or not hrp.Parent then active = false; return end
        -- Просто держим якорь и гасим случайные импульсы физики
        if not hrp.Anchored then hrp.Anchored = true end
        pcall(function()
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
        if hum and hum.PlatformStand then
            hum.PlatformStand = false
        end
    end)

    return function()
        active = false
        conn:Disconnect()
        Log("COMBAT SNAP STOP", Color3.fromRGB(180,180,180))
    end
end

-- ==================== АТАКА ====================
local function doAttack(mobHRP)
    pcall(function() mouse1click() end)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and mobHRP then
        pcall(function() firetouchinterest(hrp, mobHRP, 0) end)
        pcall(function() firetouchinterest(hrp, mobHRP, 1) end)
    end
    pcall(function() clickon(mobHRP) end)
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

-- ==================== DIALOG CLICK ====================
local function clickDialogOption()
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Dialog") then
            local choices = {}
            for _, c in ipairs(v:GetChildren()) do
                if c:IsA("DialogChoice") then table.insert(choices, c) end
            end
            table.sort(choices, function(a,b)
                return (a.ResponseOrder or 0) < (b.ResponseOrder or 0)
            end)
            for _, c in ipairs(choices) do
                for _, re in ipairs(v:GetDescendants()) do
                    if re:IsA("RemoteEvent") then
                        pcall(function() re:FireServer(c) end)
                    end
                end
                pcall(function() firesignal(c.GoodbyeChoiceSelected) end)
                pcall(function() firesignal(c.ResponseDialog.DialogChoiceSelected) end)
                Log("DIALOG CHOICE (native)", Color3.fromRGB(0,255,200))
                return true
            end
        end
    end

    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end

    local candidates = {}
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui:IsA("TextButton") and gui.Visible and gui.Active then
            local name = gui:GetFullName()
            if not name:find("BloodyHub") and not name:find("BSLog") then
                local text = (gui.Text or ""):lower()
                local prio = 50
                if     text:match("^%s*1[%.]")     then prio = 1
                elseif text:match("^%s*yes")        then prio = 2
                elseif text:match("^%s*accept")     then prio = 3
                elseif text:match("^%s*sure")       then prio = 4
                elseif text:match("^%s*ok%s*$")     then prio = 5
                elseif text:match("^%s*continue")   then prio = 6
                elseif text:match("^%s*next")       then prio = 7
                elseif text:match("^%s*start")      then prio = 8
                elseif text ~= ""                   then prio = 20
                end
                table.insert(candidates, { btn = gui, prio = prio })
            end
        end
    end

    table.sort(candidates, function(a,b) return a.prio < b.prio end)

    if #candidates > 0 then
        local best = candidates[1].btn
        pcall(function() firesignal(best.MouseButton1Click) end)
        pcall(function() firesignal(best.Activated) end)
        pcall(function()
            for _, c in ipairs(getconnections(best.MouseButton1Click)) do c:Fire() end
        end)
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            local pos = best.AbsolutePosition + best.AbsoluteSize / 2
            vim:SendMouseButtonEvent(pos.X, pos.Y, 0, true,  game, 1)
            task.wait(0.05)
            vim:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
        end)
        Log("GUI BTN clicked: "..(best.Text or "?"), Color3.fromRGB(0,255,200))
        return true
    end

    return false
end

local function waitAndClickDialog(timeoutSecs)
    local t0 = os.clock()
    while os.clock() - t0 < timeoutSecs do
        if clickDialogOption() then return true end
        task.wait(0.15)
    end
    return false
end

-- ==================== TALK LOGIC ====================
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

        local dist = (hrp.Position - npcHRP.Position).Magnitude
        if dist > 30 then
            teleportTo(function()
                if not npcHRP or not npcHRP.Parent then return nil end
                return npcHRP.Position
            end, (_G.QuestForwardDist or 4) + 2,
            function() return _G.QuestSessionId ~= sessionId end)
        end

        MoveToNPC(npcHRP, { force = true })
        forceUnlock()
        if _G.QuestSessionId ~= sessionId then return end

        local questDone = false
        local attemptMax = 5
        for attempt = 1, attemptMax do
            if _G.QuestSessionId ~= sessionId or _G.BS_Dead then break end

            MoveToNPC(npcHRP)
            forceUnlock()
            if _G.QuestSessionId ~= sessionId then break end

            task.wait(0.25)

            local fired = fireAllPromptsNear(npcHRP, 12)
            if not fired then
                Log("NO PROMPT (attempt "..attempt..")", Color3.fromRGB(255,150,0))
            end

            local clicked = waitAndClickDialog(4)
            if clicked then
                task.wait(0.4)
                if _G.QuestSessionId == sessionId then clickDialogOption() end
                task.wait(0.4)
                if _G.QuestSessionId == sessionId then clickDialogOption() end
                task.wait(0.4)
                if _G.QuestSessionId == sessionId then clickDialogOption() end
            end

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
    forceUnlock()
    if not ok then
        Log("TALK ERR: "..tostring(err), Color3.fromRGB(255,0,0))
    end
end

-- ==================== KILL LOGIC ====================
-- ИСПРАВЛЕНИЕ: lastCombatTarget отслеживает смену цели.
-- startCombatSnapLoop вызывается ОДИН РАЗ на новую цель, не на каждой итерации.
local function doKillLoop(targetName, sessionId)
    if Killing then return end
    Killing = true
    local ok, err = pcall(function()
        local lastCombatTarget = nil  -- <-- ключевая переменная для однократного позиционирования
        local stopSnap = nil

        while _G.AutoQuest_Enabled and _G.QuestSessionId == sessionId and not _G.BS_Dead do
            local mobHum = CurrentTarget and CurrentTarget:FindFirstChildOfClass("Humanoid")
            if not CurrentTarget or not CurrentTarget.Parent or not mobHum or mobHum.Health <= 0 then
                -- Цель умерла или пропала — сбрасываем snap и lastCombatTarget
                if stopSnap then stopSnap(); stopSnap = nil end
                lastCombatTarget = nil
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
            if not mob or not mob.Parent then
                CurrentTarget = nil; lastCombatTarget = nil
                if stopSnap then stopSnap(); stopSnap = nil end
                continue
            end
            local mobHRP = mob:FindFirstChild("HumanoidRootPart")
            if not mobHRP then
                CurrentTarget = nil; lastCombatTarget = nil
                if stopSnap then stopSnap(); stopSnap = nil end
                continue
            end

            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(0.5); continue end

            local dist = (hrp.Position - mobHRP.Position).Magnitude

            if dist > 15 then
                -- Далеко — останавливаем snap, телепортируемся ближе
                if stopSnap then stopSnap(); stopSnap = nil end
                lastCombatTarget = nil
                teleportTo(function()
                    if not mob or not mob.Parent then return nil end
                    local r = mob:FindFirstChild("HumanoidRootPart")
                    return r and r.Position or nil
                end, 5, function()
                    return not _G.AutoQuest_Enabled or _G.QuestSessionId ~= sessionId
                end)
                forceUnlock()
            else
                -- Близко — snap ТОЛЬКО если цель изменилась
                if mob ~= lastCombatTarget then
                    lastCombatTarget = mob
                    if stopSnap then stopSnap(); stopSnap = nil end
                    -- Перечитываем hrp после возможного forceUnlock
                    local char2 = LocalPlayer.Character
                    local hrp2  = char2 and char2:FindFirstChild("HumanoidRootPart")
                    if hrp2 then
                        stopSnap = startCombatSnapLoop(hrp2, mobHRP)
                    end
                end

                -- Атакуем (позиция уже зафиксирована, не двигаемся)
                local attackStart = os.clock()
                local attackThreshold = (_G.CombatDepth or _G.KillSnapDepth or 7) + 6

                while _G.AutoQuest_Enabled and _G.QuestSessionId == sessionId
                    and not _G.BS_Dead and mob and mob.Parent do
                    local mh = mob:FindFirstChildOfClass("Humanoid")
                    if not mh or mh.Health <= 0 then break end
                    local hr = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not hr then break end
                    if (hr.Position - mobHRP.Position).Magnitude > attackThreshold then break end
                    doAttack(mobHRP)
                    task.wait(_G.AttackDelay or 0.08)
                    if os.clock() - attackStart > 60 then
                        Log("ATTACK TIMEOUT", Color3.fromRGB(255,100,0))
                        CurrentTarget = nil; lastCombatTarget = nil; break
                    end
                end
                -- snap НЕ останавливаем здесь — цель могла просто выйти за порог
                -- stopSnap сработает только при смене/потере цели выше
            end
        end

        -- Финальная уборка
        if stopSnap then stopSnap() end
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
        if     quest.type == "talk" and not Talking then
            task.spawn(function() doTalkQuest(quest.target, sid) end)
        elseif quest.type == "kill" and not Killing then
            task.spawn(function() doKillLoop(quest.target, sid) end)
        end
    end
end)

-- ==================== AUTO RAID ====================
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

local function clickPostRaidButton(pattern)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui:IsA("TextButton") or gui:IsA("TextLabel") then
            local text = (gui.Text or ""):lower()
            if text:find(pattern:lower(), 1, true) then
                local fullName = gui:GetFullName()
                if not fullName:find("BloodyHub") and not fullName:find("BSLog") then
                    pcall(function() firesignal(gui.MouseButton1Click) end)
                    pcall(function() firesignal(gui.Activated) end)
                    pcall(function()
                        for _, c in ipairs(getconnections(gui.MouseButton1Click)) do c:Fire() end
                    end)
                    Log("POST-RAID BTN: "..gui.Text, Color3.fromRGB(0,255,200))
                    return true
                end
            end
        end
    end
    return false
end

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

-- ИСПРАВЛЕНИЕ: тот же паттерн lastCombatTarget для рейда
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

        local _, npcObj = findNpcByBillboard(data.npcName)

        if not npcObj and data.npcPos then
            Log("NPC billboard not found, teleport to npcPos", Color3.fromRGB(255,200,0))
            teleportTo(function() return data.npcPos end, 8,
                function() return _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled end)
            forceUnlock()
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

        local hrp0 = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp0 and (hrp0.Position - npcHRP.Position).Magnitude > 30 then
            teleportTo(function()
                if not npcHRP or not npcHRP.Parent then return nil end
                return npcHRP.Position
            end, (_G.QuestForwardDist or 4) + 2,
            function() return _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled end)
        end
        MoveToNPC(npcHRP, { force = true })
        forceUnlock()
        if _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled then return end

        task.wait(0.3)

        for attempt = 1, 5 do
            if _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled then break end
            MoveToNPC(npcHRP)
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

        -- Рейд: тот же однократный snap-паттерн
        local lastRaidTarget = nil
        local stopSnap = nil
        local raidKillStart = os.clock()

        while _G.AutoRaid_Enabled and _G.RaidSessionId == raidSid and not _G.BS_Dead do
            if os.clock() - raidKillStart > 600 then
                Log("RAID KILL TIMEOUT", Color3.fromRGB(255,100,0)); break
            end

            local mob = findRaidTarget(data.bossName)
            if not mob then
                Log("RAID: no more targets — waiting for post-raid GUI", Color3.fromRGB(0,255,150))
                if stopSnap then stopSnap(); stopSnap = nil end
                break
            end

            local mobHRP = mob:FindFirstChild("HumanoidRootPart")
            if not mobHRP then task.wait(0.5); continue end

            -- Сброс snap если моб сменился
            if mob ~= lastRaidTarget and stopSnap then
                stopSnap(); stopSnap = nil
            end

            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(0.5); continue end

            local dist = (hrp.Position - mobHRP.Position).Magnitude
            if dist > 15 then
                if stopSnap then stopSnap(); stopSnap = nil end
                lastRaidTarget = nil
                teleportTo(function()
                    if not mob or not mob.Parent then return nil end
                    local r = mob:FindFirstChild("HumanoidRootPart")
                    return r and r.Position or nil
                end, 5, function()
                    return not _G.AutoRaid_Enabled or _G.RaidSessionId ~= raidSid
                end)
                forceUnlock()
            else
                -- Snap один раз при смене цели
                if mob ~= lastRaidTarget then
                    lastRaidTarget = mob
                    if stopSnap then stopSnap(); stopSnap = nil end
                    local char2 = LocalPlayer.Character
                    local hrp2  = char2 and char2:FindFirstChild("HumanoidRootPart")
                    if hrp2 then
                        stopSnap = startCombatSnapLoop(hrp2, mobHRP)
                    end
                end

                local attackStart = os.clock()
                local attackThreshold = (_G.CombatDepth or _G.KillSnapDepth or 7) + 6
                while _G.AutoRaid_Enabled and _G.RaidSessionId == raidSid
                    and not _G.BS_Dead and mob and mob.Parent do
                    local mh = mob:FindFirstChildOfClass("Humanoid")
                    if not mh or mh.Health <= 0 then break end
                    local hr = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not hr then break end
                    if (hr.Position - mobHRP.Position).Magnitude > attackThreshold then break end
                    doAttack(mobHRP)
                    task.wait(_G.AttackDelay or 0.08)
                    if os.clock() - attackStart > 60 then
                        Log("RAID ATTACK TIMEOUT", Color3.fromRGB(255,100,0)); break
                    end
                end
            end
        end

        if stopSnap then stopSnap() end

        if not _G.AutoRaid_Enabled or _G.RaidSessionId ~= raidSid then return end

        Log("WAITING POST-RAID GUI...", Color3.fromRGB(200,200,0))
        waitForPostRaidGui(15)

        if _G.AutoRaid_Retry then
            local ok2 = clickPostRaidButton("auto retry")
            Log(ok2 and "AUTO RETRY triggered" or "AUTO RETRY btn not found",
                ok2 and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,100,0))
        elseif _G.AutoRaid_Return then
            local ok2 = clickPostRaidButton("return to menu")
            Log(ok2 and "AUTO RETURN triggered" or "AUTO RETURN btn not found",
                ok2 and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,100,0))
        end
    end)
    RaidRunning = false
    forceUnlock()
    if not ok then Log("RAID ERR: "..tostring(err), Color3.fromRGB(255,0,0)) end
end

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
    SetKillSnapDepth = function(v)
        local n = tonumber(v)
        if n then
            _G.KillSnapDepth = n
            _G.CombatDepth   = n
        end
    end,
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
    DestroySession = function() if _G.BS_DestroyFn then _G.BS_DestroyFn() end end,
}

Log("BloodyHub v87 LOADED", Color3.fromRGB(0,255,255))

-- ==================== LOAD UI ====================
local ok, src = pcall(function() return game:HttpGet(UI_URL, true) end)
if ok and src and src ~= "" then
    local fn, lerr = loadstring(src)
    if fn then pcall(fn)
    else warn("[BloodyHub] ui.lua compile: "..tostring(lerr)) end
else
    warn("[BloodyHub] ui.lua fetch failed")
end
