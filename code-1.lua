-- =================================================================
-- GEC MINE ANTARCTICA — HYPERDRIVE QUANTUM V4.01 (FIXED)
-- • 3D Round-Joystick Jetpack (Mobile fix — no drift)
-- • Strict AI Radar 200M (Max 30) — lighter scan
-- • Zero-Slip Slope Lock • Instant Interaction
-- • Battery Saver & Potato FPS
-- =================================================================

local EXPECTED_KEY = "Jack"

local providedKey
if type(getgenv) == "function" then providedKey = getgenv().key end
if providedKey == nil and type(_G) == "table" then providedKey = _G.key end
if providedKey ~= EXPECTED_KEY then return end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = localPlayer:WaitForChild("PlayerGui")

pcall(function()
	if setfpscap then setfpscap(999) elseif set_fps_cap then set_fps_cap(999) end
end)

local CONFIG = {
	normalSpeed = 16,
	boostMult = 3,
	jetpackSpeed = 48,
	radarIntervalIdle = 0.22,   -- lebih irit (was 0.12)
	radarIntervalMove = 0.07,   -- tetap responsif (was 0.035)
	moveThresholdSq = 1.2 * 1.2,
	maxMarkers = 30,
	scanRadius = 200,
	scanRadiusSq = 200 * 200,
	cleanupInterval = 4.0,      -- was 3.0
	lightWeightValue = 0.1,
	softFallMaxSpeed = -38,
	voidY = -80,
	groundFriction = 100,
	ingestBatch = 180,          -- batch lebih kecil biar gak spike
}

local AI_WEIGHTS = {
	Rarity = {
		Mythic = 110, Exotic = 95, Legendary = 75,
		Epic = 55, Rare = 35, Uncommon = 20, Common = 10
	},
	Nexus = {
		["Void Nexus"] = 135,
		["Solar Nexus"] = 125,
		["Aether Nexus"] = 120
	},
	FreshSpawnBoost = 45,
	PathAngleFactor = 30,
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
	bg = Color3.fromRGB(10, 11, 15), black = Color3.fromRGB(16, 17, 22),
	accent = Color3.fromRGB(88, 101, 242), green = Color3.fromRGB(87, 242, 135),
	orange = Color3.fromRGB(254, 160, 60), purple = Color3.fromRGB(180, 80, 220),
	red = Color3.fromRGB(237, 66, 69), cyan = Color3.fromRGB(0, 210, 255),
	textMain = Color3.fromRGB(235, 238, 245), textSub = Color3.fromRGB(130, 136, 148),
}

local speedOn, radarOn, boosterOn, lightWeightOn, jetpackOn = false, false, false, false, false
local antiDamageOn = true
local selectedRarities, selectedCategories, selectedNexus = {}, {}, {}
local targetRegistry, targetList = {}, {}
local activeMarkers = {}
local highlightPool = table.create(CONFIG.maxMarkers + 4)

for i = 1, CONFIG.maxMarkers + 4 do
	local hl = Instance.new("Highlight")
	hl.Name = "HyperHL"
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.25
	hl.OutlineTransparency = 0
	hl.Enabled = false
	highlightPool[i] = hl
end

local MAX_FOUND_BUFFER = 64
local foundSlots = table.create(MAX_FOUND_BUFFER)
for i = 1, MAX_FOUND_BUFFER do
	foundSlots[i] = {part = nil, data = nil, dist = 0, aiScore = 0}
end

local keepBuffer = {}
local scanRunning, lastScanClock, lastHrpPos, lastCleanup = false, 0, Vector3.zero, 0
local isMoving = false
local lastSafeCFrame = nil
local lastHealth = 100

-- ==================== HIGHLIGHT POOL ====================
local function acquireHighlight(part, color)
	local hl = table.remove(highlightPool)
	if not hl or not hl.Parent then
		hl = Instance.new("Highlight")
		hl.Name = "HyperHL"
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillTransparency = 0.25
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
	for part in pairs(activeMarkers) do releaseHighlight(part) end
	table.clear(activeMarkers)
end

-- ==================== STRING & TARGET UTILITIES ====================
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
	local ok, attr = pcall(function() return obj:GetAttribute("Value") or obj:GetAttribute("BaseValue") end)
	if ok and attr ~= nil then return attr end
	local v = obj:FindFirstChild("Value") or obj:FindFirstChild("BaseValue")
	if v and (v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("StringValue")) then return v.Value end
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
	while current and current ~= Workspace and depth < 6 do
		local norm = normalizeName(getObjectName(current))
		if norm:find("void nexus", 1, true) then return "Void Nexus"
		elseif norm:find("solar nexus", 1, true) then return "Solar Nexus"
		elseif norm:find("aether nexus", 1, true) then return "Aether Nexus" end
		current = current.Parent
		depth += 1
	end
	return nil
