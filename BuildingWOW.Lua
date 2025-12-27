--[[
	Advanced Building System
	
	This system allows players to place building pieces in the game world with real-time visual feedback.
	It handles ghost preview rendering, collision detection, grid snapping, rotation controls, and server communication.
	The system uses CFrame math for positioning, raycasting for placement detection, and tweening for smooth visual effects.
]]

-- Service references for Roblox API access
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local player = game.Players.LocalPlayer

-- Module and remote references for build system configuration and server communication
local BuildConfig = require(RS.BuildSystem.BuildConfig)
local BuildPieces = RS:WaitForChild("BuildPieces")
local PlaceBuildEvent = RS.BuildSystem.Remotes:WaitForChild("PlaceBuild")

-- State management variables that track current building status and settings
local ghostPart = nil -- The transparent preview part shown to the player
local currentPieceType = "Wall" -- Currently selected building piece type
local canPlaceHere = false -- Whether the current ghost position is valid for placement
local placing = false -- Cooldown flag to prevent spam placement
local buildMode = true -- Whether build mode is currently active

-- Constants that define build system behavior and limits
local MAX_BUILD_DISTANCE = 120 -- Maximum distance from camera to place pieces
local PLACE_COOLDOWN = 0.15 -- Time in seconds between piece placements
local ROTATION_SPEED = math.pi / 2 -- Rotation amount per key press (90 degrees)
local currentRotation = 0 -- Current rotation angle of the ghost piece

-- Visual effects cache - pre-configured highlight for ghost pieces to improve performance
local highlightTemplate = Instance.new("Highlight")
highlightTemplate.FillColor = Color3.fromRGB(0, 170, 255)
highlightTemplate.OutlineColor = Color3.fromRGB(255, 255, 255)
highlightTemplate.FillTransparency = 0.5
highlightTemplate.OutlineTransparency = 0

-- Creates overlap parameters for collision detection, excluding player and ghost from checks
local function createOverlapParams()
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {player.Character}
	if ghostPart then
		table.insert(filterList, ghostPart)
	end
	params.FilterDescendantsInstances = filterList
	return params
end

-- Metatable for tracking individual piece data including health, placement time, and position
local PieceData = {}
PieceData.__index = PieceData

-- Constructor that creates a new piece data object with initial health and timestamp
function PieceData.new(pieceType, cframe)
	local self = setmetatable({}, PieceData)
	self.Type = pieceType
	self.CFrame = cframe
	self.PlacedTime = tick()
	self.Health = BuildConfig.Pieces[pieceType].MaxHealth
	return self
end

-- Returns how long this piece has existed in seconds
function PieceData:GetAge()
	return tick() - self.PlacedTime
end

-- Performs a raycast from origin in direction while filtering out specified instances
-- This is used to detect where the player is aiming and what surfaces exist
local function performRaycast(origin, direction, filterList)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filterList or {player.Character}
	params.IgnoreWater = true
	params.RespectCanCollide = true

	local result = workspace:Raycast(origin, direction, params)
	return result
end

-- Casts a ray from the center of the screen to find where the player is looking
-- Returns the world position of the raycast hit or nil if nothing was hit
local function getMouseRay()
	local cam = workspace.CurrentCamera
	local vpSize = cam.ViewportSize
	local screenCenter = Vector2.new(vpSize.X / 2, vpSize.Y / 2)

	local filterList = {player.Character}
	if ghostPart then 
		table.insert(filterList, ghostPart)
	end

	local rayOrigin = cam.CFrame.Position
	local rayDir = cam:ScreenPointToRay(screenCenter.X, screenCenter.Y).Direction * 500

	local result = performRaycast(rayOrigin, rayDir, filterList)
	return result and result.Position or nil
end

-- Snaps a position to the nearest grid point for aligned building placement
local function snapToGrid(pos, gridSize)
	gridSize = gridSize or BuildConfig.GridSize
	return Vector3.new(
		math.round(pos.X / gridSize) * gridSize,
		math.round(pos.Y / gridSize) * gridSize,
		math.round(pos.Z / gridSize) * gridSize
	)
end

