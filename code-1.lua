-- Key check: pasang di paling atas
local EXPECTED_KEY = "Jack"

local providedKey
if type(getgenv) == "function" then providedKey = getgenv().key end
if providedKey == nil and type(_G) == "table" then providedKey = _G.key end

if providedKey ~= EXPECTED_KEY then return end


-- =================================================================
-- ENGINE V16 - COMPACT WORLD RADAR + SETTINGS EDITION
--
-- V12.0 MODERN (upgrade dari V11 — no lag on radar ON):
-- ✅ MARKER ONLY: Highlight warna-warni (tanpa nama/kg/price)
-- ✅ Multi-select rarity + nexus + category
-- ✅ Rarity OFF → marker ilang; rarity ON → marker muncul lagi
-- ✅ HARD radius 200m • sticky drop ~210m
-- ✅ maxMarkers 40
-- ✅ V12: radar ON TIDAK rebuild cache penuh (0 lag spike)
-- ✅ V12: initial cache ASYNC chunked (tidak freeze frame)
-- ✅ V12: soft-start scan (marker bertahap, tidak semua sekaligus)
-- ✅ V12: filter-first + distance² + cache color permanen
-- ✅ HAPUS size/kg/price filter + BillboardGui
-- =================================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- ================================================================
-- CONFIG
-- ================================================================

local CONFIG = {
    normalSpeed   = 16,
    boostMult     = 3,

    -- interval stabil untuk 40 marker only (tanpa label = lebih ringan)
    radarInterval = 0.25,

    -- maksimum marker warna-warni (35+ aman)
    maxMarkers    = 40,

    -- HARD RADAR RANGE 200m — marker baru ilang kalau lewat radius ini
    scanRadius    = 200,

    -- precompute radius²
    scanRadiusSq  = 200 * 200,

    -- hysteresis: marker yang sudah aktif baru dihapus di radius ini
    -- (sedikit lebih longgar dari scanRadius supaya tidak flicker di boundary)
    dropRadius    = 210,
    dropRadiusSq  = 210 * 210,

    -- fallback scan interval
    fallbackScanInterval = 22,

    -- chunk size: yield hanya jika list sangat panjang
    scanChunkSize = 64,

    -- object target
    nexusNames = {
        ["Void Nexus"] = true,
        ["Solar Nexus"] = true,
        ["Aether Nexus"] = true,
    },

}

-- ================================================================
-- FILTER DATA
-- ================================================================

-- Rarity filter mengikuti UI referensi: setiap rarity dipilih satu per satu.
-- Label UI dapat berbahasa Indonesia, sedangkan atribut game dapat berbahasa Inggris.
local RARITIES = {
    "Exotic",
    "Legendary",
    "Rare",
    "Uncommon",
    "Common",
    "Epic",
    "Mythic",
}

-- Semua label filter memakai satu kamus bahasa Indonesia.
-- Radar tetap menerima alias Inggris dari atribut game.
local RARITY_UI_LABELS = {
    Exotic = "Eksotis",
    Legendary = "Legendaris",
    Rare = "Langka",
    Uncommon = "Tidak Biasa",
    Common = "Biasa",
    Epic = "Epik",
    Mythic = "Mistik",
}

local RARITY_ALIASES = {
    exotic = "Exotic",
    eksotis = "Exotic",
    legendary = "Legendary",
    legendaris = "Legendary",
    rare = "Rare",
    langka = "Rare",
    uncommon = "Uncommon",
    ["tidak biasa"] = "Uncommon",
    common = "Common",
    biasa = "Common",
    epic = "Epic",
    epik = "Epic",
    mythic = "Mythic",
    mistik = "Mythic",
}

local CATEGORIES = {
    "Empiris",
    "Pulsar",
    "Quasar",
}

local NEXUS = {
    "Void Nexus",
    "Solar Nexus",
    "Aether Nexus",
}

local MYTHIC = "Mythic"

local SIZES = {
    "Tiny",
    "Small",
    "Medium",
    "Large",
    "Huge",
}

-- ================================================================
-- COLORS
-- ================================================================

local RARITY_COLORS = {
    Exotic = Color3.fromRGB(255,220,0),
    Common = Color3.fromRGB(180,180,180),
    Uncommon = Color3.fromRGB(90,200,90),
    Rare = Color3.fromRGB(70,140,255),
    Epic = Color3.fromRGB(170,80,255),
    Legendary = Color3.fromRGB(255,170,40),
    Mythic = Color3.fromRGB(255,60,130),
    Empiris = Color3.fromRGB(0,255,200),
    Pulsar = Color3.fromRGB(255,220,0),
    Quasar = Color3.fromRGB(255,80,80),
    ["Void Nexus"] = Color3.fromRGB(170,80,255),
    ["Solar Nexus"] = Color3.fromRGB(255,170,40),
    ["Aether Nexus"] = Color3.fromRGB(0,220,255),
}

local C = {
    bg = Color3.fromRGB(8,8,10),
    black = Color3.fromRGB(14,14,16),
    accent = Color3.fromRGB(88,101,242),
    green = Color3.fromRGB(87,242,135),
    orange = Color3.fromRGB(254,160,60),
    purple = Color3.fromRGB(180,80,220),
    red = Color3.fromRGB(237,66,69),
    teal = Color3.fromRGB(40,190,180),
    textMain = Color3.fromRGB(235,238,245),
    textSub = Color3.fromRGB(130,136,148),
}

-- ================================================================
-- STATE
-- ================================================================

local speedOn = false
local radarOn = false

-- UI Page State
local currentPage = "radar"  -- "radar" or "settings"

local selectedRarities = {}

local selectedCategories = {}
local selectedNexus = {}

local markers = {}

-- Object cache
local worldTargets = {}
local targetTimestamps = {}
local targetInfo = {}

