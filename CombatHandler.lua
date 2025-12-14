--[[
	PORTFOLIO COMBAT SYSTEM - SERVER
	
	This script handles all SERVER-SIDE combat logic.

--]]

-- ============================================================================
-- SERVICES
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ============================================================================
-- CONSTANTS - COMBAT BALANCE
-- ============================================================================
-- Damage values
local LIGHT_DAMAGE = 10   -- Light attack damage
local HEAVY_DAMAGE = 25   -- Heavy attack damage (2.5x light)

-- Hitbox configuration
local LIGHT_ATTACK_RANGE = 6   -- Light attack reaches 6 studs
local HEAVY_ATTACK_RANGE = 8   -- Heavy attack reaches 8 studs (longer range)
local HIT_ANGLE_THRESHOLD = 0.5  -- Dot product threshold (0.5 = ~60 degree cone in front)

-- Knockback configuration
local LIGHT_KNOCKBACK_POWER = 30   -- Light attack knockback force
local HEAVY_KNOCKBACK_POWER = 50   -- Heavy attack knockback force (stronger)
local KNOCKBACK_DURATION = 0.2     -- How long knockback lasts (seconds)

-- Anti-spam validation (rate limiting)
local LIGHT_ATTACK_COOLDOWN = 0.4   -- Minimum time between light attacks (server-side)
local HEAVY_ATTACK_COOLDOWN = 1.0   -- Minimum time between heavy attacks (server-side)

-- ============================================================================
-- CONSTANTS - DEBUG VISUALIZATION
-- ============================================================================
-- Toggle to show/hide debug hitboxes in Studio
-- local SHOW_DEBUG_HITBOX = true  -- Set to false to hide

-- Debug hitbox visual settings
local DEBUG_HITBOX_COLOR = Color3.fromRGB(255, 0, 0)  -- Red
local DEBUG_HITBOX_TRANSPARENCY = 0.7
local DEBUG_HITBOX_DURATION = 0.3  -- How long to show hitbox (seconds)

-- ============================================================================
-- STATE - RATE LIMITING
-- ============================================================================
-- Track last attack time for each player (anti-spam)
-- Format: playerLastAttack[player] = { light = tick(), heavy = tick() }
local playerLastAttack = {}

-- ============================================================================
-- REFERENCES
-- ============================================================================
local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent")

-- ============================================================================
-- HIT DETECTION FUNCTIONS
-- ============================================================================

--[[
	Finds a humanoid in front of the attacking character
	
	Parameters:
	- character: The attacking character's model
	- range: How far to check (in studs)
	
	Returns:
	- targetHumanoid: The humanoid that was hit (or nil if no hit)
	- targetCharacter: The character model that was hit (for feedback)
--]]
local function getHumanoidInFront(character, range)
	-- Get attacker's HumanoidRootPart (center of character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end
	
	-- Get direction attacker is facing
	local lookDirection = hrp.CFrame.LookVector
	local attackerPosition = hrp.Position
	
	-- Search all potential targets in workspace
	for _, potentialTarget in pairs(workspace:GetChildren()) do
		-- Skip if not a character model
		if not potentialTarget:IsA("Model") then continue end
		
		-- Skip if this is the attacker (prevent self-hits)
		if potentialTarget == character then continue end
		
		-- Get target's parts
		local targetHrp = potentialTarget:FindFirstChild("HumanoidRootPart")
		local targetHumanoid = potentialTarget:FindFirstChild("Humanoid")
		
		-- Skip if target doesn't have required parts or is already dead
		if not targetHrp or not targetHumanoid then continue end
		if targetHumanoid.Health <= 0 then continue end
		
		-- ====================================================================
		-- RANGE CHECK
		-- ====================================================================
		-- Calculate distance between attacker and target
		local distance = (targetHrp.Position - attackerPosition).Magnitude
		
		-- Skip if target is too far away
		if distance > range then continue end
		
		-- ====================================================================
		-- ANGLE CHECK (in front of attacker)
		-- ====================================================================
		-- Calculate direction from attacker to target
		local directionToTarget = (targetHrp.Position - attackerPosition).Unit
		
		-- Dot product: 1 = directly in front, 0 = perpendicular, -1 = behind
		local dotProduct = lookDirection:Dot(directionToTarget)
		
		-- Skip if target is not in front of attacker
		if dotProduct <= HIT_ANGLE_THRESHOLD then continue end
		
		-- ====================================================================
		-- HIT CONFIRMED
		-- ====================================================================
		return targetHumanoid, potentialTarget
	end
	
	-- No valid targets found
	return nil, nil
