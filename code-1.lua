-- Key check: pasang di paling atas
local EXPECTED_KEY = "Jack"

local providedKey
if type(getgenv) == "function" then providedKey = getgenv().key end
if providedKey == nil and type(_G) == "table" then providedKey = _G.key end

if providedKey ~= EXPECTED_KEY then return end

-- =================================================================
-- ENGINE V17 - COMPACT FIXED EDITION (styling from V14 for name tags)
--   - Name tag UI uses exact styling from original V14 toggle buttons
--   - scanRadius set to 200 meters
--   - Cache nexus models to avoid full GetDescendants each scan
--   - Robust detection and realtime updates; fixes radar lag/bugs
--   - Icon setVisual calls optimized to only run on state changes
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
    scanRadius    = 200, -- changed to 200m as requested
}

local C = {
    bg=Color3.fromRGB(8,8,10), black=Color3.fromRGB(14,14,16),
    accent=Color3.fromRGB(88,101,242), green=Color3.fromRGB(87,242,135),
    orange=Color3.fromRGB(254,160,60), purple=Color3.fromRGB(180,80,220),
    red=Color3.fromRGB(237,66,69), teal=Color3.fromRGB(40,190,180),
    textMain=Color3.fromRGB(235,238,245), textSub=Color3.fromRGB(130,136,148),
}

local SOLAR_COLOR = Color3.fromRGB(255,220,80) -- kuning
local VOID_COLOR  = Color3.fromRGB(180,80,220) -- ungu

local speedOn, radarOn = false, false
local filterSolar = true
local filterVoid  = true
-- markers: [part] = {hl = Highlight, tag = BillboardGui}
local markers = {}

-- cache of nexus models to avoid expensive workspace:GetDescendants each scan
local nexusCache = {} -- [modelInstance] = name ("Solar Nexus"/"Void Nexus")

-- ================================================================
-- SPEED 3X (identik V14)
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
        if speedOn then pcall(hookHumanoid) end
        task.wait(2)
    end
end)

-- ================================================================
-- NEXUS DETECTION (workspace-wide) with caching
-- ================================================================
local function resolvePart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function isNexusName(name)
    return name == "Solar Nexus" or name == "Void Nexus"
end

local function cacheAdd(model)
    if not model or not model.Parent then return end
    if isNexusName(model.Name) then
        nexusCache[model] = model.Name
    end
end

local function rebuildCache()
    table.clear(nexusCache)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if isNexusName(obj.Name) then
            nexusCache[obj] = obj.Name
        end
    end
end

-- init cache once
rebuildCache()

-- keep cache fresh incrementally
workspace.DescendantAdded:Connect(function(obj)
    -- if any ancestor (including itself) is a named nexus, add the ancestor model
    local cur = obj
    while cur and cur ~= workspace do
        if isNexusName(cur.Name) then
            nexusCache[cur] = cur.Name
            break
        end
        cur = cur.Parent
    end
end)

workspace.DescendantRemoving:Connect(function(obj)
    -- remove if the removed instance is the model we cached
    if nexusCache[obj] then
        nexusCache[obj] = nil
    end
end)

-- ================================================================
-- UI Name tag maker (styling copied from V14 toggle button EXACTLY)
-- V14 toggle button style: Font=GothamBold, TextSize=7, Bg=C.black,
-- UICorner radius=5, text color variable
-- ================================================================
local function makeNameTag(part, name, color)
    local bgui = Instance.new("BillboardGui")
    bgui.Name = "EngineName"
    bgui.AlwaysOnTop = true
    bgui.Size = UDim2.new(0, 140, 0, 18)
    bgui.StudsOffset = Vector3.new(0, 2.2, 0)
    bgui.Adornee = part

    local b = Instance.new("TextLabel")
    b.Name = "NameLabel"
    b.Size = UDim2.new(1, 0, 1, 0)
    b.BackgroundColor3 = C.black -- exact from V14 toggle buttons
    b.BorderSizePixel = 0
    b.Text = name
    b.TextColor3 = color or Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 7 -- exact V14
    b.TextWrapped = false
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.TextYAlignment = Enum.TextYAlignment.Center
    b.Parent = bgui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,5)
    corner.Parent = b

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0,6)
    pad.Parent = b

    return bgui
