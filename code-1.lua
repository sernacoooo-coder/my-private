-- Key check: pasang di paling atas, sisanya file tidak berubah
local EXPECTED_KEY = "dhubgokil"

local providedKey
if type(getgenv) == "function" then
    providedKey = getgenv().key
end
-- fallback ke _G jika perlu
if providedKey == nil and type(_G) == "table" then
    providedKey = _G.key
end

if providedKey ~= EXPECTED_KEY then
    -- abort jika key tidak cocok
    return
end

-- =================================================================
-- ENGINE V14 - COMPACT FIXED EDITION
--   ✅ UI KECIL lagi (seperti V12)
--   ❌ Auto-detect DIHAPUS
--   ✅ Category BARU: Empiris, Pulsar, Quasar (di atas Mythic)
--      + Size fix: Small / Medium / Large / Huge
--   ✅ LUCKY EXACT MATCH: "2.0" = hanya tepat 2.0 yang lolos
-- =================================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local CONFIG = {
    normalSpeed   = 16,
    boostMult     = 3,
    radarInterval = 0.15,
    maxMarkers    = 50,
    scanRadius    = 100,
}

local LUCK = {
    RarityMult = {1, 1.6, 2.6, 4.2, 7, 12, 216, 480, 600},
    Base       = 0.00045,
    WeightExp  = 0.5,
    KgCap      = 500,
    BombMult   = 3,
    BloodMult  = 4,
}

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
-- Category baru diposisikan DI ATAS Mythic:
local CATEGORIES = { "Empiris", "Pulsar", "Quasar" }
local MYTHIC = "Mythic"

local SIZES = { "Small", "Medium", "Large", "Huge" }

local RARITY_COLORS = {
    Common=Color3.fromRGB(180,180,180), Uncommon=Color3.fromRGB(90,200,90),
    Rare=Color3.fromRGB(70,140,255), Epic=Color3.fromRGB(170,80,255),
    Legendary=Color3.fromRGB(255,170,40), Mythic=Color3.fromRGB(255,60,130),
    Empiris=Color3.fromRGB(0,255,200), Pulsar=Color3.fromRGB(255,220,0),
    Quasar=Color3.fromRGB(255,80,80),
}

local C = {
    bg=Color3.fromRGB(8,8,10), black=Color3.fromRGB(14,14,16),
    accent=Color3.fromRGB(88,101,242), green=Color3.fromRGB(87,242,135),
    orange=Color3.fromRGB(254,160,60), purple=Color3.fromRGB(180,80,220),
    red=Color3.fromRGB(237,66,69), teal=Color3.fromRGB(40,190,180),
    textMain=Color3.fromRGB(235,238,245), textSub=Color3.fromRGB(130,136,148),
}

local speedOn, radarOn = false, false
local filterRarityMin = 0
local wantMythic      = false
local filterMinLucky  = nil          -- nil = semua; angka = EXACT match
local selectedCategories = {}
local selectedSizes      = {}
local markers = {}

-- ================================================================
-- SPEED 3X
-- ================================================================
local function targetSpeed() return CONFIG.normalSpeed * CONFIG.boostMult end

local currentConn = nil
local function hookHumanoid()
    if currentConn then currentConn:Disconnect() currentConn = nil end
    local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    currentConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if speedOn and hum.WalkSpeed ~= targetSpeed() then hum.WalkSpeed = targetSpeed() end
    end)
    hum.WalkSpeed = targetSpeed()
end

RunService.Heartbeat:Connect(function()
    if not speedOn then return end
    local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed ~= targetSpeed() then hum.WalkSpeed = targetSpeed() end
end)

localPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if speedOn then hookHumanoid() end
end)

task.spawn(function()
    while true do
        if speedOn then hookHumanoid() end
        task.wait(2)
    end
end)