-- V5.0: list target yang sudah lolos rarity (rebuild hanya saat filter berubah)
-- Scan loop HANYA iterasi list ini → tidak scan item di luar filter.
local filteredTargets = {}
local filteredDirty = true

-- Connections
local worldConnections = {}

-- Debounce
local pendingAdds = {}
local addProcessTimer = nil
local lastFallbackScan = 0
local fallbackScanBusy = false
local scanRunning = false

-- ================================================================
-- SPEED 3X
-- ================================================================

local function targetSpeed()
    return CONFIG.normalSpeed * CONFIG.boostMult
end

local currentConn = nil
local lastSpeedEnforce = 0

local function hookHumanoid()

    if currentConn then
        currentConn:Disconnect()
        currentConn = nil
    end

    local character = localPlayer.Character

    if not character then
        return
    end

    local hum = character:FindFirstChildOfClass("Humanoid")

    if not hum then
        return
    end

    currentConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if speedOn and hum.WalkSpeed ~= targetSpeed() then
            hum.WalkSpeed = targetSpeed()
        end
    end)

    hum.WalkSpeed = targetSpeed()
end

RunService.Heartbeat:Connect(function()
    if not speedOn then
        return
    end

    local now = tick()
    if (now - lastSpeedEnforce) < 0.15 then
        return
    end
    lastSpeedEnforce = now

    local character = localPlayer.Character

    if not character then
        return
    end

    local hum = character:FindFirstChildOfClass("Humanoid")

    if hum and hum.WalkSpeed ~= targetSpeed() then
        hum.WalkSpeed = targetSpeed()
    end
end)

localPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if speedOn then
        hookHumanoid()
    end
end)

-- ================================================================
-- UTILITY
-- ================================================================

local function isLocalCharacterObject(obj)
    local character = localPlayer.Character
    if not character then
        return false
    end
    return obj:IsDescendantOf(character)
end

local function isBackpackObject(obj)
    local backpack = localPlayer:FindFirstChild("Backpack")
    if not backpack then
        return false
    end
    return obj:IsDescendantOf(backpack)
end

local function isPlayerCharacterObject(obj)
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character and obj:IsDescendantOf(character) then
            return true
        end
    end
    return false
end

local function isForbiddenWorldObject(obj)
    if not obj then
        return true
    end
    if isLocalCharacterObject(obj) then
        return true
    end
    if isBackpackObject(obj) then
        return true
    end
    if isPlayerCharacterObject(obj) then
        return true
    end
    return false
end

-- ================================================================
-- NAME RESOLUTION
-- ================================================================

local function readStringAttribute(obj, key)
    local ok, value = pcall(function()
        return obj:GetAttribute(key)
    end)

    if not ok then
        return nil
    end

    if type(value) == "string" and value ~= "" then
        return value
    end

    return nil
end

local function getObjectName(obj)
    if not obj then
        return ""
    end

    local keys = {
        "ItemName", "CrystalName", "NexusName", 
        "DisplayName", "ObjectName",
    }

    for _, key in ipairs(keys) do
        local value = readStringAttribute(obj, key)
        if value then
            return value
        end
    end

    return obj.Name
end

