-- Key check: pasang di paling atas
local EXPECTED_KEY = "Jack"

local providedKey
if type(getgenv) == "function" then providedKey = getgenv().key end
if providedKey == nil and type(_G) == "table" then providedKey = _G.key end

if providedKey ~= EXPECTED_KEY then return end



-- =================================================================
-- GEC MINE ANTARCTICA — HYPERDRIVE QUANTUM V20.3 COMPLETE
-- Radar + Speed 2x + Instant Pickup + Ultra FPS 80+
-- Zero lag | Min Value INPUT di Radar | Value/BaseValue | Berat ringan
-- =================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

pcall(function()
    if setfpscap then setfpscap(999) elseif set_fps_cap then set_fps_cap(999) end
end)

local CONFIG = {
    normalSpeed = 16,
    boostMult = 2,
    radarIntervalIdle = 0.18,   -- lebih santai saat diam = zero lag
    radarIntervalMove = 0.07,  -- tetap responsif saat gerak
    moveThresholdSq = 2.5 * 2.5,
    maxMarkers = 36,
    scanRadius = 210,
    scanRadiusSq = 210 * 210,
    dropRadius = 225,
    dropRadiusSq = 225 * 225,
    cleanupInterval = 6.0,     -- cleanup lebih jarang
    lightWeightValue = 0.1,
}

local RARITIES = {"Exotic", "Legendary", "Rare", "Uncommon", "Common", "Epic", "Mythic"}
local RARITY_UI_LABELS = {
    Exotic = "Eksotis", Legendary = "Legendaris", Rare = "Langka",
    Uncommon = "Tidak Biasa", Common = "Biasa", Epic = "Epik", Mythic = "Mistik",
}
local RARITY_ALIASES = {
    exotic = "Exotic", eksotis = "Exotic", legendary = "Legendary", legendaris = "Legendary",
    rare = "Rare", langka = "Rare", uncommon = "Uncommon", ["tidak biasa"] = "Uncommon",
    common = "Common", biasa = "Common", epic = "Epic", epik = "Epic",
    mythic = "Mythic", mistik = "Mythic",
}
local CATEGORIES = {"Empiris", "Pulsar", "Quasar"}
local NEXUS = {"Void Nexus", "Solar Nexus", "Aether Nexus"}

local RARITY_COLORS = {
    Exotic = Color3.fromRGB(255, 220, 0), Common = Color3.fromRGB(180, 180, 180),
    Uncommon = Color3.fromRGB(90, 200, 90), Rare = Color3.fromRGB(70, 140, 255),
    Epic = Color3.fromRGB(170, 80, 255), Legendary = Color3.fromRGB(255, 170, 40),
    Mythic = Color3.fromRGB(255, 60, 130), Empiris = Color3.fromRGB(0, 255, 200),
    Pulsar = Color3.fromRGB(255, 220, 0), Quasar = Color3.fromRGB(255, 80, 80),
    ["Void Nexus"] = Color3.fromRGB(170, 80, 255), ["Solar Nexus"] = Color3.fromRGB(255, 170, 40),
    ["Aether Nexus"] = Color3.fromRGB(0, 220, 255),
}
local CRYSTAL_COLORS = {
    obsidian = Color3.fromRGB(155, 100, 220), ember = Color3.fromRGB(255, 85, 35),
    crystal = Color3.fromRGB(80, 210, 255),
}
local C = {
    bg = Color3.fromRGB(8, 8, 10), black = Color3.fromRGB(14, 14, 16),
    accent = Color3.fromRGB(88, 101, 242), green = Color3.fromRGB(87, 242, 135),
    orange = Color3.fromRGB(254, 160, 60), purple = Color3.fromRGB(180, 80, 220),
    red = Color3.fromRGB(237, 66, 69), textMain = Color3.fromRGB(235, 238, 245),
    textSub = Color3.fromRGB(130, 136, 148),
}

local speedOn, radarOn, boosterOn, lightWeightOn = false, false, false, false
local selectedRarities, selectedCategories, selectedNexus = {}, {}, {}
local minValueFilter = 0 -- 0 = no filter | set 1000 / 1000000 dll
local targetRegistry, targetList = {}, {}
local activeMarkers = {}
local highlightPool = table.create(CONFIG.maxMarkers + 10)

for i = 1, CONFIG.maxMarkers + 10 do
    local hl = Instance.new("Highlight")
    hl.Name = "HyperHL"
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 0.30
    hl.OutlineTransparency = 0
    hl.Enabled = false
    highlightPool[i] = hl
end

local MAX_FOUND_BUFFER = 64
local foundSlots = table.create(MAX_FOUND_BUFFER)
for i = 1, MAX_FOUND_BUFFER do
    foundSlots[i] = {part = nil, data = nil, dist = 0}
end

local keepBuffer = {}
local scanRunning, lastScanClock, lastHrpPos, lastCleanup = false, 0, Vector3.zero, 0
local isMoving = false

local function acquireHighlight(part, color)
    local hl = table.remove(highlightPool)
    if not hl or not hl.Parent then
        hl = Instance.new("Highlight")
        hl.Name = "HyperHL"
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.30
        hl.OutlineTransparency = 0
    end
    hl.FillColor = color
    hl.OutlineColor = color
    hl.Adornee = part
    hl.Parent = part
    hl.Enabled = true
    return hl
end

local function releaseHighlight(part)
    local pack = activeMarkers[part]
    if pack then
        local hl = pack.hl
        if hl then
            hl.Enabled = false
            hl.Adornee = nil
            hl.Parent = nil
            table.insert(highlightPool, hl)
        end
        activeMarkers[part] = nil
    end
end

local function clearAllMarkers()
    for part in pairs(activeMarkers) do releaseHighlight(part) end
    table.clear(activeMarkers)
end

