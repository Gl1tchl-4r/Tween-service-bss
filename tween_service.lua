--!strict
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Mover = {}
Mover.__index = Mover

export type MoverType = {
	character: Model?,
	player: Player?,
	rootPart: BasePart?,
	humanoid: Humanoid?,
	speed: number,
	isTweening: boolean,
	isWalking: boolean,
	currentTween: Tween?,
	_connections: { [number]: RBXScriptConnection },
	_charConnections: { [number]: RBXScriptConnection },
	_tweenConn: RBXScriptConnection?,
	_stepConn: RBXScriptConnection?,
	_bodyVelocity: BodyVelocity?,
	_targetCFrame: CFrame?,
	_walkId: number,
	_isDestroyed: boolean,

	set_character: (self: MoverType, character: Model) -> (),
	tween_to: (self: MoverType, targetCFrame: CFrame, speed: number?) -> Tween?,
	walk_to: (self: MoverType, target: Vector3 | CFrame, timeout: number?) -> boolean,
	walk_cancel: (self: MoverType) -> (),
	teleport_to: (self: MoverType, targetCFrame: CFrame) -> boolean,
	tween_cancel: (self: MoverType) -> (),
	destroy: (self: MoverType) -> (),
}

function Mover:set_character(character: Model)
	for _, conn in ipairs(self._charConnections) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(self._charConnections)

	self.character = character
	self.rootPart = (character:WaitForChild("HumanoidRootPart", 5) or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	self.humanoid = (character:WaitForChild("Humanoid", 5) or character:FindFirstChildOfClass("Humanoid")) :: Humanoid?

	if self.humanoid then
		local deathConn = self.humanoid.Died:Connect(function()
			self:tween_cancel()
			self:walk_cancel()
		end)
		table.insert(self._charConnections, deathConn)
	end
end

function Mover.new(characterOrPlayer: (Model | Player)?): MoverType
	local self = setmetatable({}, Mover)

	local player: Player? = nil
	local initialChar: Model? = nil

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
	self.character = nil
	self.rootPart = nil
	self.humanoid = nil
	self.speed = 70
	self.isTweening = false
	self.isWalking = false
	self.currentTween = nil
	self._tweenConn = nil
	self._stepConn = nil
	self._bodyVelocity = nil
	self._targetCFrame = nil
	self._connections = {}
	self._charConnections = {}
	self._walkId = 0
	self._isDestroyed = false

	if player then
		local charAddedConn = player.CharacterAdded:Connect(function(newChar)
			self:set_character(newChar)
		end)
		table.insert(self._connections, charAddedConn)
	end

	if initialChar then
		self:set_character(initialChar)
	end

	return (self :: any) :: MoverType
end

function Mover:_ensureValid(): boolean
	if self._isDestroyed then
		return false
	end

	if self.character and self.character.Parent and self.character:IsDescendantOf(workspace)
		and self.rootPart and self.rootPart.Parent
		and self.humanoid and self.humanoid.Parent and self.humanoid.Health > 0 then
		return true
	end

	-- หากตัวละครเดิมตายหรือยังไม่ผูก ให้ดึงตัวละครล่าสุดที่พร้อมใช้งาน
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

function Mover:_isValid(): boolean
	return self:_ensureValid()
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

function Mover:tween_to(targetCFrame: CFrame, speed: number?): Tween?
	if not self:_isValid() then
		self:tween_cancel()
		self:walk_cancel()
		return nil
	end

	if self.isTweening and self.currentTween and self._targetCFrame and (self._targetCFrame.Position - targetCFrame.Position).Magnitude < 1 then
		return self.currentTween
	end

	self:tween_cancel()
	self:walk_cancel()

	local root = self.rootPart :: BasePart
	local moveSpeed = (speed and speed > 0) and speed or self.speed or 70
	local distance = (targetCFrame.Position - root.Position).Magnitude
	local duration = math.max(distance / moveSpeed, 0.001)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)

	local bv = Instance.new("BodyVelocity")
	bv.Name = "MoverVelocity"
	bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bv.Velocity = Vector3.zero
	bv.Parent = root
	self._bodyVelocity = bv

	self._stepConn = RunService.Stepped:Connect(function()
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		for _, part in ipairs(self.character:GetChildren()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)

	self.isTweening = true
	self._targetCFrame = targetCFrame

	local tween = TweenService:Create(root, tweenInfo, { CFrame = targetCFrame })
	self.currentTween = tween

	self._tweenConn = tween.Completed:Connect(function()
		if self.currentTween == tween then
			self:tween_cancel()
		end
	end)

	tween:Play()
	return tween
end

function Mover:walk_to(target: Vector3 | CFrame, timeout: number?): boolean
	if not self:_ensureValid() then
		return false
	end

	self:tween_cancel()
	self:walk_cancel()

	local targetPos: Vector3
	if typeof(target) == "CFrame" then
		targetPos = target.Position
	elseif typeof(target) == "Vector3" then
		targetPos = target
	else
		return false
	end

	local root = self.rootPart :: BasePart
	local humanoid = self.humanoid :: Humanoid

	self.isWalking = true
	local currentId = self._walkId

	local walkSpeed = humanoid.WalkSpeed > 0 and humanoid.WalkSpeed or 16
	local maxDuration = timeout or math.max((targetPos - root.Position).Magnitude / walkSpeed + 5, 8)
	local startTime = os.clock()

	while self._walkId == currentId and not self._isDestroyed and self:_isValid() and (os.clock() - startTime) < maxDuration do
		local currentPos = root.Position
		local xzDist = Vector2.new(targetPos.X - currentPos.X, targetPos.Z - currentPos.Z).Magnitude
		local yDist = math.abs(targetPos.Y - currentPos.Y)

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

function Mover:teleport_to(targetCFrame: CFrame): boolean
	self:tween_cancel()
	self:walk_cancel()

	if not self:_isValid() then
		return false
	end

	local root = self.rootPart :: BasePart
	root.CFrame = targetCFrame
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
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
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(self._connections)

	for _, conn in ipairs(self._charConnections) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(self._charConnections)

	self.character = nil :: any
	self.rootPart = nil :: any
	self.humanoid = nil :: any
	self.player = nil :: any
end

return Mover