-- ================================================================
-- BACA INFO CRYSTAL (tanpa auto-detect — fixed keys)
-- ================================================================
local function getCrystalCategory(part)
    for _, k in ipairs({"CrystalName","CrystalType","Type","Kind"}) do
        local v = part:GetAttribute(k)
        if type(v) == "string" and v ~= "" then return v end
    end
    local tn = tostring(part:GetAttribute("TierName") or "")
    for _, cat in ipairs(CATEGORIES) do
        if tn:lower():find(cat:lower(), 1, true) then return cat end
    end
    return nil
end

local function getCrystalSize(part)
    for _, k in ipairs({"Size","CrystalSize","SizeCategory"}) do
        local v = part:GetAttribute(k)
        if type(v) == "string" and v ~= "" then return v end
    end
    local tn = tostring(part:GetAttribute("TierName") or "")
    for _, sz in ipairs(SIZES) do
        if tn:find(sz, 1, true) then return sz end
    end
    return nil
end

-- ================================================================
-- LUCKY — EXACT MATCH
--   filterMinLucky = 2.0 → hanya luck TEPAT 2.0 yang lolos
--   (toleransi 0.001 untuk pembulatan float)
-- ================================================================
local function getLuckScore(part)
    for _, key in ipairs({"CrystalLuck","LuckValue","Luck","Lucky"}) do
        local v = part:GetAttribute(key)
        if type(v) == "number" and v > 0 then return v end
    end

    local tier = tonumber(part:GetAttribute("Tier")) or 1
    local kg = tonumber(part:GetAttribute("LuckKg"))
             or tonumber(part:GetAttribute("WeightKg")) or 0
    kg = math.max(0, kg)

    local rm = LUCK.RarityMult[tier] or LUCK.RarityMult[1]
    local raw = rm * math.min(kg, LUCK.KgCap) ^ LUCK.WeightExp * LUCK.Base

    local mult = tonumber(part:GetAttribute("MutationLuckRoll")) or 1
    if part:GetAttribute("BombCrystal") == true then mult = mult * LUCK.BombMult end
    if part:GetAttribute("IsBloodCrystal") == true then mult = mult * LUCK.BloodMult end

    return math.max(raw, raw * mult, rm * mult)
end

local function passesLucky(part)
    if not filterMinLucky then return true end
    local score = getLuckScore(part)
    return math.abs(score - filterMinLucky) <= 0.001   -- EXACT saja
end

-- ================================================================
-- FILTER GABUNGAN
-- ================================================================
local function getRarityIndex(part)
    local tn = tostring(part:GetAttribute("TierName") or "")
    for i, r in ipairs(RARITIES) do
        if tn:lower():find(r:lower(), 1, true) then return i end
    end
    if tn:lower():find(MYTHIC:lower(), 1, true) then return 99 end
    return -1
end

local function passesFilter(part)
    -- Rarity biasa
    if filterRarityMin > 0 then
        local ri = getRarityIndex(part)
        local isMythic = (ri == 99)
        if isMythic then
            if not wantMythic then return false end
        elseif ri < filterRarityMin then
            return false
        end
    end
    -- Category (Empiris/Pulsar/Quasar)
    if next(selectedCategories) then
        local cat = getCrystalCategory(part)
        if not cat or not selectedCategories[cat] then return false end
    end
    -- Size
    if next(selectedSizes) then
        local sz = getCrystalSize(part)
        if not sz or not selectedSizes[sz] then return false end
    end
    return passesLucky(part)
end

local function markerColor(part)
    local r = tonumber(part:GetAttribute("TierColorR"))
    local g = tonumber(part:GetAttribute("TierColorG"))
    local b = tonumber(part:GetAttribute("TierColorB"))
    if r and g and b then return Color3.fromRGB(r,g,b) end
    local tn = tostring(part:GetAttribute("TierName") or "")
    for name, col in pairs(RARITY_COLORS) do
        if tn:lower():find(name:lower(), 1, true) then return col end
    end
    return Color3.fromRGB(200,210,230)
end

-- ================================================================
-- RADAR SCAN
-- ================================================================
local function clearAllMarkers()
    for part, m in pairs(markers) do
        pcall(function() m:Destroy() end)
        markers[part] = nil
    end
end