local function isForbiddenObject(obj)
    if not obj then return true end
    local char = localPlayer.Character
    if char and obj:IsDescendantOf(char) then return true end
    local bp = localPlayer:FindFirstChild("Backpack")
    if bp and obj:IsDescendantOf(bp) then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer and p.Character and obj:IsDescendantOf(p.Character) then return true end
    end
    return false
end

local function normalizeName(name)
    if type(name) ~= "string" then return "" end
    return name:lower():gsub("[%s_%-]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end

local function readStringAttribute(obj, key)
    local ok, value = pcall(function() return obj:GetAttribute(key) end)
    if ok and type(value) == "string" and value ~= "" then return value end
    return nil
end

-- Baca Value / BaseValue (Attribute ATAU child) → return number atau nil
local function readNumericValue(obj)
    if not obj then return nil end
    local function toNum(v)
        if type(v) == "number" then return v end
        if type(v) == "string" then
            local n = tonumber(v:gsub("[,%s]", ""))
            return n
        end
        return nil
    end
    -- Attribute
    local ok, attr = pcall(function() return obj:GetAttribute("Value") end)
    if ok and attr ~= nil then
        local n = toNum(attr)
        if n then return n end
    end
    ok, attr = pcall(function() return obj:GetAttribute("BaseValue") end)
    if ok and attr ~= nil then
        local n = toNum(attr)
        if n then return n end
    end
    -- Child
    local v = obj:FindFirstChild("Value")
    if v and (v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("StringValue")) then
        local n = toNum(v.Value)
        if n then return n end
    end
    local bv = obj:FindFirstChild("BaseValue")
    if bv and (bv:IsA("NumberValue") or bv:IsA("IntValue") or bv:IsA("StringValue")) then
        local n = toNum(bv.Value)
        if n then return n end
    end
    return nil
end

-- Baca raw Value/BaseValue (buat rarity text match juga)
local function readValueOrBaseValue(obj)
    if not obj then return nil end
    local ok, attr = pcall(function() return obj:GetAttribute("Value") end)
    if ok and attr ~= nil then return attr end
    ok, attr = pcall(function() return obj:GetAttribute("BaseValue") end)
    if ok and attr ~= nil then return attr end
    local v = obj:FindFirstChild("Value")
    if v and (v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("StringValue")) then
        return v.Value
    end
    local bv = obj:FindFirstChild("BaseValue")
    if bv and (bv:IsA("NumberValue") or bv:IsA("IntValue") or bv:IsA("StringValue")) then
        return bv.Value
    end
    return nil
end

local function getObjectName(obj)
    if not obj then return "" end
    for _, key in ipairs({"ItemName", "CrystalName", "NexusName", "DisplayName", "ObjectName"}) do
        local value = readStringAttribute(obj, key)
        if value then return value end
    end
    return obj.Name
end

local function resolveNexusName(obj)
    if not obj then return nil end
    local current, depth = obj, 0
    while current and current ~= Workspace and depth < 7 do
        local norm = normalizeName(getObjectName(current))
        if norm == "void nexus" or norm:find("void nexus", 1, true) then return "Void Nexus"
        elseif norm == "solar nexus" or norm:find("solar nexus", 1, true) then return "Solar Nexus"
        elseif norm == "aether nexus" or norm:find("aether nexus", 1, true) then return "Aether Nexus" end
        current = current.Parent
        depth += 1
    end
    return nil
end

local function isCrystalTarget(obj)
    if not obj or isForbiddenObject(obj) then return false end
    local current, depth = obj, 0
    while current and current ~= Workspace and depth < 7 do
        local name = normalizeName(getObjectName(current))
        if name:find("crystal", 1, true) or name:find("cluster", 1, true)
            or name:find("obsidian", 1, true) or name:find("ember", 1, true)
            or name:find("ore", 1, true) or name:find("gem", 1, true)
            or name:find("constellation", 1, true) or name:find("hydra", 1, true) then
            return true
        end
        if current:GetAttribute("Rarity") or current:GetAttribute("TierName")
            or current:GetAttribute("CrystalWeight") or current:GetAttribute("Health")
            or readValueOrBaseValue(current) ~= nil then
            return true
        end
        current = current.Parent
        depth += 1
    end
    return false
end

local RARITY_ALIAS_ORDER = {
    "tidak biasa", "legendaris", "uncommon", "legendary", "eksotis",
    "exotic", "mythic", "mistik", "langka", "biasa", "common", "epik", "rare", "epic",
}

local function getRarityName(part)
    if not part then return nil end
    local current, depth = part, 0
    while current and current ~= Workspace and depth < 7 do
        local values = {
            current:GetAttribute("Rarity"), current:GetAttribute("TierName"),
            current:GetAttribute("Tier"), current:GetAttribute("RarityName"), getObjectName(current),
        }
        local vb = readValueOrBaseValue(current)
        if vb ~= nil then table.insert(values, vb) end
        for _, rawValue in ipairs(values) do
            local normalized = normalizeName(tostring(rawValue or ""))
            if normalized ~= "" then
                for _, alias in ipairs(RARITY_ALIAS_ORDER) do
                    if normalized == alias or normalized:find(alias, 1, true) then
                        return RARITY_ALIASES[alias]
                    end
                end
            end
        end
        current = current.Parent
        depth += 1
    end
    return nil
end

-- Ambil numeric Value/BaseValue tertinggi di hierarchy (untuk filter min value)
local function getCrystalValue(part)
    if not part then return nil end
    local best = nil
    local current, depth = part, 0
    while current and current ~= Workspace and depth < 7 do
        local n = readNumericValue(current)
        if n and (not best or n > best) then best = n end
        current = current.Parent
        depth += 1
    end
    return best
end

local function getCrystalCategory(part)
    if not part then return nil end
    for _, key in ipairs({"CrystalName", "CrystalType", "Type", "Kind", "Category"}) do
        local value = readStringAttribute(part, key)
        if value then
            for _, category in ipairs(CATEGORIES) do
                if normalizeName(value) == normalizeName(category) then return category end
            end
        end
    end
    local tierName = tostring(part:GetAttribute("TierName") or ""):lower()
    for _, category in ipairs(CATEGORIES) do
        if tierName:find(category:lower(), 1, true) then return category end
    end
    return nil
end

local function resolveColor(part, nexusName, rarityHint)
    if nexusName and RARITY_COLORS[nexusName] then return RARITY_COLORS[nexusName] end
    local r = tonumber(part:GetAttribute("TierColorR"))
    local g = tonumber(part:GetAttribute("TierColorG"))
    local b = tonumber(part:GetAttribute("TierColorB"))
    if r and g and b then return Color3.fromRGB(r, g, b) end
    local rarity = rarityHint or getRarityName(part)
    if rarity and RARITY_COLORS[rarity] then return RARITY_COLORS[rarity] end
    local text = normalizeName(getObjectName(part))
    for key, color in pairs(CRYSTAL_COLORS) do
        if text:find(key, 1, true) then return color end
    end
    return Color3.fromRGB(200, 210, 230)
end

local function getWorldPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true) end
    if obj:IsA("Folder") then return obj:FindFirstChildWhichIsA("BasePart", true) end
    return nil
