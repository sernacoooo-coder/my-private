-- =================================================================
-- GEC MINE ANTARCTICA — HYPERDRIVE QUANTUM V5.5 (ULTRA OPTIMIZED)
-- • Radius Radar Strict 140M (Zero Lag & Manhattan Culling)
-- • Instant Mine Engine (100% Fast Break & Multi-Hit Toggle)
-- • Filter Rarity Baru "Ekzotis / Eksotis"
-- • Extreme Lag Spike Fix & Memory Leak Eliminator
-- • Smooth Anti-Slip & Godmode Anti-Damage
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
	scanRadius = 140,
	scanRadiusSq = 140 * 140,
	radarIntervalIdle = 0.15,
	radarIntervalMove = 0.05,
	moveThresholdSq = 1.0,
	maxMarkers = 20,
	cleanupInterval = 3.0,
	lightWeightValue = 0.1,
	safeFallVelocity = -35,
	voidThresholdY = -70,
	ingestBatch = 120,
	mineReachDist = 20,
}

local AI_WEIGHTS = {
	Rarity = {
		Mythic = 120, Exotic = 100, Legendary = 80,
		Epic = 60, Rare = 40, Uncommon = 25, Common = 10
	},
	Nexus = {
		["Void Nexus"] = 150,
		["Solar Nexus"] = 140,
		["Aether Nexus"] = 130
	},
	FreshSpawnBoost = 50,
	PathAngleFactor = 35,
}

local RARITIES = {"Exotic", "Legendary", "Rare", "Uncommon", "Common", "Epic", "Mythic"}
local RARITY_UI_LABELS = {
	Exotic = "Ekzotis", Legendary = "Legendaris", Rare = "Langka",
	Uncommon = "Tidak Biasa", Common = "Biasa", Epic = "Epik", Mythic = "Mistik",
}
local RARITY_ALIASES = {
	exotic = "Exotic", eksotis = "Exotic", ekzotis = "Exotic",
	legendary = "Legendary", legendaris = "Legendary",
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
	bg = Color3.fromRGB(12, 14, 18), black = Color3.fromRGB(18, 20, 26),
	accent = Color3.fromRGB(88, 101, 242), green = Color3.fromRGB(87, 242, 135),
	orange = Color3.fromRGB(254, 160, 60), purple = Color3.fromRGB(180, 80, 220),
	red = Color3.fromRGB(237, 66, 69), cyan = Color3.fromRGB(0, 210, 255),
	textMain = Color3.fromRGB(235, 238, 245), textSub = Color3.fromRGB(130, 136, 148),
}

-- State Variables
local radarOn = false
local boosterOn = false
local lightWeightOn = false
local antiDamageOn = true
local instantMineOn = false

local selectedRarities = {}
local selectedCategories = {}
local selectedNexus = {}

local targetRegistry = {}
local targetList = {}
local activeMarkers = {}

-- Object Pool Highlights
local highlightPool = table.create(CONFIG.maxMarkers + 2)
for i = 1, CONFIG.maxMarkers + 2 do
	local hl = Instance.new("Highlight")
	hl.Name = "QuantumHL"
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.3
	hl.OutlineTransparency = 0.1
	hl.Enabled = false
	highlightPool[i] = hl
end

local MAX_FOUND_BUFFER = 36
local foundSlots = table.create(MAX_FOUND_BUFFER)
for i = 1, MAX_FOUND_BUFFER do
	foundSlots[i] = {part = nil, data = nil, distSq = 0, aiScore = 0}
end

local keepBuffer = {}
local scanRunning, lastScanClock, lastHrpPos, lastCleanup = false, 0, Vector3.zero, 0
local isMoving = false
local lastSafeGroundCFrame = nil
local lastHealth = 100

-- ==================== HIGHLIGHT POOL ====================
local function acquireHighlight(part, color)
	local hl = table.remove(highlightPool)
	if not hl or not hl.Parent then
		hl = Instance.new("Highlight")
		hl.Name = "QuantumHL"
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillTransparency = 0.3
		hl.OutlineTransparency = 0.1
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

-- ==================== TARGET IDENTIFIER & CACHE ====================
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
	while current and current ~= Workspace and depth < 5 do
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
	while current and current ~= Workspace and depth < 5 do
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
	"tidak biasa", "legendaris", "uncommon", "legendary",
	"ekzotis", "eksotis", "exotic", "mythic", "mistik",
	"langka", "biasa", "common", "epik", "rare", "epic",
}

