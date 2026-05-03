--[[ BloodyHub main logic v4.3
- ФИКС КРАША НА ЗАГРУЗКЕ: __namecall теперь пробрасывает варарги напрямую
  (без {...}/table.unpack), сохраняя nil-аргументы.
- getnamecallmethod() кэшируется ПЕРВЫМ, до любых методов на self.
- Сборка args через select("#", ...) — корректно с nil.
- VirtualUser / CoreGui / Idled / hook install обёрнуты в pcall.
- tryToolAttack: только RemoteEvent внутри Tool с именем атаки (без слепого Activate).
]]
local UI_URL = "https://raw.githubusercontent.com/convenctions-hub/BloodyHub/main/ui.lua"

local HttpService   = game:GetService("HttpService")
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputSvc  = game:GetService("UserInputService")
local CoreGui       = game:GetService("CoreGui")
local LocalPlayer   = Players.LocalPlayer

local VirtualUser
pcall(function() VirtualUser = game:GetService("VirtualUser") end)

-- ==================== GLOBAL DEFAULTS ====================
_G.AutoQuest_Enabled   = _G.AutoQuest_Enabled   or false
_G.ESP_Enabled         = _G.ESP_Enabled         or false
_G.AutoDialog_Enabled  = _G.AutoQuest_Enabled
_G.FlySpeed            = 120
_G.BS_Dead             = false
_G.QuestSessionId      = _G.QuestSessionId      or 0

_G.CombatYOffset       = _G.CombatYOffset       or 6
_G.MoveTickRate        = _G.MoveTickRate        or 0.12
_G.MoveLerpAlpha       = _G.MoveLerpAlpha       or 0.35
_G.MoveSnapDist        = _G.MoveSnapDist        or 25
_G.MoveDeadZone        = _G.MoveDeadZone        or 0.4
_G.AttackCooldown      = _G.AttackCooldown      or 0.30
_G.AttackRange         = _G.AttackRange         or 18
_G.AttackTickRate      = _G.AttackTickRate      or 0.05

_G.QuestForwardDist    = _G.QuestForwardDist    or 4
_G.QuestTeleThreshold  = _G.QuestTeleThreshold  or 3.5
_G.MoveDebounce        = _G.MoveDebounce        or 0.12

_G.KillSnapDepth       = _G.KillSnapDepth       or _G.CombatYOffset
_G.CombatDepth         = _G.CombatDepth         or _G.CombatYOffset
_G.AttackDelay         = _G.AttackCooldown

_G.AutoRaid_Enabled    = false
_G.AutoRaid_Retry      = false
_G.AutoRaid_Return     = false
_G.AutoRaid_Selected   = nil
_G.RaidSessionId       = _G.RaidSessionId or 0

_G.BS_RemoteSpy_Enabled    = false
_G.BS_InputDebug_Enabled   = false
_G.BS_AttackDetectMode     = false
_G.BloodyHub_AttackRemote  = _G.BloodyHub_AttackRemote or nil

pcall(function()
    for _, g in ipairs(CoreGui:GetChildren()) do
        if g.Name == "BSLog" then pcall(function() g:Destroy() end) end
    end
end)

-- ==================== DEBUG LOGGER GUI ====================
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

