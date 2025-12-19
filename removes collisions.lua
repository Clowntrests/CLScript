local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local collisionRemovalEnabled = true
local flightEnabled = false

local carAddedConnection
local collisionToggleButton
local flightToggleButton
local flightStatusLabel

local currentSeatedCar
local currentSeatPart
local flightControllers = {}

local speedSlider
local speedSliderKnob
local speedValueLabel

local MIN_SPEED_MULTIPLIER = 0.5
local MAX_SPEED_MULTIPLIER = 5
local speedMultiplierValue = 1

local FLIGHT_HORIZONTAL_SPEED = 120
local FLIGHT_FORWARD_MULTIPLIER = 3
local FLIGHT_TURN_MULTIPLIER = 0.6
local FLIGHT_VERTICAL_SPEED = 80

local speedSliderDragging = false
local speedSliderDragInput
local seatOriginalValues = {}

-- Collision helpers -------------------------------------------------------
local function removeCollideParts(model)
	if not collisionRemovalEnabled then
		return
	end

	if model:IsA("Model") then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part.Name == "Collide" then
				part:Destroy()
			end
		end
	end
end

local function processExistingCars()
	if not collisionRemovalEnabled then
		return
	end

	local aiTraffic = workspace:FindFirstChild("AITraffic")
	if not aiTraffic then
		return
	end

	local carFolder = aiTraffic:FindFirstChild("Car")
	if not carFolder then
		return
	end

	for _, car in ipairs(carFolder:GetChildren()) do
		removeCollideParts(car)
	end
end

local function monitorNewCars()
	local aiTraffic = workspace:FindFirstChild("AITraffic")
	if not aiTraffic then
		return
	end

	local carFolder = aiTraffic:FindFirstChild("Car")
	if not carFolder then
		return
	end

	if carAddedConnection then
		carAddedConnection:Disconnect()
	end

	carAddedConnection = carFolder.ChildAdded:Connect(function(car)
		wait(0.1)
		if not collisionRemovalEnabled then
			return
		end
		removeCollideParts(car)
	end)
end

-- Flight helpers ----------------------------------------------------------
local function getPrimaryPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			model.PrimaryPart = descendant
			return descendant
		end
	end

	return nil
end

local function ensureFlightController(model)
	local primaryPart = getPrimaryPart(model)
	if not primaryPart then
		return nil, nil
	end

	local data = flightControllers[model]
	if data and data.linearVelocity and data.linearVelocity.Parent then
		return data, primaryPart
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = primaryPart

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "FlightLinearVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.Parent = primaryPart

	flightControllers[model] = {
		attachment = attachment,
		linearVelocity = linearVelocity,
	}

	return flightControllers[model], primaryPart
end

local function removeFlightController(model)
	local data = flightControllers[model]
	if not data then
		return
	end

	if data.linearVelocity then
		data.linearVelocity:Destroy()
	end

	if data.attachment then
		data.attachment:Destroy()
	end

	flightControllers[model] = nil
end

local function cacheSeatDefaults(seat)
	if not seat then
		return nil
	end

	local defaults = seatOriginalValues[seat]
	if defaults then
		return defaults
	end

	defaults = {
		MaxSpeed = seat.MaxSpeed,
		Torque = seat.Torque,
		TurnSpeed = seat.TurnSpeed,
	}
	seatOriginalValues[seat] = defaults
	return defaults
end

local function applySeatSpeedMultiplier(seat, multiplier)
	if not seat or not seat:IsA("VehicleSeat") then
		return
	end

	local defaults = cacheSeatDefaults(seat)
	if not defaults then
		return
	end

	seat.MaxSpeed = defaults.MaxSpeed * multiplier
	seat.Torque = defaults.Torque * multiplier
	seat.TurnSpeed = defaults.TurnSpeed * multiplier
end

local function restoreSeatDefaults(seat)
	if not seat then
		return
	end

	local defaults = seatOriginalValues[seat]
	if not defaults then
		return
	end

	seat.MaxSpeed = defaults.MaxSpeed
	seat.Torque = defaults.Torque
	seat.TurnSpeed = defaults.TurnSpeed
end

local function flattenVector(vec)
	local flat = Vector3.new(vec.X, 0, vec.Z)
	local magnitude = flat.Magnitude
	if magnitude < 1e-4 then
		return Vector3.zero
	end
	return flat / magnitude
