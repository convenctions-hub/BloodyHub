--[[ BloodyHub main logic v5.0
   ─────────────────────────────────────────────────────────────────
   Структура:
     1) CONFIG          — все настраиваемые числа в одном месте
     2) STATE           — рантайм-флаги, без мусорных _G
     3) UTIL            — мелкие хелперы
     4) LOGGER GUI      — простой и компактный лог
     5) DEBUG MODULE    — чистый remote-spy с фильтром по имени
     6) COMBAT MODULE   — M1 remote, без кликов, без UI-инпута
     7) MOVEMENT        — позиционирование под мобом
     8) QUEST/RAID/ESP  — без изменений по логике
     9) PUBLIC API      — для UI
    10) UI LOADER
   ─────────────────────────────────────────────────────────────────
   Атака — только через RemoteEvent:
     Workspace.Live.<Character>.client_character_controller.M1
     :FireServer(true, false)
   Никаких mouse1click / VirtualUser / firetouchinterest — НИКОГДА.
]]

local UI_URL = "https://raw.githubusercontent.com/convenctions-hub/BloodyHub/main/ui.lua"

-- ============================================================== --
--                          СЕРВИСЫ                                --
-- ============================================================== --
local HttpService   = game:GetService("HttpService")
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UserInputSvc  = game:GetService("UserInputService")
local CoreGui       = game:GetService("CoreGui")
local LocalPlayer   = Players.LocalPlayer

-- ============================================================== --
-- 1)                          CONFIG                              --
-- ============================================================== --
local CONFIG = {
    -- Combat
    AttackDelay   = 0.30,   -- секунд между M1 (slider-ready)
    AttackRange   = 18,     -- максимальная дистанция атаки (studs)
    AttackTick    = 0.05,   -- частота внутреннего цикла
    -- Movement
    CombatYOffset = 6,
    MoveTickRate  = 0.12,
    MoveLerpAlpha = 0.35,
    MoveSnapDist  = 25,
    MoveDeadZone  = 0.4,
    MoveDebounce  = 0.12,
    -- Quest
    QuestForwardDist   = 4,
    QuestTeleThreshold = 3.5,
    -- Debug
    DebugFilter   = "M1",   -- подстрока в имени remote (case-insensitive)
    DebugMaxLines = 18,
}

-- ============================================================== --
-- 2)                          STATE                               --
-- ============================================================== --
local STATE = {
    Dead          = false,
    AutoQuest     = false,
    AutoRaid      = false,
    AutoRaidRetry = false,
    AutoRaidReturn= false,
    AutoRaidPick  = nil,
    QuestSession  = 0,
    RaidSession   = 0,
    ESP           = false,
    -- Combat
    CombatToggle  = false,    -- master kill-aura toggle (для UI)
    CombatTarget  = nil,      -- текущий моб (Model)
    -- Debug
    DebugEnabled  = false,    -- логировать ли отфильтрованные remote
}

-- ============================================================== --
-- 3)                          UTIL                                --
-- ============================================================== --
local function getMyChar()
    return LocalPlayer.Character
end

local function getMyParts()
    local c = getMyChar()
    if not c then return nil, nil end
    return c:FindFirstChild("HumanoidRootPart"),
           c:FindFirstChildOfClass("Humanoid")
end

local function isAlive(mob)
    if not mob or not mob.Parent then return false end
    local hum = mob:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local hrp = mob:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    return true, hrp, hum
end

local savedCollide = {}
local function setGhost(on)
    local char = getMyChar()
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
    local hrp, hum = getMyParts()
    if hrp then hrp.Anchored = false end
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end
end

-- ============================================================== --
-- 4)                       LOGGER GUI                             --
-- ============================================================== --
pcall(function()
    for _, g in ipairs(CoreGui:GetChildren()) do
        if g.Name == "BSLog" then pcall(function() g:Destroy() end) end
    end
end)

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
local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0,6); lc.Parent = LogFrame

local LogContainer = Instance.new("Frame")
LogContainer.Parent = LogFrame
LogContainer.Size = UDim2.new(1,-10,1,-10)
LogContainer.Position = UDim2.new(0,5,0,5)
LogContainer.BackgroundTransparency = 1
local lyt = Instance.new("UIListLayout")
lyt.VerticalAlignment = Enum.VerticalAlignment.Bottom
lyt.Parent = LogContainer

local function Log(msg, color)
    if STATE.Dead then return end
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
    if #ch > CONFIG.DebugMaxLines then ch[2]:Destroy() end
end

-- ============================================================== --
-- 5)                       DEBUG MODULE                           --
--                                                                 --
--  Чистый remote-spy:                                             --
--    • включается тогглом                                         --
--    • логирует ТОЛЬКО RemoteEvent/Function, чьё имя содержит     --
--      CONFIG.DebugFilter (по умолчанию "M1")                     --
--    • печатает: имя remote + аргументы                           --
--    • не трогает оригинальный вызов (pass-through __namecall)    --
-- ============================================================== --
local Debug = {}