-- ==================================================================
-- =================== REMOTE SPY / DEBUG SYSTEM ====================
-- ==================================================================
local function safeArgPreview(args)
    local out = {}
    local n = #args
    for i = 1, math.min(n, 4) do
        local v = args[i]
        local tv = typeof(v)
        if tv == "Instance" then
            out[i] = "<"..v.ClassName..":"..v.Name..">"
        elseif tv == "Vector3" or tv == "CFrame" then
            out[i] = tv
        elseif tv == "table" then
            out[i] = "{table}"
        elseif tv == "string" then
            out[i] = '"'..v:sub(1,20)..'"'
        else
            out[i] = tostring(v)
        end
    end
    if n > 4 then out[#out+1] = "..(+"..(n-4)..")" end
    return table.concat(out, ", ")
end

local hookInstalled = false
local function installRemoteHook()
    if hookInstalled then return end
    if not hookmetamethod or not newcclosure or not getnamecallmethod then
        Log("Executor lacks hookmetamethod — RemoteSpy DISABLED", Color3.fromRGB(255,100,100))
        return
    end

    local oldNamecall
    local ok, err = pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            -- ВАЖНО: метод кэшируем ПЕРВЫМ, до любых вызовов методов на self,
            -- иначе getnamecallmethod() вернёт уже другое значение.
            local ok_m, method = pcall(getnamecallmethod)
            if not ok_m then
                return oldNamecall(self, ...)
            end

            if method == "FireServer" or method == "InvokeServer" then
                -- Захват аргументов через select — корректно с nil.
                local argc = select("#", ...)
                -- Вся логика шпиона — в pcall, чтобы не блокировать оригинальный вызов.
                pcall(function()
                    if typeof(self) ~= "Instance" then return end
                    if not (self:IsA("RemoteEvent")
                         or self:IsA("RemoteFunction")
                         or (self.IsA and self:IsA("UnreliableRemoteEvent"))) then
                        return
                    end

                    local args = table.create and table.create(argc) or {}
                    for i = 1, argc do args[i] = (select(i, ...)) end

                    if _G.BS_RemoteSpy_Enabled then
                        Log("[REM] "..method.." -> "..self.Name.." ("..safeArgPreview(args)..")",
                            Color3.fromRGB(255,200,0))
                    end

                    if _G.BS_AttackDetectMode then
                        _G.BloodyHub_AttackRemote = {
                            remote = self,
                            method = method,
                            args   = args,
                            path   = self:GetFullName(),
                        }
                        _G.BS_AttackDetectMode = false
                        Log("[ATTACK REMOTE CAPTURED] "..self:GetFullName(), Color3.fromRGB(0,255,100))
                        Log("  args: "..safeArgPreview(args), Color3.fromRGB(0,255,100))
                    end
                end)
            end

            -- ОРИГИНАЛЬНЫЙ ВЫЗОВ — варарги пробрасываются напрямую,
            -- без {...}/table.unpack, чтобы не терять nil и не ломать сигнатуру.
            return oldNamecall(self, ...)
        end))
    end)

    if ok then
        hookInstalled = true
        Log("RemoteSpy hook installed", Color3.fromRGB(0,255,200))
    else
        hookInstalled = false
        Log("RemoteSpy hook FAILED: "..tostring(err), Color3.fromRGB(255,80,80))
    end
end
pcall(installRemoteHook)

-- ==================== INPUT DEBUG ====================
pcall(function()
    UserInputSvc.InputBegan:Connect(function(input, gpe)
        if not _G.BS_InputDebug_Enabled then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Log(("[CLICK] gpe=%s pos=%d,%d"):format(
                tostring(gpe), math.floor(input.Position.X), math.floor(input.Position.Y)),
                Color3.fromRGB(0,200,255))
            if gpe then
                Log("  -> click captured by GUI (not game)!", Color3.fromRGB(255,100,100))
            end
        end
    end)
end)

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

local function getMyParts()
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hrp, hum
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

local function isValidMob(mob)
    if not mob or not mob.Parent then return false end
    local hum = mob:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if not hrp or not hrp.Parent then return false end
    return true, hrp, hum
end

local function teleportTo(getTargetPos, arriveDist, isCancelled)
    local hrp, hum = getMyParts()
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

local _lastQuestMove = 0
local function MoveToNPC(npcHRP, opts)
    opts = opts or {}
    if not npcHRP or not npcHRP.Parent then return false end
    local now = os.clock()
    if not opts.force and (now - _lastQuestMove) < (_G.MoveDebounce or 0.12) then
        return false
    end

    local hrp, hum = getMyParts()
    if not hrp then return false end

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

-- ==================================================================
-- ============= MOVEMENT CONTROLLER =================================
-- ==================================================================
local MovementController = {}
MovementController.target = nil
MovementController.active = false
MovementController.paused = false
MovementController._thread = nil