end

local function applyLightWeight(obj)
    if not obj or not lightWeightOn then return end
    pcall(function()
        local current, depth = obj, 0
        while current and current ~= Workspace and depth < 7 do
            if current:GetAttribute("CrystalWeight") ~= nil then
                current:SetAttribute("CrystalWeight", CONFIG.lightWeightValue)
            end
            local w = current:FindFirstChild("CrystalWeight") or current:FindFirstChild("Weight")
            if w and (w:IsA("NumberValue") or w:IsA("IntValue")) then
                w.Value = CONFIG.lightWeightValue
            end
            current = current.Parent
            depth += 1
        end
    end)
end

local function registerTarget(obj)
    if not obj or isForbiddenObject(obj) then return end
    local part = getWorldPart(obj)
    if not part or targetRegistry[part] then return end
    local nexus = resolveNexusName(obj) or resolveNexusName(part)
    local crystal = isCrystalTarget(obj) or isCrystalTarget(part)
    if nexus or crystal then
        local rarity = getRarityName(part)
        local value = getCrystalValue(part)
        local data = {
            part = part,
            nexus = nexus,
            crystal = crystal,
            rarity = rarity,
            category = nil,
            value = value,
            color = resolveColor(part, nexus, rarity),
        }
        targetRegistry[part] = data
        table.insert(targetList, data)
        if lightWeightOn then applyLightWeight(obj) end
    end
end

local function unregisterTarget(part)
    if targetRegistry[part] then
        targetRegistry[part] = nil
        releaseHighlight(part)
        for i = #targetList, 1, -1 do
            if targetList[i].part == part then
                table.remove(targetList, i)
                break
            end
        end
    end
end