local function getRarityName(part)
	if not part then return nil end
	local current, depth = part, 0
	while current and current ~= Workspace and depth < 5 do
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
		while current and current ~= Workspace and depth < 5 do
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

-- ==================== INSTANT MINE & PICKUP ENGINE ====================
local processedPrompts = setmetatable({}, { __mode = "k" })

local function applyInstantMine(obj)
	if not obj then return end
	pcall(function()
		-- Set health/hits attribute to break instant
		if instantMineOn then
			if obj:GetAttribute("Health") ~= nil then obj:SetAttribute("Health", 0) end
			if obj:GetAttribute("Hp") ~= nil then obj:SetAttribute("Hp", 0) end
			if obj:GetAttribute("HitsLeft") ~= nil then obj:SetAttribute("HitsLeft", 0) end
			local hpVal = obj:FindFirstChild("Health") or obj:FindFirstChild("Hp")
			if hpVal and (hpVal:IsA("NumberValue") or hpVal:IsA("IntValue")) then hpVal.Value = 0 end
		end
	end)
end

local function processPrompt(obj)
	if not obj or not obj:IsA("ProximityPrompt") or processedPrompts[obj] then return end
	processedPrompts[obj] = true
	pcall(function()
		obj.HoldDuration = 0
		obj.RequiresLineOfSight = false
		if instantMineOn then
			obj.MaxActivationDistance = math.max(obj.MaxActivationDistance, CONFIG.mineReachDist)
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
	local category = getCrystalCategory(part)
	local data = {
		part = part,
		nexus = nexus,
		crystal = crystal,
		rarity = rarity,
		category = category,
		color = resolveColor(part, nexus, rarity),
		spawnTime = os.clock(),
	}
	targetRegistry[part] = data
	table.insert(targetList, data)
	if lightWeightOn then applyLightWeight(obj) end
	if instantMineOn then applyInstantMine(obj) end
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

-- Smooth Timesliced Workspace Ingestion (Zero Lag Spike)
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
	end)
end)

Workspace.DescendantRemoving:Connect(function(obj)
	if obj and obj:IsA("BasePart") then pcall(unregisterTarget, obj) end
end)

-- Tool Auto-Hit / Instant-Mine Hook
local function hookTool(tool)
	if not tool or not tool:IsA("Tool") then return end
	tool.Activated:Connect(function()
		if not instantMineOn then return end
		local char = localPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local pPos = hrp.Position
		local reachSq = CONFIG.mineReachDist * CONFIG.mineReachDist
		for i = 1, #targetList do
			local data = targetList[i]
			local part = data and data.part
			if part and part.Parent then
				local pos = part.Position
				local dx, dy, dz = pos.X - pPos.X, pos.Y - pPos.Y, pos.Z - pPos.Z
				if (dx * dx + dy * dy + dz * dz) <= reachSq then
					applyInstantMine(part)
					if part.Parent then applyInstantMine(part.Parent) end
					for _, pr in ipairs(part:GetDescendants()) do
						if pr:IsA("ProximityPrompt") then
							pcall(function()
								pr.HoldDuration = 0
								if fireproximityprompt then fireproximityprompt(pr, 0) end
							end)
						end
					end
				end
			end
		end
	end)
end

local function hookCharacterTools(char)
	if not char then return end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then hookTool(child) end
	end)
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then hookTool(child) end
	end
	local bp = localPlayer:FindFirstChild("Backpack")
	if bp then
		bp.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then hookTool(child) end
		end)
		for _, child in ipairs(bp:GetChildren()) do
			if child:IsA("Tool") then hookTool(child) end
		end
	end
end

-- ==================== FAST AI RADAR (140M STRICT) ====================
local function passesFilter(data)
	if not data then return false end
	if next(selectedRarities) == nil then return false end
	if not data.rarity or not selectedRarities[data.rarity] then return false end
	if next(selectedNexus) and (not data.nexus or not selectedNexus[data.nexus]) then return false end
	if next(selectedCategories) and (not data.category or not selectedCategories[data.category]) then return false end
	return true
end