end

-- ============================================================================
-- KNOCKBACK FUNCTION
-- ============================================================================

--[[
	Applies knockback to the target character
	- Pushes target away from attacker
	- Uses BodyVelocity for smooth physics-based knockback
	- Automatically cleans up after duration
	
	Parameters:
	- targetCharacter: The character to apply knockback to
	- attackerCharacter: The character performing the attack (for direction)
	- knockbackPower: How strong the knockback force is
--]]
local function applyKnockback(targetCharacter, attackerCharacter, knockbackPower)
	-- Get target's HumanoidRootPart
	local targetHrp = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHrp then return end
	
	-- Get attacker's HumanoidRootPart
	local attackerHrp = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not attackerHrp then return end
	
	-- Calculate knockback direction (away from attacker)
	local knockbackDirection = (targetHrp.Position - attackerHrp.Position).Unit
	
	-- Create BodyVelocity for knockback
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Name = "KnockbackVelocity"
	bodyVelocity.MaxForce = Vector3.new(40000, 0, 40000)  -- Only horizontal knockback
	bodyVelocity.Velocity = knockbackDirection * knockbackPower
	bodyVelocity.Parent = targetHrp
	
	-- Remove BodyVelocity after knockback duration
	task.delay(KNOCKBACK_DURATION, function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
	end)
end

-- ============================================================================
-- VISUAL FEEDBACK FUNCTIONS
-- ============================================================================

--[[
	Spawns enhanced impact particles at the hit location
	- Creates sparks particle effect
	- Creates impact flash effect
	- Automatically cleans up after visual feedback completes
	
	Parameters:
	- targetCharacter: The character that was hit
	- attackerCharacter: The character performing the attack
--]]
local function spawnHitParticles(targetCharacter, attackerCharacter)
	-- Get target's HumanoidRootPart
	local targetHrp = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHrp then return end
	
	-- Get attacker's HumanoidRootPart for impact point calculation
	local attackerHrp = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not attackerHrp then return end
	
	-- ========================================================================
	-- SPARKS PARTICLE EFFECT
	-- ========================================================================
	-- Create spark particles for impact
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "ImpactSparks"
	
	-- Spark appearance
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 100)),  -- Bright orange
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 0))      -- Red fade
	})
	
	-- Spark behavior
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Rate = 0  -- Manual emit only
	sparks.Speed = NumberRange.new(15, 25)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0)
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	sparks.Acceleration = Vector3.new(0, -30, 0)  -- Gravity effect
	
	sparks.Parent = targetHrp
	sparks:Emit(30)  -- Burst of 30 sparks
	
	-- ========================================================================
	-- IMPACT FLASH EFFECT
	-- ========================================================================
	-- Create bright flash part at impact point
	local flash = Instance.new("Part")
	flash.Name = "ImpactFlash"
	flash.Size = Vector3.new(3, 3, 3)
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 255, 255)  -- Bright white
	flash.Transparency = 0.3
	flash.Anchored = true
	flash.CanCollide = false
	flash.CastShadow = false
	
	-- Position between attacker and target (impact point)
	local midpoint = (attackerHrp.Position + targetHrp.Position) / 2
	flash.CFrame = CFrame.new(midpoint)
	flash.Parent = workspace
	
	-- Animate flash (quick expand and fade)
	task.spawn(function()
		local startSize = flash.Size
		local duration = 0.15
		local elapsed = 0
		
		while elapsed < duration do
			local alpha = elapsed / duration
			flash.Size = startSize * (1 + alpha * 2)  -- Expand
			flash.Transparency = 0.3 + (alpha * 0.7)  -- Fade out
			elapsed += task.wait()
		end
		
		flash:Destroy()
	end)
	
	-- ========================================================================
	-- CLEANUP
	-- ========================================================================
	-- Remove sparks after particles finish
	task.delay(1, function()
		sparks:Destroy()
	end)
end

