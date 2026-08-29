-- Key check: pasang di paling atas
local EXPECTED_KEY = "Jack"

local providedKey
if type(getgenv) == "function" then providedKey = getgenv().key end
if providedKey == nil and type(_G) == "table" then providedKey = _G.key end

if providedKey ~= EXPECTED_KEY then return end



-- =================================================================
-- GEC MINE ANTARCTICA — HYPERDRIVE QUANTUM V20.5 PRO
-- Radar ringan+presisi • Speed 3x • Instant Pickup • Ultra FPS
-- Anti Damage + Anti Jatuh (tebing/void) • Zero lag • No crash
-- Optimal objek berat
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
    boostMult = 3,              -- Speed 3x
    radarIntervalIdle = 0.08,   -- cepat tapi ringan
    radarIntervalMove = 0.035,  -- sangat responsif saat gerak
    moveThresholdSq = 2.2 * 2.2,
    maxMarkers = 36,
    scanRadius = 210,
    scanRadiusSq = 210 * 210,
    dropRadius = 230,
    dropRadiusSq = 230 * 230,
    cleanupInterval = 5.5,
    lightWeightValue = 0.1,
    -- Anti fall
    softFallMaxSpeed = -45,     -- limit kecepatan jatuh
    voidY = -80,                -- di bawah ini di-teleport naik (anti void)
    antiFallBoost = 12,         -- dorongan naik saat jatuh bebas
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
local antiDamageOn = false
local selectedRarities, selectedCategories, selectedNexus = {}, {}, {}
local targetRegistry, targetList = {}, {}
local activeMarkers = {}
local highlightPool = table.create(CONFIG.maxMarkers + 12)

for i = 1, CONFIG.maxMarkers + 12 do
    local hl = Instance.new("Highlight")
    hl.Name = "HyperHL"
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 0.30
    hl.OutlineTransparency = 0
    hl.Enabled = false
    highlightPool[i] = hl
end

local MAX_FOUND_BUFFER = 48
local foundSlots = table.create(MAX_FOUND_BUFFER)
for i = 1, MAX_FOUND_BUFFER do
    foundSlots[i] = {part = nil, data = nil, dist = 0}
end

local keepBuffer = {}
local scanRunning, lastScanClock, lastHrpPos, lastCleanup = false, 0, Vector3.zero, 0
local isMoving = false

-- ========== HIGHLIGHT POOL ==========
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
    if not pack then return end
    local hl = pack.hl
    if hl then
        pcall(function()
            hl.Enabled = false
            hl.Adornee = nil
            hl.Parent = nil
        end)
        table.insert(highlightPool, hl)
    end
    activeMarkers[part] = nil
end

local function clearAllMarkers()
    for part in pairs(activeMarkers) do
        releaseHighlight(part)
    end
    table.clear(activeMarkers)
end

-- ========== HELPERS ==========
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
        local hasAttr = false
        pcall(function()
            if current:GetAttribute("Rarity") or current:GetAttribute("TierName")
                or current:GetAttribute("CrystalWeight") or current:GetAttribute("Health") then
                hasAttr = true
            end
        end)
        if hasAttr or readValueOrBaseValue(current) ~= nil then return true end
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
            current:GetAttribute("Rarity"),
            current:GetAttribute("TierName"),
            current:GetAttribute("Tier"),
            current:GetAttribute("RarityName"),
            getObjectName(current),
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
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    if obj:IsA("Folder") then
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
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
    local ok, part = pcall(getWorldPart, obj)
    if not ok or not part or targetRegistry[part] then return end
    local nexus = resolveNexusName(obj) or resolveNexusName(part)
    local crystal = isCrystalTarget(obj) or isCrystalTarget(part)
    if not (nexus or crystal) then return end
    local rarity = getRarityName(part)
    local data = {
        part = part,
        nexus = nexus,
        crystal = crystal,
        rarity = rarity,
        category = nil,
        color = resolveColor(part, nexus, rarity),
    }
    targetRegistry[part] = data
    table.insert(targetList, data)
    if lightWeightOn then applyLightWeight(obj) end
end

local function unregisterTarget(part)
    if not part or not targetRegistry[part] then return end
    targetRegistry[part] = nil
    releaseHighlight(part)
    for i = #targetList, 1, -1 do
        if targetList[i].part == part then
            table.remove(targetList, i)
            break
        end
    end
end