local function previewArgs(args, n)
    local out = {}
    local cap = math.min(n, 5)
    for i = 1, cap do
        local v = args[i]
        local tv = typeof(v)
        if tv == "Instance" then
            out[i] = "<"..v.ClassName..":"..v.Name..">"
        elseif tv == "Vector3" or tv == "CFrame" then
            out[i] = tostring(v)
        elseif tv == "table" then
            out[i] = "{table}"
        elseif tv == "string" then
            out[i] = '"'..(v:sub(1,24))..'"'
        elseif v == nil then
            out[i] = "nil"
        else
            out[i] = tostring(v)
        end
    end
    if n > cap then out[#out+1] = "..(+"..(n-cap)..")" end
    return table.concat(out, ", ")
end

function Debug.SetEnabled(v) STATE.DebugEnabled = v and true or false end
function Debug.SetFilter(name)
    CONFIG.DebugFilter = tostring(name or "")
    Log("Debug filter = '"..CONFIG.DebugFilter.."'", Color3.fromRGB(0,200,255))
end

local hookInstalled = false
local function installRemoteHook()
    if hookInstalled then return end
    if not (hookmetamethod and newcclosure and getnamecallmethod) then
        Log("Executor lacks hookmetamethod — Debug DISABLED",
            Color3.fromRGB(255,100,100))
        return
    end

    local oldNamecall
    local ok, err = pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            -- метод кэшируем ДО любых обращений к self
            local ok_m, method = pcall(getnamecallmethod)
            if not ok_m then return oldNamecall(self, ...) end

            if STATE.DebugEnabled
               and (method == "FireServer" or method == "InvokeServer") then
                local argc = select("#", ...)
                pcall(function()
                    if typeof(self) ~= "Instance" then return end
                    local filter = CONFIG.DebugFilter
                    if filter == "" then return end
                    local nm = self.Name or ""
                    if not nm:lower():find(filter:lower(), 1, true) then return end

                    local args = table.create and table.create(argc) or {}
                    for i = 1, argc do args[i] = (select(i, ...)) end
                    Log(("[%s] %s  (%s)"):format(method, nm,
                        previewArgs(args, argc)),
                        Color3.fromRGB(255,200,0))
                end)
            end

            -- ОРИГИНАЛЬНЫЙ ВЫЗОВ — без table.unpack, чтобы сохранить nil
            return oldNamecall(self, ...)
        end))
    end)

    if ok then
        hookInstalled = true
        Log("Debug hook installed", Color3.fromRGB(0,255,200))
    else
        Log("Debug hook FAILED: "..tostring(err), Color3.fromRGB(255,80,80))
    end
end
pcall(installRemoteHook)

-- ============================================================== --
-- 6)                       COMBAT MODULE                          --
--                                                                 --
--  Атака ТОЛЬКО через:                                            --
--    Workspace.Live.<Character>.client_character_controller.M1    --
--    :FireServer(true, false)                                     --
--                                                                 --
--  • Работает в фоне (task.spawn), независимо от фокуса окна.     --
--  • Не трогает мышь, GUI, инпут.                                 --
--  • Толстый rate-limit на CONFIG.AttackDelay.                    --
--  • Опциональная цель (placeholder findTarget) для kill-aura.    --
-- ============================================================== --
local Combat = {}
Combat._lastFire = 0
Combat._thread   = nil
Combat._target   = nil

-- Резолвим M1-remote от персонажа игрока.
-- Сначала ищем в LocalPlayer.Character, затем fallback в Workspace.Live.<Name>.
local function resolveM1Remote()
    local char = getMyChar()
    local ctrl = char and char:FindFirstChild("client_character_controller")
    if not ctrl then
        local live = workspace:FindFirstChild("Live")
        if live then
            -- сначала по имени игрока, иначе — любой моб с контроллером
            local pchar = live:FindFirstChild(LocalPlayer.Name)
            if pchar then
                ctrl = pchar:FindFirstChild("client_character_controller")
            end
            if not ctrl then
                for _, m in ipairs(live:GetChildren()) do
                    local c = m:FindFirstChild("client_character_controller")
                    if c then ctrl = c break end
                end
            end
        end
    end
    if not ctrl then return nil end
    local m1 = ctrl:FindFirstChild("M1")
    if m1 and m1:IsA("RemoteEvent") then return m1 end
    return nil
end

-- Кэш remote — обновляется только если предыдущий "умер"
local _cachedM1
local function getM1()
    if _cachedM1 and _cachedM1.Parent then return _cachedM1 end
    _cachedM1 = resolveM1Remote()
    return _cachedM1
end

-- Низкоуровневый вызов: один M1, с rate-limit'ом.
function Combat.FireOnce()
    if STATE.Dead then return false end
    local now = os.clock()
    if (now - Combat._lastFire) < CONFIG.AttackDelay then return false end
    local re = getM1()
    if not re then return false end
    local ok = pcall(function() re:FireServer(true, false) end)
    if ok then Combat._lastFire = now end
    return ok
end