local function findCrystalFolder()
    local things = workspace:FindFirstChild("Things")
    local c = things and things:FindFirstChild("Crystals")
    if c then return c end
    return workspace:FindFirstChild("Crystals", true)
end

local function scan()
    local char = localPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local folder = findCrystalFolder()
    if not folder then clearAllMarkers() return end

    local pos = hrp and hrp.Position or Vector3.zero
    local found = {}

    for _, part in ipairs(folder:GetDescendants()) do
        if part:IsA("BasePart") and part:GetAttribute("TierName") ~= nil
        and passesFilter(part) then
            local d = hrp and (part.Position - pos).Magnitude or 0
            if d <= CONFIG.scanRadius then
                found[#found+1] = {part=part, d=d}
            end
        end
    end

    table.sort(found, function(a,b) return a.d < b.d end)

    local keep = {}
    local n = math.min(#found, CONFIG.maxMarkers)
    for i = 1, n do
        local part = found[i].part
        keep[part] = true
        local m = markers[part]
        if not m or not m.Parent then
            m = Instance.new("Highlight")
            m.Name = "EngineHL"
            m.FillTransparency = 0.55
            m.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            markers[part] = m
        end
        local col = markerColor(part)
        m.FillColor = col; m.OutlineColor = col
        m.Adornee = part; m.Parent = part
    end
    for part in pairs(markers) do
        if not (keep[part] and part.Parent) then
            pcall(function() markers[part]:Destroy() end)
            markers[part] = nil
        end
    end
end

task.spawn(function()
    while true do
        if radarOn then pcall(scan) end
        task.wait(CONFIG.radarInterval)
    end
end)

-- ================================================================
-- GUI KECIL (seperti V12)
-- ================================================================
local playerGui = localPlayer:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("EngineGUI")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EngineGUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 9999
screenGui.Parent = playerGui

local outer = Instance.new("Frame", screenGui)
outer.Size = UDim2.new(0, 360, 0, 240)
outer.Position = UDim2.new(0, 12, 0.5, -120)
outer.BackgroundColor3 = C.bg; outer.BorderSizePixel = 0; outer.Active = true
Instance.new("UICorner", outer).CornerRadius = UDim.new(0, 16)
local oStroke = Instance.new("UIStroke", outer)
oStroke.Color = Color3.fromRGB(45,45,52); oStroke.Thickness = 1

local titleBar = Instance.new("Frame", outer)
titleBar.Size = UDim2.new(1,0,0,28); titleBar.BackgroundColor3 = C.accent
titleBar.BackgroundTransparency = 0.25; titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,16)
local tbFix = Instance.new("Frame", titleBar)
tbFix.Size = UDim2.new(1,0,0,12); tbFix.Position = UDim2.new(0,0,1,-12)
tbFix.BackgroundColor3 = C.accent; tbFix.BackgroundTransparency = 0.25; tbFix.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(1,-52,1,0); titleLabel.Position = UDim2.new(0,10,0,0)
titleLabel.Text = "⚡ Engine V14"; titleLabel.TextColor3 = Color3.new(1,1,1)
titleLabel.TextSize = 12; titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.BackgroundTransparency = 1

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0,20,0,18); minBtn.Position = UDim2.new(1,-24,0.5,-9)
minBtn.Text = "_"; minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.BackgroundColor3 = Color3.fromRGB(70,80,110)
minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 11; minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,6)

------------------------------------------------------------
-- KIRI: ikon toggle
------------------------------------------------------------
local leftCol = Instance.new("Frame", outer)
leftCol.Size = UDim2.new(0,48,1,-38); leftCol.Position = UDim2.new(0,6,0,34)
leftCol.BackgroundTransparency = 1

local CYAN = Color3.fromRGB(0,200,255)
local PINK = Color3.fromRGB(255,100,160)