-- Initial register (chunked, no freeze even on heavy maps)
task.spawn(function()
    local ok, desc = pcall(function() return Workspace:GetDescendants() end)
    if not ok or not desc then return end
    for i = 1, #desc do
        local obj = desc[i]
        if obj and (obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder")) then
            pcall(registerTarget, obj)
        end
        if i % 250 == 0 then task.wait() end
    end
end)

Workspace.DescendantAdded:Connect(function(obj)
    if not obj then return end
    if obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder") then
        task.defer(function()
            pcall(registerTarget, obj)
            if lightWeightOn then applyLightWeight(obj) end
        end)
    end
end)

Workspace.DescendantRemoving:Connect(function(obj)
    if obj and obj:IsA("BasePart") then
        pcall(unregisterTarget, obj)
    end
end)

local function passesFilter(data)
    if not data then return false end
    if next(selectedRarities) == nil then return false end
    if not data.rarity or not selectedRarities[data.rarity] then return false end
    if next(selectedNexus) then
        if not data.nexus or not selectedNexus[data.nexus] then return false end
    end
    if next(selectedCategories) then
        if not data.category then
            data.category = getCrystalCategory(data.part)
        end
        if not data.category or not selectedCategories[data.category] then return false end
    end
    return true
end

-- ========== RADAR RINGAN + PRESISI (optimal objek berat) ==========
-- Method: early AABB reject (X lalu Z) → distSq → filter → partial sort top-N
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
    local radiusSq = CONFIG.scanRadiusSq
    local dropSq = CONFIG.dropRadiusSq
    local foundCount = 0
    local listLen = #targetList
    local maxBuf = MAX_FOUND_BUFFER

    -- Pass 1: collect candidates (cheap math only)
    for i = 1, listLen do
        local data = targetList[i]
        local part = data and data.part
        if part and part.Parent then
            local pos = part.Position
            local dx = pos.X - ox
            if dx * dx <= radiusSq then
                local dz = pos.Z - oz
                if dz * dz <= radiusSq then
                    local dy = pos.Y - oy
                    local distSq = dx * dx + dy * dy + dz * dz
                    if distSq <= radiusSq and passesFilter(data) then
                        foundCount += 1
                        if foundCount <= maxBuf then
                            local slot = foundSlots[foundCount]
                            slot.part = part
                            slot.data = data
                            slot.dist = distSq
                        end
                    end
                end
            end
        end
    end

    local actualFound = math.min(foundCount, maxBuf)

    -- Partial sort by distance (only when needed)
    if actualFound > 1 then
        table.sort(foundSlots, function(a, b)
            if a.dist == 0 then return false end
            if b.dist == 0 then return true end
            return a.dist < b.dist
        end)
    end

    table.clear(keepBuffer)
    local activeCount = 0

    -- Keep valid existing markers
    for part, pack in pairs(activeMarkers) do
        local valid = false
        if part and part.Parent and pack.hl and pack.rarity and selectedRarities[pack.rarity] then
            local pos = part.Position
            local dx = pos.X - ox
            local dy = pos.Y - oy
            local dz = pos.Z - oz
            if (dx * dx + dy * dy + dz * dz) <= dropSq then
                local data = targetRegistry[part]
                if data and passesFilter(data) then
                    valid = true
                    keepBuffer[part] = true
                    activeCount += 1
                end
            end
        end
        if not valid then
            releaseHighlight(part)
        end
    end

    -- Add new closest markers
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
        foundSlots[i].dist = 0
        foundSlots[i].part = nil
        foundSlots[i].data = nil
    end
end

-- Instant Pickup (event-driven, zero lag)
local processedPrompts = setmetatable({}, { __mode = "k" })

local function processPrompt(obj)
    if not obj or not obj:IsA("ProximityPrompt") or processedPrompts[obj] then return end
    processedPrompts[obj] = true
    pcall(function()
        if obj.HoldDuration and obj.HoldDuration > 0 then
            obj.HoldDuration = 0
        end
        obj.RequiresLineOfSight = false
    end)
end

task.spawn(function()
    local ok, desc = pcall(function() return Workspace:GetDescendants() end)
    if not ok or not desc then return end
    for i = 1, #desc do
        processPrompt(desc[i])
        if i % 400 == 0 then task.wait() end
    end
end)

Workspace.DescendantAdded:Connect(function(obj)
    if obj and obj:IsA("ProximityPrompt") then
        task.defer(processPrompt, obj)
    end
end)

-- ========== ANTI DAMAGE + ANTI JATUH (tebing / void) ==========
local antiConn = {}
local lastSafeCFrame = nil
local lastHealth = 100

local function clearAntiConns()
    for _, c in ipairs(antiConn) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(antiConn)
end

local function hookAntiDamage(char)
    clearAntiConns()
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum then return end

    lastHealth = hum.Health
    if hrp then lastSafeCFrame = hrp.CFrame end

    -- Disable dangerous states
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
    end)

    -- Anti damage: restore health jika turun
    table.insert(antiConn, hum.HealthChanged:Connect(function(h)
        if not antiDamageOn then return end
        if h < lastHealth and h > 0 then
            pcall(function()
                hum.Health = math.max(lastHealth, hum.MaxHealth)
            end)
        end
        if h > lastHealth then lastHealth = h end
        if hum.Health >= hum.MaxHealth then lastHealth = hum.MaxHealth end
    end))

    -- State guard: cancel FallingDown / Ragdoll
    table.insert(antiConn, hum.StateChanged:Connect(function(_, new)
        if not antiDamageOn then return end
        if new == Enum.HumanoidStateType.FallingDown
            or new == Enum.HumanoidStateType.Ragdoll then
            pcall(function()
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
    end))

    -- Soft fall + anti void + remember safe spot (Heartbeat ringan)
    table.insert(antiConn, RunService.Heartbeat:Connect(function()
        if not antiDamageOn then return end
        local c = localPlayer.Character
        if not c then return end
        local h = c:FindFirstChildOfClass("Humanoid")
        local root = c:FindFirstChild("HumanoidRootPart")
        if not h or not root then return end

        local state = h:GetState()
        local pos = root.Position
        local vel = root.AssemblyLinearVelocity

        -- Simpan posisi aman saat grounded
        if state == Enum.HumanoidStateType.Running
            or state == Enum.HumanoidStateType.Landed
            or state == Enum.HumanoidStateType.Climbing then
            if vel.Y > -5 then
                lastSafeCFrame = root.CFrame
            end
        end

        -- Soft fall: batasi kecepatan jatuh + dorong naik sedikit
        if state == Enum.HumanoidStateType.Freefall then
            if vel.Y < CONFIG.softFallMaxSpeed then
                root.AssemblyLinearVelocity = Vector3.new(vel.X, CONFIG.softFallMaxSpeed, vel.Z)
            end
            -- dorongan ringan biar nggak jatuh ke void dari tebing
            if vel.Y < -20 then
                root.AssemblyLinearVelocity = Vector3.new(
                    vel.X,
                    math.max(vel.Y + CONFIG.antiFallBoost * 0.15, CONFIG.softFallMaxSpeed),
                    vel.Z
                )
            end
        end

        -- Anti void: di bawah Y threshold → kembalikan ke last safe
        if pos.Y < CONFIG.voidY and lastSafeCFrame then
            pcall(function()
                root.CFrame = lastSafeCFrame + Vector3.new(0, 3, 0)
                root.AssemblyLinearVelocity = Vector3.zero
                h:ChangeState(Enum.HumanoidStateType.Running)
            end)
        end
    end))
end

local function enableAntiDamage()
    antiDamageOn = true
    local char = localPlayer.Character
    if char then hookAntiDamage(char) end
end

local function disableAntiDamage()
    antiDamageOn = false
    clearAntiConns()
end

localPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.35)
    if antiDamageOn then hookAntiDamage(char) end
    if speedOn then
        -- speed rehook below
    end