-- Register initial (yielded keras biar zero lag load)
task.spawn(function()
    local desc = Workspace:GetDescendants()
    local n = #desc
    for i = 1, n do
        local obj = desc[i]
        if obj and (obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder")) then
            pcall(registerTarget, obj)
        end
        if i % 350 == 0 then task.wait() end
    end
end)

Workspace.DescendantAdded:Connect(function(obj)
    if obj and (obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder")) then
        task.defer(function()
            pcall(registerTarget, obj)
            if lightWeightOn then applyLightWeight(obj) end
        end)
    end
end)

Workspace.DescendantRemoving:Connect(function(obj)
    if obj:IsA("BasePart") then unregisterTarget(obj) end
end)

local function passesFilter(data)
    if not data or next(selectedRarities) == nil then return false end
    if not data.rarity or not selectedRarities[data.rarity] then return false end
    -- Min Value filter: harus >= minValueFilter (kalau minValueFilter > 0)
    if minValueFilter > 0 then
        local v = data.value
        if v == nil then
            -- coba refresh value sekali
            v = getCrystalValue(data.part)
            data.value = v
        end
        if v == nil or v < minValueFilter then return false end
    end
    if next(selectedNexus) and (not data.nexus or not selectedNexus[data.nexus]) then return false end
    if next(selectedCategories) then
        if not data.category then data.category = getCrystalCategory(data.part) end
        if not data.category or not selectedCategories[data.category] then return false end
    end
    return true
end

local function scanRealTime()
    if not radarOn or next(selectedRarities) == nil then
        if next(activeMarkers) then clearAllMarkers() end
        return
    end
    local character = localPlayer.Character
    if not character then clearAllMarkers() return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then clearAllMarkers() return end

    local origin = hrp.Position
    local ox, oy, oz = origin.X, origin.Y, origin.Z
    local radiusSq, dropSq = CONFIG.scanRadiusSq, CONFIG.dropRadiusSq
    local foundCount = 0
    local listLen = #targetList

    for i = 1, listLen do
        local data = targetList[i]
        local part = data.part
        if part and part.Parent then
            local pos = part.Position
            local dx = pos.X - ox
            if dx * dx <= radiusSq then
                local dz = pos.Z - oz
                if dz * dz <= radiusSq then
                    local dy = pos.Y - oy
                    local distSq = dx*dx + dy*dy + dz*dz
                    if distSq <= radiusSq and passesFilter(data) then
                        foundCount += 1
                        if foundCount <= MAX_FOUND_BUFFER then
                            local slot = foundSlots[foundCount]
                            slot.part, slot.data, slot.dist = part, data, distSq
                        end
                    end
                end
            end
        end
    end

    local actualFound = math.min(foundCount, MAX_FOUND_BUFFER)
    table.sort(foundSlots, function(a, b)
        if a.dist == 0 then return false end
        if b.dist == 0 then return true end
        return a.dist < b.dist
    end)

    table.clear(keepBuffer)
    local activeCount = 0
    for part, pack in pairs(activeMarkers) do
        local valid = false
        if part and part.Parent and pack.hl and pack.rarity and selectedRarities[pack.rarity] then
            local pos = part.Position
            local dx, dy, dz = pos.X - ox, pos.Y - oy, pos.Z - oz
            if (dx*dx + dy*dy + dz*dz) <= dropSq then
                -- re-check value filter biar marker yang di bawah threshold hilang
                local data = targetRegistry[part]
                if data and passesFilter(data) then
                    valid = true
                    keepBuffer[part] = true
                    activeCount += 1
                end
            end
        end
        if not valid then releaseHighlight(part) end
    end

    for i = 1, actualFound do
        if activeCount >= CONFIG.maxMarkers then break end
        local slot = foundSlots[i]
        local part = slot.part
        if part and not keepBuffer[part] then
            if not activeMarkers[part] then
                local hl = acquireHighlight(part, slot.data.color)
                activeMarkers[part] = {hl = hl, rarity = slot.data.rarity}
                activeCount += 1
            end
            keepBuffer[part] = true
        end
    end

    for i = 1, actualFound do
        foundSlots[i].dist, foundSlots[i].part, foundSlots[i].data = 0, nil, nil
    end
end

-- Instant Pickup ZERO LAG (event-driven only)
local processedPrompts = setmetatable({}, {__mode = "k"})
local function processPrompt(obj)
    if not obj or not obj:IsA("ProximityPrompt") or processedPrompts[obj] then return end
    processedPrompts[obj] = true
    pcall(function()
        if obj.HoldDuration and obj.HoldDuration > 0 then obj.HoldDuration = 0 end
        obj.RequiresLineOfSight = false
    end)
end

task.spawn(function()
    local desc = Workspace:GetDescendants()
    for i = 1, #desc do
        processPrompt(desc[i])
        if i % 500 == 0 then task.wait() end
    end
end)

Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("ProximityPrompt") then
        task.defer(processPrompt, obj)
    end
end)

RunService.Heartbeat:Connect(function()
    local now = tick()
    if radarOn and not scanRunning then
        local character = localPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local pos = hrp.Position
            local delta = (pos - lastHrpPos).Magnitude
            isMoving = (delta * delta) > CONFIG.moveThresholdSq
            if isMoving then lastHrpPos = pos end
        end
        local interval = isMoving and CONFIG.radarIntervalMove or CONFIG.radarIntervalIdle
        if (now - lastScanClock) >= interval then
            lastScanClock = now
            scanRunning = true
            pcall(scanRealTime)
            scanRunning = false
        end
    end
    if now - lastCleanup > CONFIG.cleanupInterval then
        lastCleanup = now
        for i = #targetList, 1, -1 do
            local data = targetList[i]
            if not data.part or not data.part.Parent then unregisterTarget(data.part) end
        end
    end
end)

-- Ultra FPS 80+
local boosterBackup = {effects = {}, savedSettings = {}}
local boosterEvent = nil

local function enableGameBooster()
    boosterBackup.globalShadows = Lighting.GlobalShadows
    boosterBackup.fogEnd = Lighting.FogEnd
    boosterBackup.brightness = Lighting.Brightness

    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.FogStart = 0
        Lighting.Brightness = 1.25
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.Ambient = Color3.fromRGB(50, 50, 50)
        Lighting.OutdoorAmbient = Color3.fromRGB(50, 50, 50)
    end)

    table.clear(boosterBackup.effects)
    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("PostProcessEffect") or effect:IsA("BloomEffect") or effect:IsA("BlurEffect")
            or effect:IsA("ColorCorrectionEffect") or effect:IsA("SunRaysEffect") or effect:IsA("DepthOfFieldEffect") then
            boosterBackup.effects[effect] = effect.Enabled
            pcall(function() effect.Enabled = false end)
        end
    end

    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        boosterBackup.terrainDecoration = terrain.Decoration
        boosterBackup.waterWaveSize = terrain.WaterWaveSize
        boosterBackup.waterWaveSpeed = terrain.WaterWaveSpeed
        pcall(function()
            terrain.Decoration = false
            terrain.WaterWaveSize = 0
            terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0
        end)
    end

    pcall(function()
        if UserGameSettings then
            boosterBackup.savedSettings.SavedQualityLevel = UserGameSettings.SavedQualityLevel
            UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        end
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)

    if boosterEvent then boosterEvent:Disconnect() end
    boosterEvent = Workspace.DescendantAdded:Connect(function(obj)
        if not boosterOn then return end
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
            pcall(function() obj.Enabled = false end)
        elseif obj:IsA("BasePart") or obj:IsA("MeshPart") then
            pcall(function() obj.CastShadow = false end)
        end
    end)

    task.spawn(function()
        local count = 0
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if not boosterOn then break end
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
                or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                pcall(function() obj.Enabled = false end)
            elseif obj:IsA("BasePart") or obj:IsA("MeshPart") then
                pcall(function() obj.CastShadow = false end)
            end
            count += 1
            if count % 400 == 0 then task.wait() end
        end
    end)
end

local function disableGameBooster()
    if boosterEvent then boosterEvent:Disconnect() boosterEvent = nil end
    pcall(function()
        if boosterBackup.globalShadows ~= nil then Lighting.GlobalShadows = boosterBackup.globalShadows end
        if boosterBackup.fogEnd ~= nil then Lighting.FogEnd = boosterBackup.fogEnd end
        if boosterBackup.brightness ~= nil then Lighting.Brightness = boosterBackup.brightness end
        Lighting.EnvironmentDiffuseScale = 1
        Lighting.EnvironmentSpecularScale = 1
    end)
    for effect, state in pairs(boosterBackup.effects) do
        if effect and effect.Parent then pcall(function() effect.Enabled = state end) end
    end
    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        pcall(function()
            if boosterBackup.terrainDecoration ~= nil then terrain.Decoration = boosterBackup.terrainDecoration end
            if boosterBackup.waterWaveSize ~= nil then terrain.WaterWaveSize = boosterBackup.waterWaveSize end
            if boosterBackup.waterWaveSpeed ~= nil then terrain.WaterWaveSpeed = boosterBackup.waterWaveSpeed end
        end)
    end
    pcall(function()
        if UserGameSettings and boosterBackup.savedSettings.SavedQualityLevel then
            UserGameSettings.SavedQualityLevel = boosterBackup.savedSettings.SavedQualityLevel
        end
    end)