local function calculateAIScore(data, distSq, headingDir, dx, dz, now)
	local dist = math.sqrt(distSq)
	local baseScore = (data.nexus and AI_WEIGHTS.Nexus[data.nexus])
		or (data.rarity and AI_WEIGHTS.Rarity[data.rarity])
		or 10
	local proximityScore = (1 - (dist / 140)) * 60
	local freshBonus = 0
	if data.spawnTime and (now - data.spawnTime) < 8 then
		freshBonus = (1 - ((now - data.spawnTime) / 8)) * AI_WEIGHTS.FreshSpawnBoost
	end
	local headingBonus = 0
	local magXZ = dx * dx + dz * dz
	if magXZ > 0.04 and headingDir.Magnitude > 0.1 then
		local invMag = 1 / math.sqrt(magXZ)
		local dot = headingDir.X * (dx * invMag) + headingDir.Z * (dz * invMag)
		if dot > 0 then headingBonus = dot * AI_WEIGHTS.PathAngleFactor end
	end
	return baseScore + proximityScore + freshBonus + headingBonus
end

local function scanRealTime()
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
	local radius = 140
	local radiusSq = CONFIG.scanRadiusSq
	local moveDir = hum and hum.MoveDirection or Vector3.zero
	local headingDir = moveDir.Magnitude > 0.1 and moveDir or hrp.CFrame.LookVector
	local now = os.clock()

	local foundCount = 0
	local listLen = #targetList
	local maxBuf = MAX_FOUND_BUFFER

	for i = 1, listLen do
		local data = targetList[i]
		local part = data and data.part
		if part and part.Parent then
			local pos = part.Position
			local dx = pos.X - ox
			local dz = pos.Z - oz
			-- Manhattan Culling (Fast Exit)
			if math.abs(dx) <= radius and math.abs(dz) <= radius then
				local dy = pos.Y - oy
				if math.abs(dy) <= radius then
					local distSq = dx * dx + dy * dy + dz * dz
					if distSq <= radiusSq and passesFilter(data) then
						foundCount += 1
						if foundCount <= maxBuf then
							local slot = foundSlots[foundCount]
							slot.part = part
							slot.data = data
							slot.distSq = distSq
							slot.aiScore = calculateAIScore(data, distSq, headingDir, dx, dz, now)
						end
					end
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
		local s = foundSlots[i]
		s.distSq = 0
		s.aiScore = 0
		s.part = nil
		s.data = nil
	end
end

-- ==================== SMOOTH ANTI-SLIP & ANTI-DAMAGE ====================
local antiConn = {}
local groundRayParams = RaycastParams.new()
groundRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function clearAntiConns()
	for _, c in ipairs(antiConn) do pcall(function() c:Disconnect() end) end
	table.clear(antiConn)
end

local function applyCharacterPhysics(char, hum)
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		pcall(function()
			hrp.CustomPhysicalProperties = PhysicalProperties.new(1.0, 1.2, 0, 10, 10)
		end)
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
	local hum = char:WaitForChild("Humanoid", 3)
	local hrp = char:WaitForChild("HumanoidRootPart", 3)
	if not hum or not hrp then return end

	lastHealth = hum.Health
	lastSafeGroundCFrame = hrp.CFrame
	applyCharacterPhysics(char, hum)
	hookCharacterTools(char)

	-- Godmode HP Protection
	table.insert(antiConn, hum.HealthChanged:Connect(function(newHealth)
		if not antiDamageOn then return end
		if newHealth < lastHealth and newHealth > 0 then
			pcall(function() hum.Health = hum.MaxHealth end)
		end
		lastHealth = math.max(hum.Health, hum.MaxHealth)
	end))

	-- Physics Fall & Void Protection
	table.insert(antiConn, RunService.PreSimulation:Connect(function()
		if not antiDamageOn then return end
		local c = localPlayer.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if not h or not root then return end

		local pos = root.Position
		local vel = root.AssemblyLinearVelocity

		groundRayParams.FilterDescendantsInstances = {c}
		local rayResult = Workspace:Raycast(pos, Vector3.new(0, -6, 0), groundRayParams)
		local isGrounded = rayResult ~= nil or h.FloorMaterial ~= Enum.Material.Air

		if isGrounded then
			if vel.Y > -4 then
				lastSafeGroundCFrame = root.CFrame
			end
		else
			if vel.Y < CONFIG.safeFallVelocity then
				root.AssemblyLinearVelocity = Vector3.new(vel.X, CONFIG.safeFallVelocity, vel.Z)
			end
		end

		if pos.Y < CONFIG.voidThresholdY and lastSafeGroundCFrame then
			pcall(function()
				root.CFrame = lastSafeGroundCFrame + Vector3.new(0, 3, 0)
				root.AssemblyLinearVelocity = Vector3.zero
				h:ChangeState(Enum.HumanoidStateType.Running)
			end)
		end
	end))