end

local function isCrystalTarget(obj)
	if not obj or isForbiddenObject(obj) then return false end
	local current, depth = obj, 0
	while current and current ~= Workspace and depth < 6 do
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
	while current and current ~= Workspace and depth < 6 do
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
	local r, g, b = tonumber(part:GetAttribute("TierColorR")), tonumber(part:GetAttribute("TierColorG")), tonumber(part:GetAttribute("TierColorB"))
	if r and g and b then return Color3.fromRGB(r, g, b) end
	local rarity = rarityHint or getRarityName(part)
	if rarity and RARITY_COLORS[rarity] then return RARITY_COLORS[rarity] end
	local text = normalizeName(getObjectName(part))
	for key, color in pairs(CRYSTAL_COLORS) do
		if text:find(key, 1, true) then return color end
	end
	return Color3.fromRGB(200, 215, 235)
end

local function getWorldPart(obj)
	if not obj then return nil end
	if obj:IsA("BasePart") then return obj end
	if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true) end
	return nil
end

local function applyLightWeight(obj)
	if not obj or not lightWeightOn then return end
	pcall(function()
		local current, depth = obj, 0
		while current and current ~= Workspace and depth < 6 do
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

local scanRealTime

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
		spawnTime = os.clock(),
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
		if targetList[i].part == part then table.remove(targetList, i) break end
	end
end

-- ==================== INSTANT PICKUP ====================
local processedPrompts = setmetatable({}, { __mode = "k" })
local function processPrompt(obj)
	if not obj or not obj:IsA("ProximityPrompt") or processedPrompts[obj] then return end
	processedPrompts[obj] = true
	pcall(function()
		if obj.HoldDuration and obj.HoldDuration > 0 then obj.HoldDuration = 0 end
		obj.RequiresLineOfSight = false
	end)
end

-- ==================== ULTRA BATTERY OPTIMIZER ====================
local boosterBackup = { effects = {}, savedSettings = {} }

local function stripLagObject(obj)
	if not boosterOn or not obj then return end
	if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
		or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
		pcall(function() obj.Enabled = false end)
	elseif obj:IsA("Decal") or obj:IsA("Texture") then
		pcall(function() obj.Transparency = 1 end)
	elseif obj:IsA("BasePart") or obj:IsA("MeshPart") then
		pcall(function()
			obj.CastShadow = false
			obj.Material = Enum.Material.SmoothPlastic
			obj.Reflectance = 0
		end)
	end
end

-- Ingest lebih pelan (kurangi lag spike startup)
task.spawn(function()
	local ok, desc = pcall(function() return Workspace:GetDescendants() end)
	if not ok or not desc then return end
	local batch = CONFIG.ingestBatch
	for i = 1, #desc do
		local obj = desc[i]
		if obj then
			if obj:IsA("BasePart") or obj:IsA("Model") then
				pcall(registerTarget, obj)
			elseif obj:IsA("ProximityPrompt") then
				pcall(processPrompt, obj)
			end
			if boosterOn then pcall(stripLagObject, obj) end
		end
		if i % batch == 0 then task.wait() end
	end
end)

Workspace.DescendantAdded:Connect(function(obj)
	if not obj then return end
	task.defer(function()
		if not obj.Parent then return end
		if obj:IsA("BasePart") or obj:IsA("Model") then
			pcall(registerTarget, obj)
		elseif obj:IsA("ProximityPrompt") then
			pcall(processPrompt, obj)
		end
		if boosterOn then pcall(stripLagObject, obj) end
	end)
end)

Workspace.DescendantRemoving:Connect(function(obj)
	if obj and obj:IsA("BasePart") then pcall(unregisterTarget, obj) end
end)

-- ==================== AI RADAR ====================
local function passesFilter(data)
	if not data then return false end
	if next(selectedRarities) == nil then return false end
	if not data.rarity or not selectedRarities[data.rarity] then return false end
	if next(selectedNexus) and (not data.nexus or not selectedNexus[data.nexus]) then return false end
	if next(selectedCategories) then
		if not data.category then data.category = getCrystalCategory(data.part) end
		if not data.category or not selectedCategories[data.category] then return false end
	end
	return true
end

local function calculateAIScore(data, dx, dy, dz, distSq, moveDir, lookVec, now)
	local dist = math.sqrt(distSq)
	local baseScore = (data.nexus and AI_WEIGHTS.Nexus[data.nexus])
		or (data.rarity and AI_WEIGHTS.Rarity[data.rarity])
		or 10
	local proximityScore = (1 - (dist / CONFIG.scanRadius)) * 60
	local freshBonus = 0
	if data.spawnTime and (now - data.spawnTime) < 10 then
		freshBonus = (1 - ((now - data.spawnTime) / 10)) * AI_WEIGHTS.FreshSpawnBoost
	end
	local headingBonus = 0
	local headingDir = moveDir.Magnitude > 0.1 and moveDir or lookVec
	local targetDirXZ = Vector3.new(dx, 0, dz)
	if targetDirXZ.Magnitude > 0.1 then
		local dot = headingDir:Dot(targetDirXZ.Unit)
		if dot > 0 then headingBonus = dot * AI_WEIGHTS.PathAngleFactor end
	end
	return baseScore + proximityScore + freshBonus + headingBonus
end

scanRealTime = function()
	if not radarOn or next(selectedRarities) == nil then
		if next(activeMarkers) then clearAllMarkers() end
		return
	end
	local character = localPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp then clearAllMarkers() return end

	local origin = hrp.Position
	local ox, oy, oz = origin.X, origin.Y, origin.Z
	local radiusSq = CONFIG.scanRadiusSq
	local moveDir = hum and hum.MoveDirection or Vector3.zero
	local lookVec = hrp.CFrame.LookVector
	local now = os.clock()

	local foundCount = 0
	local listLen = #targetList
	local maxBuf = MAX_FOUND_BUFFER

	for i = 1, listLen do
		local data = targetList[i]
		local part = data and data.part
		if part and part.Parent then
			local pos = part.Position
			local dx, dy, dz = pos.X - ox, pos.Y - oy, pos.Z - oz
			local distSq = dx * dx + dy * dy + dz * dz
			if distSq <= radiusSq and passesFilter(data) then
				foundCount += 1
				if foundCount <= maxBuf then
					local slot = foundSlots[foundCount]
					slot.part = part
					slot.data = data
					slot.dist = distSq
					slot.aiScore = calculateAIScore(data, dx, dy, dz, distSq, moveDir, lookVec, now)
				end
			end
		end
	end

	local actualFound = math.min(foundCount, maxBuf)
	if actualFound > 1 then
		table.sort(foundSlots, function(a, b)
			if not a or a.aiScore == 0 then return false end
			if not b or b.aiScore == 0 then return true end
			return a.aiScore > b.aiScore
		end)
	end

	table.clear(keepBuffer)
	local activeCount = 0
	for part, pack in pairs(activeMarkers) do
		local valid = false
		if part and part.Parent and pack.hl and pack.rarity and selectedRarities[pack.rarity] then
			local pos = part.Position
			local dx, dy, dz = pos.X - ox, pos.Y - oy, pos.Z - oz
			if (dx * dx + dy * dy + dz * dz) <= radiusSq then
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
		foundSlots[i].dist = 0
		foundSlots[i].aiScore = 0
		foundSlots[i].part = nil
		foundSlots[i].data = nil
	end
end

-- ==================== SPEED MODULE ====================
local function targetSpeed() return CONFIG.normalSpeed * CONFIG.boostMult end
local lastSpeedApply = 0
local speedConn = nil

local function applySpeedSafe(hum)
	if not hum or not speedOn or jetpackOn then return end
	local want = targetSpeed()
	if math.abs(hum.WalkSpeed - want) > 0.5 then
		pcall(function() hum.WalkSpeed = want end)
	end
end

local function hookSpeed()
	if speedConn then speedConn:Disconnect() speedConn = nil end
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	speedConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if not speedOn or jetpackOn then return end
		local now = os.clock()
		if now - lastSpeedApply < 0.08 then return end
		lastSpeedApply = now
		applySpeedSafe(hum)
	end)
	applySpeedSafe(hum)
