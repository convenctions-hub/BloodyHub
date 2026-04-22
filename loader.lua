--[[ BloodyHub loader v1 ]]
local BASE = "https://raw.githubusercontent.com/conventions-hub/BloodyHub/main/"

local function fetch(name)
    local ok, src = pcall(function()
        return game:HttpGet(BASE .. name, true)
    end)
    if not ok or not src or src == "" then
        warn("[BloodyHub] Не удалось загрузить " .. name)
        return nil
    end
    return src
end

-- 1) Загрузочное меню
local loading = fetch("loading.lua")
if loading then
    local fn, err = loadstring(loading)
    if fn then pcall(fn) else warn("[BloodyHub] loading.lua: " .. tostring(err)) end
end

task.wait(2)

-- 2) Основной код (main.lua сам подтянет ui.lua в конце)
local main = fetch("main.lua")
if main then
    local fn, err = loadstring(main)
    if fn then pcall(fn) else warn("[BloodyHub] main.lua: " .. tostring(err)) end
end