end

local function enableAntiDamage()
	antiDamageOn = true
	if localPlayer.Character then hookAntiDamage(localPlayer.Character) end
end

local function disableAntiDamage()
	antiDamageOn = false
	clearAntiConns()
	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		pcall(function() hrp.CustomPhysicalProperties = nil end)
	end
end

localPlayer.CharacterAdded:Connect(function(char)
	task.wait(0.3)
	if antiDamageOn then hookAntiDamage(char) end
end)

-- Optimized Heartbeat Radar
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if radarOn and not scanRunning then
		local character = localPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local pos = hrp.Position
			local dx, dy, dz = pos.X - lastHrpPos.X, pos.Y - lastHrpPos.Y, pos.Z - lastHrpPos.Z
			isMoving = (dx * dx + dy * dy + dz * dz) > CONFIG.moveThresholdSq
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

-- ==================== POTATO FPS OPTIMIZER ====================
local boosterBackup = { effects = {}, savedSettings = {} }

local function enableGameBooster()
	boosterBackup.globalShadows = Lighting.GlobalShadows
	boosterBackup.fogEnd = Lighting.FogEnd
	boosterBackup.brightness = Lighting.Brightness

	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.FogEnd = 9e9
		Lighting.Brightness = 1.2
	end)

	table.clear(boosterBackup.effects)
	for _, effect in ipairs(Lighting:GetChildren()) do
		if effect:IsA("PostProcessEffect") or effect:IsA("BloomEffect") or effect:IsA("BlurEffect")
			or effect:IsA("ColorCorrectionEffect") or effect:IsA("SunRaysEffect") or effect:IsA("DepthOfFieldEffect")
			or effect:IsA("Atmosphere") or effect:IsA("Clouds") then
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

-- ==================== GUI INTERFACE ====================
local old = playerGui:FindFirstChild("GecMineAntarctica") or playerGui:FindFirstChild("EngineGUI")
if old then old:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GecMineAntarctica"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 9999
screenGui.Parent = playerGui

local outer = Instance.new("Frame", screenGui)
outer.Size = UDim2.new(0, 420, 0, 360)
outer.Position = UDim2.new(0, 20, 0.5, -180)
outer.BackgroundColor3 = C.bg
outer.BorderSizePixel = 0
outer.Active = true
Instance.new("UICorner", outer).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", outer).Color = Color3.fromRGB(40, 44, 58)

local titleBar = Instance.new("Frame", outer)
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = C.accent
titleBar.BackgroundTransparency = 0.15
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14)

