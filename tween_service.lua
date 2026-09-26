--!strict
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Mover = {}
Mover.__index = Mover

export type MoverType = {
	character: Model,
	rootPart: BasePart?,
	humanoid: Humanoid?,
	speed: number,
	isTweening: boolean,
	isWalking: boolean,
	currentTween: Tween?,
	_connections: { [number]: RBXScriptConnection },
	_tweenConn: RBXScriptConnection?,
	_stepConn: RBXScriptConnection?,
	_bodyVelocity: BodyVelocity?,
	_targetCFrame: CFrame?,
	_walkId: number,
	_isDestroyed: boolean,

	tween_to: (self: MoverType, targetCFrame: CFrame, speed: number?) -> Tween?,
	walk_to: (self: MoverType, target: Vector3 | CFrame, timeout: number?) -> boolean,
	walk_cancel: (self: MoverType) -> (),
	teleport_to: (self: MoverType, targetCFrame: CFrame) -> boolean,
	tween_cancel: (self: MoverType) -> (),
	destroy: (self: MoverType) -> (),
}

function Mover.new(character: Model): MoverType
	local self = setmetatable({}, Mover)

	self.character = character
	self.rootPart = (character:WaitForChild("HumanoidRootPart", 5) or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	self.humanoid = character:FindFirstChildOfClass("Humanoid")
	self.speed = 70
	self.isTweening = false
	self.isWalking = false
	self.currentTween = nil
	self._tweenConn = nil
	self._stepConn = nil
	self._bodyVelocity = nil
	self._targetCFrame = nil
	self._connections = {}
	self._walkId = 0
	self._isDestroyed = false

	if self.humanoid then
		local deathConn = self.humanoid.Died:Connect(function()
			self:tween_cancel()
			self:walk_cancel()
		end)
		table.insert(self._connections, deathConn)
	end

	local ancestryConn = character.AncestryChanged:Connect(function(_, parent)
		if not parent or not character:IsDescendantOf(workspace) then
			self:destroy()
		end
	end)
	table.insert(self._connections, ancestryConn)

	local destroyingConn = character.Destroying:Connect(function()
		self:destroy()
	end)
	table.insert(self._connections, destroyingConn)

	return (self :: any) :: MoverType
end

function Mover:_isValid(): boolean
	if self._isDestroyed then
		return false
	end
	if not self.character or not self.character.Parent or not self.character:IsDescendantOf(workspace) then
		return false
	end
	if not self.rootPart or not self.rootPart.Parent then
		return false
	end
	if self.humanoid and self.humanoid.Health <= 0 then
		return false
	end
	return true
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

	-- หากกำลัง Tween ไปเป้าหมายเดิมอยู่แล้ว ไม่ต้องเริ่มใหม่ ป้องกันการกระตุกเมื่อถูกเรียกซ้ำ
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

	-- ต้านแรงโน้มถ่วงและแรงเฉื่อยฟิสิกส์ให้เป็น 0 (Smooth โดยไม่ต้อง Anchored)
	local bv = Instance.new("BodyVelocity")
	bv.Name = "MoverVelocity"
	bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bv.Velocity = Vector3.zero
	bv.Parent = root
	self._bodyVelocity = bv

	-- ล็อคความเร็วและปิด CanCollide ชั่วคราว ป้องกันการชนสิ่งกีดขวาง/พื้นจนกล้องสั่น
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
	if not self:_isValid() or not self.humanoid then
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

	while self:_isValid() and self._walkId == currentId and (os.clock() - startTime) < maxDuration do
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

	self.character = nil :: any
	self.rootPart = nil :: any
	self.humanoid = nil :: any

	setmetatable(self, nil)
end

return Mover