end

-- Speed 2x
local function targetSpeed() return CONFIG.normalSpeed * CONFIG.boostMult end
local speedConn, speedRenderConn = nil, nil

local function applySpeed(hum)
    if hum and speedOn and hum.WalkSpeed ~= targetSpeed() then
        hum.WalkSpeed = targetSpeed()
    end
end

local function hookSpeed()
    if speedConn then speedConn:Disconnect() end
    if speedRenderConn then speedRenderConn:Disconnect() end
    local char = localPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    speedConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if speedOn then applySpeed(hum) end
    end)
    speedRenderConn = RunService.RenderStepped:Connect(function()
        if not speedOn then return end
        local c = localPlayer.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        if h then applySpeed(h) end
    end)
    applySpeed(hum)
end

local function unhookSpeed()
    if speedConn then speedConn:Disconnect() speedConn = nil end
    if speedRenderConn then speedRenderConn:Disconnect() speedRenderConn = nil end
    local char = localPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = CONFIG.normalSpeed end
end

localPlayer.CharacterAdded:Connect(function()
    task.wait(0.4)
    if speedOn then hookSpeed() end
end)

-- GUI
local old = playerGui:FindFirstChild("GecMineAntarctica") or playerGui:FindFirstChild("EngineGUI")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GecMineAntarctica"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 9999
screenGui.Parent = playerGui

local outer = Instance.new("Frame", screenGui)
outer.Size = UDim2.new(0, 430, 0, 420)
outer.Position = UDim2.new(0, 12, 0.5, -195)
outer.BackgroundColor3 = C.bg
outer.BorderSizePixel = 0
outer.Active = true
Instance.new("UICorner", outer).CornerRadius = UDim.new(0, 16)
Instance.new("UIStroke", outer).Color = Color3.fromRGB(45, 45, 52)

local titleBar = Instance.new("Frame", outer)
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundColor3 = C.accent
titleBar.BackgroundTransparency = 0.25
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 16)

local tbFix = Instance.new("Frame", titleBar)
tbFix.Size = UDim2.new(1, 0, 0, 12)
tbFix.Position = UDim2.new(0, 0, 1, -12)
tbFix.BackgroundColor3 = C.accent
tbFix.BackgroundTransparency = 0.25
tbFix.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(1, -52, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.Text = "❄ Gec Mine Antarctica • V20.3 Complete"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.TextSize = 12
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.BackgroundTransparency = 1

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0, 20, 0, 18)
minBtn.Position = UDim2.new(1, -24, 0.5, -9)
minBtn.Text = "_"
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.BackgroundColor3 = Color3.fromRGB(70, 80, 110)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 11
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local leftCol = Instance.new("Frame", outer)
leftCol.Size = UDim2.new(0, 48, 1, -38)
leftCol.Position = UDim2.new(0, 6, 0, 34)
leftCol.BackgroundTransparency = 1

local function makeIconButton(yPos, icon, gradA, gradB)
    local btn = Instance.new("TextButton", leftCol)
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.Position = UDim2.new(0, 0, 0, yPos)
    btn.Text = icon
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 18
    btn.Font = Enum.Font.GothamBold
    btn.BackgroundColor3 = C.black
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 11)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(45, 45, 52)
    stroke.Thickness = 1.5
    local grad = Instance.new("UIGradient", btn)
    grad.Color = ColorSequence.new(gradB, gradB)
    grad.Transparency = NumberSequence.new(0.88)
    local function setVisual(on)
        if on then
            grad.Color = ColorSequence.new(gradA, gradB)
            grad.Transparency = NumberSequence.new(0.15)
            stroke.Color = gradB
        else
            grad.Color = ColorSequence.new(gradB, gradB)
            grad.Transparency = NumberSequence.new(0.88)
            stroke.Color = Color3.fromRGB(45, 45, 52)
        end
    end
    return btn, setVisual
end

local CYAN = Color3.fromRGB(0, 200, 255)
local PINK = Color3.fromRGB(255, 100, 160)
local LIME = Color3.fromRGB(100, 255, 100)

local speedBtn, setSpeedVis = makeIconButton(0, "⚡", C.accent, CYAN)
local radarBtn, setRadarVis = makeIconButton(46, "◎", C.orange, PINK)
local settingsBtn, setSettingsVis = makeIconButton(92, "⚙", C.green, LIME)

local divider = Instance.new("Frame", outer)
divider.Size = UDim2.new(0, 1, 1, -46)
divider.Position = UDim2.new(0, 60, 0, 40)
divider.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
divider.BorderSizePixel = 0

local rightCol = Instance.new("Frame", outer)
rightCol.Size = UDim2.new(1, -74, 1, -46)
rightCol.Position = UDim2.new(0, 66, 0, 34)
rightCol.BackgroundTransparency = 1

local radarPage = Instance.new("Frame", rightCol)
radarPage.Size = UDim2.new(1, 0, 1, 0)
radarPage.BackgroundTransparency = 1
radarPage.Visible = true

local fTitle = Instance.new("TextLabel", radarPage)
fTitle.Size = UDim2.new(1, -54, 0, 13)
fTitle.Text = "SELECT RARITIES"
fTitle.TextColor3 = C.purple
fTitle.TextSize = 9
fTitle.Font = Enum.Font.GothamBold
fTitle.TextXAlignment = Enum.TextXAlignment.Left
fTitle.BackgroundTransparency = 1