end

local function updateFlightMotion()
	if not flightEnabled then
		return
	end

	local car = currentSeatedCar
	if not car then
		return
	end

	local controller, primaryPart = ensureFlightController(car)
	if not controller or not primaryPart then
		return
	end

	local forwardDir = flattenVector(primaryPart.CFrame.LookVector)
	local rightDir = flattenVector(primaryPart.CFrame.RightVector)

	local forwardInput = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		forwardInput += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		forwardInput -= 1
	end

	local strafeInput = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		strafeInput += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		strafeInput -= 1
	end

	local verticalInput = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then
		verticalInput += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		verticalInput -= 1
	end

	local forwardVelocity = forwardDir * forwardInput * (FLIGHT_HORIZONTAL_SPEED * FLIGHT_FORWARD_MULTIPLIER)
	local strafeVelocity = rightDir * strafeInput * (FLIGHT_HORIZONTAL_SPEED * FLIGHT_TURN_MULTIPLIER)
	local horizontalVelocity = forwardVelocity + strafeVelocity
	if math.abs(forwardInput) < 1e-3 and math.abs(strafeInput) < 1e-3 then
		horizontalVelocity = Vector3.zero
	end
	local verticalVelocity = Vector3.new(0, verticalInput * FLIGHT_VERTICAL_SPEED, 0)

	controller.linearVelocity.VectorVelocity = horizontalVelocity + verticalVelocity
	primaryPart.AssemblyAngularVelocity = Vector3.zero
end

RunService.Heartbeat:Connect(updateFlightMotion)

-- UI helpers ---------------------------------------------------------------
local function clampOffsetsToViewport(uiObject, offsetX, offsetY)
	local camera = workspace.CurrentCamera
	if not camera then
		return offsetX, offsetY
	end

	local viewportSize = camera.ViewportSize
	local objectSize = uiObject.AbsoluteSize
	local maxX = viewportSize.X - objectSize.X
	local maxY = viewportSize.Y - objectSize.Y

	return math.clamp(offsetX, 0, math.max(maxX, 0)), math.clamp(offsetY, 0, math.max(maxY, 0))
end

local function enableGuiDragging(uiObject)
	local dragging = false
	local dragInput
	local dragStart
	local startPos

	local function updatePosition(input)
		local delta = input.Position - dragStart
		local newOffsetX = startPos.X.Offset + delta.X
		local newOffsetY = startPos.Y.Offset + delta.Y
		local clampedX, clampedY = clampOffsetsToViewport(uiObject, newOffsetX, newOffsetY)
		uiObject.Position = UDim2.new(startPos.X.Scale, clampedX, startPos.Y.Scale, clampedY)
	end

	uiObject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = uiObject.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	uiObject.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			updatePosition(input)
		end
	end)
end

local function updateCollisionToggleButton()
	if not collisionToggleButton then
		return
	end

	collisionToggleButton.Text = collisionRemovalEnabled and "AI Traffic Collisions: ON" or "AI Traffic Collisions: OFF"
	collisionToggleButton.BackgroundColor3 = collisionRemovalEnabled and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(170, 0, 0)
end

local function updateFlightToggleButton()
	if not flightToggleButton then
		return
	end

	flightToggleButton.Text = flightEnabled and "Flight Mode: ON" or "Flight Mode: OFF"
	flightToggleButton.BackgroundColor3 = flightEnabled and Color3.fromRGB(0, 120, 255) or Color3.fromRGB(60, 60, 60)
end

local function updateFlightStatusLabel()
	if not flightStatusLabel then
		return
	end

	if flightEnabled then
		flightStatusLabel.Text = "Flight Controls: WASD move, E ascend, Q/LeftCtrl descend"
	else
		flightStatusLabel.Text = "Flight Controls disabled"
	end
end

local function setFlightEnabled(enabled)
	if flightEnabled == enabled then
		return
	end

	flightEnabled = enabled

	if not flightEnabled and currentSeatedCar then
		removeFlightController(currentSeatedCar)
	elseif flightEnabled and currentSeatedCar then
		ensureFlightController(currentSeatedCar)
	end

	updateFlightToggleButton()
	updateFlightStatusLabel()
end

local function updateSpeedValueLabel()
	if not speedValueLabel then
		return
	end

	speedValueLabel.Text = string.format("Speed Multiplier: x%.1f", speedMultiplierValue)