local function makeIconButton(yPos, icon, gradA, gradB)
    local btn = Instance.new("TextButton", leftCol)
    btn.Size = UDim2.new(1,0,0,40); btn.Position = UDim2.new(0,0,0,yPos)
    btn.Text = icon; btn.TextColor3 = Color3.new(1,1,1); btn.TextSize = 18
    btn.Font = Enum.Font.GothamBold
    btn.BackgroundColor3 = C.black; btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,11)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(45,45,52); stroke.Thickness = 1.5
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
            stroke.Color = Color3.fromRGB(45,45,52)
        end
    end
    return btn, setVisual
end

local speedBtn, setSpeedVis = makeIconButton(0, "⚡", C.accent, CYAN)
local radarBtn, setRadarVis = makeIconButton(46, "◎", C.orange, PINK)

------------------------------------------------------------
-- KANAN: FILTER (kompak, 2 baris scrollable)
------------------------------------------------------------
local divider = Instance.new("Frame", outer)
divider.Size = UDim2.new(0,1,1,-46); divider.Position = UDim2.new(0,60,0,40)
divider.BackgroundColor3 = Color3.fromRGB(35,35,42); divider.BorderSizePixel = 0

local rightCol = Instance.new("Frame", outer)
rightCol.Size = UDim2.new(1,-74,1,-46); rightCol.Position = UDim2.new(0,66,0,34)
rightCol.BackgroundTransparency = 1

local fTitle = Instance.new("TextLabel", rightCol)
fTitle.Size = UDim2.new(1,0,0,13); fTitle.Text = "🎛️ FILTER RADAR"
fTitle.TextColor3 = C.purple; fTitle.TextSize = 9
fTitle.Font = Enum.Font.GothamBold; fTitle.TextXAlignment = Enum.TextXAlignment.Left
fTitle.BackgroundTransparency = 1

-- BARIS 1: Rarity + Mythic + 3 category baru (Empiris/Pulsar/Quasar)
local catScroll = Instance.new("ScrollingFrame", rightCol)
catScroll.Size = UDim2.new(1,0,0,30); catScroll.Position = UDim2.new(0,0,0,15)
catScroll.BackgroundTransparency = 1; catScroll.BorderSizePixel = 0
catScroll.ScrollingDirection = Enum.ScrollingDirection.XY
catScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
catScroll.CanvasSize = UDim2.new(0,0,0,0)
catScroll.ScrollBarThickness = 2
local catGrid = Instance.new("UIGridLayout", catScroll)
catGrid.CellSize = UDim2.new(0,54,0,13); catGrid.CellPadding = UDim2.new(0,3,0,3)

local toggleButtons = {} -- [nama] = {btn, get, set}

local function makeToggleButton(name, color, getState, setState)
    local b = Instance.new("TextButton", catScroll)
    b.Text = name; b.TextColor3 = color; b.TextSize = 7
    b.Font = Enum.Font.GothamBold
    b.BackgroundColor3 = C.black; b.BorderSizePixel = 0
    b.TextTruncate = Enum.TextTruncate.AtEnd
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,5)
    toggleButtons[name] = {btn=b, get=getState}
    b.MouseButton1Click:Connect(function()
        setState()
        b.BackgroundColor3 = getState() and color or C.black
        if radarOn then pcall(scan) end
    end)
end

-- Rarity biasa
local rarityState = function(i) return function() return filterRarityMin == i end end
local raritySet = function(i) return function()
    filterRarityMin = (filterRarityMin == i) and 0 or i
end end
for i, r in ipairs(RARITIES) do
    makeToggleButton(r, RARITY_COLORS[r], rarityState(i), raritySet(i))
end
-- Mythic (toggle terpisah)
makeToggleButton(MYTHIC, RARITY_COLORS[MYTHIC],
    function() return wantMythic end,
    function() wantMythic = not wantMythic end)
-- 3 CATEGORY BARU — di atas Mythic secara logika filter
for _, cat in ipairs(CATEGORIES) do
    makeToggleButton(cat, RARITY_COLORS[cat],
        function() return selectedCategories[cat] == true end,
        function()
            if selectedCategories[cat] then selectedCategories[cat] = nil
            else selectedCategories[cat] = true end
        end)