function MovementController:setTarget(mob) self.target = mob end
function MovementController:clearTarget()
    self.target = nil
    local hrp, hum = getMyParts()
    if hrp then hrp.Anchored = false end
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
    setGhost(false)
end
function MovementController:setPaused(v)
    self.paused = v and true or false
    if self.paused then
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Anchored = false end
        setGhost(false)
    end
end

local function computeUnderTargetCFrame(mobHRP)
    local mp = mobHRP.Position
    local desiredPos = Vector3.new(mp.X, mp.Y - (_G.CombatYOffset or 6), mp.Z)
    local lookAt = Vector3.new(mp.X, mp.Y, mp.Z + 0.001)
    return CFrame.new(desiredPos, lookAt)
end

function MovementController:start()
    if self.active then return end
    self.active = true

    self._thread = task.spawn(function()
        while self.active do
            if self.paused or _G.BS_Dead then
                task.wait(_G.MoveTickRate or 0.12); continue
            end

            local mob = self.target
            local valid, mobHRP = isValidMob(mob)
            if not valid then
                local hrp, hum = getMyParts()
                if hrp and hrp.Anchored then hrp.Anchored = false end
                if hum then pcall(function() hum.PlatformStand = false end) end
                task.wait(_G.MoveTickRate or 0.12); continue
            end

            local hrp, hum = getMyParts()
            if not hrp then task.wait(_G.MoveTickRate or 0.12); continue end

            setGhost(true)
            if not hrp.Anchored then hrp.Anchored = true end
            pcall(function()
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                if hum then hum.PlatformStand = false end
            end)

            local desiredCF = computeUnderTargetCFrame(mobHRP)
            local delta = (hrp.Position - desiredCF.Position).Magnitude

            if delta > (_G.MoveSnapDist or 25) then
                hrp.CFrame = desiredCF
            elseif delta > (_G.MoveDeadZone or 0.4) then
                local alpha = math.clamp(_G.MoveLerpAlpha or 0.35, 0.05, 1)
                hrp.CFrame = hrp.CFrame:Lerp(desiredCF, alpha)
            end

            task.wait(_G.MoveTickRate or 0.12)
        end
    end)
end

function MovementController:stop()
    self.active = false
    self._thread = nil
    self:clearTarget()
end

-- ==================================================================
-- ============= ATTACK CONTROLLER ==================================
-- ==================================================================
local AttackController = {}
AttackController.target = nil
AttackController.active = false
AttackController.paused = false
AttackController._thread = nil

function AttackController:setTarget(mob) self.target = mob end
function AttackController:clearTarget()  self.target = nil end
function AttackController:setPaused(v)   self.paused = v and true or false end

local ATTACK_NAME_PATTERNS = { "attack", "hit", "m1", "swing", "punch", "combat", "damage", "strike" }