end

local function updateSpeedSliderVisual()
	if not speedSlider or not speedSliderKnob then
		return
	end

	local range = MAX_SPEED_MULTIPLIER - MIN_SPEED_MULTIPLIER
	local normalized = range > 0 and (speedMultiplierValue - MIN_SPEED_MULTIPLIER) / range or 0
	normalized = math.clamp(normalized, 0, 1)
	speedSliderKnob.Position = UDim2.new(normalized, 0, 0.5, 0)
end

local function applyMultiplierToCurrentSeat()
	if not currentSeatPart or not currentSeatPart:IsA("VehicleSeat") then
		return
	end

	if math.abs(speedMultiplierValue - 1) < 1e-3 then
		restoreSeatDefaults(currentSeatPart)
	else
		applySeatSpeedMultiplier(currentSeatPart, speedMultiplierValue)
	end
end

local function setSpeedMultiplierValue(newValue)
	newValue = math.clamp(newValue, MIN_SPEED_MULTIPLIER, MAX_SPEED_MULTIPLIER)
	if math.abs(newValue - speedMultiplierValue) < 1e-3 then
		return
	end

	speedMultiplierValue = newValue
	applyMultiplierToCurrentSeat()
	updateSpeedValueLabel()
	updateSpeedSliderVisual()
end

local function updateSpeedSliderFromPosition(position)
	if not speedSlider then
		return
	end

	local sliderWidth = speedSlider.AbsoluteSize.X
	if sliderWidth <= 0 then
		return
	end

	local normalized = math.clamp((position.X - speedSlider.AbsolutePosition.X) / sliderWidth, 0, 1)
	local value = MIN_SPEED_MULTIPLIER + normalized * (MAX_SPEED_MULTIPLIER - MIN_SPEED_MULTIPLIER)
	setSpeedMultiplierValue(value)
end

local function hookSpeedSliderInput(guiObject)
	guiObject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			speedSliderDragging = true
			speedSliderDragInput = input
			updateSpeedSliderFromPosition(input.Position)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					speedSliderDragging = false
				end
			end)
		end
	end)

	guiObject.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			speedSliderDragInput = input
		end
	end)
end

UserInputService.InputChanged:Connect(function(input)
	if input == speedSliderDragInput and speedSliderDragging then
		updateSpeedSliderFromPosition(input.Position)
	end
end)

