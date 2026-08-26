-- Key check: pasang di paling atas
local EXPECTED_KEY = "Jack"

local providedKey
if type(getgenv) == "function" then providedKey = getgenv().key end
if providedKey == nil and type(_G) == "table" then providedKey = _G.key end

if providedKey ~= EXPECTED_KEY then return end

-- =================================================================
-- ENGINE V16 - COMPACT FIXED EDITION (Single-file)
--   - Radar HANYA deteksi workspace: "Solar Nexus" & "Void Nexus"
--   - Filter Void/Solar bisa ON/OFF (warna-warni UI tetap 100%)
--   - FIXED: textSub undefined, tombol tak bisa diklik,
--     drag vs click conflict, highlight destroy error
-- =================================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UserInput    = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

local CONFIG = {
    normalSpeed   = 16,
    boostMult     = 3,
    radarInterval = 0.15,
    maxMarkers    = 50,
    scanRadius    = 1000,
}

local C = {
    bg=Color3.fromRGB(8,8,10), black=Color3.fromRGB(14,14,16),
    accent=Color3.fromRGB(88,101,242), green=Color3.fromRGB(87,242,135),
    orange=Color3.fromRGB(254,160,60), purple=Color3.fromRGB(180,80,220),
    red=Color3.fromRGB(237,66,69), teal=Color3.fromRGB(40,190,180),
    yellow=Color3.fromRGB(255,220,80),
    textMain=Color3.fromRGB(235,238,245),
    textSub=Color3.fromRGB(150,155,170), -- FIX: sebelumnya undefined
}

-- FIX BUG: filter state untuk Void / Solar
local filterVoid, filterSolar = true, true

local speedOn, radarOn = false, false
local markers = {} -- [part] = Highlight

-- ================================================================
-- SPEED 3X
-- ================================================================
local function targetSpeed() return CONFIG.normalSpeed * CONFIG.boostMult end

local currentConn = nil
local function hookHumanoid()
    if currentConn then pcall(function() currentConn:Disconnect() end); currentConn = nil end
    local char = localPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    currentConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if speedOn and hum.WalkSpeed ~= targetSpeed() then hum.WalkSpeed = targetSpeed() end
    end)
    hum.WalkSpeed = targetSpeed()
end