local function isMeshNoiseName(name)
    local normalized = tostring(name or ""):lower():gsub("[%s_%-]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    return normalized == "mesh"
        or normalized:match("^mesh[%.%s_%-]*%d*$") ~= nil
        or normalized == "handle"
        or normalized == "basepart"
        or normalized == "part"
end

local function getCleanCrystalName(obj, fallbackPart)
    local current = obj or fallbackPart
    local depth = 0
    while current and current ~= workspace and depth < 8 do
        for _, key in ipairs({"ItemName", "CrystalName", "DisplayName", "ObjectName"}) do
            local value = readStringAttribute(current, key)
            if value and not isMeshNoiseName(value) then
                return value
            end
        end
        if not isMeshNoiseName(current.Name) then
            return current.Name
        end
        current = current.Parent
        depth += 1
    end
    return "Crystal"
end

local function readAttribute(obj, key)
    if not obj then
        return nil
    end
    local ok, value = pcall(function()
        return obj:GetAttribute(key)
    end)
    return ok and value or nil
end

local function parseNumber(value)
    if type(value) == "number" then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end
    local cleaned = value:gsub(",", ""):gsub("%$", "")
    return tonumber(cleaned:match("[-+]?%d*%.?%d+"))
end

local function readNumericFromObject(obj, keys)
    for _, key in ipairs(keys) do
        local value = parseNumber(readAttribute(obj, key))
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function findNumericValue(part, keys)
    local current = part
    local depth = 0
    while current and current ~= workspace and depth < 8 do
        local value = readNumericFromObject(current, keys)
        if value ~= nil then
            return value
        end
        current = current.Parent
        depth += 1
    end
    return nil
end

local function extractMetricFromText(text, kind)
    text = tostring(text or ""):gsub(",", "")
    if kind == "weight" then
        return parseNumber(text:match("([%d%.]+)%s*[kK][gG]"))
    end
    return parseNumber(text:match("%$%s*([%d%.]+)"))
end

local function getDisplayMetric(part, kind)
    local current = part
    local depth = 0
    while current and current ~= workspace and depth < 8 do
        local value = extractMetricFromText(getObjectName(current), kind)
        if value ~= nil then
            return value
        end
        current = current.Parent
        depth += 1
    end
    return nil
end

local function getCrystalWeightKg(part)
    return findNumericValue(part, {
        "WeightKg", "Weight", "MassKg", "Mass", "CrystalWeight", "Kilograms",
    }) or getDisplayMetric(part, "weight")
end

local function getCrystalPrice(part)
    return findNumericValue(part, {
        "Price", "SellPrice", "CrystalPrice", "Value", "Worth", "CashValue",
    }) or getDisplayMetric(part, "price")
end

local normalizeName

local function isCrystalCluster(obj)
    if not obj or isForbiddenWorldObject(obj) then
        return false
    end
    local text = normalizeName(getObjectName(obj))
    return text:find("crystal", 1, true) ~= nil
        and text:find("cluster", 1, true) ~= nil
end

-- ================================================================
-- NEXUS DETECTION
-- ================================================================

function normalizeName(name)
    if type(name) ~= "string" then
        return ""
    end
    return name
        :lower()
        :gsub("[%s_%-]+", " ")
        :gsub("%s+", " ")
        :match("^%s*(.-)%s*$")
end

-- Metadata tetap dibaca internal dari object/parent, tetapi tidak pernah ditampilkan.
local function getCrystalSearchText(obj)
    local values = {}
    local current = obj
    local depth = 0
    while current and current ~= workspace and depth < 8 do
        table.insert(values, tostring(current.Name or ""))
        table.insert(values, getObjectName(current))
        for _, key in ipairs({
            "ItemName", "CrystalName", "DisplayName", "ObjectName",
            "CrystalType", "Type", "Category", "TierName", "Rarity",
        }) do
            local value = readAttribute(current, key)
            if value ~= nil then
                table.insert(values, tostring(value))
            end
        end
        current = current.Parent
        depth += 1
    end
    return normalizeName(table.concat(values, " "))
end

local function isCrystalTarget(obj)
    if not obj or isForbiddenWorldObject(obj) then
        return false
    end
    local text = getCrystalSearchText(obj)
    local namedCrystal = text:find("crystal", 1, true) ~= nil
        and (text:find("cluster", 1, true) ~= nil
            or text:find("obsidian", 1, true) ~= nil
            or text:find("ember", 1, true) ~= nil)
    local hasMetric = getCrystalWeightKg(obj) ~= nil or getCrystalPrice(obj) ~= nil
    return namedCrystal or hasMetric
end

local function resolveNexusName(obj)
    if not obj then
        return nil
    end

    local name = getObjectName(obj)
    local normalized = normalizeName(name)

    if normalized == "void nexus" then
        return "Void Nexus"
    elseif normalized == "solar nexus" then
        return "Solar Nexus"
    elseif normalized == "aether nexus" then
        return "Aether Nexus"
    end

    -- Telusuri seluruh ancestor agar target jauh/nested langsung dikenali.
    local ancestor = obj.Parent
    while ancestor and ancestor ~= workspace do
        local parentName = getObjectName(ancestor)
        local parentNormalized = normalizeName(parentName)

        if parentNormalized == "void nexus" then
            return "Void Nexus"
        elseif parentNormalized == "solar nexus" then
            return "Solar Nexus"
        elseif parentNormalized == "aether nexus" then
            return "Aether Nexus"
        end

        ancestor = ancestor.Parent
    end

    return nil
end

local function isWorldNexus(obj)
    if not obj then
        return false
    end
    if isForbiddenWorldObject(obj) then
        return false
    end
    return resolveNexusName(obj) ~= nil
end

-- ================================================================
-- GET WORLD PART
-- ================================================================

local function getWorldPart(obj)
    if not obj then
        return nil
    end

    if obj:IsA("BasePart") then
        return obj
    end

    if obj:IsA("Model") then
        local primary = obj.PrimaryPart
        if primary and primary:IsA("BasePart") then
            return primary
        end

        local part = obj:FindFirstChildWhichIsA("BasePart", true)
        if part then
            return part
        end
    end

    if obj:IsA("Folder") then
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

-- ================================================================
-- CRYSTAL CATEGORY
-- ================================================================

local function getCrystalCategory(part)
    if not part then
        return nil
    end

    for _, key in ipairs({
        "CrystalName", "CrystalType", "Type", "Kind", "Category",
    }) do
        local value = readStringAttribute(part, key)
        if value then
            for _, category in ipairs(CATEGORIES) do
                if normalizeName(value) == normalizeName(category) then
                    return category
                end
            end
        end
    end

    local tierName = tostring(part:GetAttribute("TierName") or "")
    local lower = tierName:lower()

    for _, category in ipairs(CATEGORIES) do
        if lower:find(category:lower(), 1, true) then
            return category
        end
    end

    return nil
end

-- ================================================================
-- CRYSTAL SIZE
-- ================================================================

local function getCrystalSize(part)
    if not part then
        return nil
    end

    for _, key in ipairs({
        "Size", "CrystalSize", "SizeCategory",
    }) do
        local value = readStringAttribute(part, key)
        if value then
            for _, size in ipairs(SIZES) do
                if normalizeName(value) == normalizeName(size) then
                    return size
                end
            end
        end
    end

    local tierName = tostring(part:GetAttribute("TierName") or "")
    local objectText = normalizeName(getObjectName(part) .. " " .. tierName)

    local current = part
    local depth = 0
    while current and current ~= workspace and depth < 8 do
        objectText = objectText .. " " .. normalizeName(getObjectName(current))
        current = current.Parent
        depth += 1
    end

    for _, size in ipairs(SIZES) do
        if objectText:find(size:lower(), 1, true) then
            return size
        end
    end

    return nil
end

-- ================================================================
-- RARITY
-- ================================================================

local RARITY_ALIAS_ORDER = {
    "tidak biasa", "legendaris", "uncommon", "legendary", "eksotis",
    "exotic", "mythic", "mistik", "langka", "biasa", "common", "epik",
    "rare", "epic",
}

local function getRarityName(part)
    if not part then
        return nil
    end

    local current = part
    local depth = 0
    while current and current ~= workspace and depth < 8 do
        local values = {
            current:GetAttribute("Rarity"),
            current:GetAttribute("TierName"),
            current:GetAttribute("Tier"),
            current:GetAttribute("RarityName"),
            getObjectName(current),
        }

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

-- ================================================================
-- STATIC METADATA CACHE (ringan tanpa pengaruh ke frame) - V2.0.0
-- ================================================================
-- Rarity/category/size/kg/price sebuah crystal praktis tidak pernah
-- berubah selama part itu ada. Sebelumnya nilai ini dihitung ULANG
-- setiap scan tick (5x/detik) untuk SETIAP target dalam radius --
-- itu penyebab utama lag.
--
-- V2.0.0: sekarang LAZY. Rarity (whitelist, selalu dipakai) dihitung
-- sekali pas target register. category/size/kg/price -- yang defaultnya
-- KOSONG dan sering emang gak pernah dipakai user -- baru dihitung
-- kalau filter itu betulan aktif, dan hasilnya di-cache permanen supaya
-- gak dihitung dua kali. Kalau user cuma pakai filter rarity (default),
-- 4 metadata itu gak pernah disentuh sama sekali = 0 biaya frame.

local function getCachedCategory(part, info)
    if not info.categoryComputed then
        info.category = getCrystalCategory(part)
        info.categoryComputed = true
    end
    return info.category
end

local function getCachedSize(part, info)
    if not info.sizeComputed then
        info.size = getCrystalSize(part)
        info.sizeComputed = true
    end
    return info.size
end

local function getCachedWeight(part, info)
    if not info.weightComputed then
        info.weight = getCrystalWeightKg(part)
        info.weightComputed = true
    end
    return info.weight
end

local function getCachedPrice(part, info)
    if not info.priceComputed then
        info.price = getCrystalPrice(part)
        info.priceComputed = true
    end
    return info.price
end

-- V9: nama di-cache permanen (dipakai label ringan)
local function getCachedName(obj, part, info)
    if not info.nameComputed then
        info.name = getCleanCrystalName(obj, part)
        info.nameComputed = true
    end
    return info.name
end

-- ================================================================
-- FILTER
-- ================================================================

local function passesFilter(part, info)
    if not part or not info then
        return false
    end

    -- Rarity whitelist: wajib dicentang
    if next(selectedRarities) == nil then
        return false
    end

    local rarity = info.rarity
    if not rarity or not selectedRarities[rarity] then
        return false
    end

    -- Category opsional (lazy cache)
    if next(selectedCategories) then
        local category = getCachedCategory(part, info)
        if not category or not selectedCategories[category] then
            return false
        end
    end

    return true
end

-- V5.0: rebuild list target yang lolos rarity (whitelist).
-- Dipanggil HANYA saat filter rarity/nexus berubah atau target baru masuk.
-- Scan loop tidak lagi iterasi seluruh worldTargets.
local function rebuildFilteredTargets()
    table.clear(filteredTargets)
    if next(selectedRarities) == nil then
        filteredDirty = false
        return
    end

    local hasNexusFilter = next(selectedNexus) ~= nil

    for obj in pairs(worldTargets) do
        if obj and obj.Parent then
            local info = targetInfo[obj]
            if info and info.rarity and selectedRarities[info.rarity] then
                -- Sama logika original: nexus filter kosong = semua; kalau ada, harus match nexus
                if not hasNexusFilter or (info.nexus and selectedNexus[info.nexus]) then
                    filteredTargets[#filteredTargets + 1] = obj
                end
            end
        end
    end
    filteredDirty = false
end

local function markFilteredDirty()
    filteredDirty = true
end

-- ================================================================
-- MARKER COLOR
-- ================================================================

local CRYSTAL_COLORS = {
    obsidian = Color3.fromRGB(155, 100, 220),
    ember = Color3.fromRGB(255, 85, 35),
    crystal = Color3.fromRGB(80, 210, 255),
}

local function markerColor(part, nexusName, rarityHint)
    if nexusName and RARITY_COLORS[nexusName] then
        return RARITY_COLORS[nexusName]
    end

    local r = tonumber(part:GetAttribute("TierColorR"))
    local g = tonumber(part:GetAttribute("TierColorG"))
    local b = tonumber(part:GetAttribute("TierColorB"))
    if r and g and b then
        return Color3.fromRGB(r, g, b)
    end

    local rarity = rarityHint or getRarityName(part)
    if rarity and RARITY_COLORS[rarity] then
        return RARITY_COLORS[rarity]
    end

    local current = part
    local depth = 0
    while current and current ~= workspace and depth < 8 do
        local text = normalizeName(getObjectName(current))
        for key, color in pairs(CRYSTAL_COLORS) do
            if text:find(key, 1, true) then
                return color
            end
        end
        current = current.Parent
        depth += 1
    end

    return Color3.fromRGB(200, 210, 230)
end

local function getCachedColor(part, info)
    if not info.colorComputed then
        info.color = markerColor(part, info.nexus, info.rarity)
        info.colorComputed = true
    end
    return info.color
end

-- ================================================================
-- MARKER CLEANUP
-- ================================================================

local function destroyMarker(part)
    local pack = markers[part]
    if pack then
        if typeof(pack) == "Instance" then
            pcall(function() pack:Destroy() end)
        else
            if pack.hl then pcall(function() pack.hl:Destroy() end) end
            if pack.bb then pcall(function() pack.bb:Destroy() end) end
        end
        markers[part] = nil
    end
end

local function clearAllMarkers()
    for part in pairs(markers) do
        destroyMarker(part)
    end
end

-- V12: marker ONLY — Highlight warna-warni, tanpa nama/kg
local function createMarkerPack(part, obj, info, color)
    local hl = Instance.new("Highlight")
    hl.Name = "EngineHL"
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = color
    hl.OutlineColor = color
    hl.Adornee = part
    hl.Parent = part

    -- simpan rarity agar sticky pass bisa drop saat filter di-OFF
    return { hl = hl, rarity = info and info.rarity or nil }
end

-- ================================================================
-- TARGET CACHE
-- ================================================================

-- Dipanggil hanya SEKALI per target baru (bukan per scan tick).
-- V2.0.0: cuma rarity yang dihitung di sini (selalu wajib dipakai
-- sebagai whitelist). category/size/kg/price TIDAK dihitung kalau
-- filternya kosong -- lihat getCachedCategory/Size/Weight/Price di atas.
-- "part" juga di-cache di sini supaya scan() gak perlu getWorldPart()
-- (tree-search) ulang tiap 0.2 detik.
local function buildTargetInfo(obj, nexus, crystal)
    local part = getWorldPart(obj)
    return {
        nexus = nexus,
        crystal = crystal,
        part = part,
        rarity = getRarityName(part),
        category = nil, categoryComputed = false,
        size = nil, sizeComputed = false,
        weight = nil, weightComputed = false,
        price = nil, priceComputed = false,
        name = nil, nameComputed = false,
        color = nil, colorComputed = false,
    }
end

local function registerTarget(obj)
    if not obj or isForbiddenWorldObject(obj) then
        return
    end

    -- Register setiap part/model/folder di bawah Nexus agar beberapa
    -- Crystal masuk radar bersamaan, bukan hanya part utama container.
    if obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder") then
        local nexus = resolveNexusName(obj)
        local crystal = isCrystalTarget(obj)
        if nexus or crystal then
            worldTargets[obj] = true
            targetTimestamps[obj] = tick()
            targetInfo[obj] = buildTargetInfo(obj, nexus, crystal)
            markFilteredDirty()
        end
    end
end

local function unregisterTarget(obj)
    if not obj then
        return
    end

    if worldTargets[obj] then
        markFilteredDirty()
    end

    worldTargets[obj] = nil
    targetTimestamps[obj] = nil
    targetInfo[obj] = nil

    local part = getWorldPart(obj)
    if part then
        destroyMarker(part)
    end

    destroyMarker(obj)
end

-- ================================================================
-- INITIAL WORLD CACHE (V12 — async chunked, tidak freeze frame)
-- ================================================================

local cacheBuilding = false

local function buildInitialCacheAsync()
    if cacheBuilding then
        return
    end
    cacheBuilding = true

    task.spawn(function()
        local descendants = workspace:GetDescendants()
        local now = tick()
        for index, obj in ipairs(descendants) do
            if obj and obj.Parent and (obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder")) then
                if not worldTargets[obj] and not isForbiddenWorldObject(obj) then
                    local nexus = resolveNexusName(obj)
                    local crystal = isCrystalTarget(obj)
                    if nexus or crystal then
                        worldTargets[obj] = true
                        targetTimestamps[obj] = now
                        targetInfo[obj] = buildTargetInfo(obj, nexus, crystal)
                    end
                end
            end
            -- yield tiap 80 object → 0 freeze saat load
            if index % 80 == 0 then
                task.wait()
            end
        end
        markFilteredDirty()
        cacheBuilding = false
    end)
end

-- Soft warm-up di background (bukan blocking)
buildInitialCacheAsync()

-- ================================================================
-- DYNAMIC WORLD EVENTS
-- ================================================================

local function processPendingAdds()
    for obj in pairs(pendingAdds) do
        if obj and obj.Parent then
            registerTarget(obj)
            local parent = obj.Parent
            if parent then
                registerTarget(parent)
            end
        end
    end

    table.clear(pendingAdds)
    addProcessTimer = nil
end

table.insert(
    worldConnections,
    workspace.DescendantAdded:Connect(function(obj)
        registerTarget(obj)
        pendingAdds[obj] = true

        if not addProcessTimer then
            addProcessTimer = task.delay(0.1, processPendingAdds)
        end
    end)
)

table.insert(
    worldConnections,
    workspace.DescendantRemoving:Connect(function(obj)
        unregisterTarget(obj)
        pendingAdds[obj] = nil
    end)
)

-- ================================================================
-- RADAR SCAN (V10 — sticky 200m, filter-first, distance², smooth 40 marker)
-- ================================================================

local function scan()
    if not radarOn then
        return
    end

    -- Tanpa rarity dicentang → tidak scan apa pun
    if next(selectedRarities) == nil then
        clearAllMarkers()
        return
    end

    local character = localPlayer.Character

    if not character then
        clearAllMarkers()
        return
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")

    if not hrp then
        clearAllMarkers()
        return
    end

    local origin = hrp.Position
    local ox, oy, oz = origin.X, origin.Y, origin.Z
    local radiusSq = CONFIG.scanRadiusSq
    local dropSq = CONFIG.dropRadiusSq
    local found = {}
    local seen = {}
    -- part yang masih dalam radius (untuk sticky keep)
    local inRangeParts = {}

    -- Rebuild filtered list hanya bila dirty
    if filteredDirty then
        rebuildFilteredTargets()
    end

    local list = filteredTargets
    local n = #list
    local chunk = CONFIG.scanChunkSize
    local needRebuild = false

    for i = 1, n do
        local obj = list[i]
        if not obj or not obj.Parent then
            needRebuild = true
        else
            local info = targetInfo[obj]
            if info then
                local part = info.part
                if not part or not part.Parent then
                    part = getWorldPart(obj)
                    info.part = part
                end

                if part and part.Parent and not seen[part] then
                    seen[part] = true

                    local p = part.Position
                    local dx = p.X - ox
                    local dy = p.Y - oy
                    local dz = p.Z - oz
                    local distSq = dx * dx + dy * dy + dz * dz

                    -- STICKY: catat semua part dalam drop radius (bukan hanya top-N)
                    if distSq <= dropSq then
                        inRangeParts[part] = true
                    end

                    if distSq <= radiusSq then
                        if passesFilter(part, info) then
                            found[#found + 1] = {
                                object = obj,
                                part = part,
                                distance = math.sqrt(distSq),
                                nexus = info.nexus,
                                distSq = distSq,
                            }
                        end
                    end
                end
            end
        end

        -- yield hanya jika list panjang (hindari stuck, tapi jangan spam yield)
        if n > chunk and i % chunk == 0 and i < n then
            task.wait()
            if not radarOn then
                return
            end
            if hrp.Parent then
                origin = hrp.Position
                ox, oy, oz = origin.X, origin.Y, origin.Z
            end
        end
    end

    if needRebuild then
        markFilteredDirty()
    end

    -- FALLBACK SCAN jarang
    local currentTime = tick()

    if (currentTime - lastFallbackScan) >= CONFIG.fallbackScanInterval
    and not fallbackScanBusy then
        lastFallbackScan = currentTime
        fallbackScanBusy = true

        task.spawn(function()
            local descendants = workspace:GetDescendants()
            local added = false
            for index, obj in ipairs(descendants) do
                if not radarOn then
                    break
                end

                if obj and obj.Parent and not isForbiddenWorldObject(obj) then
                    if worldTargets[obj] then
                        targetTimestamps[obj] = currentTime
                    else
                        if obj:IsA("BasePart") or obj:IsA("Model") or obj:IsA("Folder") then
                            local nexus = resolveNexusName(obj)
                            local crystal = isCrystalTarget(obj)
                            if nexus or crystal then
                                worldTargets[obj] = true
                                targetTimestamps[obj] = currentTime
                                targetInfo[obj] = buildTargetInfo(obj, nexus, crystal)
                                added = true
                            end
                        end
                    end
                end

                if index % 150 == 0 then
                    task.wait()
                end
            end
            if added then
                markFilteredDirty()
            end
            fallbackScanBusy = false
        end)
    end

    -- SORT TERDEKAT (untuk prioritas NEW marker)
    table.sort(found, function(a, b)
        return a.distance < b.distance
    end)

    -- ============================================================
    -- STICKY MARKERS (V10):
    -- 1) Marker yang SUDAH ada: tetap hidup selama part valid + jarak ≤ dropRadius (210m)
    --    → tidak hilang hanya karena keluar top-N / ranking berubah
    -- 2) Marker BARU: dibuat sampai maxMarkers untuk crystal dalam 200m
    -- 3) Hapus HANYA jika: part hilang, gagal filter, atau jarak > 200/210m
    -- ============================================================
    local keep = {}
    local activeCount = 0

    -- Pass 1: sticky — tetap hidup jika dalam radius DAN rarity masih dicentang
    for part, pack in pairs(markers) do
        local ok = false
        if part and part.Parent and pack and pack.hl and pack.hl.Parent then
            local rarityOk = pack.rarity and selectedRarities[pack.rarity]
            if rarityOk then
                local p = part.Position
                local dx = p.X - ox
                local dy = p.Y - oy
                local dz = p.Z - oz
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq <= dropSq then
                    ok = true
                    keep[part] = true
                    activeCount += 1
                end
            end
        end
        if not ok then
            destroyMarker(part)
        end
    end

    -- Pass 2: soft-start — max 10 marker BARU per tick (hindari lag spike ON)
    local amount = #found
    local newBudget = 10
    local created = 0

    for i = 1, amount do
        if activeCount >= CONFIG.maxMarkers then
            break
        end
        if created >= newBudget then
            break
        end

        local data = found[i]
        local part = data.part
        local obj = data.object

        if part and part.Parent and not keep[part] then
            local pack = markers[part]
            local alive = pack and pack.hl and pack.hl.Parent

            if not alive then
                local info = targetInfo[obj]
                if not info then
                    info = buildTargetInfo(obj, data.nexus, true)
                    targetInfo[obj] = info
                end
                if passesFilter(part, info) then
                    local color = getCachedColor(part, info)
                    pack = createMarkerPack(part, obj, info, color)
                    markers[part] = pack
                    keep[part] = true
                    activeCount += 1
                    created += 1
                end
            else
                keep[part] = true
            end
        end
    end