-- Placeholder для интеграции с автофармом / kill-aura.
-- Возвращает (mob, hrp) или nil. Можно подменить снаружи через Combat.SetFinder.
local function defaultFindTarget()
    -- если кто-то снаружи задал цель — используем её
    if Combat._target then
        local ok, hrp = isAlive(Combat._target)
        if ok then return Combat._target, hrp end
    end
    -- иначе — ближайший моб в Workspace.Live в радиусе AttackRange
    local myHRP = select(1, getMyParts())
    if not myHRP then return nil end
    local live = workspace:FindFirstChild("Live")
    if not live then return nil end
    local best, bestD, bestHRP = nil, math.huge, nil
    for _, m in ipairs(live:GetDescendants()) do
        if m:IsA("Model") and m ~= getMyChar()
           and not Players:GetPlayerFromCharacter(m) then
            local ok, hrp = isAlive(m)
            if ok then
                local d = (hrp.Position - myHRP.Position).Magnitude
                if d < bestD and d <= CONFIG.AttackRange then
                    best, bestD, bestHRP = m, d, hrp
                end
            end
        end
    end
    return best, bestHRP
end

local _finderFn = defaultFindTarget
function Combat.SetFinder(fn) _finderFn = fn or defaultFindTarget end
function Combat.SetTarget(mob) Combat._target = mob end
function Combat.ClearTarget()  Combat._target = nil end

-- Главный цикл: запускается один раз, сам спит до тиков.
function Combat.Start()
    if Combat._thread then return end
    STATE.CombatToggle = true
    Combat._thread = task.spawn(function()
        while STATE.CombatToggle and not STATE.Dead do
            local mob, mobHRP = _finderFn()
            local myHRP = select(1, getMyParts())
            if mob and mobHRP and myHRP then
                local d = (myHRP.Position - mobHRP.Position).Magnitude
                if d <= CONFIG.AttackRange then
                    Combat.FireOnce()
                end
            end
            task.wait(CONFIG.AttackTick)
        end
        Combat._thread = nil
    end)
end

function Combat.Stop()
    STATE.CombatToggle = false
    Combat._thread = nil
    Combat.ClearTarget()
end

function Combat.SetEnabled(v)
    if v then Combat.Start() else Combat.Stop() end
end

function Combat.SetDelay(v)
    local n = tonumber(v); if n and n > 0 then CONFIG.AttackDelay = n end
end
function Combat.SetRange(v)
    local n = tonumber(v); if n and n > 0 then CONFIG.AttackRange = n end
end

-- ============================================================== --
-- 7)                       MOVEMENT                               --
-- ============================================================== --
local MovementController = {
    target = nil, active = false, paused = false, _thread = nil,
}
function MovementController:setTarget(mob) self.target = mob end
function MovementController:clearTarget()
    self.target = nil
    local hrp, hum = getMyParts()
    if hrp then hrp.Anchored = false end
    if hum then pcall(function()
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end) end
    setGhost(false)
end
function MovementController:setPaused(v)
    self.paused = v and true or false
    if self.paused then
        local hrp = select(1, getMyParts())
        if hrp then hrp.Anchored = false end
        setGhost(false)
    end
end

local function computeUnderTargetCFrame(mobHRP)
    local mp = mobHRP.Position
    local desired = Vector3.new(mp.X, mp.Y - CONFIG.CombatYOffset, mp.Z)
    local lookAt  = Vector3.new(mp.X, mp.Y, mp.Z + 0.001)
    return CFrame.new(desired, lookAt)
end

function MovementController:start()
    if self.active then return end
    self.active = true
    self._thread = task.spawn(function()
        while self.active do
            if self.paused or STATE.Dead then
                task.wait(CONFIG.MoveTickRate); continue
            end
            local mob = self.target
            local valid, mobHRP = isAlive(mob)
            local hrp = select(1, getMyParts())
            if not valid or not hrp then
                if hrp and hrp.Anchored then hrp.Anchored = false end
                task.wait(CONFIG.MoveTickRate); continue
            end
            setGhost(true)
            if not hrp.Anchored then hrp.Anchored = true end
            pcall(function()
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)
            local desired = computeUnderTargetCFrame(mobHRP)
            local delta   = (hrp.Position - desired.Position).Magnitude
            if delta > CONFIG.MoveSnapDist then
                hrp.CFrame = desired
            elseif delta > CONFIG.MoveDeadZone then
                local a = math.clamp(CONFIG.MoveLerpAlpha, 0.05, 1)
                hrp.CFrame = hrp.CFrame:Lerp(desired, a)
            end
            task.wait(CONFIG.MoveTickRate)
        end
    end)
end
function MovementController:stop()
    self.active = false
    self._thread = nil
    self:clearTarget()
end

-- ============================================================== --
-- 8)                  QUEST PARSING / NPC HELPERS                 --
-- ============================================================== --
local RAID_DATA = {
    ["Muhammad Avdol Raid"] = { bossName = "Muhammad Avdol", npcName = "Avdol" },
    ["Jotaro Kujo Raid"]    = { bossName = "Jotaro Kujo",    npcName = "Jotaro" },
    ["Kira Yoshikage Raid"] = { bossName = "Yoshikage Kira", npcName = "Kira" },
    ["Dio Brando Raid"]     = { bossName = "Dio Brando",     npcName = "Dio" },
    ["Prison Escape Raid"]  = { bossName = "Prison Guard",   npcName = "Prison Warden" },
    ["Death 13 Raid"]       = { bossName = "Death 13",       npcName = "Death 13" },
    ["Twoh Raid"]           = { bossName = "DIO Over Heaven",npcName = "Dio Over Heaven" },
}