end)

-- Heartbeat radar + cleanup
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
            if not data or not data.part or not data.part.Parent then
                if data and data.part then
                    pcall(unregisterTarget, data.part)
                else
                    table.remove(targetList, i)
                end
            end
        end
    end
end)

-- Ultra FPS 80+
local boosterBackup = { effects = {}, savedSettings = {} }
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

    if boosterEvent then boosterEvent:Disconnect() boosterEvent = nil end
    boosterEvent = Workspace.DescendantAdded:Connect(function(obj)
        if not boosterOn or not obj then return end
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
            pcall(function() obj.Enabled = false end)
        elseif obj:IsA("BasePart") or obj:IsA("MeshPart") then
            pcall(function() obj.CastShadow = false end)
        end
    end)

    task.spawn(function()
        local ok, desc = pcall(function() return Workspace:GetDescendants() end)
        if not ok or not desc then return end
        local count = 0
        for _, obj in ipairs(desc) do
            if not boosterOn then break end
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
                or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                pcall(function() obj.Enabled = false end)
            elseif obj:IsA("BasePart") or obj:IsA("MeshPart") then
                pcall(function() obj.CastShadow = false end)
            end
            count += 1
            if count % 350 == 0 then task.wait() end
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

-- Speed 3x
local function targetSpeed()
    return CONFIG.normalSpeed * CONFIG.boostMult
end

local speedConn, speedRenderConn = nil, nil

local function applySpeed(hum)
    if hum and speedOn and hum.WalkSpeed ~= targetSpeed() then
        hum.WalkSpeed = targetSpeed()
    end
end

local function hookSpeed()
    if speedConn then speedConn:Disconnect() speedConn = nil end
    if speedRenderConn then speedRenderConn:Disconnect() speedRenderConn = nil end
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
    if antiDamageOn then
        local char = localPlayer.Character
        if char then hookAntiDamage(char) end
    end
end)

-- ========== GUI ==========
local old = playerGui:FindFirstChild("GecMineAntarctica") or playerGui:FindFirstChild("EngineGUI")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GecMineAntarctica"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 9999
screenGui.Parent = playerGui