end

local function unhookSpeed()
	if speedConn then speedConn:Disconnect() speedConn = nil end
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then pcall(function() hum.WalkSpeed = CONFIG.normalSpeed end) end
end

-- ==================== 3D JETPACK (MOBILE FIXED) ====================
local jetpackBV = nil
local jetpackInputVector = Vector2.zero
local jetpackActiveLoop = nil
local stickTouchId = nil -- track touch yang pegang stick (anti geser)

local function createJetpackPhysics(hrp)
	if jetpackBV and jetpackBV.Parent then jetpackBV:Destroy() end
	jetpackBV = Instance.new("BodyVelocity")
	jetpackBV.Name = "QuantumJetpackBV"
	jetpackBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	jetpackBV.Velocity = Vector3.zero
	jetpackBV.Parent = hrp
end

local function removeJetpackPhysics()
	if jetpackBV then
		pcall(function() jetpackBV:Destroy() end)
		jetpackBV = nil
	end
end

local function enableJetpack()
	jetpackOn = true
	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	hum.PlatformStand = true
	createJetpackPhysics(hrp)
	lastSafeCFrame = hrp.CFrame

	if jetpackActiveLoop then jetpackActiveLoop:Disconnect() end
	jetpackActiveLoop = RunService.PreSimulation:Connect(function()
		if not jetpackOn or not hrp or not hrp.Parent then return end
		lastSafeCFrame = hrp.CFrame

		local camCF = camera.CFrame
		local look = camCF.LookVector
		local right = camCF.RightVector
		local moveDirection = Vector3.zero
		if jetpackInputVector.Magnitude > 0.05 then
			moveDirection = (look * jetpackInputVector.Y) + (right * jetpackInputVector.X)
		end
		if moveDirection.Magnitude > 0.05 then
			jetpackBV.Velocity = moveDirection.Unit * CONFIG.jetpackSpeed
		else
			jetpackBV.Velocity = Vector3.zero
		end
	end)