local radarStatus
local radarToggleBtn = Instance.new("TextButton", radarPage)
radarToggleBtn.Size = UDim2.new(0, 50, 0, 16)
radarToggleBtn.Position = UDim2.new(1, -50, 0, -2)
radarToggleBtn.TextColor3 = Color3.new(1, 1, 1)
radarToggleBtn.TextSize = 7
radarToggleBtn.Font = Enum.Font.GothamBold
radarToggleBtn.BorderSizePixel = 0
Instance.new("UICorner", radarToggleBtn).CornerRadius = UDim.new(0, 5)

local function refreshRadarToggle()
    radarToggleBtn.Text = radarOn and "RADAR ON" or "RADAR OFF"
    radarToggleBtn.BackgroundColor3 = radarOn and C.accent or C.red
end

radarToggleBtn.MouseButton1Click:Connect(function()
    radarOn = not radarOn
    setRadarVis(radarOn)
    refreshRadarToggle()
    if radarOn then
        radarStatus.Text = "ANTARCTICA • 210M • 36 MARKERS • ON"
        lastScanClock = 0
        task.defer(scanRealTime)
    else
        radarStatus.Text = "ANTARCTICA • 210M • OFF"
        clearAllMarkers()
    end
end)

local catScroll = Instance.new("ScrollingFrame", radarPage)
catScroll.Size = UDim2.new(1, 0, 0, 30)
catScroll.Position = UDim2.new(0, 0, 0, 15)
catScroll.BackgroundTransparency = 1
catScroll.BorderSizePixel = 0
catScroll.ScrollingDirection = Enum.ScrollingDirection.XY
catScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
catScroll.ScrollBarThickness = 2
local catGrid = Instance.new("UIGridLayout", catScroll)
catGrid.CellSize = UDim2.new(0, 54, 0, 13)
catGrid.CellPadding = UDim2.new(0, 3, 0, 3)

local toggleButtons = {}
local updateFilterStatus

local function makeToggleButton(name, color, getState, setState)
    local b = Instance.new("TextButton", catScroll)
    b.Text = name
    b.TextColor3 = color
    b.TextSize = 7
    b.Font = Enum.Font.GothamBold
    b.BackgroundColor3 = C.black
    b.BorderSizePixel = 0
    b.TextTruncate = Enum.TextTruncate.AtEnd
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
    toggleButtons[name] = {btn = b, get = getState, color = color}
    b.MouseButton1Click:Connect(function()
        setState()
        b.BackgroundColor3 = getState() and color or C.black
        updateFilterStatus()
        if radarOn then
            if next(selectedRarities) == nil then clearAllMarkers()
            else task.defer(scanRealTime) end
        end
    end)
end

for _, rarity in ipairs(RARITIES) do
    makeToggleButton(RARITY_UI_LABELS[rarity], RARITY_COLORS[rarity],
        function() return selectedRarities[rarity] == true end,
        function() selectedRarities[rarity] = not selectedRarities[rarity] or nil end)
end
for _, nexus in ipairs(NEXUS) do
    makeToggleButton(nexus, RARITY_COLORS[nexus],
        function() return selectedNexus[nexus] == true end,
        function() selectedNexus[nexus] = not selectedNexus[nexus] or nil end)
end
for _, category in ipairs(CATEGORIES) do
    makeToggleButton(category, RARITY_COLORS[category],
        function() return selectedCategories[category] == true end,
        function() selectedCategories[category] = not selectedCategories[category] or nil end)
end

radarStatus = Instance.new("TextLabel", radarPage)
radarStatus.Size = UDim2.new(1, 0, 0, 22)
radarStatus.Position = UDim2.new(0, 0, 0, 52)
radarStatus.Text = "ANTARCTICA • 210M • OFF"
radarStatus.TextColor3 = C.textMain
radarStatus.TextSize = 9
radarStatus.Font = Enum.Font.GothamBold
radarStatus.TextXAlignment = Enum.TextXAlignment.Left
radarStatus.TextYAlignment = Enum.TextYAlignment.Center
radarStatus.BackgroundColor3 = C.black
radarStatus.BackgroundTransparency = 0.1
radarStatus.BorderSizePixel = 0
Instance.new("UICorner", radarStatus).CornerRadius = UDim.new(0, 7)
Instance.new("UIPadding", radarStatus).PaddingLeft = UDim.new(0, 7)

-- ========== MIN VALUE INPUT (Value / BaseValue) — RADAR PAGE ==========
local valueTitle = Instance.new("TextLabel", radarPage)
valueTitle.Size = UDim2.new(1, 0, 0, 12)
valueTitle.Position = UDim2.new(0, 0, 0, 78)
valueTitle.Text = "MIN VALUE / BASEVALUE  (isi angka → APPLY)"
valueTitle.TextColor3 = C.orange
valueTitle.TextSize = 8
valueTitle.Font = Enum.Font.GothamBold
valueTitle.TextXAlignment = Enum.TextXAlignment.Left
valueTitle.BackgroundTransparency = 1

local valueRow = Instance.new("Frame", radarPage)
valueRow.Size = UDim2.new(1, 0, 0, 32)
valueRow.Position = UDim2.new(0, 0, 0, 92)
valueRow.BackgroundColor3 = C.black
valueRow.BackgroundTransparency = 0.1
valueRow.BorderSizePixel = 0
Instance.new("UICorner", valueRow).CornerRadius = UDim.new(0, 8)
local valueStroke = Instance.new("UIStroke", valueRow)
valueStroke.Color = C.orange
valueStroke.Thickness = 1.2
valueStroke.Transparency = 0.4

local valueLabel = Instance.new("TextLabel", valueRow)
valueLabel.Size = UDim2.new(0, 78, 1, 0)
valueLabel.Position = UDim2.new(0, 8, 0, 0)
valueLabel.Text = "VALUE ≥"
valueLabel.TextColor3 = C.orange
valueLabel.TextSize = 10
valueLabel.Font = Enum.Font.GothamBold
valueLabel.TextXAlignment = Enum.TextXAlignment.Left
valueLabel.BackgroundTransparency = 1