local outer = Instance.new("Frame", screenGui)
outer.Size = UDim2.new(0, 430, 0, 400)
outer.Position = UDim2.new(0, 12, 0.5, -185)
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
titleLabel.Text = "❄ Gec Mine Antarctica • V20.5 Pro"
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

-- RADAR PAGE
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
        task.defer(function() pcall(scanRealTime) end)
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
    toggleButtons[name] = { btn = b, get = getState, color = color }
    b.MouseButton1Click:Connect(function()
        setState()
        b.BackgroundColor3 = getState() and color or C.black
        updateFilterStatus()
        if radarOn then
            if next(selectedRarities) == nil then
                clearAllMarkers()
            else
                task.defer(function() pcall(scanRealTime) end)
            end
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

local resetBtn = Instance.new("TextButton", radarPage)
resetBtn.Size = UDim2.new(1, 0, 0, 22)
resetBtn.Position = UDim2.new(0, 0, 0, 78)
resetBtn.Text = "↺ RESET FILTER"
resetBtn.TextColor3 = Color3.new(1, 1, 1)
resetBtn.BackgroundColor3 = C.red
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 9
resetBtn.BorderSizePixel = 0
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 7)

local filterStatus = Instance.new("TextLabel", radarPage)
filterStatus.Size = UDim2.new(1, 0, 0, 30)
filterStatus.Position = UDim2.new(0, 0, 0, 104)
filterStatus.Text = ""
filterStatus.TextColor3 = C.green
filterStatus.TextSize = 9
filterStatus.Font = Enum.Font.GothamBold
filterStatus.TextXAlignment = Enum.TextXAlignment.Left
filterStatus.TextYAlignment = Enum.TextYAlignment.Top
filterStatus.BackgroundTransparency = 1
filterStatus.TextWrapped = true

-- SETTINGS PAGE
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

local function makeSettingCard(parent, y, title, subtitle)
    local card = Instance.new("Frame", parent)
    card.Size = UDim2.new(1, 0, 0, 44)
    card.Position = UDim2.new(0, 0, 0, y)
    card.BackgroundColor3 = C.black
    card.BackgroundTransparency = 0.2
    card.BorderSizePixel = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 7)

    local info = Instance.new("TextLabel", card)
    info.Size = UDim2.new(1, -70, 1, 0)
    info.Position = UDim2.new(0, 8, 0, 0)
    info.Text = title .. "\n" .. subtitle
    info.TextColor3 = C.textMain
    info.TextSize = 8
    info.Font = Enum.Font.GothamBold
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Center
    info.BackgroundTransparency = 1

    local btn = Instance.new("TextButton", card)
    btn.Size = UDim2.new(0, 52, 0, 24)
    btn.Position = UDim2.new(1, -60, 0.5, -12)
    btn.Text = "OFF"
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 7
    btn.Font = Enum.Font.GothamBold
    btn.BackgroundColor3 = C.red
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    return btn
end

local boosterToggleBtn = makeSettingCard(settingsPage, 20, "⚡ ULTRA FPS 80+", "Graphics Optimized • Cooler")
boosterToggleBtn.Text = "BOOST OFF"
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

local weightToggleBtn = makeSettingCard(settingsPage, 70, "🪶 BERAT RINGAN 100%", "CrystalWeight → 0.1")
weightToggleBtn.Text = "LIGHT OFF"
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

local antiToggleBtn = makeSettingCard(settingsPage, 120, "🛡 ANTI DAMAGE + ANTI JATUH", "Tebing/void aman • No lag")
antiToggleBtn.Text = "ANTI OFF"
antiToggleBtn.MouseButton1Click:Connect(function()
    if antiDamageOn then
        disableAntiDamage()
        antiToggleBtn.Text = "ANTI OFF"
        antiToggleBtn.BackgroundColor3 = C.red
    else
        enableAntiDamage()
        antiToggleBtn.Text = "ANTI ON"
        antiToggleBtn.BackgroundColor3 = C.green
    end
end)

local pInfo = Instance.new("TextLabel", settingsPage)
pInfo.Position = UDim2.new(0, 0, 0, 172)
pInfo.Size = UDim2.new(1, 0, 0, 55)
pInfo.Text = "V20.5 Pro\nRadar ringan+presisi • Speed 3x • Instant Pickup\nUltra FPS • Anti Damage/Jatuh • Berat Ringan"
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
    clearAllMarkers()
    refreshToggles()
    updateFilterStatus()
    if radarOn then task.defer(function() pcall(scanRealTime) end) end
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
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    frame.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(outer)
makeDraggable(miniBubble)

updateFilterStatus()
refreshToggles()
refreshRadarToggle()

print("❄ GEC MINE ANTARCTICA V20.5 PRO LOADED ✔ | Radar ringan • Speed 3x • Anti Damage/Jatuh")