end

-- ================================================================
-- RADAR LOOP
-- ================================================================

task.spawn(function()
    while true do
        if radarOn and not scanRunning then
            scanRunning = true
            local ok, err = pcall(scan)
            scanRunning = false
            if not ok then
                warn("ENGINE radar scan error:", err)
            end
        end
        task.wait(CONFIG.radarInterval)
    end
end)

-- ================================================================
-- GUI
-- ================================================================

local old = playerGui:FindFirstChild("EngineGUI")
if old then
    old:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EngineGUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 9999
screenGui.Parent = playerGui

-- ================================================================
-- OUTER MAIN
-- ================================================================

local outer = Instance.new("Frame", screenGui)
outer.Size = UDim2.new(0, 430, 0, 350)
outer.Position = UDim2.new(0, 12, 0.5, -160)
outer.BackgroundColor3 = C.bg
outer.BorderSizePixel = 0
outer.Active = true

Instance.new("UICorner", outer).CornerRadius = UDim.new(0, 16)

local oStroke = Instance.new("UIStroke", outer)
oStroke.Color = Color3.fromRGB(45, 45, 52)
oStroke.Thickness = 1

-- ================================================================
-- TITLE BAR
-- ================================================================

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
titleLabel.Text = "⚡ Engine V16 PRO • V12"
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

