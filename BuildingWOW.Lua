-- Advanced Fortnite-Style Building System
-- Demonstrates: CFrame math, raycasting, collision detection, input handling, tweening, and custom physics

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local player = game.Players.LocalPlayer

-- Module references
local BuildConfig = require(RS.BuildSystem.BuildConfig)
local BuildPieces = RS:WaitForChild("BuildPieces")
local PlaceBuildEvent = RS.BuildSystem.Remotes:WaitForChild("PlaceBuild")

-- State management
local ghostPart = nil
local currentPieceType = "Wall"
local canPlaceHere = false
local placing = false
local buildMode = true

-- Constants
local MAX_BUILD_DISTANCE = 120
local PLACE_COOLDOWN = 0.15
local ROTATION_SPEED = math.pi / 2
local currentRotation = 0

-- Visual effects cache
local highlightTemplate = Instance.new("Highlight")
highlightTemplate.FillColor = Color3.fromRGB(0, 170, 255)
highlightTemplate.OutlineColor = Color3.fromRGB(255, 255, 255)
highlightTemplate.FillTransparency = 0.5
highlightTemplate.OutlineTransparency = 0

-- Overlap params for collision detection (recreated each check to update filter list)
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

-- Metatable for piece data tracking
local PieceData = {}
PieceData.__index = PieceData

function PieceData.new(pieceType, cframe)
	local self = setmetatable({}, PieceData)
	self.Type = pieceType
	self.CFrame = cframe
	self.PlacedTime = tick()
	self.Health = BuildConfig.Pieces[pieceType].MaxHealth
	return self
end

function PieceData:GetAge()
	return tick() - self.PlacedTime
end

-- Advanced raycast with multiple filter options
local function performRaycast(origin, direction, filterList)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filterList or {player.Character}
	params.IgnoreWater = true
	params.RespectCanCollide = true

	local result = workspace:Raycast(origin, direction, params)
	return result
end

-- Get center screen raycast
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

-- Grid snapping with configurable precision
local function snapToGrid(pos, gridSize)
	gridSize = gridSize or BuildConfig.GridSize
	return Vector3.new(
		math.round(pos.X / gridSize) * gridSize,
		math.round(pos.Y / gridSize) * gridSize,
		math.round(pos.Z / gridSize) * gridSize
	)
end

-- Calculate surface normal alignment using CFrame math
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

-- Check if position is within build range using magnitude
local function isInBuildRange(position)
	local camPos = workspace.CurrentCamera.CFrame.Position
	local distance = (position - camPos).Magnitude
	return distance <= MAX_BUILD_DISTANCE
end

-- Advanced collision detection with region optimization
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

-- Create visual highlight effect
local function createHighlight(part)
	local highlight = highlightTemplate:Clone()
	highlight.Parent = part
	return highlight
end

-- Tween ghost transparency for visual feedback
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

-- Play placement sound with variation
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

-- Create ghost with advanced properties
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

-- Calculate camera-relative rotation using CFrame math
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

-- Handle piece rotation
local function rotatePiece(direction)
	currentRotation = currentRotation + (direction * ROTATION_SPEED)
	currentRotation = currentRotation % (math.pi * 2)
end

-- Request build placement with validation
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

-- Switch piece type with validation
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

-- Toggle build mode
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

-- Initialize system
createGhost()

-- Main render loop with CFrame calculations
RunService.RenderStepped:Connect(function()
	if not ghostPart or not buildMode then return end

	local hitPos = getMouseRay()
	if not hitPos then return end

	local snappedPos = snapToGrid(hitPos)

	if snappedPos.Y < 0.5 then
		snappedPos = Vector3.new(snappedPos.X, 0.5, snappedPos.Z)
	end

	local halfHeight = ghostPart.Size.Y / 2
	local adjustedPos = Vector3.new(snappedPos.X, snappedPos.Y + halfHeight, snappedPos.Z)

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

	if currentPieceType == "Floor" then
		ghostPart.CFrame = CFrame.new(adjustedPos) * CFrame.Angles(0, currentRotation, 0)
	elseif currentPieceType == "Ramp" then
		local baseCFrame = getCameraRelativeRotation(adjustedPos, lookDir)
		ghostPart.CFrame = baseCFrame * CFrame.Angles(0, math.pi, 0)
	else
		ghostPart.CFrame = getCameraRelativeRotation(adjustedPos, lookDir)
	end

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

-- Input handling with multiple control schemes
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

-- Cleanup on character respawn
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