local tbFix = Instance.new("Frame", titleBar)
tbFix.Size = UDim2.new(1, 0, 0, 12)
tbFix.Position = UDim2.new(0, 0, 1, -12)
tbFix.BackgroundColor3 = C.accent
tbFix.BackgroundTransparency = 0.15
tbFix.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size = UDim2.new(1, -55, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.Text = "❄ GEC MINE ANTARCTICA • HYPERDRIVE V5.5"
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

-- Sidebar Tabs
local leftCol = Instance.new("Frame", outer)
leftCol.Size = UDim2.new(0, 48, 1, -42)
leftCol.Position = UDim2.new(0, 6, 0, 36)
leftCol.BackgroundTransparency = 1

local function makeTabButton(yPos, icon, gradA, gradB)
	local btn = Instance.new("TextButton", leftCol)
	btn.Size = UDim2.new(1, 0, 0, 44)
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

local radarBtn, setRadarVis = makeTabButton(0, "◎", C.orange, C.red)
local settingsBtn, setSettingsVis = makeTabButton(52, "⚙", C.green, C.cyan)

local divider = Instance.new("Frame", outer)
divider.Size = UDim2.new(0, 1, 1, -46)
divider.Position = UDim2.new(0, 60, 0, 38)
divider.BackgroundColor3 = Color3.fromRGB(32, 35, 46)
divider.BorderSizePixel = 0

local rightCol = Instance.new("Frame", outer)
rightCol.Size = UDim2.new(1, -70, 1, -44)
rightCol.Position = UDim2.new(0, 66, 0, 36)
rightCol.BackgroundTransparency = 1

-- ==================== TAB 1: RADAR PAGE ====================
local radarPage = Instance.new("Frame", rightCol)
radarPage.Size = UDim2.new(1, 0, 1, 0)
radarPage.BackgroundTransparency = 1
radarPage.Visible = true

local fTitle = Instance.new("TextLabel", radarPage)
fTitle.Size = UDim2.new(1, -70, 0, 16)
fTitle.Text = "STRICT 140M RADAR (FAST SCAN)"
fTitle.TextColor3 = C.purple
fTitle.TextSize = 9.5
fTitle.Font = Enum.Font.GothamBold
fTitle.TextXAlignment = Enum.TextXAlignment.Left
fTitle.BackgroundTransparency = 1

local radarStatus
local radarToggleBtn = Instance.new("TextButton", radarPage)
radarToggleBtn.Size = UDim2.new(0, 64, 0, 18)
radarToggleBtn.Position = UDim2.new(1, -64, 0, -1)
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
		radarStatus.Text = "AI 140M RADAR • RUNNING"
		lastScanClock = 0
		task.defer(function() pcall(scanRealTime) end)
	else
		radarStatus.Text = "AI 140M RADAR • OFF"
		clearAllMarkers()
	end
end)

local catScroll = Instance.new("ScrollingFrame", radarPage)
catScroll.Size = UDim2.new(1, 0, 0, 68)
catScroll.Position = UDim2.new(0, 0, 0, 22)
catScroll.BackgroundTransparency = 1
catScroll.BorderSizePixel = 0
catScroll.ScrollingDirection = Enum.ScrollingDirection.XY
catScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
catScroll.ScrollBarThickness = 2

local catGrid = Instance.new("UIGridLayout", catScroll)
catGrid.CellSize = UDim2.new(0, 64, 0, 18)
catGrid.CellPadding = UDim2.new(0, 3, 0, 3)

local toggleButtons = {}
local updateFilterStatus

local function makeFilterButton(name, color, getState, setState)
	local b = Instance.new("TextButton", catScroll)
	b.Text = name
	b.TextColor3 = color
	b.TextSize = 8
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
	makeFilterButton(RARITY_UI_LABELS[rarity] or rarity, RARITY_COLORS[rarity],
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
radarStatus.Size = UDim2.new(1, 0, 0, 22)
radarStatus.Position = UDim2.new(0, 0, 0, 96)
radarStatus.Text = "AI 140M RADAR • OFF"
radarStatus.TextColor3 = C.textMain
radarStatus.TextSize = 8.5
radarStatus.Font = Enum.Font.GothamBold
radarStatus.TextXAlignment = Enum.TextXAlignment.Left
radarStatus.BackgroundColor3 = C.black
radarStatus.BorderSizePixel = 0
Instance.new("UICorner", radarStatus).CornerRadius = UDim.new(0, 6)
Instance.new("UIPadding", radarStatus).PaddingLeft = UDim.new(0, 6)

local resetBtn = Instance.new("TextButton", radarPage)
resetBtn.Size = UDim2.new(1, 0, 0, 22)
resetBtn.Position = UDim2.new(0, 0, 0, 122)
resetBtn.Text = "↺ RESET ALL FILTERS"
resetBtn.TextColor3 = Color3.new(1, 1, 1)
resetBtn.BackgroundColor3 = C.red
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 8.5
resetBtn.BorderSizePixel = 0
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)

local filterStatus = Instance.new("TextLabel", radarPage)
filterStatus.Size = UDim2.new(1, 0, 0, 32)
filterStatus.Position = UDim2.new(0, 0, 0, 148)
filterStatus.Text = ""
filterStatus.TextColor3 = C.green
filterStatus.TextSize = 8.5
filterStatus.Font = Enum.Font.GothamBold
filterStatus.TextXAlignment = Enum.TextXAlignment.Left
filterStatus.TextYAlignment = Enum.TextYAlignment.Top
filterStatus.BackgroundTransparency = 1
filterStatus.TextWrapped = true