end

-- BARIS 2: Size
local sizeScroll = Instance.new("ScrollingFrame", rightCol)
sizeScroll.Size = UDim2.new(1,0,0,16); sizeScroll.Position = UDim2.new(0,0,0,49)
sizeScroll.BackgroundTransparency = 1; sizeScroll.BorderSizePixel = 0
sizeScroll.ScrollingDirection = Enum.ScrollingDirection.X
sizeScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
sizeScroll.CanvasSize = UDim2.new(0,0,0,0)
sizeScroll.ScrollBarThickness = 2
local sizeGrid = Instance.new("UIGridLayout", sizeScroll)
sizeGrid.CellSize = UDim2.new(0,54,0,13); sizeGrid.CellPadding = UDim2.new(0,3,0,3)

for _, sz in ipairs(SIZES) do
    local b = Instance.new("TextButton", sizeScroll)
    b.Text = sz; b.TextColor3 = C.orange; b.TextSize = 7
    b.Font = Enum.Font.GothamBold
    b.BackgroundColor3 = C.black; b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,5)
    b.MouseButton1Click:Connect(function()
        if selectedSizes[sz] then selectedSizes[sz] = nil
        else selectedSizes[sz] = true end
        b.BackgroundColor3 = selectedSizes[sz] and C.orange or C.black
        if radarOn then pcall(scan) end
    end)
end

-- Lucky EXACT
local luckyRow = Instance.new("Frame", rightCol)
luckyRow.Size = UDim2.new(1,0,0,22); luckyRow.Position = UDim2.new(0,0,0,72)
luckyRow.BackgroundTransparency = 1

local luckyBox = Instance.new("TextBox", luckyRow)
luckyBox.Size = UDim2.new(0,110,1,0)
luckyBox.PlaceholderText = "Lucky: 2.0 exact"
luckyBox.Text = ""; luckyBox.TextColor3 = C.textMain; luckyBox.TextSize = 11
luckyBox.Font = Enum.Font.GothamBold; luckyBox.BackgroundColor3 = C.black
luckyBox.ClearTextOnFocus = false; luckyBox.BorderSizePixel = 0
Instance.new("UICorner", luckyBox).CornerRadius = UDim.new(0,7)
local lbPad = Instance.new("UIPadding", luckyBox)
lbPad.PaddingLeft = UDim.new(0,7)

local clearLuckyBtn = Instance.new("TextButton", luckyRow)
clearLuckyBtn.Size = UDim2.new(0,44,1,0); clearLuckyBtn.Position = UDim2.new(0,114,0,0)
clearLuckyBtn.Text = "✕"; clearLuckyBtn.TextColor3 = Color3.new(1,1,1)
clearLuckyBtn.BackgroundColor3 = Color3.fromRGB(50,50,58)
clearLuckyBtn.Font = Enum.Font.GothamBold; clearLuckyBtn.TextSize = 11
clearLuckyBtn.BorderSizePixel = 0
Instance.new("UICorner", clearLuckyBtn).CornerRadius = UDim.new(0,7)

local resetBtn = Instance.new("TextButton", luckyRow)
resetBtn.Size = UDim2.new(1,-162,1,0); resetBtn.Position = UDim2.new(0,162,0,0)
resetBtn.Text = "↺ RESET"; resetBtn.TextColor3 = Color3.new(1,1,1)
resetBtn.BackgroundColor3 = C.red; resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 9; resetBtn.BorderSizePixel = 0
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0,7)

local filterStatus = Instance.new("TextLabel", rightCol)
filterStatus.Size = UDim2.new(1,0,0,30); filterStatus.Position = UDim2.new(0,0,0,100)
filterStatus.Text = ""; filterStatus.TextColor3 = C.green
filterStatus.TextSize = 9; filterStatus.Font = Enum.Font.GothamBold
filterStatus.TextXAlignment = Enum.TextXAlignment.Left
filterStatus.TextYAlignment = Enum.TextYAlignment.Top
filterStatus.BackgroundTransparency = 1; filterStatus.TextWrapped = true