end

local function disableJetpack()
	jetpackOn = false
	if jetpackActiveLoop then jetpackActiveLoop:Disconnect() jetpackActiveLoop = nil end
	removeJetpackPhysics()
	jetpackInputVector = Vector2.zero
	stickTouchId = nil

	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hrp and hum then
		lastSafeCFrame = hrp.CFrame
		hrp.AssemblyLinearVelocity = Vector3.zero
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	if speedOn then hookSpeed() end
end

-- ==================== ANTI-SLIP & ANTI-DAMAGE ====================
local antiConn = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function clearAntiConns()
	for _, c in ipairs(antiConn) do pcall(function() c:Disconnect() end) end
	table.clear(antiConn)
end

local function applyAntiSlipProperties(char, hum)
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part.CustomPhysicalProperties = PhysicalProperties.new(2.0, CONFIG.groundFriction, 0, 100, 100)
			end)
		end
	end
	if hum then
		pcall(function()
			hum.MaxSlopeAngle = 89.5
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		end)
	end
end

local function hookAntiDamage(char)
	clearAntiConns()
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then return end

	lastHealth = hum.Health
	lastSafeCFrame = hrp.CFrame
	applyAntiSlipProperties(char, hum)

	table.insert(antiConn, hum.HealthChanged:Connect(function(h)
		if not antiDamageOn then return end
		if h < lastHealth and h > 0 then
			pcall(function() hum.Health = math.max(lastHealth, hum.MaxHealth) end)
		end
		if h > lastHealth then lastHealth = h end
		if hum.Health >= hum.MaxHealth then lastHealth = hum.MaxHealth end
	end))

	table.insert(antiConn, RunService.PreSimulation:Connect(function()
		if not antiDamageOn or jetpackOn then return end
		local c = localPlayer.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if not h or not root then return end

		local state = h:GetState()
		local pos = root.Position
		local vel = root.AssemblyLinearVelocity
		local moveDir = h.MoveDirection

		rayParams.FilterDescendantsInstances = {c}
		local groundRay = Workspace:Raycast(pos, Vector3.new(0, -5.5, 0), rayParams)
		local isGrounded = groundRay ~= nil or h.FloorMaterial ~= Enum.Material.Air

		if isGrounded then
			if vel.Y > -5 then lastSafeCFrame = root.CFrame end
			if moveDir.Magnitude < 0.05 then
				root.AssemblyLinearVelocity = Vector3.new(0, math.clamp(vel.Y, -2, 2), 0)
			else
				local targetSpeedVal = speedOn and targetSpeed() or CONFIG.normalSpeed
				local desired = moveDir * targetSpeedVal
				root.AssemblyLinearVelocity = Vector3.new(desired.X, vel.Y, desired.Z)
			end
		end

		if state == Enum.HumanoidStateType.Freefall and not isGrounded then
			if vel.Y < CONFIG.softFallMaxSpeed then
				root.AssemblyLinearVelocity = Vector3.new(vel.X, CONFIG.softFallMaxSpeed, vel.Z)
			end
		end

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
	local char = localPlayer.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				pcall(function() part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5) end)
			end
		end
	end
end

localPlayer.CharacterAdded:Connect(function(char)
	task.wait(0.35)
	if jetpackOn then disableJetpack() end
	if speedOn then hookSpeed() end
	if antiDamageOn then hookAntiDamage(char) end
end)

-- Heartbeat radar (interval lebih irit)
RunService.Heartbeat:Connect(function()
	local now = os.clock()
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
				if data and data.part then pcall(unregisterTarget, data.part)
				else table.remove(targetList, i) end
			end
		end
	end
end)

-- ==================== POTATO FPS ====================
local function enableGameBooster()
	boosterBackup.globalShadows = Lighting.GlobalShadows
	boosterBackup.fogEnd = Lighting.FogEnd
	boosterBackup.brightness = Lighting.Brightness
	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.FogEnd = 9e9
		Lighting.FogStart = 0
		Lighting.Brightness = 1.5
		Lighting.EnvironmentDiffuseScale = 0
		Lighting.EnvironmentSpecularScale = 0
	end)
	table.clear(boosterBackup.effects)
	for _, effect in ipairs(Lighting:GetChildren()) do
		if effect:IsA("PostProcessEffect") or effect:IsA("BloomEffect") or effect:IsA("BlurEffect")
			or effect:IsA("ColorCorrectionEffect") or effect:IsA("SunRaysEffect") or effect:IsA("DepthOfFieldEffect")
			or effect:IsA("Atmosphere") or effect:IsA("Clouds") or effect:IsA("Sky") then
			boosterBackup.effects[effect] = effect.Enabled
			pcall(function() effect.Enabled = false end)
		end
	end
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		boosterBackup.terrainDecoration = terrain.Decoration
		pcall(function()
			terrain.Decoration = false
			terrain.WaterWaveSize = 0
			terrain.WaterWaveSpeed = 0
			terrain.WaterReflectance = 0
			terrain.WaterTransparency = 0
		end)
	end
	pcall(function()
		if UserGameSettings then
			boosterBackup.savedSettings.SavedQualityLevel = UserGameSettings.SavedQualityLevel
			UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
		end
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
end

local function disableGameBooster()
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
	if terrain and boosterBackup.terrainDecoration ~= nil then
		pcall(function() terrain.Decoration = boosterBackup.terrainDecoration end)
	end
	pcall(function()
		if UserGameSettings and boosterBackup.savedSettings.SavedQualityLevel then
			UserGameSettings.SavedQualityLevel = boosterBackup.savedSettings.SavedQualityLevel
		end
	end)
end

-- ==================== GUI ====================
local old = playerGui:FindFirstChild("GecMineAntarctica") or playerGui:FindFirstChild("EngineGUI")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GecMineAntarctica"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 9999
screenGui.Parent = playerGui

local outer = Instance.new("Frame", screenGui)
outer.Size = UDim2.new(0, 440, 0, 390)
outer.Position = UDim2.new(0, 15, 0.5, -195)
outer.BackgroundColor3 = C.bg
outer.BorderSizePixel = 0
outer.Active = true
Instance.new("UICorner", outer).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", outer).Color = Color3.fromRGB(40, 42, 54)

local titleBar = Instance.new("Frame", outer)
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = C.accent
titleBar.BackgroundTransparency = 0.2
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local tbFix = Instance.new("Frame", titleBar)
tbFix.Size = UDim2.new(1, 0, 0, 12)
tbFix.Position = UDim2.new(0, 0, 1, -12)
tbFix.BackgroundColor3 = C.accent
tbFix.BackgroundTransparency = 0.2
tbFix.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(1, -55, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.Text = "❄ GEC MINE ANTARCTICA • V4.01 FIXED"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.TextSize = 11
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.BackgroundTransparency = 1

local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0, 22, 0, 20)
minBtn.Position = UDim2.new(1, -28, 0.5, -10)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 80)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 10
minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local leftCol = Instance.new("Frame", outer)
leftCol.Size = UDim2.new(0, 50, 1, -40)
leftCol.Position = UDim2.new(0, 6, 0, 34)
leftCol.BackgroundTransparency = 1