end

local function clearAllMarkers()
    for part, data in pairs(markers) do
        pcall(function()
            if data.hl then data.hl:Destroy() end
            if data.tag then data.tag:Destroy() end
        end)
        markers[part] = nil
    end
end

-- ================================================================
-- RADAR SCAN (uses cached nexusCache for performance)
-- ================================================================
local function scan()
    local char = localPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position or Vector3.zero
    local found = {}

    -- iterate cached models
    for model, name in pairs(nexusCache) do
        if model and model.Parent then
            local part = resolvePart(model)
            if part and part.Parent then
                local ok, d = pcall(function() return (part.Position - pos).Magnitude end)
                if ok and d and d <= CONFIG.scanRadius then
                    found[#found+1] = {part = part, name = name, d = d, model = model}
                end
            end
        end
    end

    -- sort berdasarkan jarak
    table.sort(found, function(a,b) return a.d < b.d end)

    local keep = {}
    local n = math.min(#found, CONFIG.maxMarkers)
    for i = 1, n do
        local entry = found[i]
        local part = entry.part
        keep[part] = true
        local data = markers[part]
        if not data then
            data = {}
            -- highlight
            local m = Instance.new("Highlight")
            m.Name = "EngineHL"
            m.FillTransparency = 0.55
            m.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            m.Parent = part
            data.hl = m
            -- name tag UI (billboard) styled exactly like V14
            local col = (entry.name == "Solar Nexus") and SOLAR_COLOR or VOID_COLOR
            local tag = makeNameTag(part, entry.name, col)
            tag.Parent = part
            data.tag = tag
            markers[part] = data
        else
            -- ensure parent and adornee are correct
            if data.hl and not data.hl.Parent then data.hl.Parent = part end
            if data.tag and not data.tag.Parent then data.tag.Parent = part end
            if data.tag then data.tag.Adornee = part end
        end
        -- color/outline sync
        if data.hl then
            local col = (entry.name == "Solar Nexus") and SOLAR_COLOR or VOID_COLOR
            data.hl.FillColor = col; data.hl.OutlineColor = col
            data.hl.Adornee = part
        end
        if data.tag then
            -- update text with distance realtime (rounded down) but keep name UI styling
            local label = data.tag:FindFirstChild("NameLabel")
            if label then
                label.Text = entry.name .. "  (" .. math.floor(entry.d) .. "m)"
                label.TextColor3 = (entry.name == "Solar Nexus") and SOLAR_COLOR or VOID_COLOR
            end
        end
    end

    -- remove markers that are no longer kept or whose part removed
    for part, data in pairs(markers) do
        if not (keep[part] and part.Parent) then
            pcall(function()
                if data.hl then data.hl:Destroy() end
                if data.tag then data.tag:Destroy() end
            end)
            markers[part] = nil
        end
    end
end

-- immediate scan on toggle to avoid waiting interval
local function startRadar()
    if radarOn then
        pcall(scan)
    end
end

-- scanning loop (lightweight now because we iterate cached models only)
task.spawn(function()
    while true do
        if radarOn then pcall(scan) end
        task.wait(CONFIG.radarInterval)
    end
end)

-- ================================================================
-- GUI KECIL (100% gaya V14)
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
titleLabel.Text = "��� Engine V17"; titleLabel.TextColor3 = Color3.new(1,1,1)
titleLabel.TextSize = 12; titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.BackgroundTransparency = 1

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0,20,0,18); minBtn.Position = UDim2.new(1,-24,0.5,-9)
minBtn.Text = "_"; minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.BackgroundColor3 = Color3.fromRGB(70,80,110)
minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 11; minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,6)

-- ------------------------------------------------------------
-- KIRI: ikon toggle (persis V14) with optimized setVisual
-- ------------------------------------------------------------
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
    -- optimized setVisual: only update if state changed
    local currentState = false
    local function setVisual(on)
        if currentState == on then return end
        currentState = on
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