local function getQuestInfo()
    local pd = LocalPlayer:FindFirstChild("PlayerData")
    local sd = pd and pd:FindFirstChild("SlotData")
    local cq = sd and sd:FindFirstChild("CurrentQuests")
    if not cq or cq.Value == "" or cq.Value == "[]" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(cq.Value) end)
    if not ok or not data or not data[1] then return nil end
    local q = data[1]
    if type(q.Talk) == "table" then
        for npcName, done in pairs(q.Talk) do
            if done == false or done == 0 then
                return { type = "talk", target = tostring(npcName) }
            end
        end
    end
    if type(q.Kills) == "table" then
        for name, info in pairs(q.Kills) do
            local needed, current
            if type(info) == "table" then
                needed  = info.Needed  or info.needed  or 1
                current = info.Current or info.current or 0
            elseif type(info) == "number" then
                needed = math.huge; current = info
            else needed = 1; current = 0 end
            if current < needed then
                return { type = "kill", target = tostring(name) }
            end
        end
    end
    if q.TalkTo then return { type = "talk", target = tostring(q.TalkTo) } end
    if q.NPC    then return { type = "talk", target = tostring(q.NPC) } end
    if type(q.Objective) == "string" then
        local npc = q.Objective:match("[Tt]alk to:?%s*(.+)")
        if npc then return { type = "talk", target = npc } end
    end
    return nil
end

local function findNpcByBillboard(targetName)
    local lower = targetName:lower()
    for _, v in ipairs(workspace:GetDescendants()) do
        local text = nil
        if v:IsA("BillboardGui") then
            for _, c in ipairs(v:GetDescendants()) do
                if c:IsA("TextLabel") and c.Text ~= "" then text = c.Text break end
            end
        elseif v:IsA("TextLabel") and v.Text ~= "" then
            text = v.Text
        end
        if text and text:lower():find(lower, 1, true) then
            local part = v.Parent
            while part and part ~= workspace do
                if part:IsA("BasePart") then return part.Position, part end
                if part:IsA("Model") and not Players:GetPlayerFromCharacter(part) then
                    local hrp = part:FindFirstChild("HumanoidRootPart")
                                or part.PrimaryPart
                    if hrp then return hrp.Position, part end
                end
                part = part.Parent
            end
        end
    end
end

local function getNpcHRP(npcObj)
    if not npcObj or not npcObj.Parent then return nil end
    local model = npcObj
    if npcObj:IsA("BasePart") then model = npcObj.Parent end
    if model and model:IsA("Model") then
        return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    end
    return npcObj:IsA("BasePart") and npcObj or nil
end

local function teleportTo(getPos, arriveDist, isCancelled)
    local hrp, hum = getMyParts()
    if not hrp then return false end
    if isCancelled and isCancelled() then return false end
    local pos = getPos()
    if not pos or STATE.Dead then return false end
    setGhost(true); hrp.Anchored = true
    local d = (hrp.Position - pos).Magnitude
    if d > (arriveDist or 5) then
        local dir = (hrp.Position - pos)
        local off = dir.Magnitude > 0.1
            and dir.Unit * (arriveDist or 5)
            or Vector3.new(0, 0, arriveDist or 5)
        local myPos = pos + off
        hrp.CFrame = CFrame.new(myPos, Vector3.new(pos.X, myPos.Y, pos.Z))
    end
    task.wait(0.05)
    if hum then pcall(function()
        hum.PlatformStand = false
        hum.Sit = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end) end
    return true
end

local _lastQuestMove = 0
local function MoveToNPC(npcHRP, opts)
    opts = opts or {}
    if not npcHRP or not npcHRP.Parent then return false end
    local now = os.clock()
    if not opts.force and (now - _lastQuestMove) < CONFIG.MoveDebounce then return false end
    local hrp, hum = getMyParts()
    if not hrp then return false end
    setGhost(true)
    if hum then pcall(function()
        hum.PlatformStand = false
        hum.Sit = false
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end) end
    hrp.Anchored = true
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    local fwd = opts.forwardDist or CONFIG.QuestForwardDist
    local target = npcHRP.CFrame * CFrame.new(0, 0, -fwd)
    local thr = opts.threshold or CONFIG.QuestTeleThreshold
    if not opts.force and (hrp.Position - target.Position).Magnitude <= thr then
        return false
    end
    local myPos = target.Position
    local lookAt = Vector3.new(npcHRP.Position.X, myPos.Y, npcHRP.Position.Z)
    hrp.CFrame = CFrame.new(myPos, lookAt)
    _lastQuestMove = now
    return true
end