local function makeTabButton(yPos, icon, gradA, gradB)
	local btn = Instance.new("TextButton", leftCol)
	btn.Size = UDim2.new(1, 0, 0, 42)
	btn.Position = UDim2.new(0, 0, 0, yPos)
	btn.Text = icon
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 18
	btn.Font = Enum.Font.GothamBold
	btn.BackgroundColor3 = C.black
	btn.BorderSizePixel = 0
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = Color3.fromRGB(40, 42, 54)
	stroke.Thickness = 1.2
	local grad = Instance.new("UIGradient", btn)
	grad.Color = ColorSequence.new(gradB, gradB)
	grad.Transparency = NumberSequence.new(0.85)
	local function setVisual(on)
		if on then
			grad.Color = ColorSequence.new(gradA, gradB)
			grad.Transparency = NumberSequence.new(0.15)
			stroke.Color = gradB
		else
			grad.Color = ColorSequence.new(gradB, gradB)
			grad.Transparency = NumberSequence.new(0.85)
			stroke.Color = Color3.fromRGB(40, 42, 54)
		end
	end
	return btn, setVisual
end

local speedBtn, setSpeedVis = makeTabButton(0, "⚡", C.accent, C.cyan)
local jetpackBtn, setJetpackVis = makeTabButton(48, "🚀", C.purple, C.orange)
local radarBtn, setRadarVis = makeTabButton(96, "◎", C.orange, C.red)
local settingsBtn, setSettingsVis = makeTabButton(144, "⚙", C.green, C.cyan)