local function createControlGui()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CollisionFlightGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "ControlPanel"
	panel.Parent = screenGui
	panel.Size = UDim2.new(0, 260, 0, 230)
	panel.Position = UDim2.new(0, 20, 0, 20)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.Active = true

	enableGuiDragging(panel)

	collisionToggleButton = Instance.new("TextButton")
	collisionToggleButton.Name = "CollisionToggleButton"
	collisionToggleButton.Parent = panel
	collisionToggleButton.Size = UDim2.new(1, -20, 0, 40)
	collisionToggleButton.Position = UDim2.new(0, 10, 0, 10)
	collisionToggleButton.Font = Enum.Font.SourceSansBold
	collisionToggleButton.TextSize = 18
	collisionToggleButton.TextColor3 = Color3.new(1, 1, 1)
	collisionToggleButton.AutoButtonColor = false
	collisionToggleButton.BorderSizePixel = 0

	flightToggleButton = Instance.new("TextButton")
	flightToggleButton.Name = "FlightToggleButton"
	flightToggleButton.Parent = panel
	flightToggleButton.Size = UDim2.new(1, -20, 0, 40)
	flightToggleButton.Position = UDim2.new(0, 10, 0, 60)
	flightToggleButton.Font = Enum.Font.SourceSansBold
	flightToggleButton.TextSize = 18
	flightToggleButton.TextColor3 = Color3.new(1, 1, 1)
	flightToggleButton.AutoButtonColor = false
	flightToggleButton.BorderSizePixel = 0

	flightStatusLabel = Instance.new("TextLabel")
	flightStatusLabel.Name = "FlightStatusLabel"
	flightStatusLabel.Parent = panel
	flightStatusLabel.BackgroundTransparency = 1
	flightStatusLabel.Size = UDim2.new(1, -20, 0, 30)
	flightStatusLabel.Position = UDim2.new(0, 10, 0, 110)
	flightStatusLabel.Font = Enum.Font.SourceSans
	flightStatusLabel.TextSize = 16
	flightStatusLabel.TextColor3 = Color3.new(1, 1, 1)
	flightStatusLabel.TextWrapped = true
	flightStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	flightStatusLabel.TextYAlignment = Enum.TextYAlignment.Top

	speedValueLabel = Instance.new("TextLabel")
	speedValueLabel.Name = "SpeedValueLabel"
	speedValueLabel.Parent = panel
	speedValueLabel.BackgroundTransparency = 1
	speedValueLabel.Size = UDim2.new(1, -20, 0, 24)
	speedValueLabel.Position = UDim2.new(0, 10, 0, 150)
	speedValueLabel.Font = Enum.Font.SourceSans
	speedValueLabel.TextSize = 16
	speedValueLabel.TextColor3 = Color3.new(1, 1, 1)
	speedValueLabel.TextXAlignment = Enum.TextXAlignment.Left

	speedSlider = Instance.new("Frame")
	speedSlider.Name = "SpeedSlider"
	speedSlider.Parent = panel
	speedSlider.Size = UDim2.new(1, -40, 0, 6)
	speedSlider.Position = UDim2.new(0, 20, 0, 190)
	speedSlider.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	speedSlider.BorderSizePixel = 0
	speedSlider.Active = true

	speedSliderKnob = Instance.new("Frame")
	speedSliderKnob.Name = "SpeedSliderKnob"
	speedSliderKnob.Parent = speedSlider
	speedSliderKnob.Size = UDim2.new(0, 18, 0, 18)
	speedSliderKnob.Position = UDim2.new(0, 0, 0.5, 0)
	speedSliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	speedSliderKnob.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
	speedSliderKnob.BorderSizePixel = 0
	speedSliderKnob.ZIndex = 2
	speedSliderKnob.Active = true

	hookSpeedSliderInput(speedSlider)
	hookSpeedSliderInput(speedSliderKnob)

	collisionToggleButton.MouseButton1Click:Connect(function()
		collisionRemovalEnabled = not collisionRemovalEnabled
		if collisionRemovalEnabled then
			processExistingCars()
		end
		updateCollisionToggleButton()
	end)

	flightToggleButton.MouseButton1Click:Connect(function()
		setFlightEnabled(not flightEnabled)
	end)

	updateCollisionToggleButton()
	updateFlightToggleButton()
	updateFlightStatusLabel()
	updateSpeedValueLabel()
	updateSpeedSliderVisual()
end

-- Character hooks ---------------------------------------------------------
local function handleSeatChange(seatPart)
	local carModel = seatPart and seatPart:FindFirstAncestorOfClass("Model")
	if not carModel then
		return
	end

	if currentSeatedCar and currentSeatedCar ~= carModel then
		removeFlightController(currentSeatedCar)
	end

	if currentSeatPart and currentSeatPart ~= seatPart then
		restoreSeatDefaults(currentSeatPart)
	end

	currentSeatPart = seatPart
	if currentSeatPart and currentSeatPart:IsA("VehicleSeat") then
		applyMultiplierToCurrentSeat()
	else
		currentSeatPart = nil
	end

	currentSeatedCar = carModel
	if flightEnabled then
		ensureFlightController(carModel)
	else
		removeFlightController(carModel)
	end
end

local function setupCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	humanoid.Seated:Connect(function(isSeated, seatPart)
		if not isSeated then
			if currentSeatedCar then
				removeFlightController(currentSeatedCar)
				currentSeatedCar = nil
			end
			if currentSeatPart then
				restoreSeatDefaults(currentSeatPart)
				currentSeatPart = nil
			end
			return
		end

		if not seatPart then
			return
		end

		handleSeatChange(seatPart)
	end)

	humanoid.Died:Connect(function()
		if currentSeatedCar then
			removeFlightController(currentSeatedCar)
			currentSeatedCar = nil
		end
		if currentSeatPart then
			restoreSeatDefaults(currentSeatPart)
			currentSeatPart = nil
		end
	end)
end

local localPlayer = Players.LocalPlayer
if localPlayer then
	if localPlayer.Character then
		task.defer(setupCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(setupCharacter)
end

-- Run the script ----------------------------------------------------------
processExistingCars()
monitorNewCars()
createControlGui()