-- Поиск моба для kill-квеста (по имени)
local function findKillTarget(targetName)
    local lower = targetName:lower()
    local hrp0 = select(1, getMyParts())
    local best, bestD = nil, math.huge
    local npcFolder = workspace:FindFirstChild("Npcs")
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("Model") and not Players:GetPlayerFromCharacter(v) then
            local hum = v:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local isQ = false
                if npcFolder then
                    local p = v.Parent
                    while p and p ~= workspace do
                        if p == npcFolder then isQ = true break end
                        p = p.Parent
                    end
                end
                if not isQ then
                    local matched = v.Name:lower():find(lower, 1, true) and true
                    if not matched then
                        for _, c in ipairs(v:GetDescendants()) do
                            if c:IsA("TextLabel") and c.Text ~= ""
                               and c.Text:lower():find(lower, 1, true) then
                                matched = true; break
                            end
                        end
                    end
                    if matched then
                        local r = v:FindFirstChild("HumanoidRootPart")
                        if r and hrp0 then
                            local d = (r.Position - hrp0.Position).Magnitude
                            if d < bestD then best = v; bestD = d end
                        end
                    end
                end
            end
        end
    end
    return best, bestD
end

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
                fired = fired + 1
            end
        end
    end
    return fired > 0
end

-- Клик по диалоговой кнопке через firesignal — это НЕ симуляция мыши,
-- а прямой вызов Click-сигнала на конкретной кнопке. Для совместимости
-- с квестовой системой оставлено.
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
                return true
            end
        end
    end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    local cands = {}
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("TextButton") and gui.Visible and gui.Active then
            local fn = gui:GetFullName()
            if not fn:find("BloodyHub") and not fn:find("BSLog") then
                local txt = (gui.Text or ""):lower()
                local prio = 50
                if     txt:match("^%s*1[%.]")   then prio = 1
                elseif txt:match("^%s*yes")     then prio = 2
                elseif txt:match("^%s*accept")  then prio = 3
                elseif txt:match("^%s*continue")then prio = 6
                elseif txt:match("^%s*next")    then prio = 7
                elseif txt:match("^%s*start")   then prio = 8
                elseif txt ~= ""                then prio = 20 end
                table.insert(cands, { btn = gui, prio = prio })
            end
        end
    end
    table.sort(cands, function(a,b) return a.prio < b.prio end)
    if #cands > 0 then
        local b = cands[1].btn
        pcall(function() firesignal(b.MouseButton1Click) end)
        pcall(function() firesignal(b.Activated) end)
        pcall(function()
            for _, c in ipairs(getconnections(b.MouseButton1Click)) do c:Fire() end
        end)
        return true
    end
    return false
end

local function waitAndClickDialog(timeout)
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        if clickDialogOption() then return true end
        task.wait(0.15)
    end
    return false
end

-- ============================================================== --
--                      QUEST: TALK / KILL                         --
-- ============================================================== --
local Talking, Killing = false, false

local function doTalkQuest(name, sid)
    if Talking then return end
    Talking = true
    MovementController:setPaused(true)
    Combat.Stop()
    MovementController:clearTarget()

    pcall(function()
        local pd = LocalPlayer:FindFirstChild("PlayerData")
        local sd = pd and pd:FindFirstChild("SlotData")
        local cq = sd and sd:FindFirstChild("CurrentQuests")
        local oldVal = cq and cq.Value or ""
        local _, npcObj = findNpcByBillboard(name)
        if not npcObj then Log("NPC NOT FOUND: "..name, Color3.fromRGB(255,50,50)); return end
        local npcHRP = getNpcHRP(npcObj)
        if not npcHRP then return end
        local hrp = select(1, getMyParts()); if not hrp then return end
        Log("TALK -> "..name, Color3.fromRGB(0,200,255))
        local d = (hrp.Position - npcHRP.Position).Magnitude
        if d > 30 then
            teleportTo(function() return npcHRP and npcHRP.Parent and npcHRP.Position or nil end,
                CONFIG.QuestForwardDist + 2,
                function() return STATE.QuestSession ~= sid end)
        end
        MoveToNPC(npcHRP, { force = true }); forceUnlock()
        if STATE.QuestSession ~= sid then return end
        local done = false
        for attempt = 1, 5 do
            if STATE.QuestSession ~= sid or STATE.Dead then break end
            MoveToNPC(npcHRP); forceUnlock(); task.wait(0.25)
            fireAllPromptsNear(npcHRP, 12)
            local clicked = waitAndClickDialog(4)
            if clicked then
                task.wait(0.4); clickDialogOption()
                task.wait(0.4); clickDialogOption()
                task.wait(0.4); clickDialogOption()
            end
            local t0 = os.clock()
            while os.clock() - t0 < 5 do
                if cq and cq.Value ~= oldVal then done = true; break end
                task.wait(0.1)
            end
            if done then break end
            task.wait(0.5)
        end
    end)

    Talking = false
    MovementController:setPaused(false)
    forceUnlock()
end