local divider = Instance.new("Frame", outer)
divider.Size = UDim2.new(0, 1, 1, -44)
divider.Position = UDim2.new(0, 62, 0, 36)
divider.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
divider.BorderSizePixel = 0

local rightCol = Instance.new("Frame", outer)
rightCol.Size = UDim2.new(1, -74, 1, -44)
rightCol.Position = UDim2.new(0, 68, 0, 36)
rightCol.BackgroundTransparency = 1

-- RADAR PAGE
local radarPage = Instance.new("Frame", rightCol)
radarPage.Size = UDim2.new(1, 0, 1, 0)
radarPage.BackgroundTransparency = 1
radarPage.Visible = true

local fTitle = Instance.new("TextLabel", radarPage)
fTitle.Size = UDim2.new(1, -60, 0, 14)
fTitle.Text = "FILTER RARITIES (MAX 30 • 200M STRICT)"
fTitle.TextColor3 = C.purple
fTitle.TextSize = 9
fTitle.Font = Enum.Font.GothamBold
fTitle.TextXAlignment = Enum.TextXAlignment.Left
fTitle.BackgroundTransparency = 1

local radarStatus
local radarToggleBtn = Instance.new("TextButton", radarPage)
radarToggleBtn.Size = UDim2.new(0, 56, 0, 16)
radarToggleBtn.Position = UDim2.new(1, -56, 0, -2)
radarToggleBtn.TextColor3 = Color3.new(1, 1, 1)
radarToggleBtn.TextSize = 8
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
		radarStatus.Text = "AI 200M RADAR • MAX 30 TARGETS • ON"
		lastScanClock = 0
		task.defer(function() pcall(scanRealTime) end)
	else
		radarStatus.Text = "AI 200M RADAR • OFF"
		clearAllMarkers()
	end
end)

local catScroll = Instance.new("ScrollingFrame", radarPage)
catScroll.Size = UDim2.new(1, 0, 0, 48)
catScroll.Position = UDim2.new(0, 0, 0, 16)
catScroll.BackgroundTransparency = 1
catScroll.BorderSizePixel = 0
catScroll.ScrollingDirection = Enum.ScrollingDirection.XY
catScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
catScroll.ScrollBarThickness = 2

local catGrid = Instance.new("UIGridLayout", catScroll)
catGrid.CellSize = UDim2.new(0, 58, 0, 14)
catGrid.CellPadding = UDim2.new(0, 3, 0, 3)

local toggleButtons = {}
local updateFilterStatus

local function makeFilterButton(name, color, getState, setState)
	local b = Instance.new("TextButton", catScroll)
	b.Text = name
	b.TextColor3 = color
	b.TextSize = 7.5
	b.Font = Enum.Font.GothamBold
	b.BackgroundColor3 = C.black
	b.BorderSizePixel = 0
	b.TextTruncate = Enum.TextTruncate.AtEnd
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	toggleButtons[name] = { btn = b, get = getState, color = color }
	b.MouseButton1Click:Connect(function()
		setState()
		b.BackgroundColor3 = getState() and color or C.black
		updateFilterStatus()
		if radarOn then
			if next(selectedRarities) == nil then clearAllMarkers()
			else task.defer(function() pcall(scanRealTime) end) end
		end
	end)
end

for _, rarity in ipairs(RARITIES) do
	makeFilterButton(RARITY_UI_LABELS[rarity], RARITY_COLORS[rarity],
		function() return selectedRarities[rarity] == true end,
		function() selectedRarities[rarity] = not selectedRarities[rarity] or nil end)
end
for _, nexus in ipairs(NEXUS) do
	makeFilterButton(nexus, RARITY_COLORS[nexus],
		function() return selectedNexus[nexus] == true end,
		function() selectedNexus[nexus] = not selectedNexus[nexus] or nil end)
end
for _, category in ipairs(CATEGORIES) do
	makeFilterButton(category, RARITY_COLORS[category],
		function() return selectedCategories[category] == true end,
		function() selectedCategories[category] = not selectedCategories[category] or nil end)
end

radarStatus = Instance.new("TextLabel", radarPage)
radarStatus.Size = UDim2.new(1, 0, 0, 20)
radarStatus.Position = UDim2.new(0, 0, 0, 70)
radarStatus.Text = "AI 200M RADAR • OFF"
radarStatus.TextColor3 = C.textMain
radarStatus.TextSize = 8.5
radarStatus.Font = Enum.Font.GothamBold
radarStatus.TextXAlignment = Enum.TextXAlignment.Left
radarStatus.BackgroundColor3 = C.black
radarStatus.BorderSizePixel = 0
Instance.new("UICorner", radarStatus).CornerRadius = UDim.new(0, 6)
Instance.new("UIPadding", radarStatus).PaddingLeft = UDim.new(0, 6)