--[[
	Shows a debug visualization of the hitbox (Studio only)
	
	Parameters:
	- attackerCharacter: The character performing the attack
	- range: The range of the attack (hitbox size)
--]]
--[[
local function showDebugHitbox(attackerCharacter, range)
	-- Only show in Studio, skip in live game
	if not RunService:IsStudio() then return end
	if not SHOW_DEBUG_HITBOX then return end
	
	-- Get attacker's HumanoidRootPart
	local hrp = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	-- Create visual hitbox part
	local hitboxPart = Instance.new("Part")
	hitboxPart.Size = Vector3.new(range * 1.5, 4, range)  -- Wide cone shape
	hitboxPart.Color = DEBUG_HITBOX_COLOR
	hitboxPart.Transparency = DEBUG_HITBOX_TRANSPARENCY
	hitboxPart.Anchored = true
	hitboxPart.CanCollide = false
	hitboxPart.Material = Enum.Material.Neon
	hitboxPart.Name = "DebugHitbox"
	
	-- Position in front of attacker
	hitboxPart.CFrame = hrp.CFrame * CFrame.new(0, 0, -range / 2)
	
	-- Add to workspace
	hitboxPart.Parent = workspace
	
	-- Clean up after short duration
	task.delay(DEBUG_HITBOX_DURATION, function()
		hitboxPart:Destroy()
	end)
end
--]]

-- ============================================================================
-- ANTI-SPAM VALIDATION
-- ============================================================================

--[[
	Checks if a player is allowed to attack (rate limiting)
	
	Parameters:
	- player: The player attempting to attack
	- attackType: "light" or "heavy"
	
	Returns:
	- boolean: true if attack is allowed, false if spam detected
--]]
local function canPlayerAttack(player, attackType)
	-- Initialize player's attack history if first time
	if not playerLastAttack[player] then
		playerLastAttack[player] = {
			light = 0,
			heavy = 0
		}
	end
	
	-- Get current time
	local currentTime = tick()
	
	-- Get cooldown for this attack type
	local cooldown = (attackType == "light") and LIGHT_ATTACK_COOLDOWN or HEAVY_ATTACK_COOLDOWN
	
	-- Get time since last attack of this type
	local timeSinceLastAttack = currentTime - playerLastAttack[player][attackType]
	
	-- Check if enough time has passed
	if timeSinceLastAttack < cooldown then
		-- Still on cooldown - reject (possible exploit/spam)
		return false
	end
	
	-- Update last attack time
	playerLastAttack[player][attackType] = currentTime
	
	-- Attack allowed
	return true
end

-- ============================================================================
-- MAIN COMBAT EVENT HANDLER
-- ============================================================================

--[[
	Handles combat requests from clients
	
	Parameters (from client):
	- player: The player who sent the request (automatic)
	- attackType: "light" or "heavy"
--]]
combatEvent.OnServerEvent:Connect(function(player, attackType)
	-- ========================================================================
	-- VALIDATION: Player has character
	-- ========================================================================
	local character = player.Character
	if not character then return end
	
	-- ========================================================================
	-- VALIDATION: Anti-spam check
	-- ========================================================================
	if not canPlayerAttack(player, attackType) then
		-- Player is attacking too fast (possible exploit)
		warn("[CombatHandler] Spam detected from", player.Name)
		return
	end
	
	-- ========================================================================
	-- GET ATTACK PARAMETERS
	-- ========================================================================
	local damage = 0
	local range = 0
	local knockbackPower = 0
	
	if attackType == "light" then
		damage = LIGHT_DAMAGE
		range = LIGHT_ATTACK_RANGE
		knockbackPower = LIGHT_KNOCKBACK_POWER
	elseif attackType == "heavy" then
		damage = HEAVY_DAMAGE
		range = HEAVY_ATTACK_RANGE
		knockbackPower = HEAVY_KNOCKBACK_POWER
	else
		-- Invalid attack type
		warn("[CombatHandler] Invalid attack type from", player.Name, ":", attackType)
		return
	end
	
	-- ========================================================================
	-- DEBUG: Show hitbox visualization (Studio only)
	-- ========================================================================
	-- showDebugHitbox(character, range)
	
	-- ========================================================================
	-- HIT DETECTION
	-- ========================================================================
	local targetHumanoid, targetCharacter = getHumanoidInFront(character, range)
	
	if targetHumanoid and targetCharacter then
		-- Hit confirmed!
		
		-- Apply damage
		targetHumanoid:TakeDamage(damage)
		
		-- Apply knockback
		applyKnockback(targetCharacter, character, knockbackPower)
		
		-- Show enhanced visual feedback
		spawnHitParticles(targetCharacter, character)
	end
end)

-- ============================================================================
-- CLEANUP
-- ============================================================================

--[[
	Clean up player data when they leave (prevent memory leaks)
--]]
game:GetService("Players").PlayerRemoving:Connect(function(player)
	playerLastAttack[player] = nil
end)