local function doKillLoop(name, sid)
    if Killing then return end
    Killing = true
    MovementController:start()
    Combat.Start()

    pcall(function()
        local cur = nil
        while STATE.AutoQuest and STATE.QuestSession == sid and not STATE.Dead do
            local q = getQuestInfo()
            if not q or q.type ~= "kill"
               or q.target:lower() ~= name:lower() then break end
            local valid = isAlive(cur)
            if not valid then
                MovementController:clearTarget()
                Combat.ClearTarget()
                cur = nil
                local mob, dist = findKillTarget(name)
                if mob then
                    cur = mob
                    Log("TARGET: "..mob.Name.." ("..math.floor(dist).."m)",
                        Color3.fromRGB(255,100,100))
                else
                    task.wait(1); continue
                end
            end
            local hrp = select(1, getMyParts())
            local mh  = cur and cur:FindFirstChild("HumanoidRootPart")
            if not hrp or not mh then task.wait(0.5); continue end
            local d = (hrp.Position - mh.Position).Magnitude
            if d > 60 then
                MovementController:setPaused(true)
                teleportTo(function()
                    if not cur or not cur.Parent then return nil end
                    local r = cur:FindFirstChild("HumanoidRootPart")
                    return r and r.Position or nil
                end, 8, function()
                    return not STATE.AutoQuest or STATE.QuestSession ~= sid
                end)
                MovementController:setPaused(false)
            end
            MovementController:setTarget(cur)
            Combat.SetTarget(cur)
            task.wait(0.3)
        end
    end)

    MovementController:stop()
    Combat.Stop()
    Killing = false
    forceUnlock()
end

-- ==================== MAIN QUEST LOOP ====================
task.spawn(function()
    local lastT, lastN = nil, nil
    local act = os.clock()
    while task.wait(0.5) do
        if STATE.Dead then break end
        if not STATE.AutoQuest then lastT, lastN = nil, nil; continue end
        if Killing or Talking then
            if os.clock() - act > 35 then
                Log("WATCHDOG reset", Color3.fromRGB(255,200,0))
                Killing, Talking = false, false
                MovementController:stop(); Combat.Stop(); forceUnlock()
                act = os.clock()
            end
        else act = os.clock() end
        local q = getQuestInfo()
        if not q then
            if lastT then Log("NO QUEST — idle", Color3.fromRGB(180,180,180)) end
            lastT, lastN = nil, nil
            MovementController:clearTarget(); Combat.ClearTarget()
            continue
        end
        if q.type ~= lastT or q.target ~= lastN then
            lastT, lastN = q.type, q.target
            Talking, Killing = false, false
            MovementController:stop(); Combat.Stop()
            act = os.clock()
            Log("QUEST ["..q.type:upper().."]: "..q.target, Color3.fromRGB(0,220,255))
        end
        local sid = STATE.QuestSession
        if     q.type == "talk" and not Talking then
            task.spawn(function() doTalkQuest(q.target, sid) end)
        elseif q.type == "kill" and not Killing then
            task.spawn(function() doKillLoop(q.target, sid) end)
        end
    end
end)

-- ============================================================== --
--                         AUTO RAID                               --
-- ============================================================== --
local function findRaidTarget(bossName)
    local live = workspace:FindFirstChild("Live"); if not live then return nil end
    local lower = bossName:lower()
    local hrp0 = select(1, getMyParts())
    local best, bestD = nil, math.huge
    for _, v in ipairs(live:GetDescendants()) do
        if v:IsA("Model") and not Players:GetPlayerFromCharacter(v) then
            local hum = v:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local matched = v.Name:lower():find(lower, 1, true) and true
                if not matched then
                    for _, c in ipairs(v:GetDescendants()) do
                        if c:IsA("TextLabel")
                           and c.Text:lower():find(lower, 1, true) then
                            matched = true; break
                        end
                    end
                end
                if matched then
                    local r = v:FindFirstChild("HumanoidRootPart")
                    if r and hrp0 then
                        local d = (r.Position - hrp0.Position).Magnitude
                        if d < bestD then best = v; bestD = d end
                    elseif r then best = v; bestD = 0 end
                end
            end
        end
    end
    return best
end

local function clickPostRaidButton(pattern)
    local pg = LocalPlayer:FindFirstChild("PlayerGui"); if not pg then return false end
    for _, gui in ipairs(pg:GetDescendants()) do
        if gui:IsA("TextButton") or gui:IsA("TextLabel") then
            local txt = (gui.Text or ""):lower()
            if txt:find(pattern:lower(), 1, true) then
                local fn = gui:GetFullName()
                if not fn:find("BloodyHub") and not fn:find("BSLog") then
                    pcall(function() firesignal(gui.MouseButton1Click) end)
                    pcall(function() firesignal(gui.Activated) end)
                    pcall(function()
                        for _, c in ipairs(getconnections(gui.MouseButton1Click)) do c:Fire() end
                    end)
                    return true
                end
            end
        end
    end
    return false
end