-- ------------------------------------------------------------
-- KANAN: FILTER NEXUS (ganti semua filter lama)
-- ------------------------------------------------------------
local divider = Instance.new("Frame", outer)
divider.Size = UDim2.new(0,1,1,-46); divider.Position = UDim2.new(0,60,0,40)
divider.BackgroundColor3 = Color3.fromRGB(35,35,42); divider.BorderSizePixel = 0

local rightCol = Instance.new("Frame", outer)
rightCol.Size = UDim2.new(1,-74,1,-46); rightCol.Position = UDim2.new(0,66,0,34)
rightCol.BackgroundTransparency = 1

local fTitle = Instance.new("TextLabel", rightCol)
fTitle.Size = UDim2.new(1,0,0,13); fTitle.Text = "◎ RADAR NEXUS"
fTitle.TextColor3 = C.purple; fTitle.TextSize = 9
fTitle.Font = Enum.Font.GothamBold; fTitle.TextXAlignment = Enum.TextXAlignment.Left
fTitle.BackgroundTransparency = 1

-- Tombol filter Solar & Void (warna-warni, toggle ON/OFF)
local solarBtn = Instance.new("TextButton", rightCol)
solarBtn.Size = UDim2.new(1,0,0,24); solarBtn.Position = UDim2.new(0,0,0,16)
solarBtn.Text = "☀  SOLAR NEXUS"; solarBtn.TextSize = 9
solarBtn.Font = Enum.Font.GothamBold; solarBtn.TextColor3 = Color3.new(1,1,1)
solarBtn.BackgroundColor3 = SOLAR_COLOR; solarBtn.BorderSizePixel = 0
Instance.new("UICorner", solarBtn).CornerRadius = UDim.new(0,7)

local voidBtn = Instance.new("TextButton", rightCol)
voidBtn.Size = UDim2.new(1,0,0,24); voidBtn.Position = UDim2.new(0,0,0,44)
voidBtn.Text = "🌑  VOID NEXUS"; voidBtn.TextSize = 9
voidBtn.Font = Enum.Font.GothamBold; voidBtn.TextColor3 = Color3.new(1,1,1)
voidBtn.BackgroundColor3 = VOID_COLOR; voidBtn.BorderSizePixel = 0
Instance.new("UICorner", voidBtn).CornerRadius = UDim.new(0,7)

local filterStatus = Instance.new("TextLabel", rightCol)
filterStatus.Size = UDim2.new(1,0,0,30); filterStatus.Position = UDim2.new(0,0,0,74)
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

-- ------------------------------------------------------------
-- HANDLERS
-- ------------------------------------------------------------
local function updateFilterStatus()
    local parts = {}
    if filterSolar then table.insert(parts, "Solar ✓") end
    if filterVoid  then table.insert(parts, "Void ✓") end
    filterStatus.Text = (#parts > 0)
        and ("Filter: "..table.concat(parts, " | ").." | Radius: "..CONFIG.scanRadius)
        or "Filter: TIDAK ADA (matikan salah satu)"
end

solarBtn.MouseButton1Click:Connect(function()
    filterSolar = not filterSolar
    solarBtn.BackgroundColor3 = filterSolar and SOLAR_COLOR or C.black
    solarBtn.TextColor3 = filterSolar and Color3.new(1,1,1) or C.textSub
    clearAllMarkers()
    updateFilterStatus()
    if radarOn then startRadar() end
end)

voidBtn.MouseButton1Click:Connect(function()
    filterVoid = not filterVoid
    voidBtn.BackgroundColor3 = filterVoid and VOID_COLOR or C.black
    voidBtn.TextColor3 = filterVoid and Color3.new(1,1,1) or C.textSub
    clearAllMarkers()
    updateFilterStatus()
    if radarOn then startRadar() end
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
    if not radarOn then
        clearAllMarkers()
    else
        startRadar() -- immediate scan so we don't wait interval
    end
end)

minBtn.MouseButton1Click:Connect(function()
    miniBubble.Position = outer.Position
    outer.Visible = false; miniBubble.Visible = true
end)
miniBubble.MouseButton1Click:Connect(function()
    outer.Visible = true; miniBubble.Visible = false
end)

updateFilterStatus()

-- ===== DRAG (persis V14 yang sudah proven work) =====
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

print("ENGINE V17 - LOADED ✔ (UI V14 styling for name tags | optimized radar)")
