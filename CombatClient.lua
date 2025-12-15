
-- Services
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Cooldowns and fade
local LIGHT_ATTACK_COOLDOWN = 0.5
local HEAVY_ATTACK_COOLDOWN = 1.2
local FADE_TIME = 0.15

-- Movement
local NORMAL_SPEED = 16
local SPRINT_SPEED = 25
local NORMAL_FOV = 70
local SPRINT_FOV = 80

-- references
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera


local character = nil
local humanoid = nil
local animator = nil

-- Animation
local walkTrack = nil
local sprintTrack = nil
local lightAttackTrack = nil
local heavyAttackTrack = nil

-- State flags
local lightAttackReady = true
local heavyAttackReady = true
local isSprinting = false
local runningConn = nil

-- Shift lock
local isShiftLocked = false
local shiftLockRenderConn = nil

-- Stop animation
local function stopTrack(track)
	if track and track.IsPlaying then
		track:Stop(FADE_TIME)
	end
end

-- Play animation
local function playTrack(track)
	if track and not track.IsPlaying then
		track:Play(FADE_TIME)
	end
end


local function applyWalkStats()
	if not humanoid then return end
	humanoid.WalkSpeed = NORMAL_SPEED
	camera.FieldOfView = NORMAL_FOV
end

-- Apply sprint 
local function applySprintStats()
	if not humanoid then return end
	humanoid.WalkSpeed = SPRINT_SPEED
	camera.FieldOfView = SPRINT_FOV
end

-- Enable shift lock
local function enableShiftLock()
	if not humanoid or not character then return end
	isShiftLocked = true

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	humanoid.CameraOffset = Vector3.new(1.75, 0, 0)
	humanoid.AutoRotate = false

	if shiftLockRenderConn then
		shiftLockRenderConn:Disconnect()
	end

	
	shiftLockRenderConn = RunService.RenderStepped:Connect(function()
		if not isShiftLocked then return end
		if not root or not camera then return end

		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local lookVector = camera.CFrame.LookVector
		local horizontalLook = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
		root.CFrame = CFrame.new(root.Position, root.Position + horizontalLook)
	end)
end


local function disableShiftLock()
	isShiftLocked = false

	if shiftLockRenderConn then
		shiftLockRenderConn:Disconnect()
		shiftLockRenderConn = nil
	end

	if humanoid then
		humanoid.CameraOffset = Vector3.new(0, 0, 0)
		humanoid.AutoRotate = true
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end


local function toggleShiftLock()
	if isShiftLocked then
		disableShiftLock()
	else
		enableShiftLock()
	end
end

-- Light attack input
local function performLightAttack()
	if not lightAttackReady or not lightAttackTrack then return end
	lightAttackReady = false
	lightAttackTrack:Play(FADE_TIME)

	local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent")
	combatEvent:FireServer("light")

	task.wait(LIGHT_ATTACK_COOLDOWN)
	lightAttackReady = true
end

-- Heavy attack input
local function performHeavyAttack()
	if not heavyAttackReady or not heavyAttackTrack then return end
	heavyAttackReady = false
	heavyAttackTrack:Play(FADE_TIME)

	local combatEvent = ReplicatedStorage:WaitForChild("CombatEvent")
	combatEvent:FireServer("heavy")

	task.wait(HEAVY_ATTACK_COOLDOWN)
	heavyAttackReady = true
end

-- Setup character and animations
local function setupCharacter(char)
	character = char
	humanoid = character:WaitForChild("Humanoid")
	animator = humanoid:WaitForChild("Animator")

	local animFolder = ReplicatedStorage:WaitForChild("Animations")

	-- Movement animations
	walkTrack = animator:LoadAnimation(animFolder:WaitForChild("Walking"))
	walkTrack.Priority = Enum.AnimationPriority.Movement
	walkTrack.Looped = true

	sprintTrack = animator:LoadAnimation(animFolder:WaitForChild("Sprint"))
	sprintTrack.Priority = Enum.AnimationPriority.Action
	sprintTrack.Looped = true

	-- Combat animations
	lightAttackTrack = animator:LoadAnimation(animFolder:WaitForChild("Punch"))
	lightAttackTrack.Priority = Enum.AnimationPriority.Action
	lightAttackTrack.Looped = false

	heavyAttackTrack = animator:LoadAnimation(animFolder:WaitForChild("Punch"))
	heavyAttackTrack.Priority = Enum.AnimationPriority.Action
	heavyAttackTrack.Looped = false

	-- Reset 
	isSprinting = false
	lightAttackReady = true
	heavyAttackReady = true

	applyWalkStats()
	stopTrack(walkTrack)
	stopTrack(sprintTrack)

	if isShiftLocked then
		disableShiftLock()
	end

	if runningConn then
		runningConn:Disconnect()
	end

	-- movement animation switching
	runningConn = humanoid.Running:Connect(function(speed)
		if speed <= 0.1 then
			stopTrack(walkTrack)
			stopTrack(sprintTrack)
			return
		end

		if isSprinting then
			stopTrack(walkTrack)
			playTrack(sprintTrack)
		else
			stopTrack(sprintTrack)
			playTrack(walkTrack)
		end
	end)
end

-- character setup
setupCharacter(player.Character or player.CharacterAdded:Wait())
player.CharacterAdded:Connect(setupCharacter)

-- Input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.LeftShift then
		isSprinting = true
		applySprintStats()
		stopTrack(walkTrack)
		playTrack(sprintTrack)
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		toggleShiftLock()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		performLightAttack()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		performHeavyAttack()
	end
end)

-- Stop sprint on release
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		isSprinting = false
		applyWalkStats()
		stopTrack(sprintTrack)
	end
end)