local function waitForPostRaidGui(timeout)
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, gui in ipairs(pg:GetDescendants()) do
                if (gui:IsA("TextButton") or gui:IsA("TextLabel")) and gui.Visible then
                    local txt = (gui.Text or ""):lower()
                    if txt:find("auto retry") or txt:find("return to menu") then
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
local function doRaidLoop(raidName, sid)
    if RaidRunning then return end
    RaidRunning = true
    pcall(function()
        local data = RAID_DATA[raidName]
        if not data then Log("RAID DATA NOT FOUND", Color3.fromRGB(255,0,0)); return end
        Log("RAID START: "..raidName, Color3.fromRGB(255,180,0))
        MovementController:setPaused(true); Combat.Stop()
        local _, npcObj = findNpcByBillboard(data.npcName)
        if not npcObj then Log("RAID NPC NOT FOUND", Color3.fromRGB(255,0,0)); return end
        local npcHRP = getNpcHRP(npcObj); if not npcHRP then return end
        local hrp0 = select(1, getMyParts())
        if hrp0 and (hrp0.Position - npcHRP.Position).Magnitude > 30 then
            teleportTo(function() return npcHRP and npcHRP.Parent and npcHRP.Position or nil end,
                CONFIG.QuestForwardDist + 2,
                function() return STATE.RaidSession ~= sid or not STATE.AutoRaid end)
        end
        MoveToNPC(npcHRP, { force = true }); forceUnlock()
        if STATE.RaidSession ~= sid or not STATE.AutoRaid then return end
        task.wait(0.3)
        for attempt = 1, 5 do
            if STATE.RaidSession ~= sid or not STATE.AutoRaid then break end
            MoveToNPC(npcHRP); forceUnlock(); task.wait(0.25)
            fireAllPromptsNear(npcHRP, 12)
            local clicked = waitAndClickDialog(4)
            if clicked then
                task.wait(0.4); clickDialogOption()
                task.wait(0.4); clickDialogOption()
                break
            end
            task.wait(0.5)
        end
        Log("WAITING FOR TELEPORT TO RAID...", Color3.fromRGB(255,200,0))
        local tp = false
        local t0 = os.clock()
        while os.clock() - t0 < 25 do
            if not STATE.AutoRaid or STATE.RaidSession ~= sid then return end
            local target = findRaidTarget(data.bossName)
            if target then tp = true break end
            task.wait(0.5)
        end
        if not tp then Log("TELEPORT TIMEOUT", Color3.fromRGB(255,100,0)); return end

        MovementController:setPaused(false)
        MovementController:start(); Combat.Start()

        local startT = os.clock()
        local cur = nil
        while STATE.AutoRaid and STATE.RaidSession == sid and not STATE.Dead do
            if os.clock() - startT > 600 then break end
            local valid = isAlive(cur)
            if not valid then
                MovementController:clearTarget(); Combat.ClearTarget()
                cur = findRaidTarget(data.bossName)
                if not cur then break end
            end
            local hrp = select(1, getMyParts())
            local mh  = cur and cur:FindFirstChild("HumanoidRootPart")
            if not hrp or not mh then task.wait(0.5); continue end
            local d = (hrp.Position - mh.Position).Magnitude
            if d > 60 then
                MovementController:setPaused(true)
                teleportTo(function()
                    if not cur or not cur.Parent then return nil end
                    local r = cur:FindFirstChild("HumanoidRootPart")
                    return r and r.Position or nil
                end, 8, function()
                    return not STATE.AutoRaid or STATE.RaidSession ~= sid
                end)
                MovementController:setPaused(false)
            end
            MovementController:setTarget(cur)
            Combat.SetTarget(cur)
            task.wait(0.3)
        end
        MovementController:stop(); Combat.Stop()
        if not STATE.AutoRaid or STATE.RaidSession ~= sid then return end
        Log("WAITING POST-RAID GUI...", Color3.fromRGB(200,200,0))
        waitForPostRaidGui(15)
        if STATE.AutoRaidRetry then
            local ok = clickPostRaidButton("auto retry")
            Log(ok and "AUTO RETRY triggered" or "AUTO RETRY btn not found",
                ok and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,100,0))
        elseif STATE.AutoRaidReturn then
            local ok = clickPostRaidButton("return to menu")
            Log(ok and "AUTO RETURN triggered" or "AUTO RETURN btn not found",
                ok and Color3.fromRGB(0,255,100) or Color3.fromRGB(255,100,0))
        end
    end)
    MovementController:stop(); Combat.Stop()
    RaidRunning = false; forceUnlock()
end

task.spawn(function()
    while task.wait(1) do
        if STATE.Dead then break end
        if not STATE.AutoRaid then RaidRunning = false; continue end
        if RaidRunning then continue end
        if not STATE.AutoRaidPick then task.wait(3); continue end
        local sid = STATE.RaidSession
        task.spawn(function() doRaidLoop(STATE.AutoRaidPick, sid) end)
    end
end)