local function findToolAttackRemote(tool)
    if not tool then return nil end
    for _, d in ipairs(tool:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            local lname = d.Name:lower()
            for _, p in ipairs(ATTACK_NAME_PATTERNS) do
                if lname:find(p, 1, true) then return d end
            end
        end
    end
    return nil
end

-- Безопасный unpack: не теряет nil при правильно собранном массиве
local function safeUnpack(t)
    return table.unpack(t, 1, #t)
end

-- Приоритет 1: replay захваченного remote
local function tryReplayCapturedRemote(mobHRP)
    local cap = _G.BloodyHub_AttackRemote
    if not cap or typeof(cap) ~= "table" then return false end
    local remote = cap.remote
    if not remote or not remote.Parent then return false end

    local args = cap.args or {}
    local replayArgs = {}
    for i = 1, #args do
        local v = args[i]
        local tv = typeof(v)
        if tv == "Instance" and (v:IsA("BasePart") or v:IsA("Model")) and mobHRP then
            replayArgs[i] = mobHRP
        elseif tv == "Vector3" and mobHRP then
            replayArgs[i] = mobHRP.Position
        else
            replayArgs[i] = v
        end
    end

    local ok = pcall(function()
        if cap.method == "FireServer" then
            remote:FireServer(safeUnpack(replayArgs))
        else
            remote:InvokeServer(safeUnpack(replayArgs))
        end
    end)
    return ok
end

-- Приоритет 2: RemoteEvent внутри Tool с именем атаки
-- ВАЖНО: tool:Activate() УБРАН — он триггерит Summon VFX и вызывает краши
local function tryToolAttack(mobHRP)
    local char = LocalPlayer.Character
    if not char then return false end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return false end

    local re = findToolAttackRemote(tool)
    if re and mobHRP then
        pcall(function()
            if re:IsA("RemoteEvent") then
                re:FireServer(mobHRP)
            else
                re:InvokeServer(mobHRP)
            end
        end)
        return true
    end

    return false
end

-- Приоритет 3: touch fallback
local function tryTouchHit(mobHRP)
    if not firetouchinterest then return false end
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp or not mobHRP or not mobHRP.Parent then return false end
    pcall(function() firetouchinterest(hrp, mobHRP, 0) end)
    pcall(function() firetouchinterest(hrp, mobHRP, 1) end)
    return true
end

local function performAttack(mobHRP)
    if tryReplayCapturedRemote(mobHRP) then return end
    if tryToolAttack(mobHRP) then return end
    tryTouchHit(mobHRP)
end

function AttackController:start()
    if self.active then return end
    self.active = true

    self._thread = task.spawn(function()
        local lastAttack = 0
        while self.active do
            if self.paused or _G.BS_Dead then
                task.wait(_G.AttackTickRate or 0.05); continue
            end

            local mob = self.target
            local valid, mobHRP = isValidMob(mob)
            if not valid then
                task.wait(_G.AttackTickRate or 0.05); continue
            end

            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                task.wait(_G.AttackTickRate or 0.05); continue
            end

            local dist = (hrp.Position - mobHRP.Position).Magnitude
            if dist > (_G.AttackRange or 18) then
                task.wait(_G.AttackTickRate or 0.05); continue
            end

            local now = os.clock()
            if (now - lastAttack) >= (_G.AttackCooldown or 0.3) then
                performAttack(mobHRP)
                lastAttack = now
            end

            task.wait(_G.AttackTickRate or 0.05)
        end
    end)
end

function AttackController:stop()
    self.active = false
    self._thread = nil
    self:clearTarget()
end

-- ==================== KILL TARGET SEARCH ====================
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

-- ==================== PROMPTS / DIALOG ====================
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

local function clickDialogOption()
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Dialog") then
            local choices = {}
            for _, c in ipairs(v:GetChildren()) do
                if c:IsA("DialogChoice") then table.insert(choices, c) end
            end
            table.sort(choices, function(a,b) return (a.ResponseOrder or 0) < (b.ResponseOrder or 0) end)
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

-- ==================== TALK / KILL LOGIC ====================
local Talking, Killing = false, false

local function doTalkQuest(targetName, sessionId)
    if Talking then return end
    Talking = true
    MovementController:setPaused(true)
    AttackController:setPaused(true)
    MovementController:clearTarget()
    AttackController:clearTarget()

    local ok, err = pcall(function()
        local pd  = LocalPlayer:FindFirstChild("PlayerData")
        local sd  = pd and pd:FindFirstChild("SlotData")
        local cq  = sd and sd:FindFirstChild("CurrentQuests")
        local oldValue = cq and cq.Value or ""

        local _, npcObj = findNpcByBillboard(targetName)
        if not npcObj then Log("NPC NOT FOUND: ["..targetName.."]", Color3.fromRGB(255,50,50)); return end
        local npcHRP = getNpcHRP(npcObj)
        if not npcHRP then Log("HRP NOT FOUND: ["..targetName.."]", Color3.fromRGB(255,50,50)); return end
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
        for attempt = 1, 5 do
            if _G.QuestSessionId ~= sessionId or _G.BS_Dead then break end
            MoveToNPC(npcHRP); forceUnlock()
            if _G.QuestSessionId ~= sessionId then break end
            task.wait(0.25)
            if not fireAllPromptsNear(npcHRP, 12) then
                Log("NO PROMPT (attempt "..attempt..")", Color3.fromRGB(255,150,0))
            end
            local clicked = waitAndClickDialog(4)
            if clicked then
                task.wait(0.4); if _G.QuestSessionId == sessionId then clickDialogOption() end
                task.wait(0.4); if _G.QuestSessionId == sessionId then clickDialogOption() end
                task.wait(0.4); if _G.QuestSessionId == sessionId then clickDialogOption() end
            end
            local t0 = os.clock()
            while os.clock() - t0 < 5 do
                if cq and cq.Value ~= oldValue then
                    Log("QUEST UPDATED ✓", Color3.fromRGB(0,255,150))
                    questDone = true; break
                end
                task.wait(0.1)
            end
            if questDone then break end
            Log("RETRY DIALOG "..attempt.."/5", Color3.fromRGB(255,200,0))
            task.wait(0.5)
        end
        if not questDone then Log("DIALOG TIMEOUT — продолжаем", Color3.fromRGB(255,100,0)) end
    end)

    Talking = false
    MovementController:setPaused(false)
    AttackController:setPaused(false)
    forceUnlock()
    if not ok then Log("TALK ERR: "..tostring(err), Color3.fromRGB(255,0,0)) end
end

local function doKillLoop(targetName, sessionId)
    if Killing then return end
    Killing = true

    MovementController:start()
    AttackController:start()

    local ok, err = pcall(function()
        local currentMob = nil
        while _G.AutoQuest_Enabled and _G.QuestSessionId == sessionId and not _G.BS_Dead do
            local quest = getQuestInfo()
            if not quest or quest.type ~= "kill"
                or quest.target:lower() ~= targetName:lower() then
                Log("KILL DONE ✓", Color3.fromRGB(0,255,150)); break
            end

            local valid = isValidMob(currentMob)
            if not valid then
                MovementController:clearTarget()
                AttackController:clearTarget()
                currentMob = nil
                local mob, dist = findKillTarget(targetName)
                if mob then
                    currentMob = mob
                    Log("TARGET: "..mob.Name.." ("..math.floor(dist).."m)", Color3.fromRGB(255,100,100))
                else
                    Log("SEARCHING: "..targetName, Color3.fromRGB(255,150,0))
                    task.wait(1); continue
                end
            end

            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local mobHRP = currentMob and currentMob:FindFirstChild("HumanoidRootPart")
            if not hrp or not mobHRP then task.wait(0.5); continue end

            local dist = (hrp.Position - mobHRP.Position).Magnitude
            if dist > 60 then
                MovementController:setPaused(true)
                AttackController:setPaused(true)
                MovementController:clearTarget()
                AttackController:clearTarget()
                teleportTo(function()
                    if not currentMob or not currentMob.Parent then return nil end
                    local r = currentMob:FindFirstChild("HumanoidRootPart")
                    return r and r.Position or nil
                end, 8, function()
                    return not _G.AutoQuest_Enabled or _G.QuestSessionId ~= sessionId
                end)
                MovementController:setPaused(false)
                AttackController:setPaused(false)
            end

            MovementController:setTarget(currentMob)
            AttackController:setTarget(currentMob)
            task.wait(0.3)
        end
    end)

    MovementController:stop()
    AttackController:stop()
    Killing = false
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
                MovementController:stop(); AttackController:stop()
                forceUnlock()
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
            MovementController:clearTarget()
            AttackController:clearTarget()
            continue
        end
        if quest.type ~= lastQuestType or quest.target ~= lastQuestTarget then
            lastQuestType = quest.type; lastQuestTarget = quest.target
            Talking = false; Killing = false
            MovementController:stop(); AttackController:stop()
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
                    elseif root then best = v; bestDist = 0 end
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
                    if text:find("auto retry") or text:find("return to menu") then return true end
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
        if not data then Log("RAID DATA NOT FOUND: "..tostring(raidName), Color3.fromRGB(255,0,0)); return end
        Log("RAID START: "..raidName, Color3.fromRGB(255,180,0))

        MovementController:setPaused(true)
        AttackController:setPaused(true)
        MovementController:clearTarget()
        AttackController:clearTarget()

        local _, npcObj = findNpcByBillboard(data.npcName)
        if not npcObj and data.npcPos then
            teleportTo(function() return data.npcPos end, 8,
                function() return _G.RaidSessionId ~= raidSid or not _G.AutoRaid_Enabled end)
            forceUnlock()
            _, npcObj = findNpcByBillboard(data.npcName)
        end
        if not npcObj then Log("RAID NPC NOT FOUND: "..data.npcName, Color3.fromRGB(255,0,0)); return end

        local npcHRP = getNpcHRP(npcObj)
        if not npcHRP then Log("RAID NPC HRP NOT FOUND", Color3.fromRGB(255,0,0)); return end

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
            MoveToNPC(npcHRP); forceUnlock(); task.wait(0.25)
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
            if target then teleported = true; Log("IN RAID — target found: "..target.Name, Color3.fromRGB(0,255,100)); break end
            task.wait(0.5)
        end
        if not teleported then Log("TELEPORT TIMEOUT", Color3.fromRGB(255,100,0)); return end

        MovementController:setPaused(false)
        AttackController:setPaused(false)
        MovementController:start()
        AttackController:start()

        local raidKillStart = os.clock()
        local currentMob = nil

        while _G.AutoRaid_Enabled and _G.RaidSessionId == raidSid and not _G.BS_Dead do
            if os.clock() - raidKillStart > 600 then Log("RAID KILL TIMEOUT", Color3.fromRGB(255,100,0)); break end
            local valid = isValidMob(currentMob)
            if not valid then
                MovementController:clearTarget(); AttackController:clearTarget()
                currentMob = findRaidTarget(data.bossName)
                if not currentMob then Log("RAID: no more targets", Color3.fromRGB(0,255,150)); break end
            end
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local mobHRP = currentMob and currentMob:FindFirstChild("HumanoidRootPart")
            if not hrp or not mobHRP then task.wait(0.5); continue end
            local dist = (hrp.Position - mobHRP.Position).Magnitude
            if dist > 60 then
                MovementController:setPaused(true); AttackController:setPaused(true)
                teleportTo(function()
                    if not currentMob or not currentMob.Parent then return nil end
                    local r = currentMob:FindFirstChild("HumanoidRootPart")
                    return r and r.Position or nil
                end, 8, function()
                    return not _G.AutoRaid_Enabled or _G.RaidSessionId ~= raidSid
                end)
                MovementController:setPaused(false); AttackController:setPaused(false)
            end
            MovementController:setTarget(currentMob)
            AttackController:setTarget(currentMob)
            task.wait(0.3)
        end

        MovementController:stop(); AttackController:stop()
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
    MovementController:stop(); AttackController:stop()
    RaidRunning = false; forceUnlock()
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
        bg.Parent = head; bg.Name = "BS_ESP"; bg.AlwaysOnTop = true
        bg.Size = UDim2.new(0,100,0,30)
        local tl = Instance.new("TextLabel")
        tl.Parent = bg; tl.Size = UDim2.new(1,0,1,0)
        tl.BackgroundTransparency = 1; tl.TextColor3 = Color3.new(1,1,1)
        tl.Font = Enum.Font.GothamBold; tl.TextSize = 13
        local highOk, high = pcall(Instance.new, "Highlight")
        if not highOk then high = nil end
        if high then
            high.Name = "BS_ESP"; high.FillColor = Color3.fromRGB(255,0,50); high.Parent = char
        end
        local conn = RunService.Heartbeat:Connect(function()
            if _G.BS_Dead then bg:Destroy(); if high then high:Destroy() end; return end
            if _G.ESP_Enabled and char and char.Parent
                and LocalPlayer.Character
                and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local d = math.floor(
                    (LocalPlayer.Character.HumanoidRootPart.Position - head.Position).Magnitude)
                tl.Text = p.Name.." ["..d.."m]"
                bg.Enabled = true; if high then high.Enabled = true end
            else
                bg.Enabled = false; if high then high.Enabled = false end
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
    MovementController:stop(); AttackController:stop()
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

pcall(function()
    LocalPlayer.Idled:Connect(function()
        if _G.BS_Dead then return end
        if not VirtualUser then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    savedCollide = {}
    Talking = false; Killing = false; RaidRunning = false
    MovementController:stop(); AttackController:stop()
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
        if v then _G.QuestSessionId = _G.QuestSessionId + 1
        else
            Talking = false; Killing = false
            MovementController:stop(); AttackController:stop()
        end
    end,

    SetESP           = function(v) _G.ESP_Enabled = v and true or false end,
    SetKillSnapDepth = function(v)
        local n = tonumber(v)
        if n then _G.KillSnapDepth = n; _G.CombatDepth = n; _G.CombatYOffset = n end
    end,
    SetCombatYOffset = function(v)
        local n = tonumber(v)
        if n then _G.CombatYOffset = n; _G.KillSnapDepth = n; _G.CombatDepth = n end
    end,
    SetAttackCooldown = function(v)
        local n = tonumber(v); if n then _G.AttackCooldown = n; _G.AttackDelay = n end
    end,
    SetMoveTickRate = function(v) local n = tonumber(v); if n then _G.MoveTickRate = n end end,
    SetMoveLerpAlpha = function(v)
        local n = tonumber(v); if n then _G.MoveLerpAlpha = math.clamp(n, 0.05, 1) end
    end,

    SetAutoRaid = function(v)
        _G.AutoRaid_Enabled = v and true or false
        if v then _G.RaidSessionId = _G.RaidSessionId + 1
        else
            RaidRunning = false
            MovementController:stop(); AttackController:stop()
        end
    end,
    SetAutoRaidRetry  = function(v) _G.AutoRaid_Retry  = v and true or false end,
    SetAutoRaidReturn = function(v) _G.AutoRaid_Return = v and true or false end,
    SetRaidSelected   = function(v) _G.AutoRaid_Selected = v end,

    ToggleRemoteSpy = function(v)
        _G.BS_RemoteSpy_Enabled = v and true or false
        Log("RemoteSpy: "..(v and "ON" or "OFF"),
            v and Color3.fromRGB(0,255,150) or Color3.fromRGB(180,180,180))
    end,
    ToggleInputDebug = function(v)
        _G.BS_InputDebug_Enabled = v and true or false
        Log("InputDebug: "..(v and "ON" or "OFF"),
            v and Color3.fromRGB(0,255,150) or Color3.fromRGB(180,180,180))
    end,
    StartAttackDetect = function()
        if not hookInstalled then
            Log("Cannot detect — hookmetamethod missing/failed", Color3.fromRGB(255,100,100))
            return
        end
        _G.BS_AttackDetectMode = true
        Log(">> Click M1 ONCE on a mob now <<", Color3.fromRGB(255,255,0))
    end,
    ClearAttackRemote = function()
        _G.BloodyHub_AttackRemote = nil
        Log("Captured attack remote cleared", Color3.fromRGB(255,200,0))
    end,
    GetAttackRemoteInfo = function()
        local cap = _G.BloodyHub_AttackRemote
        if not cap then return "none" end
        return cap.path or "?"
    end,

    DestroySession = function() if _G.BS_DestroyFn then _G.BS_DestroyFn() end end,
}

Log("BloodyHub v4.3 LOADED (namecall pass-through fix)", Color3.fromRGB(0,255,255))

-- ==================== LOAD UI ====================
local ok, src = pcall(function() return game:HttpGet(UI_URL, true) end)
if ok and src and src ~= "" then
    local fn, lerr = loadstring(src)
    if fn then pcall(fn)
    else warn("[BloodyHub] ui.lua compile: "..tostring(lerr)) end
else
    warn("[BloodyHub] ui.lua fetch failed")
end