local valueBox = Instance.new("TextBox", valueRow)
valueBox.Size = UDim2.new(0, 130, 0, 22)
valueBox.Position = UDim2.new(0, 86, 0.5, -11)
valueBox.Text = "0"
valueBox.PlaceholderText = "contoh: 1000 / 1000000"
valueBox.TextColor3 = Color3.new(1, 1, 1)
valueBox.PlaceholderColor3 = C.textSub
valueBox.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
valueBox.Font = Enum.Font.GothamBold
valueBox.TextSize = 11
valueBox.BorderSizePixel = 0
valueBox.ClearTextOnFocus = false
valueBox.TextXAlignment = Enum.TextXAlignment.Center
Instance.new("UICorner", valueBox).CornerRadius = UDim.new(0, 6)

local valueApplyBtn = Instance.new("TextButton", valueRow)
valueApplyBtn.Size = UDim2.new(0, 58, 0, 22)
valueApplyBtn.Position = UDim2.new(1, -66, 0.5, -11)
valueApplyBtn.Text = "APPLY"
valueApplyBtn.TextColor3 = Color3.new(1, 1, 1)
valueApplyBtn.BackgroundColor3 = C.accent
valueApplyBtn.Font = Enum.Font.GothamBold
valueApplyBtn.TextSize = 9
valueApplyBtn.BorderSizePixel = 0
Instance.new("UICorner", valueApplyBtn).CornerRadius = UDim.new(0, 6)

local function applyMinValue()
    local raw = valueBox.Text:gsub("[,%s]", "")
    local n = tonumber(raw)
    if not n or n < 0 then n = 0 end
    minValueFilter = n
    valueBox.Text = tostring(n)
    updateFilterStatus()
    if radarOn then
        if next(selectedRarities) == nil then clearAllMarkers()
        else task.defer(scanRealTime) end
    end
end

valueApplyBtn.MouseButton1Click:Connect(applyMinValue)
valueBox.FocusLost:Connect(function(enter)
    applyMinValue()
end)

local resetBtn = Instance.new("TextButton", radarPage)
resetBtn.Size = UDim2.new(1, 0, 0, 22)
resetBtn.Position = UDim2.new(0, 0, 0, 130)
resetBtn.Text = "↺ RESET FILTER"
resetBtn.TextColor3 = Color3.new(1, 1, 1)
resetBtn.BackgroundColor3 = C.red
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 9
resetBtn.BorderSizePixel = 0
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 7)

local filterStatus = Instance.new("TextLabel", radarPage)
filterStatus.Size = UDim2.new(1, 0, 0, 40)
filterStatus.Position = UDim2.new(0, 0, 0, 156)
filterStatus.Text = ""
filterStatus.TextColor3 = C.green
filterStatus.TextSize = 9
filterStatus.Font = Enum.Font.GothamBold
filterStatus.TextXAlignment = Enum.TextXAlignment.Left
filterStatus.TextYAlignment = Enum.TextYAlignment.Top
filterStatus.BackgroundTransparency = 1
filterStatus.TextWrapped = true

local settingsPage = Instance.new("Frame", rightCol)
settingsPage.Size = UDim2.new(1, 0, 1, 0)
settingsPage.BackgroundTransparency = 1
settingsPage.Visible = false

local pTitle = Instance.new("TextLabel", settingsPage)
pTitle.Size = UDim2.new(1, 0, 0, 16)
pTitle.Text = "⚙ SETTINGS"
pTitle.TextColor3 = C.green
pTitle.TextSize = 10
pTitle.Font = Enum.Font.GothamBold
pTitle.TextXAlignment = Enum.TextXAlignment.Left
pTitle.BackgroundTransparency = 1

local boosterCard = Instance.new("Frame", settingsPage)
boosterCard.Size = UDim2.new(1, 0, 0, 48)
boosterCard.Position = UDim2.new(0, 0, 0, 20)
boosterCard.BackgroundColor3 = C.black
boosterCard.BackgroundTransparency = 0.2
boosterCard.BorderSizePixel = 0
Instance.new("UICorner", boosterCard).CornerRadius = UDim.new(0, 7)

local bInfoLabel = Instance.new("TextLabel", boosterCard)
bInfoLabel.Size = UDim2.new(1, -70, 1, 0)
bInfoLabel.Position = UDim2.new(0, 8, 0, 0)
bInfoLabel.Text = "⚡ ULTRA FPS 80+\nGraphics Optimized • Cooler"
bInfoLabel.TextColor3 = C.textMain
bInfoLabel.TextSize = 8
bInfoLabel.Font = Enum.Font.GothamBold
bInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
bInfoLabel.TextYAlignment = Enum.TextYAlignment.Center
bInfoLabel.BackgroundTransparency = 1

local boosterToggleBtn = Instance.new("TextButton", boosterCard)
boosterToggleBtn.Size = UDim2.new(0, 52, 0, 24)
boosterToggleBtn.Position = UDim2.new(1, -60, 0.5, -12)
boosterToggleBtn.Text = "BOOST OFF"
boosterToggleBtn.TextColor3 = Color3.new(1, 1, 1)
boosterToggleBtn.TextSize = 7
boosterToggleBtn.Font = Enum.Font.GothamBold
boosterToggleBtn.BackgroundColor3 = C.red
boosterToggleBtn.BorderSizePixel = 0
Instance.new("UICorner", boosterToggleBtn).CornerRadius = UDim.new(0, 6)

boosterToggleBtn.MouseButton1Click:Connect(function()
    boosterOn = not boosterOn
    if boosterOn then
        boosterToggleBtn.Text = "BOOST ON"
        boosterToggleBtn.BackgroundColor3 = C.green
        enableGameBooster()
    else
        boosterToggleBtn.Text = "BOOST OFF"
        boosterToggleBtn.BackgroundColor3 = C.red
        disableGameBooster()
    end
end)