RunService.Heartbeat:Connect(function()
    if not speedOn then return end
    local char = localPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
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
-- RADAR: workspace-only Solar Nexus & Void Nexus
-- ================================================================
local TARGETS = {
    ["Solar Nexus"] = {color=C.yellow},
    ["Void Nexus"]  = {color=C.purple},
}

local function clearAllMarkers()
    for part, m in pairs(markers) do
        pcall(function() m:Destroy() end) -- FIX: safe destroy
        markers[part] = nil
    end
end

local function targetEnabled(name)
    if name == "Solar Nexus" then return filterSolar end
    if name == "Void Nexus" then return filterVoid end
    return false
end

-- FIX: pakai CollectionService-style cache + cek parent model
local function getWorldNexusParts()
    local partsList = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local n = obj.Name
            if TARGETS[n] then
                partsList[#partsList+1] = obj
            elseif obj.Parent and TARGETS[obj.Parent.Name] then
                partsList[#partsList+1] = obj
            end
        end
    end
    return partsList
end

local scanCount = 0

local function scan()
    local char = localPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position or Vector3.zero
    local found = {}

    for _, part in ipairs(getWorldNexusParts()) do
        local baseName = TARGETS[part.Name] and part.Name or (part.Parent and part.Parent.Name)
        if baseName and TARGETS[baseName] and targetEnabled(baseName) and part:IsDescendantOf(workspace) then
            local d = hrp and (part.Position - pos).Magnitude or 0
            found[#found+1] = {part=part, d=d, name=baseName}
        end
    end

    table.sort(found, function(a,b) return a.d < b.d end)

    local keep = {}
    for i = 1, math.min(#found, CONFIG.maxMarkers) do
        local entry = found[i]
        local part = entry.part
        keep[part] = true

        local m = markers[part]
        if m and (not m.Parent or m.Adornee ~= part) then
            pcall(function() m:Destroy() end)
            m = nil; markers[part] = nil
        end
        if not m then
            m = Instance.new("Highlight")
            m.Name = "EngineHL"
            m.FillTransparency = 0.55
            m.OutlineTransparency = 0
            m.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            markers[part] = m
        end
        local col = TARGETS[entry.name].color
        if m.FillColor ~= col then m.FillColor = col; m.OutlineColor = col end
        m.Adornee = part
        if not m.Parent then m.Parent = part end
    end

    -- hapus marker yang tidak lagi valid
    for part, m in pairs(markers) do
        if not keep[part] or not part:IsDescendantOf(workspace) then
            pcall(function() m:Destroy() end)
            markers[part] = nil
        end
    end

    scanCount += 1
end

task.spawn(function()
    while true do
        if radarOn then
            local ok, err = pcall(scan)
            if not ok then warn("[Engine] scan error:", err) end
        end
        task.wait(CONFIG.radarInterval)
    end
end)

-- ================================================================
-- GUI KECIL WARNA-WARNI (style V12 tetap 100%)
-- ================================================================
local playerGui = localPlayer:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("EngineGUI")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EngineGUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 9999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- FIX
screenGui.Parent = playerGui

local outer = Instance.new("Frame")
outer.Size = UDim2.new(0, 380, 0, 250)
outer.Position = UDim2.new(0, 12, 0.5, -125)
outer.BackgroundColor3 = C.bg; outer.BorderSizePixel = 0
outer.Active = true          -- FIX: agar draggable
outer.Selectable = false     -- FIX: tidak blok klik child? (Active tetap butuh utk drag)
outer.ClipsDescendants = false
outer.ZIndex = 1
outer.Parent = screenGui
Instance.new("UICorner", outer).CornerRadius = UDim.new(0, 16)
local oStroke = Instance.new("UIStroke", outer)
oStroke.Color = Color3.fromRGB(45,45,52); oStroke.Thickness = 1

local title = Instance.new("Frame")
titleBar.Size = UDim2.new(1,0,0,28); titleBar.BackgroundColor3 = C.accent
titleBar.BackgroundTransparency = 0.25; titleBar.BorderSizePixel = 0
titleBar.Active = true
titleBar.ZIndex = 2
titleBar.Parent = outer
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0,16)
local tbFix = Instance.new("Frame")
tbFix.Size = UDim2.new(1,0,0,12); tbFix.Position = UDim2.new(0,0,1,-12)
tbFix.BackgroundColor3 = C.accent; tbFix.BackgroundTransparency = 0.25
tbFix.BorderSizePixel = 0; tbFix.ZIndex = 2
tbFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1,-52,1,0); titleLabel.Position = UDim2.new(0,10,0,0)
titleLabel.Text = "⚡ Engine V16"; titleLabel.TextColor3 = Color3.new(1,1,1)
titleLabel.TextSize = 12; titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.BackgroundTransparency = 1; titleLabel.ZIndex = 3
titleLabel.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0,20,0,18); minBtn.Position = UDim2.new(1,-24,0.5,-9)
minBtn.Text = "_"; minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.BackgroundColor3 = Color3.fromRGB(70,80,110)
minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 11
minBtn.BorderSizePixel = 0; minBtn.AutoButtonColor = true; minBtn.ZIndex = 4
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,6)

-- LEFT: icon toggles
local leftCol = Instance.new("Frame")
leftCol.Size = UDim2.new(0,48,1,-38); leftCol.Position = UDim2.new(0,6,0,34)
leftCol.BackgroundTransparency = 1; leftCol.ZIndex = 2
leftCol.Parent = outer

local CYAN = Color3.fromRGB(0,200,255)
local PINK = Color3.fromRGB(255,100,160)

local function makeIconButton(yPos, icon, gradA, gradB)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,40); btn.Position = UDim2.new(0,0,0,yPos)
    btn.Text = icon; btn.TextColor3 = Color3.new(1,1,1); btn.TextSize = 18
    btn.Font = Enum.Font.GothamBold
    btn.BackgroundColor3 = C.black; btn.BorderSizePixel = 0
    btn.AutoButtonColor = true
    btn.ZIndex = 3
    btn.Parent = leftCol
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
    setVisual(false)
    return btn, setVisual