-- ============================================================== --
--                            ESP                                  --
-- ============================================================== --
local espConnections = {}
local function CreateESP(p)
    if p == LocalPlayer then return end
    local function setup(char)
        if not char then return end
        local head = char:WaitForChild("Head", 10); if not head then return end
        local bg = Instance.new("BillboardGui")
        bg.Parent = head; bg.Name = "BS_ESP"; bg.AlwaysOnTop = true
        bg.Size = UDim2.new(0,100,0,30)
        local tl = Instance.new("TextLabel")
        tl.Parent = bg; tl.Size = UDim2.new(1,0,1,0)
        tl.BackgroundTransparency = 1; tl.TextColor3 = Color3.new(1,1,1)
        tl.Font = Enum.Font.GothamBold; tl.TextSize = 13
        local hOk, h = pcall(Instance.new, "Highlight")
        if hOk and h then
            h.Name = "BS_ESP"; h.FillColor = Color3.fromRGB(255,0,50); h.Parent = char
        end
        local conn = RunService.Heartbeat:Connect(function()
            if STATE.Dead then bg:Destroy(); if h then h:Destroy() end; return end
            local myHRP = select(1, getMyParts())
            if STATE.ESP and char and char.Parent and myHRP then
                local d = math.floor((myHRP.Position - head.Position).Magnitude)
                tl.Text = p.Name.." ["..d.."m]"
                bg.Enabled = true; if h then h.Enabled = true end
            else
                bg.Enabled = false; if h then h.Enabled = false end
            end
        end)
        table.insert(espConnections, conn)
    end
    p.CharacterAdded:Connect(setup)
    if p.Character then setup(p.Character) end
end
for _, p in pairs(Players:GetPlayers()) do CreateESP(p) end
Players.PlayerAdded:Connect(CreateESP)

-- ============================================================== --
--                       DESTROY SESSION                           --
-- ============================================================== --
local function DestroySession()
    Log("DESTROYING...", Color3.fromRGB(255,50,50))
    STATE.Dead = true
    STATE.AutoQuest = false; STATE.AutoRaid = false
    Talking, Killing, RaidRunning = false, false, false
    MovementController:stop(); Combat.Stop(); forceUnlock()
    for _, c in ipairs(espConnections) do pcall(function() c:Disconnect() end) end
    espConnections = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character then
            for _, o in ipairs(p.Character:GetDescendants()) do
                if o.Name == "BS_ESP" then pcall(function() o:Destroy() end) end
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

-- Сброс состояния на респаун (без VirtualUser anti-idle —
-- никаких click-симуляций мы больше не делаем).
LocalPlayer.CharacterAdded:Connect(function(char)
    savedCollide = {}
    Talking, Killing, RaidRunning = false, false, false
    MovementController:stop(); Combat.Stop()
    _cachedM1 = nil
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if hrp then hrp.Anchored = false end
    Log("RESPAWN — state reset", Color3.fromRGB(200,200,0))
end)

-- ============================================================== --
-- 9)                       PUBLIC API                             --
-- ============================================================== --
_G.BloodyHub_API = {
    Log = Log,

    -- Quest / Raid
    SetAutoQuest = function(v)
        STATE.AutoQuest = v and true or false
        if v then STATE.QuestSession = STATE.QuestSession + 1
        else
            Talking, Killing = false, false
            MovementController:stop(); Combat.Stop()
        end
    end,
    SetAutoRaid = function(v)
        STATE.AutoRaid = v and true or false
        if v then STATE.RaidSession = STATE.RaidSession + 1
        else
            RaidRunning = false
            MovementController:stop(); Combat.Stop()
        end
    end,
    SetAutoRaidRetry  = function(v) STATE.AutoRaidRetry  = v and true or false end,
    SetAutoRaidReturn = function(v) STATE.AutoRaidReturn = v and true or false end,
    SetRaidSelected   = function(v) STATE.AutoRaidPick = v end,

    -- Combat
    SetCombat        = function(v) Combat.SetEnabled(v) end,    -- master kill-aura
    SetAttackDelay   = function(v) Combat.SetDelay(v) end,
    SetAttackRange   = function(v) Combat.SetRange(v) end,
    FireM1Once       = function()  Combat.FireOnce() end,       -- ручной выстрел
    SetCombatTarget  = function(m) Combat.SetTarget(m) end,
    ClearCombatTarget= function()  Combat.ClearTarget() end,

    -- Movement / camera
    SetCombatYOffset = function(v)
        local n = tonumber(v); if n then CONFIG.CombatYOffset = n end
    end,
    SetMoveTickRate  = function(v)
        local n = tonumber(v); if n then CONFIG.MoveTickRate = n end
    end,
    SetMoveLerpAlpha = function(v)
        local n = tonumber(v); if n then
            CONFIG.MoveLerpAlpha = math.clamp(n, 0.05, 1)
        end
    end,

    -- Debug
    SetDebug       = function(v) Debug.SetEnabled(v) end,
    SetDebugFilter = function(s) Debug.SetFilter(s) end,

    -- ESP
    SetESP = function(v) STATE.ESP = v and true or false end,

    -- Session
    DestroySession = DestroySession,
}

Log("BloodyHub v5.0 LOADED (clean combat + debug)", Color3.fromRGB(0,255,255))

-- ============================================================== --
-- 10)                       UI LOADER                             --
-- ============================================================== --
local ok, src = pcall(function() return game:HttpGet(UI_URL, true) end)
if ok and src and src ~= "" then
    local fn, lerr = loadstring(src)
    if fn then pcall(fn)
    else warn("[BloodyHub] ui.lua compile: "..tostring(lerr)) end
else
    warn("[BloodyHub] ui.lua fetch failed")
end