local resetBtn = Instance.new("TextButton", radarPage)
resetBtn.Size = UDim2.new(1, 0, 0, 20)
resetBtn.Position = UDim2.new(0, 0, 0, 94)
resetBtn.Text = "↺ RESET ALL FILTERS"
resetBtn.TextColor3 = Color3.new(1, 1, 1)
resetBtn.BackgroundColor3 = C.red
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 8.5
resetBtn.BorderSizePixel = 0
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)

local filterStatus = Instance.new("TextLabel", radarPage)
filterStatus.Size = UDim2.new(1, 0, 0, 32)
filterStatus.Position = UDim2.new(0, 0, 0, 118)
filterStatus.Text = ""
filterStatus.TextColor3 = C.green
filterStatus.TextSize = 8.5
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
pTitle.Size = UDim2.new(1, 0, 0, 14)
pTitle.Text = "⚙ QUANTUM PERFORMANCE & PHYSICS"
pTitle.TextColor3 = C.green
pTitle.TextSize = 9.5
pTitle.Font = Enum.Font.GothamBold
pTitle.TextXAlignment = Enum.TextXAlignment.Left
pTitle.BackgroundTransparency = 1

local function makeSettingCard(parent, y, title, subtitle)
	local card = Instance.new("Frame", parent)
	card.Size = UDim2.new(1, 0, 0, 40)
	card.Position = UDim2.new(0, 0, 0, y)
	card.BackgroundColor3 = C.black
	card.BorderSizePixel = 0
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
	local info = Instance.new("TextLabel", card)
	info.Size = UDim2.new(1, -65, 1, 0)
	info.Position = UDim2.new(0, 8, 0, 0)
	info.Text = title .. "\n" .. subtitle
	info.TextColor3 = C.textMain
	info.TextSize = 8
	info.Font = Enum.Font.GothamBold
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Center
	info.BackgroundTransparency = 1
	local btn = Instance.new("TextButton", card)
	btn.Size = UDim2.new(0, 52, 0, 20)
	btn.Position = UDim2.new(1, -58, 0.5, -10)
	btn.Text = "OFF"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 7.5
	btn.Font = Enum.Font.GothamBold
	btn.BackgroundColor3 = C.red
	btn.BorderSizePixel = 0
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
	return btn
end

local boosterToggleBtn = makeSettingCard(settingsPage, 16, "⚡ ULTRA FPS & BATTERY SAVER", "Potato Mode • Zero Lag Spike")
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

local weightToggleBtn = makeSettingCard(settingsPage, 60, "🪶 LIGHTWEIGHT CRYSTALS", "CrystalWeight = 0.1")
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

local antiToggleBtn = makeSettingCard(settingsPage, 104, "🛡 ANTI DAMAGE & 100% SLOPE LOCK", "Tebing Curam Es Bebas Luncur")
antiToggleBtn.Text = "ANTI ON"
antiToggleBtn.BackgroundColor3 = C.green
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

-- ==================== JETPACK JOYSTICK (FIXED MOBILE) ====================
-- Frame joystick TIDAK di-drag saat stick dipakai
local joystickFrame = Instance.new("Frame", screenGui)
joystickFrame.Size = UDim2.new(0, 120, 0, 120)
joystickFrame.Position = UDim2.new(1, -145, 1, -155)
joystickFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 26)
joystickFrame.BackgroundTransparency = 0.3
joystickFrame.BorderSizePixel = 0
joystickFrame.Visible = false
joystickFrame.Active = true
Instance.new("UICorner", joystickFrame).CornerRadius = UDim.new(1, 0)
local jStroke = Instance.new("UIStroke", joystickFrame)
jStroke.Color = C.cyan
jStroke.Thickness = 2

-- Handle kecil di atas untuk GESER POSISI joystick (bukan whole frame)
local dragHandle = Instance.new("TextButton", joystickFrame)
dragHandle.Size = UDim2.new(1, 0, 0, 18)
dragHandle.Position = UDim2.new(0, 0, 0, -22)
dragHandle.BackgroundColor3 = C.accent
dragHandle.BackgroundTransparency = 0.3
dragHandle.Text = "⋮⋮ geser"
dragHandle.TextColor3 = Color3.new(1,1,1)
dragHandle.TextSize = 9
dragHandle.Font = Enum.Font.GothamBold
dragHandle.BorderSizePixel = 0
Instance.new("UICorner", dragHandle).CornerRadius = UDim.new(0, 6)

local jCenter = Instance.new("Frame", joystickFrame)
jCenter.Size = UDim2.new(0, 48, 0, 48)
jCenter.Position = UDim2.new(0.5, -24, 0.5, -24)
jCenter.BackgroundColor3 = C.accent
jCenter.BorderSizePixel = 0
jCenter.ZIndex = 2
Instance.new("UICorner", jCenter).CornerRadius = UDim.new(1, 0)