-- Calculates a CFrame aligned to a surface normal using cross products
-- This allows pieces to be placed flush against angled surfaces
local function alignToSurface(position, normal)
	local upVector = Vector3.new(0, 1, 0)
	local rightVector = normal:Cross(upVector)

	if rightVector.Magnitude < 0.001 then
		rightVector = Vector3.new(1, 0, 0)
	else
		rightVector = rightVector.Unit
	end

	local forwardVector = rightVector:Cross(normal)
	return CFrame.fromMatrix(position, rightVector, normal, -forwardVector)
end

-- Checks if a position is within maximum build distance from the camera
local function isInBuildRange(position)
	local camPos = workspace.CurrentCamera.CFrame.Position
	local distance = (position - camPos).Magnitude
	return distance <= MAX_BUILD_DISTANCE
end

-- Checks if the ghost part overlaps with any solid collidable parts in the workspace
-- Returns true if collision is detected, preventing placement at that location
local function checkCollision(part)
	local params = createOverlapParams()
	local touchingParts = workspace:GetPartsInPart(part, params)

	for _, touchedPart in ipairs(touchingParts) do
		if touchedPart.CanCollide and touchedPart:IsDescendantOf(workspace) then
			return true
		end
	end

	return false
end

-- Clones and attaches a highlight effect to a part for visual feedback
local function createHighlight(part)
	local highlight = highlightTemplate:Clone()
	highlight.Parent = part
	return highlight
end