-- ================================================================
-- LEFT ICONS (MAIN CONTROLS)
-- ================================================================

local leftCol = Instance.new("Frame", outer)
leftCol.Size = UDim2.new(0, 48, 1, -38)
leftCol.Position = UDim2.new(0, 6, 0, 34)
leftCol.BackgroundTransparency = 1

local CYAN = Color3.fromRGB(0, 200, 255)
local PINK = Color3.fromRGB(255, 100, 160)
local LIME = Color3.fromRGB(100, 255, 100)

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

local speedBtn, setSpeedVis = makeIconButton(0, "⚡", C.accent, CYAN)
local radarBtn, setRadarVis = makeIconButton(46, "◎", C.orange, PINK)
local settingsBtn, setSettingsVis = makeIconButton(92, "⚙", C.green, LIME)

-- ================================================================
-- DIVIDER
-- ================================================================

local divider = Instance.new("Frame", outer)
divider.Size = UDim2.new(0, 1, 1, -46)
divider.Position = UDim2.new(0, 60, 0, 40)
divider.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
divider.BorderSizePixel = 0

-- ================================================================
-- RIGHT CONTENT AREA
-- ================================================================

local rightCol = Instance.new("Frame", outer)
rightCol.Size = UDim2.new(1, -74, 1, -46)
rightCol.Position = UDim2.new(0, 66, 0, 34)
rightCol.BackgroundTransparency = 1

