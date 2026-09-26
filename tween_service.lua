--!strict
local TweenService = game:GetService("TweenService")

local Mover = {}
Mover.__index = Mover

export type MoverType = {
	character: Model,
	rootPart: BasePart?,
	humanoid: Humanoid?,
	speed: number,
	isTweening: boolean,
	currentTween: Tween?,
	_connections: { [number]: RBXScriptConnection },
	_tweenConn: RBXScriptConnection?,
	_isDestroyed: boolean,

	tween_to: (self: MoverType, targetCFrame: CFrame, speed: number?) -> Tween?,
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
	self.currentTween = nil
	self._tweenConn = nil
	self._connections = {}
	self._isDestroyed = false

	if self.humanoid then
		local deathConn = self.humanoid.Died:Connect(function()
			self:tween_cancel()
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
	if self._tweenConn then
		self._tweenConn:Disconnect()
		self._tweenConn = nil
	end

	if self.currentTween then
		self.currentTween:Cancel()
		self.currentTween = nil
	end

	self.isTweening = false

	if self.rootPart and self.rootPart.Parent then
		self.rootPart.Anchored = false
		self.rootPart.AssemblyLinearVelocity = Vector3.zero
		self.rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function Mover:tween_to(targetCFrame: CFrame, speed: number?): Tween?
	if not self:_isValid() then
		self:tween_cancel()
		return nil
	end

	self:tween_cancel()

	local root = self.rootPart :: BasePart
	local moveSpeed = (speed and speed > 0) and speed or self.speed or 70
	local distance = (targetCFrame.Position - root.Position).Magnitude
	local duration = math.max(distance / moveSpeed, 0.001)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)

	root.Anchored = true
	self.isTweening = true

	local tween = TweenService:Create(root, tweenInfo, { CFrame = targetCFrame })
	self.currentTween = tween

	self._tweenConn = tween.Completed:Connect(function()
		if self._tweenConn then
			self._tweenConn:Disconnect()
			self._tweenConn = nil
		end

		if self.currentTween == tween then
			self.currentTween = nil
			self.isTweening = false
			if root and root.Parent then
				root.Anchored = false
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end)

	tween:Play()
	return tween
end

function Mover:teleport_to(targetCFrame: CFrame): boolean
	self:tween_cancel()

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
