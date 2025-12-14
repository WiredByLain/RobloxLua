--server side code


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LIGHT_DAMAGE = 10
local HEAVY_DAMAGE = 25

local LIGHT_ATTACK_RANGE = 6
local HEAVY_ATTACK_RANGE = 8
local HIT_ANGLE_THRESHOLD = 0.5

local LIGHT_KNOCKBACK_POWER = 30
local HEAVY_KNOCKBACK_POWER = 50
local KNOCKBACK_DURATION = 0.2

local LIGHT_ATTACK_COOLDOWN = 0.4
local HEAVY_ATTACK_COOLDOWN = 1.0

local DEBUG_HITBOX_COLOR = Color3.fromRGB(255, 0, 0)
local DEBUG_HITBOX_TRANSPARENCY = 0.7
local DEBUG_HITBOX_DURATION = 0.3

local playerLastAttack = {}

local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent")

local function getHumanoidInFront(character, range)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil, nil end

	local lookDirection = hrp.CFrame.LookVector
	local attackerPosition = hrp.Position

	for _, potentialTarget in pairs(workspace:GetChildren()) do
		if not potentialTarget:IsA("Model") then continue end
		if potentialTarget == character then continue end

		local targetHrp = potentialTarget:FindFirstChild("HumanoidRootPart")
		local targetHumanoid = potentialTarget:FindFirstChild("Humanoid")

		if not targetHrp or not targetHumanoid then continue end
		if targetHumanoid.Health <= 0 then continue end

		local distance = (targetHrp.Position - attackerPosition).Magnitude
		if distance > range then continue end

		local directionToTarget = (targetHrp.Position - attackerPosition).Unit
		local dotProduct = lookDirection:Dot(directionToTarget)
		if dotProduct <= HIT_ANGLE_THRESHOLD then continue end

		return targetHumanoid, potentialTarget
	end

	return nil, nil
end

local function applyKnockback(targetCharacter, attackerCharacter, knockbackPower)
	local targetHrp = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHrp then return end

	local attackerHrp = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not attackerHrp then return end

	local knockbackDirection = (targetHrp.Position - attackerHrp.Position).Unit

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Name = "KnockbackVelocity"
	bodyVelocity.MaxForce = Vector3.new(40000, 0, 40000)
	bodyVelocity.Velocity = knockbackDirection * knockbackPower
	bodyVelocity.Parent = targetHrp

	task.delay(KNOCKBACK_DURATION, function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
	end)
end

local function spawnHitParticles(targetCharacter, attackerCharacter)
	local targetHrp = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHrp then return end

	local attackerHrp = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not attackerHrp then return end

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "ImpactSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 0))
	})
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Rate = 0
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
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Parent = targetHrp
	sparks:Emit(30)

	local flash = Instance.new("Part")
	flash.Name = "ImpactFlash"
	flash.Size = Vector3.new(3, 3, 3)
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 255, 255)
	flash.Transparency = 0.3
	flash.Anchored = true
	flash.CanCollide = false
	flash.CastShadow = false

	local midpoint = (attackerHrp.Position + targetHrp.Position) / 2
	flash.CFrame = CFrame.new(midpoint)
	flash.Parent = workspace

	task.spawn(function()
		local startSize = flash.Size
		local duration = 0.15
		local elapsed = 0

		while elapsed < duration do
			local alpha = elapsed / duration
			flash.Size = startSize * (1 + alpha * 2)
			flash.Transparency = 0.3 + (alpha * 0.7)
			elapsed += task.wait()
		end

		flash:Destroy()
	end)

	task.delay(1, function()
		sparks:Destroy()
	end)
end

local function canPlayerAttack(player, attackType)
	if not playerLastAttack[player] then
		playerLastAttack[player] = { light = 0, heavy = 0 }
	end

	local currentTime = tick()
	local cooldown = (attackType == "light") and LIGHT_ATTACK_COOLDOWN or HEAVY_ATTACK_COOLDOWN
	local timeSinceLastAttack = currentTime - playerLastAttack[player][attackType]

	if timeSinceLastAttack < cooldown then
		return false
	end

	playerLastAttack[player][attackType] = currentTime
	return true
end

combatEvent.OnServerEvent:Connect(function(player, attackType)
	local character = player.Character
	if not character then return end

	if not canPlayerAttack(player, attackType) then
		warn("[CombatHandler] Spam detected from", player.Name)
		return
	end

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
		warn("[CombatHandler] Invalid attack type from", player.Name, ":", attackType)
		return
	end

	local targetHumanoid, targetCharacter = getHumanoidInFront(character, range)

	if targetHumanoid and targetCharacter then
		targetHumanoid:TakeDamage(damage)
		applyKnockback(targetCharacter, character, knockbackPower)
		spawnHitParticles(targetCharacter, character)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerLastAttack[player] = nil
end)