-- ================================================================
-- PAGE RADAR
-- ================================================================

local radarPage = Instance.new("Frame", rightCol)
radarPage.Name = "RadarPage"
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
        -- V12: TIDAK rebuild cache penuh (itu penyebab lag lama)
        -- pakai cache yang sudah ada + DescendantAdded events
        radarStatus.Text = "WORLD • 200M • MARKER • SCANNING"
        markFilteredDirty()
        -- soft-start: scan ringan di frame berikutnya
        task.defer(function()
            if radarOn then
                scan()
            end
        end)
        -- background warm-up bila cache masih kosong
        if next(worldTargets) == nil then
            buildInitialCacheAsync()
        end
    else
        radarStatus.Text = "WORLD • 200M • MARKER ONLY"
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
catScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
catScroll.ScrollBarThickness = 2

local catGrid = Instance.new("UIGridLayout", catScroll)
catGrid.CellSize = UDim2.new(0, 54, 0, 13)
catGrid.CellPadding = UDim2.new(0, 3, 0, 3)

local toggleButtons = {}

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

    toggleButtons[name] = {
        btn = b,
        get = getState,
        color = color,
    }

    b.MouseButton1Click:Connect(function()
        setState()
        b.BackgroundColor3 = getState() and color or C.black
        updateFilterStatus()

        if radarOn then
            -- rarity semua OFF → marker langsung ilang
            if next(selectedRarities) == nil then
                clearAllMarkers()
            else
                task.defer(scan)
            end
        end
    end)