local jLabel = Instance.new("TextLabel", joystickFrame)
jLabel.Size = UDim2.new(1, 0, 0, 12)
jLabel.Position = UDim2.new(0, 0, 1, 4)
jLabel.Text = "🚀 3D JETPACK"
jLabel.TextColor3 = C.cyan
jLabel.TextSize = 8
jLabel.Font = Enum.Font.GothamBold
jLabel.BackgroundTransparency = 1

local maxRadius = 42
local draggingStick = false

local function getStickCenter()
	local abs = joystickFrame.AbsolutePosition
	local size = joystickFrame.AbsoluteSize
	return Vector2.new(abs.X + size.X * 0.5, abs.Y + size.Y * 0.5)
end

local function updateStickPosition(inputPos)
	local center = getStickCenter()
	local delta = Vector2.new(inputPos.X - center.X, inputPos.Y - center.Y)
	local dist = delta.Magnitude
	if dist > maxRadius then
		delta = delta.Unit * maxRadius
	end
	jCenter.Position = UDim2.new(0.5, delta.X - 24, 0.5, delta.Y - 24)
	jetpackInputVector = Vector2.new(delta.X / maxRadius, -(delta.Y / maxRadius))
end

local function resetStickPosition()
	draggingStick = false
	stickTouchId = nil
	jCenter.Position = UDim2.new(0.5, -24, 0.5, -24)
	jetpackInputVector = Vector2.zero
end

-- Stick input: HANYA di area joystickFrame, track input object
joystickFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		-- Jangan ambil input di drag handle
		local pos = input.Position
		local handleAbs = dragHandle.AbsolutePosition
		local handleSize = dragHandle.AbsoluteSize
		if pos.X >= handleAbs.X and pos.X <= handleAbs.X + handleSize.X
			and pos.Y >= handleAbs.Y and pos.Y <= handleAbs.Y + handleSize.Y then
			return
		end
		draggingStick = true
		stickTouchId = input
		updateStickPosition(pos)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not draggingStick then return end
	-- Hanya ikuti input yang sama (anti multi-touch geser)
	if stickTouchId and input ~= stickTouchId
		and input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		updateStickPosition(input.Position)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not draggingStick then return end
	-- Hanya reset kalau input yang memegang stick yang lepas
	if input == stickTouchId
		or input.UserInputType == Enum.UserInputType.MouseButton1 then
		resetStickPosition()
	end
end)

-- Drag HANYA via handle (bukan whole joystick) — fix geser-geser di HP
do
	local d, s, p
	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			d = true
			s = input.Position
			p = joystickFrame.Position
		end
	end)
	dragHandle.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			d = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if d and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - s
			joystickFrame.Position = UDim2.new(p.X.Scale, p.X.Offset + delta.X, p.Y.Scale, p.Y.Offset + delta.Y)
		end
	end)
end

-- Sidebar
speedBtn.MouseButton1Click:Connect(function()
	speedOn = not speedOn
	setSpeedVis(speedOn)
	if speedOn then hookSpeed() else unhookSpeed() end
end)

jetpackBtn.MouseButton1Click:Connect(function()
	if jetpackOn then
		disableJetpack()
		setJetpackVis(false)
		joystickFrame.Visible = false
	else
		enableJetpack()
		setJetpackVis(true)
		joystickFrame.Visible = true
	end
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
miniBubble.Size = UDim2.new(0, 46, 0, 46)
miniBubble.Position = UDim2.new(0, 15, 0.5, -23)
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
-- joystickFrame TIDAK makeDraggable penuh (hanya handle) → fix HP

function updateFilterStatus()
	local parts = {}
	local rCount = 0
	for _ in pairs(selectedRarities) do rCount += 1 end
	if rCount > 0 then table.insert(parts, rCount .. " Rarity") end
	local nCount = 0
	for _ in pairs(selectedNexus) do nCount += 1 end
	if nCount > 0 then table.insert(parts, nCount .. " Nexus") end
	local cCount = 0
	for _ in pairs(selectedCategories) do cCount += 1 end
	if cCount > 0 then table.insert(parts, cCount .. " Kategori") end
	filterStatus.Text = #parts > 0 and ("Filter: " .. table.concat(parts, " | ")) or "Filter: SEMUA NONAKTIF"
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

updateFilterStatus()
refreshToggles()
refreshRadarToggle()
if localPlayer.Character then hookAntiDamage(localPlayer.Character) end

print("❄ GEC MINE ANTARCTICA V4.01 FIXED | Lag↓ FPS↑ Jetpack HP stable")