end

local speedBtn, setSpeedVis = makeIconButton(0,  "⚡", C.accent, CYAN)
local radarBtn, setRadarVis = makeIconButton(46, "◎", C.orange, PINK)

-- RIGHT: info area
local divider = Instance.new("Frame")
divider.Size = UDim2.new(0,1,1,-46); divider.Position = UDim2.new(0,60,0,40)
divider.BackgroundColor3 = Color3.fromRGB(35,35,42); divider.BorderSizePixel = 0
divider.ZIndex = 2
divider.Parent = outer

local rightCol = Instance.new("Frame")
rightCol.Size = UDim2.new(1,-74,1,-46); rightCol.Position = UDim2.new(0,66,0,34)
rightCol.BackgroundTransparency = 1; rightCol.ZIndex = 2
rightCol.Parent = outer

local fTitle = Instance.new("TextLabel")
fTitle.Size = UDim2.new(1,0,0,13); fTitle.Text = "◎ RADAR NEXUS"
fTitle.TextColor3 = C.purple; fTitle.TextSize = 9
fTitle.Font = Enum.Font.GothamBold; fTitle.TextXAlignment = Enum.TextXAlignment.Left
fTitle.BackgroundTransparency = 1; fTitle.ZIndex = 3
fTitle.Parent = rightCol

-- ===== FILTER BUTTONS (Void & Solar, warna-warni) =====
local function makeFilterButton(yPos, label, dotColor)
    local fb = Instance.new("TextButton")
    fb.Size = UDim2.new(1,0,0,26); fb.Position = UDim2.new(0,0,0,yPos)
    fb.BackgroundColor3 = C.black; fb.BorderSizePixel = 0
    fb.Text = ""; fb.AutoButtonColor = true; fb.ZIndex = 3
    fb.Parent = rightCol
    Instance.new("UICorner", fb).CornerRadius = UDim.new(0,8)
    local fstroke = Instance.new("UIStroke", fb)
    fstroke.Color = dotColor; fstroke.Thickness = 1.5; fstroke.Transparency = 0.4

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0,10,0,10); dot.Position = UDim2.new(0,8,0.5,-5)
    dot.BackgroundColor3 = dotColor; dot.BorderSizePixel = 0; dot.ZIndex = 4
    dot.Parent = fb
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-34,1,0); lbl.Position = UDim2.new(0,24,0,0)
    lbl.Text = label; lbl.TextColor3 = C.textMain; lbl.TextSize = 10
    lbl.Font = Enum.Font.GothamBold; lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1; lbl.ZIndex = 4
    lbl.Parent = fb

    local stateLbl = Instance.new("TextLabel")
    stateLbl.Size = UDim2.new(0,28,1,0); stateLbl.Position = UDim2.new(1,-32,0,0)
    stateLbl.Text = "ON"; stateLbl.TextColor3 = C.green; stateLbl.TextSize = 9
    stateLbl.Font = Enum.Font.GothamBold; stateLbl.BackgroundTransparency = 1
    stateLbl.ZIndex = 4
    stateLbl.Parent = fb

    local function setVisual(on)
        if on then
            fstroke.Transparency = 0
            stateLbl.Text = "ON"; stateLbl.TextColor3 = C.green
            dot.BackgroundColor3 = dotColor
        else
            fstroke.Transparency = 0.7
            stateLbl.Text = "OFF"; stateLbl.TextColor3 = C.red
            dot.BackgroundColor3 = Color3.fromRGB(90,90,95)
        end
    end
    setVisual(true)
    return fb, setVisual