-- ==================== TAB 2: SETTINGS PAGE ====================
local settingsPage = Instance.new("Frame", rightCol)
settingsPage.Size = UDim2.new(1, 0, 1, 0)
settingsPage.BackgroundTransparency = 1
settingsPage.Visible = false

local pTitle = Instance.new("TextLabel", settingsPage)
pTitle.Size = UDim2.new(1, 0, 0, 16)
pTitle.Text = "⚙ SYSTEM OPTIMIZER & PHYSICS"
pTitle.TextColor3 = C.green
pTitle.TextSize = 9.5
pTitle.Font = Enum.Font.GothamBold
pTitle.TextXAlignment = Enum.TextXAlignment.Left
pTitle.BackgroundTransparency = 1

local setScroll = Instance.new("ScrollingFrame", settingsPage)
setScroll.Size = UDim2.new(1, 0, 1, -20)
setScroll.Position = UDim2.new(0, 0, 0, 20)
setScroll.BackgroundTransparency = 1
setScroll.BorderSizePixel = 0
setScroll.ScrollBarThickness = 2
setScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

local setListLayout = Instance.new("UIListLayout", setScroll)
setListLayout.Padding = UDim.new(0, 6)
setListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function makeSettingCard(title, subtitle, layoutOrder)
	local card = Instance.new("Frame", setScroll)
	card.Size = UDim2.new(1, -4, 0, 44)
	card.BackgroundColor3 = C.black
	card.BorderSizePixel = 0
	card.LayoutOrder = layoutOrder or 1
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

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
	btn.Size = UDim2.new(0, 56, 0, 22)
	btn.Position = UDim2.new(1, -62, 0.5, -11)
	btn.Text = "OFF"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.TextSize = 8
	btn.Font = Enum.Font.GothamBold
	btn.BackgroundColor3 = C.red
	btn.BorderSizePixel = 0
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
	return btn
end

-- Setting Cards
local mineToggleBtn = makeSettingCard("⛏ INSTANT MINE (100% CEPAT)", "Auto Break & Instant Multi-Hit", 1)
mineToggleBtn.Text = "MINE OFF"
mineToggleBtn.MouseButton1Click:Connect(function()
	instantMineOn = not instantMineOn
	if instantMineOn then
		mineToggleBtn.Text = "MINE ON"
		mineToggleBtn.BackgroundColor3 = C.green
		for _, data in ipairs(targetList) do
			if data.part then applyInstantMine(data.part) end
		end
		for obj in pairs(processedPrompts) do
			if obj:IsA("ProximityPrompt") then
				obj.HoldDuration = 0
				obj.MaxActivationDistance = math.max(obj.MaxActivationDistance, CONFIG.mineReachDist)
			end
		end
	else
		mineToggleBtn.Text = "MINE OFF"
		mineToggleBtn.BackgroundColor3 = C.red
	end
end)

local boosterToggleBtn = makeSettingCard("⚡ POTATO FPS (ZERO SPIKE)", "Matikan Efek & Hemat Baterai", 2)
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

local weightToggleBtn = makeSettingCard("🪶 LIGHTWEIGHT CRYSTALS", "Set Weight Crystal = 0.1", 3)
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

local antiToggleBtn = makeSettingCard("🛡 ANTI DAMAGE & ANTI SLIP", "Kebal Jatuh, Anti-Void & Daki Tebing", 4)
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

-- Sidebar Navigation
radarBtn.MouseButton1Click:Connect(function()
	setRadarVis(true)
	setSettingsVis(false)
	radarPage.Visible = true
	settingsPage.Visible = false
end)

settingsBtn.MouseButton1Click:Connect(function()
	setRadarVis(false)
	setSettingsVis(true)
	radarPage.Visible = false
	settingsPage.Visible = true
end)

-- Minimize Bubble
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

-- Draggable Logic
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
	filterStatus.Text = #parts > 0 and ("Filter Aktif: " .. table.concat(parts, " | ")) or "Filter: SEMUA NONAKTIF"
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

-- Initial Execution
updateFilterStatus()
refreshToggles()
refreshRadarToggle()
setRadarVis(true)
if localPlayer.Character then hookAntiDamage(localPlayer.Character) end

print("❄ GEC MINE ANTARCTICA V5.5 | Instant Mine ON/OFF | Ekzotis Filter Added | Ultra Zero Lag Loaded!")
