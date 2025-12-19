local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local collisionRemovalEnabled = true
local carAddedConnection
local toggleButton

-- Function to remove Collide parts from a model
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

-- Function to process all existing cars
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

-- Function to monitor for new cars being added
local function monitorNewCars()
	local aiTraffic = workspace:FindFirstChild("AITraffic")
	if not aiTraffic then return end
	
	local carFolder = aiTraffic:FindFirstChild("Car")
	if not carFolder then return end

	if carAddedConnection then
		carAddedConnection:Disconnect()
	end
	
	-- Listen for new cars being added
	carAddedConnection = carFolder.ChildAdded:Connect(function(car)
		wait(0.1) -- Small delay to ensure the model is fully loaded
		if not collisionRemovalEnabled then
			return
		end
		removeCollideParts(car)
	end)
end

-- UI helpers ---------------------------------------------------------------
local function clampOffsetsToViewport(button, offsetX, offsetY)
	local camera = workspace.CurrentCamera
	if not camera then
		return offsetX, offsetY
	end

	local viewportSize = camera.ViewportSize
	local buttonSize = button.AbsoluteSize
	local maxX = viewportSize.X - buttonSize.X
	local maxY = viewportSize.Y - buttonSize.Y

	return math.clamp(offsetX, 0, math.max(maxX, 0)), math.clamp(offsetY, 0, math.max(maxY, 0))
end

local function enableButtonDragging(button)
	local dragging = false
	local dragInput
	local dragStart
	local startPos

	local function updatePosition(input)
		local delta = input.Position - dragStart
		local newOffsetX = startPos.X.Offset + delta.X
		local newOffsetY = startPos.Y.Offset + delta.Y
		local clampedX, clampedY = clampOffsetsToViewport(button, newOffsetX, newOffsetY)
		button.Position = UDim2.new(startPos.X.Scale, clampedX, startPos.Y.Scale, clampedY)
	end

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = button.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	button.InputChanged:Connect(function(input)
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

local function updateToggleButton()
	if not toggleButton then
		return
	end

	toggleButton.Text = collisionRemovalEnabled and "AI Traffic Collisions: ON" or "AI Traffic Collisions: OFF"
	toggleButton.BackgroundColor3 = collisionRemovalEnabled and Color3.fromRGB(0, 170, 0) or Color3.fromRGB(170, 0, 0)
end

local function createToggleGui()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CollisionToggleGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	toggleButton = Instance.new("TextButton")
	toggleButton.Name = "CollisionToggleButton"
	toggleButton.Parent = screenGui
	toggleButton.Size = UDim2.new(0, 220, 0, 40)
	toggleButton.Position = UDim2.new(0, 20, 0, 20)
	toggleButton.Font = Enum.Font.SourceSansBold
	toggleButton.TextSize = 18
	toggleButton.TextColor3 = Color3.new(1, 1, 1)
	toggleButton.AutoButtonColor = false
	toggleButton.BorderSizePixel = 0

	enableButtonDragging(toggleButton)

	-- Toggling simply flips the enabled flag and optionally reprocesses cars
	toggleButton.MouseButton1Click:Connect(function()
		collisionRemovalEnabled = not collisionRemovalEnabled
		if collisionRemovalEnabled then
			processExistingCars()
		end
		updateToggleButton()
	end)

	updateToggleButton()
end

-- Run the script
processExistingCars()
monitorNewCars()
createToggleGui()