-- animates the ghost part's transparency using TweenService for visual feedback
local function tweenGhostFeedback(transparency, duration)
	if not ghostPart then return end

	local tweenInfo = TweenInfo.new(
		duration or 0.1,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local goal = {Transparency = transparency}
	local tween = TweenService:Create(ghostPart, tweenInfo, goal)
	tween:Play()
end

-- Creates a temporary sound at the placement position with random pitch
local function playPlacementSound(position)
	local soundPart = Instance.new("Part")
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.Transparency = 1
	soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
	soundPart.Position = position
	soundPart.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://98112849852832"
	sound.Volume = 0.5
	sound.PlaybackSpeed = 0.9 + math.random() * 0.2
	sound.Parent = soundPart
	sound:Play()

	Debris:AddItem(soundPart, 2)
end

-- Creates a new ghost preview part based on the current piece
-- The ghost is semi-transparent and shows where the piece will be placed
local function createGhost()
	if ghostPart then 
		ghostPart:Destroy()
		ghostPart = nil
	end

	local cfg = BuildConfig.Pieces[currentPieceType]
	if not cfg then 
		warn("Invalid piece type:", currentPieceType)
		return 
	end

	local template = BuildPieces:FindFirstChild(cfg.ModelName)
	if not template then 
		warn("Missing template:", cfg.ModelName)
		return 
	end

	ghostPart = template:Clone()
	ghostPart.Name = "Ghost_" .. currentPieceType
	ghostPart.Anchored = true
	ghostPart.CanCollide = false
	ghostPart.Transparency = 0.5
	ghostPart.Material = Enum.Material.ForceField
	ghostPart.Color = Color3.fromRGB(0, 170, 255)
	ghostPart.CastShadow = false

	local highlight = createHighlight(ghostPart)
	ghostPart.Parent = workspace
end

-- Calculates a CFrame rotated relative to the camera's direction
-- This makes pieces face away from the camera when placed, feeling more natural
local function getCameraRelativeRotation(basePosition, lookDirection)
	local flatLook = Vector3.new(lookDirection.X, 0, lookDirection.Z)

	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	local baseCFrame = CFrame.new(basePosition, basePosition + flatLook)
	local rotationCFrame = CFrame.Angles(0, currentRotation, 0)

	return baseCFrame * rotationCFrame
end

-- Rotates the current piece by 90 degrees in the specified direction
local function rotatePiece(direction)
	currentRotation = currentRotation + (direction * ROTATION_SPEED)
	currentRotation = currentRotation % (math.pi * 2)
end

-- Sends a placement request to the server after validating the ghost position
-- Includes cooldown handling and feedback for the placement
local function requestPlace()
	if placing or not ghostPart or not canPlaceHere then return end

	placing = true

	local pieceData = PieceData.new(currentPieceType, ghostPart.CFrame)
	PlaceBuildEvent:FireServer(currentPieceType, ghostPart.CFrame)

	playPlacementSound(ghostPart.Position)
	tweenGhostFeedback(0.2, 0.1)

	task.delay(0.1, function()
		tweenGhostFeedback(0.5, 0.1)
	end)

	task.delay(PLACE_COOLDOWN, function()
		placing = false
	end)
end

-- Changes the current piece type and recreates the ghost with the new model
local function setPieceType(pieceType)
	if currentPieceType == pieceType then return end

	local cfg = BuildConfig.Pieces[pieceType]
	if not cfg then 
		warn("Invalid piece type:", pieceType)
		return 
	end

	currentPieceType = pieceType
	currentRotation = 0
	createGhost()
end

-- Toggles build mode on/off
local function toggleBuildMode()
	buildMode = not buildMode

	if buildMode then
		createGhost()
	else
		if ghostPart then
			ghostPart:Destroy()
			ghostPart = nil
		end
	end
end

-- Initialize the system by creating the initial ghost part
createGhost()

-- Main render loop that updates ghost position and visual state every frame
-- Handles raycast positioning, grid snapping, rotation, range checking, and collision validation
RunService.RenderStepped:Connect(function()
	if not ghostPart or not buildMode then return end

	local hitPos = getMouseRay()
	if not hitPos then return end

	local snappedPos = snapToGrid(hitPos)

	-- Prevent pieces from going below ground level
	if snappedPos.Y < 0.5 then
		snappedPos = Vector3.new(snappedPos.X, 0.5, snappedPos.Z)
	end

	-- Adjust position by half the piece height so it sits on the surface
	local halfHeight = ghostPart.Size.Y / 2
	local adjustedPos = Vector3.new(snappedPos.X, snappedPos.Y + halfHeight, snappedPos.Z)

	-- Check if position is within build range and show orange if too far
	if not isInBuildRange(adjustedPos) then
		ghostPart.Position = adjustedPos
		ghostPart.Color = Color3.fromRGB(255, 165, 0)
		canPlaceHere = false

		local highlight = ghostPart:FindFirstChildOfClass("Highlight")
		if highlight then
			highlight.FillColor = Color3.fromRGB(255, 165, 0)
		end
		return
	end

	local cam = workspace.CurrentCamera
	local lookDir = cam.CFrame.LookVector

	-- Apply piece-specific rotation logic based on type
	if currentPieceType == "Floor" then
		ghostPart.CFrame = CFrame.new(adjustedPos) * CFrame.Angles(0, currentRotation, 0)
	elseif currentPieceType == "Ramp" then
		local baseCFrame = getCameraRelativeRotation(adjustedPos, lookDir)
		ghostPart.CFrame = baseCFrame * CFrame.Angles(0, math.pi, 0)
	else
		ghostPart.CFrame = getCameraRelativeRotation(adjustedPos, lookDir)
	end

	-- Update ghost color based on collision
	local isColliding = checkCollision(ghostPart)
	local highlight = ghostPart:FindFirstChildOfClass("Highlight")

	if isColliding then
		ghostPart.Color = Color3.fromRGB(255, 0, 0)
		if highlight then
			highlight.FillColor = Color3.fromRGB(255, 0, 0)
		end
		canPlaceHere = false
	else
		ghostPart.Color = Color3.fromRGB(0, 170, 255)
		if highlight then
			highlight.FillColor = Color3.fromRGB(0, 170, 255)
		end
		canPlaceHere = true
	end
end)

-- Input handling for piece selection, rotation, build mode toggle, and placement
-- Q=Wall, V=Floor, R=Ramp, E/T=Rotate, B=Toggle build mode, Left Click=Place
UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end

	if input.KeyCode == Enum.KeyCode.Q then 
		setPieceType("Wall")
	elseif input.KeyCode == Enum.KeyCode.V then 
		setPieceType("Floor")
	elseif input.KeyCode == Enum.KeyCode.R then 
		setPieceType("Ramp")
	elseif input.KeyCode == Enum.KeyCode.E then
		rotatePiece(1)
	elseif input.KeyCode == Enum.KeyCode.T then
		rotatePiece(-1)
	elseif input.KeyCode == Enum.KeyCode.B then
		toggleBuildMode()
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		requestPlace()
	end
end)

-- Cleanup and reinitialize ghost when player respawns
player.CharacterAdded:Connect(function()
	if ghostPart then
		ghostPart:Destroy()
		ghostPart = nil
	end

	task.wait(1)

	if buildMode then
		createGhost()
	end
end)