end

-- Rarity multi-select: OFF = marker ilang, ON = muncul lagi

for _, rarity in ipairs(RARITIES) do
    makeToggleButton(RARITY_UI_LABELS[rarity], RARITY_COLORS[rarity],
        function()
            return selectedRarities[rarity] == true
        end,
        function()
            if selectedRarities[rarity] then
                selectedRarities[rarity] = nil
            else
                selectedRarities[rarity] = true
            end
            markFilteredDirty()
        end
    )
end

for _, nexus in ipairs(NEXUS) do
    makeToggleButton(nexus, RARITY_COLORS[nexus],
        function()
            return selectedNexus[nexus] == true
        end,
        function()
            if selectedNexus[nexus] then
                selectedNexus[nexus] = nil
            else
                selectedNexus[nexus] = true
            end
            markFilteredDirty()
        end
    )
end

-- Mythic sudah menjadi bagian dari daftar rarity multi-select.

for _, category in ipairs(CATEGORIES) do
    makeToggleButton(category, RARITY_COLORS[category],
        function()
            return selectedCategories[category] == true
        end,
        function()
            if selectedCategories[category] then
                selectedCategories[category] = nil
            else
                selectedCategories[category] = true
            end
        end
    )
end

local updateFilterStatus

-- V11: size / kg / price UI dihapus agar lebih ringan

radarStatus = Instance.new("TextLabel", radarPage)
radarStatus.Size = UDim2.new(1, 0, 0, 22)
radarStatus.Position = UDim2.new(0, 0, 0, 52)
radarStatus.Text = "WORLD • 200M • MARKER ONLY"
radarStatus.TextColor3 = C.textMain
radarStatus.TextSize = 9
radarStatus.Font = Enum.Font.GothamBold
radarStatus.TextXAlignment = Enum.TextXAlignment.Left
radarStatus.TextYAlignment = Enum.TextYAlignment.Center
radarStatus.BackgroundColor3 = C.black
radarStatus.BackgroundTransparency = 0.1
radarStatus.BorderSizePixel = 0

Instance.new("UICorner", radarStatus).CornerRadius = UDim.new(0, 7)

local statusPadding = Instance.new("UIPadding", radarStatus)
statusPadding.PaddingLeft = UDim.new(0, 7)

local resetBtn = Instance.new("TextButton", radarPage)
resetBtn.Size = UDim2.new(1, 0, 0, 22)
resetBtn.Position = UDim2.new(0, 0, 0, 78)
resetBtn.Text = "↺ RESET"
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

-- ================================================================
-- PAGE SETTINGS
-- ================================================================

local settingsPage = Instance.new("Frame", rightCol)
settingsPage.Name = "SettingsPage"
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

local pStatus = Instance.new("TextLabel", settingsPage)
pStatus.Size = UDim2.new(1, 0, 0, 28)
pStatus.Position = UDim2.new(0, 0, 0, 18)
pStatus.Text = "SOON FEATURE\nFast Mine / Pickup"
pStatus.TextColor3 = C.textSub
pStatus.TextSize = 8
pStatus.Font = Enum.Font.Gotham
pStatus.TextXAlignment = Enum.TextXAlignment.Left
pStatus.TextYAlignment = Enum.TextYAlignment.Top
pStatus.BackgroundColor3 = C.black
pStatus.BackgroundTransparency = 0.2
pStatus.BorderSizePixel = 0
pStatus.TextWrapped = true

Instance.new("UICorner", pStatus).CornerRadius = UDim.new(0, 6)

local pPadding = Instance.new("UIPadding", pStatus)
pPadding.PaddingLeft = UDim.new(0, 6)
pPadding.PaddingTop = UDim.new(0, 3)

