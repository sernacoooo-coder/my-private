-- Key check: pasang di paling atas
local EXPECTED_KEY = "Jack"

local providedKey
if type(getgenv) == "function" then providedKey = getgenv().key end
if providedKey == nil and type(_G) == "table" then providedKey = _G.key end

if providedKey ~= EXPECTED_KEY then return end

-- =================================================================
-- ENGINE V15 - COMPACT FIXED EDITION (Single-file)
--   - UI kecil seperti V12 (dipertahankan)
--   - Radar HANYA deteksi workspace: "Solar Nexus" & "Void Nexus"
--   - Semua tombol nama (rarity/category/size) DIHAPUS dari UI
--   - Key: Jack
-- =================================================================

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")

local localPlayer = Players.LocalPlayer

local CONFIG = {
    normalSpeed   = 16,
    boostMult     = 3,
    radarInterval = 0.15,
    maxMarkers    = 50,
    scanRadius    = 100,
}

local C = {
    bg=Color3.fromRGB(8,8,10), black=Color3.fromRGB(14,14,16),
    accent=Color3.fromRGB(88,101,242), green=Color3.fromRGB(87,242,135),
    orange=Color3.fromRGB(254,160,60), purple=Color3.fromRGB(180,80,220),
    red=Color3.fromRGB(237,66,69), teal=Color3.fromRGB(40,190,180),
}

local speedOn, radarOn = false, false
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
-- RADAR: only world-spawned Solar Nexus & Void Nexus (workspace)
-- ================================================================
local TARGET_NAMES = { ["Solar Nexus"] = Color3.fromRGB(255,220,80), ["Void Nexus"] = Color3.fromRGB(160,80,255) }

local function clearAllMarkers()
    for part, m in pairs(markers) do
        pcall(function() m:Destroy() end)
        markers[part] = nil
    end
end

local function getWorldNexusParts()
    local partsList = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        local col = TARGET_NAMES[obj.Name]
        if col then
            if obj:IsA("BasePart") then
                partsList[#partsList+1] = obj
            elseif obj:IsA("Model") then
                partsList[#partsList+1] = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            else
                local prim = obj:FindFirstChildWhichIsA("BasePart")
                if prim then partsList[#partsList+1] = prim end
            end
        end
    end
    return partsList
end

local function scan()
    local char = localPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local pos = hrp and hrp.Position or Vector3.zero
    local found = {}

    for _, part in ipairs(getWorldNexusParts()) do
        if part and part:IsA("BasePart") then
            local d = hrp and (part.Position - pos).Magnitude or 0
            if d <= CONFIG.scanRadius then
                found[#found+1] = {part=part, d=d}
            end
        end
    end

    table.sort(found, function(a,b) return a.d < b.d end)

    local keep = {}
    for i = 1, math.min(#found, CONFIG.maxMarkers) do
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
        local col = TARGET_NAMES[part.Name] or Color3.fromRGB(200,210,230)
        -- jika part adalah child, cek parent model juga
        if part.Parent and TARGET_NAMES[part.Parent.Name] then
            col = TARGET_NAMES[part.Parent.Name]
        end
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

-- background loop
task.spawn(function()
    while true do
        if radarOn then pcall(scan) end
        task.wait(CONFIG.radarInterval)
    end
end)

-- ================================================================
-- GUI KECIL (like V12) - filter names removed
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
titleLabel.Text = "⚡ Engine V15"; titleLabel.TextColor3 = Color3.new(1,1,1)
titleLabel.TextSize = 12; titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.BackgroundTransparency = 1

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0,20,0,18); minBtn.Position = UDim2.new(1,-24,0.5,-9)
minBtn.Text = "_"; minBtn.TextColor3 = Color3.new(1,1,1)
minBtn.BackgroundColor3 = Color3.fromRGB(70,80,110)
minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 11; minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0,6)

-- LEFT: icon toggles
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

-- RIGHT: info area (filter names removed)
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

-- Info target list (no toggle buttons)
local infoLabel = Instance.new("TextLabel", rightCol)
infoLabel.Size = UDim2.new(1,0,0,40); infoLabel.Position = UDim2.new(0,0,0,16)
infoLabel.Text = "Target:\n• Solar Nexus\n• Void Nexus"
infoLabel.TextColor3 = C.textMain; infoLabel.TextSize = 10
infoLabel.Font = Enum.Font.GothamBold
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.TextYAlignment = Enum.TextYAlignment.Top
infoLabel.BackgroundTransparency = 1; infoLabel.TextWrapped = true

local statusLabel = Instance.new("TextLabel", rightCol)
statusLabel.Size = UDim2.new(1,0,0,30); statusLabel.Position = UDim2.new(0,0,0,100)
statusLabel.Text = "Radar: OFF | Radius: "..CONFIG.scanRadius
statusLabel.TextColor3 = C.textSub; statusLabel.TextSize = 9
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.BackgroundTransparency = 1; statusLabel.TextWrapped = true

local miniBubble = Instance.new("TextButton", screenGui)
miniBubble.Size = UDim2.new(0,42,0,42); miniBubble.Position = UDim2.new(0,12,0.5,-21)
miniBubble.Text = "⚡"; miniBubble.TextColor3 = Color3.new(1,1,1)
miniBubble.BackgroundColor3 = C.accent; miniBubble.Font = Enum.Font.GothamBold
miniBubble.TextSize = 16; miniBubble.BorderSizePixel = 0; miniBubble.Visible = false
Instance.new("UICorner", miniBubble).CornerRadius = UDim.new(1,0)

-- HANDLERS
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
    statusLabel.Text = "Radar: "..(radarOn and "ON" or "OFF").." | Radius: "..CONFIG.scanRadius
    statusLabel.TextColor3 = radarOn and C.green or C.textSub
    if not radarOn then clearAllMarkers() end
end)

minBtn.MouseButton1Click:Connect(function()
    miniBubble.Position = outer.Position
    outer.Visible = false; miniBubble.Visible = true
end)
miniBubble.MouseButton1Click:Connect(function()
    outer.Visible = true; miniBubble.Visible = false
end)

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

print("ENGINE V15 - LOADED ✔ (UI kecil | Workspace Nexus-only | Key=Jack)")