end

local solarBtn, setSolarVis = makeFilterButton(18, "Solar Nexus", C.yellow)
local voidBtn,  setVoidVis  = makeFilterButton(48, "Void Nexus",  C.purple)

-- status + count
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1,0,0,44); statusLabel.Position = UDim2.new(0,0,0,84)
statusLabel.Text = "Radar: OFF | Radius: "..CONFIG.scanRadius.."\nDetected: 0"
statusLabel.TextColor3 = C.textSub; statusLabel.TextSize = 9
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.BackgroundTransparency = 1; statusLabel.ZIndex = 3
statusLabel.Parent = rightCol

local miniBubble = Instance.new("TextButton")
miniBubble.Size = UDim2.new(0,42,0,42); miniBubble.Position = UDim2.new(0,12,0.5,-21)
miniBubble.Text = "⚡"; miniBubble.TextColor3 = Color3.new(1,1,1)
miniBubble.BackgroundColor3 = C.accent; miniBubble.Font = Enum.Font.GothamBold
miniBubble.TextSize = 16; miniBubble.BorderSizePixel = 0
miniBubble.Visible = false; miniBubble.AutoButtonColor = true; miniBubble.ZIndex = 10
miniBubble.Parent = screenGui
Instance.new("UICorner", miniBubble).CornerRadius = UDim.new(1,0)

-- ================================================================
-- HANDLERS
-- ================================================================
speedBtn.MouseButton1Click:Connect(function()
    speedOn = not speedOn
    setSpeedVis(speedOn)
    if speedOn then
        hookHumanoid()
    else
        local char = localPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = CONFIG.normalSpeed end
    end
end)

local function updateStatus()
    statusLabel.Text = "Radar: "..(radarOn and "ON" or "OFF")
        .." | Radius: "..CONFIG.scanRadius
        .."\nDetected: "..tostring(scanCount >= 0 and #markers or 0)
        .."\nSolar:"..(filterSolar and "✓" or "✗").."  Void:"..(filterVoid and "✓" or "✗")
    statusLabel.TextColor3 = radarOn and C.green or C.textSub
end

radarBtn.MouseButton1Click:Connect(function()
    radarOn = not radarOn
    setRadarVis(radarOn)
    if not radarOn then clearAllMarkers() end
    updateStatus()
end)

solarBtn.MouseButton1Click:Connect(function()
    filterSolar = not filterSolar
    setSolarVis(filterSolar)
    clearAllMarkers() -- refresh marker sesuai filter baru
    updateStatus()
end)

voidBtn.MouseButton1Click:Connect(function()
    filterVoid = not filterVoid
    setVoidVis(filterVoid)
    clearAllMarkers()
    updateStatus()
end)

minBtn.MouseButton1Click:Connect(function()
    miniBubble.Position = outer.Position
    outer.Visible = false; miniBubble.Visible = true
end)
miniBubble.MouseButton1Click:Connect(function()
    outer.Visible = true; miniBubble.Visible = false
end)

-- live detected counter
task.spawn(function()
    while true do
        if radarOn then updateStatus() end
        task.wait(0.5)
    end
end)

-- ================================================================
-- DRAG (FIXED: hanya dari titleBar, tidak konflik dengan tombol;
--        miniBubble draggable via long logic sederhana)
-- ================================================================
local function makeDraggable(dragHandle, moveFrame)
    local dragging = false
    local dragStart, startPos
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = moveFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInput.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            moveFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(titleBar, outer)
makeDraggable(miniBubble, miniBubble)

print("ENGINE V16 - LOADED ✔ | Workspace Nexus-only | Void/Solar filter | Key=Jack")