local miniBubble = Instance.new("TextButton", screenGui)
miniBubble.Size = UDim2.new(0,42,0,42); miniBubble.Position = UDim2.new(0,12,0.5,-21)
miniBubble.Text = "⚡"; miniBubble.TextColor3 = Color3.new(1,1,1)
miniBubble.BackgroundColor3 = C.accent; miniBubble.Font = Enum.Font.GothamBold
miniBubble.TextSize = 16; miniBubble.BorderSizePixel = 0; miniBubble.Visible = false
Instance.new("UICorner", miniBubble).CornerRadius = UDim.new(1,0)

------------------------------------------------------------
-- HANDLERS
------------------------------------------------------------
local function updateFilterStatus()
    local parts = {}
    if filterRarityMin > 0 then table.insert(parts, RARITIES[filterRarityMin].."+") end
    if wantMythic then table.insert(parts, "Mythic") end
    local nc, ns = 0, 0
    for _ in pairs(selectedCategories) do nc += 1 end
    for _ in pairs(selectedSizes) do ns += 1 end
    if nc > 0 then table.insert(parts, nc.." cat") end
    if ns > 0 then table.insert(parts, ns.." size") end
    if filterMinLucky then
        local v = filterMinLucky
        local txt = (v == math.floor(v)) and ("%g"):format(v) or ("%.1f"):format(v)
        table.insert(parts, "Luck="..txt.." exact")
    end
    filterStatus.Text = (#parts > 0) and table.concat(parts, " | ") or "Filter: SEMUA"
end

local function refreshToggles()
    for name, data in pairs(toggleButtons) do
        if data.get() then
            -- cari warna asli
            local col = C.accent
            for _, r in ipairs(RARITIES) do if name == r then col = RARITY_COLORS[r] end end
            if name == MYTHIC then col = RARITY_COLORS[MYTHIC] end
            for _, cat in ipairs(CATEGORIES) do if name == cat then col = RARITY_COLORS[cat] end end
            data.btn.BackgroundColor3 = col
        else
            data.btn.BackgroundColor3 = C.black
        end
    end
end

luckyBox.FocusLost:Connect(function()
    local txt = luckyBox.Text:gsub("[%s,]", "")
    if txt == "" then
        filterMinLucky = nil
    else
        local v = tonumber(txt)
        filterMinLucky = v   -- bisa apa saja, termasuk 2.0 / 50.0
    end
    updateFilterStatus()
    if radarOn then pcall(scan) end
end)

clearLuckyBtn.MouseButton1Click:Connect(function()
    filterMinLucky = nil
    luckyBox.Text = ""
    updateFilterStatus()
    if radarOn then pcall(scan) end
end)

resetBtn.MouseButton1Click:Connect(function()
    filterRarityMin, wantMythic = 0, false
    filterMinLucky = nil
    selectedCategories = {}
    selectedSizes = {}
    luckyBox.Text = ""
    refreshToggles(); updateFilterStatus()
    if radarOn then pcall(scan) end
end)

speedBtn.MouseButton1Click:Connect(function()
    speedOn = not speedOn
    setSpeedVis(speedOn)
    if speedOn then
        hookHumanoid()
    else
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = CONFIG.normalSpeed end
    end
end)

radarBtn.MouseButton1Click:Connect(function()
    radarOn = not radarOn
    setRadarVis(radarOn)
    if not radarOn then clearAllMarkers() end
end)

minBtn.MouseButton1Click:Connect(function()
    miniBubble.Position = outer.Position
    outer.Visible = false; miniBubble.Visible = true
end)
miniBubble.MouseButton1Click:Connect(function()
    outer.Visible = true; miniBubble.Visible = false
end)

updateFilterStatus()

-- ===== DRAG =====
local function makeDraggable(frame)
    local dragging = false
    local dragStart, startPos
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = frame.Position
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

print("ENGINE V14 - LOADED ✔ (UI kecil | No auto-detect | Empiris/Pulsar/Quasar | Lucky EXACT)")
