--[[ AnimeCrusadersHub loader v1.0 ]]
local BASE = "https://raw.githubusercontent.com/convenctions-hub/BloodyHub/main/"

local function fetch(name)
	local ok, src = pcall(function()
		return game:HttpGet(BASE .. name, true)
	end)
	if not ok or not src or src == "" then
		warn("[AnimeCrusadersHub] Не удалось загрузить " .. name)
		return nil
	end
	return src
end

-- 1) Loading screen
local loading = fetch("loading.lua")
if loading then
	local fn, err = loadstring(loading)
	if fn then pcall(fn) else warn("[AnimeCrusadersHub] loading.lua: " .. tostring(err)) end
end

task.wait(1.5)

-- 2) Main (main.lua сам подтянет ui.lua)
local main = fetch("main.lua")
if main then
	local fn, err = loadstring(main)
	if fn then pcall(fn) else warn("[AnimeCrusadersHub] main.lua: " .. tostring(err)) end
end