local soonFeature = Instance.new("TextLabel", settingsPage)
soonFeature.Size = UDim2.new(1, 0, 0, 42)
soonFeature.Position = UDim2.new(0, 0, 0, 49)
soonFeature.Text = "SOON FEATURE\nFast Mine / Pickup"
soonFeature.TextColor3 = C.textSub
soonFeature.TextSize = 8
soonFeature.Font = Enum.Font.GothamBold
soonFeature.TextXAlignment = Enum.TextXAlignment.Left
soonFeature.TextYAlignment = Enum.TextYAlignment.Center
soonFeature.BackgroundColor3 = C.black
soonFeature.BackgroundTransparency = 0.2
soonFeature.BorderSizePixel = 0
soonFeature.TextWrapped = true
Instance.new("UICorner", soonFeature).CornerRadius = UDim.new(0, 6)

local pInfo = Instance.new("TextLabel", settingsPage)
pInfo.Position = UDim2.new(0, 0, 0, 98)
pInfo.Size = UDim2.new(1, 0, 0, 42)
pInfo.Text = "Fast Mine dan Pickup dinonaktifkan pada V3.0.\nRadar tetap aktif dengan cache multi-Crystal jarak jauh."
pInfo.TextColor3 = C.textSub
pInfo.TextSize = 7
pInfo.Font = Enum.Font.Gotham
pInfo.TextXAlignment = Enum.TextXAlignment.Left
pInfo.TextYAlignment = Enum.TextYAlignment.Top
pInfo.BackgroundTransparency = 1
pInfo.TextWrapped = true

-- ================================================================
-- FILTER STATUS UPDATE
-- ================================================================

-- FAST MINE / PICKUP REMOVED IN V3.0
-- Settings area is intentionally reserved for future features.

function updateFilterStatus()
    local parts = {}

    local rarityCount = 0
    for _ in pairs(selectedRarities) do
        rarityCount += 1
    end
    if rarityCount > 0 then
        table.insert(parts, rarityCount .. " rarity")
    end

    local nexusCount = 0
    for _ in pairs(selectedNexus) do
        nexusCount += 1
    end
    if nexusCount > 0 then
        table.insert(parts, nexusCount .. " Nexus")
    end

    local categoryCount = 0
    for _ in pairs(selectedCategories) do
        categoryCount += 1
    end
    if categoryCount > 0 then
        table.insert(parts, categoryCount .. " cat")
    end

    if #parts > 0 then
        filterStatus.Text = table.concat(parts, " | ")
    else
        filterStatus.Text = "Filter: SEMUA"
    end
end

-- ================================================================
-- REFRESH TOGGLES
-- ================================================================

local function refreshToggles()
    for name, data in pairs(toggleButtons) do
        if data.get() then
            local color = data.color or C.accent
            data.btn.BackgroundColor3 = color
        else
            data.btn.BackgroundColor3 = C.black
        end
    end
end

-- ================================================================
-- RESET
-- ================================================================

resetBtn.MouseButton1Click:Connect(function()
    selectedRarities = {}
    selectedCategories = {}
    selectedNexus = {}

    markFilteredDirty()
    clearAllMarkers()
    refreshToggles()
    updateFilterStatus()

    if radarOn then
        task.defer(scan)
    end
end)

-- ================================================================
-- SPEED
-- ================================================================

speedBtn.MouseButton1Click:Connect(function()
    speedOn = not speedOn
    setSpeedVis(speedOn)

    if speedOn then
        hookHumanoid()
    else
        local character = localPlayer.Character
        local hum = character and character:FindFirstChildOfClass("Humanoid")

        if hum then
            hum.WalkSpeed = CONFIG.normalSpeed
        end
    end
end)

-- ================================================================
-- RADAR
-- ================================================================

radarBtn.MouseButton1Click:Connect(function()
    setSettingsVis(false)
    radarPage.Visible = true
    settingsPage.Visible = false
    currentPage = "radar"
    refreshRadarToggle()
end)

-- ================================================================
-- SETTINGS
-- ================================================================

settingsBtn.MouseButton1Click:Connect(function()
    setSettingsVis(true)
    radarPage.Visible = false
    settingsPage.Visible = true
    currentPage = "settings"
end)


-- ================================================================
-- MINI BUBBLE
-- ================================================================

local miniBubble = Instance.new("TextButton", screenGui)
miniBubble.Size = UDim2.new(0, 48, 0, 48)
miniBubble.Position = UDim2.new(0, 12, 0.5, -24)
miniBubble.Text = "⚡"
miniBubble.TextColor3 = Color3.new(1, 1, 1)
miniBubble.BackgroundColor3 = C.accent
miniBubble.Font = Enum.Font.GothamBold
miniBubble.TextSize = 16
miniBubble.BorderSizePixel = 0
miniBubble.Visible = false

Instance.new("UICorner", miniBubble).CornerRadius = UDim.new(1, 0)

-- ================================================================
-- MINIMIZE
-- ================================================================

minBtn.MouseButton1Click:Connect(function()
    miniBubble.Position = outer.Position
    outer.Visible = false
    miniBubble.Visible = true
end)

miniBubble.MouseButton1Click:Connect(function()
    outer.Visible = true
    miniBubble.Visible = false
end)

-- ================================================================
-- DRAG
-- ================================================================

local function makeDraggable(frame)
    local dragging = false
    local dragStart
    local startPos

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
        if not dragging then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart

            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(outer)
makeDraggable(miniBubble)

-- ================================================================
-- INITIAL UI
-- ================================================================

updateFilterStatus()
refreshToggles()
refreshRadarToggle()

print(
    "ENGINE V16 V12.0 MODERN LOADED ✔",
    "| NO LAG ON RADAR ON",
    "| ASYNC CACHE + SOFT-START",
    "| RARITY OFF=HIDE / ON=SHOW",
    "| MARKER ONLY • 200M • STICKY",
    "| FILTER-FIRST + DIST²"
)
