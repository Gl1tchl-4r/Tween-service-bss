local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Mover = {}
Mover.__index = Mover

function Mover.new(characterOrPlayer)
	local self = setmetatable({}, Mover)

	local player, initialChar

	if characterOrPlayer then
		if characterOrPlayer:IsA("Player") then
			player = characterOrPlayer
			initialChar = characterOrPlayer.Character
		elseif characterOrPlayer:IsA("Model") then
			initialChar = characterOrPlayer
			player = Players:GetPlayerFromCharacter(characterOrPlayer) or Players.LocalPlayer
		end
	else
		player = Players.LocalPlayer
		initialChar = player and player.Character
	end

	self.player = player
	self.speed = 70
	self.isTweening = false
	self.isWalking = false
	self.currentTween = nil
	self._connections = {}
	self._charConnections = {}
	self._walkId = 0
	self._isDestroyed = false

	if player then
		table.insert(self._connections, player.CharacterAdded:Connect(function(newChar)
			self:set_character(newChar)
		end))
	end

	if initialChar then
		self:set_character(initialChar)
	end

	return self
end

function Mover:set_character(character)
	for _, conn in ipairs(self._charConnections) do
		conn:Disconnect()
	end
	table.clear(self._charConnections)

	self.character = character
	self.rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	self.humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)

	if self.humanoid then
		table.insert(self._charConnections, self.humanoid.Died:Connect(function()
			self:tween_cancel()
			self:walk_cancel()
		end))
	end
end

-- ตรวจสอบว่าตัวละครยังใช้งานได้อยู่ไหม ถ้าไม่ พยายามดึงตัวใหม่จาก player อัตโนมัติ
function Mover:_isValid()
	if self._isDestroyed then
		return false
	end

	if self.rootPart and self.rootPart.Parent and self.humanoid and self.humanoid.Health > 0 then
		return true
	end

	local player = self.player or Players.LocalPlayer
	local char = player and player.Character
	if char and char:IsDescendantOf(workspace) then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 and root then
			self:set_character(char)
			return true
		end
	end

	return false
end

function Mover:tween_cancel()
	if self._stepConn then
		self._stepConn:Disconnect()
		self._stepConn = nil
	end

	if self._bodyVelocity then
		self._bodyVelocity:Destroy()
		self._bodyVelocity = nil
	end

	if self._tweenConn then
		self._tweenConn:Disconnect()
		self._tweenConn = nil
	end

	if self.currentTween then
		self.currentTween:Cancel()
		self.currentTween = nil
	end

	self.isTweening = false
	self._targetCFrame = nil

	if self.rootPart and self.rootPart.Parent then
		self.rootPart.AssemblyLinearVelocity = Vector3.zero
		self.rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function Mover:walk_cancel()
	self._walkId += 1
	self.isWalking = false

	if self.humanoid and self.rootPart and self.rootPart.Parent then
		self.humanoid:MoveTo(self.rootPart.Position)
	end
end

function Mover:tween_to(targetCFrame, speed)
	if not self:_isValid() then
		return nil
	end

	if self.isTweening and self._targetCFrame
		and (self._targetCFrame.Position - targetCFrame.Position).Magnitude < 1 then
		return self.currentTween
	end

	self:tween_cancel()
	self:walk_cancel()

	local root = self.rootPart
	local moveSpeed = (speed and speed > 0) and speed or self.speed
	local duration = math.max((targetCFrame.Position - root.Position).Magnitude / moveSpeed, 0.001)

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bv.Velocity = Vector3.zero
	bv.Parent = root
	self._bodyVelocity = bv

	self._stepConn = RunService.Stepped:Connect(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)

	self.isTweening = true
	self._targetCFrame = targetCFrame

	local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = targetCFrame })
	self.currentTween = tween

	self._tweenConn = tween.Completed:Connect(function()
		if self.currentTween == tween then
			self:tween_cancel()
		end
	end)

	tween:Play()
	return tween
end

function Mover:walk_to(target, timeout)
	if not self:_isValid() then
		return false
	end

	self:tween_cancel()
	self:walk_cancel()

	local targetPos = typeof(target) == "CFrame" and target.Position or target
	if typeof(targetPos) ~= "Vector3" then
		return false
	end

	local root, humanoid = self.rootPart, self.humanoid
	self.isWalking = true
	local currentId = self._walkId

	local walkSpeed = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or 16
	local maxDuration = timeout or math.max((targetPos - root.Position).Magnitude / walkSpeed + 5, 8)
	local startTime = os.clock()

	while self._walkId == currentId and self:_isValid() and (os.clock() - startTime) < maxDuration do
		local pos = root.Position
		local xzDist = Vector2.new(targetPos.X - pos.X, targetPos.Z - pos.Z).Magnitude
		local yDist = math.abs(targetPos.Y - pos.Y)

		if xzDist <= 3.5 and yDist <= 6 then
			self:walk_cancel()
			return true
		end

		humanoid:MoveTo(targetPos)
		task.wait(0.2)
	end

	if self._walkId == currentId then
		self:walk_cancel()
	end

	return false
end

function Mover:teleport_to(targetCFrame)
	self:tween_cancel()
	self:walk_cancel()

	if not self:_isValid() then
		return false
	end

	self.rootPart.CFrame = targetCFrame
	self.rootPart.AssemblyLinearVelocity = Vector3.zero
	self.rootPart.AssemblyAngularVelocity = Vector3.zero
	return true
end

function Mover:destroy()
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true

	self:tween_cancel()
	self:walk_cancel()

	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	for _, conn in ipairs(self._charConnections) do
		conn:Disconnect()
	end

	self.character = nil
	self.rootPart = nil
	self.humanoid = nil
	self.player = nil
end

return Mover