local weightCard = Instance.new("Frame", settingsPage)
weightCard.Size = UDim2.new(1, 0, 0, 48)
weightCard.Position = UDim2.new(0, 0, 0, 76)
weightCard.BackgroundColor3 = C.black
weightCard.BackgroundTransparency = 0.2
weightCard.BorderSizePixel = 0
Instance.new("UICorner", weightCard).CornerRadius = UDim.new(0, 7)

local wInfoLabel = Instance.new("TextLabel", weightCard)
wInfoLabel.Size = UDim2.new(1, -70, 1, 0)
wInfoLabel.Position = UDim2.new(0, 8, 0, 0)
wInfoLabel.Text = "🪶 BERAT RINGAN 100%\nCrystalWeight → 0.1"
wInfoLabel.TextColor3 = C.textMain
wInfoLabel.TextSize = 8
wInfoLabel.Font = Enum.Font.GothamBold
wInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
wInfoLabel.TextYAlignment = Enum.TextYAlignment.Center
wInfoLabel.BackgroundTransparency = 1

local weightToggleBtn = Instance.new("TextButton", weightCard)
weightToggleBtn.Size = UDim2.new(0, 52, 0, 24)
weightToggleBtn.Position = UDim2.new(1, -60, 0.5, -12)
weightToggleBtn.Text = "LIGHT OFF"
weightToggleBtn.TextColor3 = Color3.new(1, 1, 1)
weightToggleBtn.TextSize = 7
weightToggleBtn.Font = Enum.Font.GothamBold
weightToggleBtn.BackgroundColor3 = C.red
weightToggleBtn.BorderSizePixel = 0
Instance.new("UICorner", weightToggleBtn).CornerRadius = UDim.new(0, 6)

weightToggleBtn.MouseButton1Click:Connect(function()
    lightWeightOn = not lightWeightOn
    if lightWeightOn then
        weightToggleBtn.Text = "LIGHT ON"
        weightToggleBtn.BackgroundColor3 = C.green
        for _, data in ipairs(targetList) do
            if data.part then applyLightWeight(data.part) end
        end
    else
        weightToggleBtn.Text = "LIGHT OFF"
        weightToggleBtn.BackgroundColor3 = C.red
    end
end)

local pInfo = Instance.new("TextLabel", settingsPage)
pInfo.Position = UDim2.new(0, 0, 0, 134)
pInfo.Size = UDim2.new(1, 0, 0, 55)
pInfo.Text = "V20.3 Complete\nRadar • Speed 2x • Instant Pickup • Ultra FPS 80+\nMin Value INPUT di Radar • Value/BaseValue • Berat Ringan"
pInfo.TextColor3 = C.textSub
pInfo.TextSize = 8
pInfo.Font = Enum.Font.Gotham
pInfo.TextXAlignment = Enum.TextXAlignment.Left
pInfo.BackgroundTransparency = 1
pInfo.TextWrapped = true

function updateFilterStatus()
    local parts = {}
    local rCount = 0
    for _ in pairs(selectedRarities) do rCount += 1 end
    if rCount > 0 then table.insert(parts, rCount .. " rarity") end
    local nCount = 0
    for _ in pairs(selectedNexus) do nCount += 1 end
    if nCount > 0 then table.insert(parts, nCount .. " Nexus") end
    local cCount = 0
    for _ in pairs(selectedCategories) do cCount += 1 end
    if cCount > 0 then table.insert(parts, cCount .. " cat") end
    if minValueFilter > 0 then
        table.insert(parts, "Value ≥ " .. tostring(minValueFilter))
    end
    filterStatus.Text = #parts > 0 and table.concat(parts, " | ") or "Filter: SEMUA NONAKTIF"
end

local function refreshToggles()
    for _, data in pairs(toggleButtons) do
        data.btn.BackgroundColor3 = data.get() and (data.color or C.accent) or C.black
    end
end

resetBtn.MouseButton1Click:Connect(function()
    table.clear(selectedRarities)
    table.clear(selectedCategories)
    table.clear(selectedNexus)
    minValueFilter = 0
    valueBox.Text = "0"
    clearAllMarkers()
    refreshToggles()
    updateFilterStatus()
    if radarOn then task.defer(scanRealTime) end
end)

speedBtn.MouseButton1Click:Connect(function()
    speedOn = not speedOn
    setSpeedVis(speedOn)
    if speedOn then hookSpeed() else unhookSpeed() end
end)

radarBtn.MouseButton1Click:Connect(function()
    setSettingsVis(false)
    radarPage.Visible = true
    settingsPage.Visible = false
    refreshRadarToggle()
end)

settingsBtn.MouseButton1Click:Connect(function()
    setSettingsVis(true)
    radarPage.Visible = false
    settingsPage.Visible = true
end)

local miniBubble = Instance.new("TextButton", screenGui)
miniBubble.Size = UDim2.new(0, 48, 0, 48)
miniBubble.Position = UDim2.new(0, 12, 0.5, -24)
miniBubble.Text = "❄"
miniBubble.TextColor3 = Color3.new(1, 1, 1)
miniBubble.BackgroundColor3 = C.accent
miniBubble.Font = Enum.Font.GothamBold
miniBubble.TextSize = 18
miniBubble.BorderSizePixel = 0
miniBubble.Visible = false
Instance.new("UICorner", miniBubble).CornerRadius = UDim.new(1, 0)

minBtn.MouseButton1Click:Connect(function()
    miniBubble.Position = outer.Position
    outer.Visible = false
    miniBubble.Visible = true
end)
miniBubble.MouseButton1Click:Connect(function()
    outer.Visible = true
    miniBubble.Visible = false
end)

local function makeDraggable(frame)
    local dragging, dragStart, startPos = false, nil, nil
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    frame.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

makeDraggable(outer)
makeDraggable(miniBubble)

updateFilterStatus()
refreshToggles()
refreshRadarToggle()

print("❄ GEC MINE ANTARCTICA V20.3 COMPLETE LOADED ✔ | Min Value INPUT di Radar page")
