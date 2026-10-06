-- OilFighterClient (LocalScript, StarterPlayerScripts)
-- Cliente del combate en aceite: física con inercia, input (teclas), efectos y resaltado de estados.
-- CONTROLES (también en el HUD; fuente única: ReplicatedStorage.OilControls):
--   Clic izq. = Empujón | Q = Embestida | F = Agarre | R (mantener) = Bloqueo (tocar R justo antes del golpe = PARRY)
--   E = Esquiva | X (2 veces) o botón = Renunciar

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

local OilPhysics = require(ReplicatedStorage:WaitForChild("OilPhysics"))
local Controls = require(ReplicatedStorage:WaitForChild("OilControls"))
local actionRemote = ReplicatedStorage:WaitForChild("OilAction")
local eventRemote = ReplicatedStorage:WaitForChild("OilEvent")
local knockRemote = ReplicatedStorage:WaitForChild("OilKnock")
local resignRemote = ReplicatedStorage:WaitForChild("OilResign")

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function inMatch()
	return player:GetAttribute("InOilMatch") == true
end

-- Dirección de apuntado: del jugador hacia el cursor (proyectado al plano horizontal)
-- ===== Fijar cámara (LOCK con SHIFT IZQ.) =====
-- Fija la cámara en el rival más cercano: el personaje lo mira y los ataques apuntan hacia él.
local lockActive = false
local lockTarget = nil
local lockMarker = nil
local lastLockDir = Vector3.new(0, 0, -1)

local function rootOf(char)
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function isValidTarget(char)
	if not char or not char.Parent or char == player.Character then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and rootOf(char) ~= nil and CollectionService:HasTag(char, "OilFighter")
end

local function nearestTarget()
	local myRoot = rootOf(player.Character)
	if not myRoot then
		return nil
	end
	local best, bestD
	for _, c in ipairs(CollectionService:GetTagged("OilFighter")) do
		if isValidTarget(c) then
			local d = (rootOf(c).Position - myRoot.Position).Magnitude
			if not bestD or d < bestD then
				best, bestD = c, d
			end
		end
	end
	return best
end

local function setMarker(char)
	if lockMarker then
		lockMarker:Destroy()
		lockMarker = nil
	end
	local root = rootOf(char)
	if not root then
		return
	end
	local g = Instance.new("BillboardGui")
	g.Name = "OilLockMarker"
	g.Adornee = root
	g.Size = UDim2.fromOffset(30, 30)
	g.StudsOffset = Vector3.new(0, 6, 0)
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = "▼"
	l.TextColor3 = Color3.fromRGB(255, 80, 70)
	l.TextStrokeTransparency = 0.3
	l.Parent = g
	g.Parent = player:WaitForChild("PlayerGui")
	lockMarker = g
end

local function setLock(on)
	local cam = workspace.CurrentCamera
	if on then
		local t = nearestTarget()
		if not (t and cam) then
			return
		end
		lockActive = true
		lockTarget = t
		setMarker(t)
		cam.CameraType = Enum.CameraType.Scriptable
	elseif lockActive then
		lockActive = false
		lockTarget = nil
		setMarker(nil)
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				cam.CameraSubject = hum
			end
		end
	end
end

-- Dirección (horizontal) hacia el rival fijado; nil si no hay lock
local function lockFace()
	if not lockActive or not isValidTarget(lockTarget) then
		return nil
	end
	local myRoot = rootOf(player.Character)
	if not myRoot then
		return nil
	end
	local d = flat(rootOf(lockTarget).Position - myRoot.Position)
	if d.Magnitude > 0.1 then
		return d.Unit
	end
	return nil
end

RunService:BindToRenderStep("OilLockCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not lockActive then
		return
	end
	local cam = workspace.CurrentCamera
	local myRoot = rootOf(player.Character)
	if not (cam and myRoot) or not inMatch() then
		setLock(false)
		return
	end
	if not isValidTarget(lockTarget) then
		lockTarget = nearestTarget()
		if not lockTarget then
			setLock(false)
			return
		end
		setMarker(lockTarget)
	end
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local tRoot = rootOf(lockTarget)
	local delta = flat(tRoot.Position - myRoot.Position)
	local dir = lastLockDir
	if delta.Magnitude > 0.1 then
		dir = delta.Unit
		lastLockDir = dir
	end
	local back = math.clamp(11 + delta.Magnitude * 0.25, 11, 18)
	local desired = myRoot.Position - dir * back + Vector3.new(0, 6.5, 0)
	local focus = myRoot.Position:Lerp(tRoot.Position, 0.45) + Vector3.new(0, 2, 0)
	local goal = CFrame.lookAt(desired, focus)
	cam.CFrame = cam.CFrame:Lerp(goal, 1 - math.exp(-12 * dt))
end)

local function aimDirection()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local lf = lockFace()
	if lf then
		return lf -- con lock, todo ataque apunta al rival fijado
	end
	if UserInputService.MouseEnabled then
		local cam = workspace.CurrentCamera
		local loc = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(loc.X, loc.Y)
		if math.abs(ray.Direction.Y) > 1e-3 then
			local t = (root.Position.Y - ray.Origin.Y) / ray.Direction.Y
			if t > 0 then
				local p = ray.Origin + ray.Direction * t
				local d = Vector3.new(p.X - root.Position.X, 0, p.Z - root.Position.Z)
				if d.Magnitude > 0.5 then
					return d.Unit
				end
			end
		end
	end
	-- táctil / mando: hacia donde mira el personaje
	local look = flat(root.CFrame.LookVector)
	if look.Magnitude > 0.05 then
		return look.Unit
	end
	return nil
end

-- ===== Envío de acciones =====
local lastSent = {}
local function fire(action, aim)
	if not inMatch() then
		return
	end
	if action ~= "block" and action ~= "unblock" then
		local now = os.clock()
		if lastSent[action] and now - lastSent[action] < 0.08 then
			return
		end
		lastSent[action] = now
	end
	actionRemote:FireServer(action, aim)
end

local function isReady(action)
	local untilT = player:GetAttribute("cd_" .. action)
	return untilT == nil or workspace:GetServerTimeNow() >= untilT
end

local blockHeld = false
local resignArmedUntil = 0

local function trigger(id, isDown)
	if isDown == nil then
		isDown = true
	end
	if not inMatch() then
		return
	end

	-- Fijar cámara: SHIFT IZQ. alterna el lock sobre el rival más cercano
	if id == "lock" then
		if isDown then
			setLock(not lockActive)
		end
		return
	end

	-- Renunciar: hay que pulsar dos veces (3 s) para evitar renuncias por accidente
	if id == "resign" then
		if not isDown then
			return
		end
		local now = os.clock()
		if now < resignArmedUntil then
			resignArmedUntil = 0
			Controls.ResignState:Fire("sent")
			resignRemote:FireServer()
		else
			resignArmedUntil = now + 3
			local token = resignArmedUntil
			Controls.ResignState:Fire("armed")
			task.delay(3, function()
				if resignArmedUntil == token then
					resignArmedUntil = 0
					Controls.ResignState:Fire("reset")
				end
			end)
		end
		return
	end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root) or hum.Health <= 0 then
		return
	end

	if id == "block" then
		blockHeld = isDown
		if isDown then
			local aim = aimDirection()
			if aim and OilPhysics.getState(char) then
				OilPhysics.faceFor(char, aim, 0.2)
			end
			fire("block", aim)
		else
			fire("unblock")
		end
		return
	end

	if not isDown then
		return
	end

	if id == "push" or id == "charge" or id == "grab" then
		local aim = aimDirection()
		if isReady(id) then
			if aim and OilPhysics.getState(char) then
				OilPhysics.faceFor(char, aim, 0.4) -- girar hacia donde apuntas
			end
			if id == "push" then
				char:SetAttribute("PushStartTime", os.clock()) -- animación de empuje (FightIdle)
			end
		end
		fire(id, aim)
	elseif id == "dodge" then
		local move = flat(hum.MoveDirection)
		local dir
		if move.Magnitude > 0.1 then
			dir = move.Unit
		else
			local back = -flat(root.CFrame.LookVector)
			dir = back.Magnitude > 0.05 and back.Unit or nil
		end
		fire("dodge", dir)
	end
end

local function matches(binding, input)
	for _, k in ipairs(binding.keys) do
		if input.KeyCode == k or input.UserInputType == k then
			return true
		end
	end
	return false
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	for _, b in ipairs(Controls.Bindings) do
		if matches(b, input) then
			trigger(b.id, true)
			return
		end
	end
end)

-- Soltar siempre se procesa (aunque el cursor esté sobre la interfaz), para no dejar el bloqueo "pegado"
UserInputService.InputEnded:Connect(function(input)
	for _, b in ipairs(Controls.Bindings) do
		if b.hold and matches(b, input) then
			trigger(b.id, false)
			return
		end
	end
end)

-- Botones de la interfaz (táctil / ratón)
Controls.Request.Event:Connect(trigger)

-- ===== Física del luchador (este cliente es dueño de la física de su personaje) =====
RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	if not char then
		return
	end
	if inMatch() then
		if not OilPhysics.getState(char) then
			OilPhysics.attach(char)
		end
		local pst = OilPhysics.getState(char)
		if pst then
			pst.getFace = lockFace -- con lock el personaje mira siempre al rival
		end
		OilPhysics.step(dt)
		if blockHeld then
			local aim = aimDirection()
			if aim then
				OilPhysics.faceFor(char, aim, 0.12) -- con la guardia arriba miras hacia el cursor
			end
		end
	else
		blockHeld = false
		if OilPhysics.getState(char) then
			OilPhysics.detach(char)
		end
	end
end)

-- Impulsos físicos que manda el servidor (empujones, derribos, esquiva...)
knockRemote.OnClientEvent:Connect(function(kind, impulse, stun, lift, stagger)
	local char = player.Character
	if not char then
		return
	end
	if kind == "knock" then
		if not OilPhysics.getState(char) then
			OilPhysics.attach(char)
		end
		OilPhysics.knock(char, impulse, stun, lift, stagger)
	elseif kind == "reset" then
		OilPhysics.reset(char)
	end
end)

-- ===== Efectos de impacto =====
local FX = {
	hit = { Color3.fromRGB(255, 225, 130), 5 },
	counter = { Color3.fromRGB(255, 170, 60), 8 },
	throw = { Color3.fromRGB(255, 120, 80), 8 },
	launch = { Color3.fromRGB(255, 70, 50), 13 },
	grab = { Color3.fromRGB(190, 120, 255), 5 },
	block = { Color3.fromRGB(110, 170, 255), 4 },
	parry = { Color3.fromRGB(120, 230, 255), 9 },
	guardbreak = { Color3.fromRGB(255, 235, 90), 8 },
	dodge = { Color3.fromRGB(255, 255, 255), 6 },
	dash = { Color3.fromRGB(230, 240, 255), 4 },
	["break"] = { Color3.fromRGB(255, 130, 40), 10 },
	ringout = { Color3.fromRGB(255, 200, 80), 14 },
	victory = { Color3.fromRGB(255, 215, 90), 18 },
}

local function burst(pos, color, size)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.3
	p.Size = Vector3.one * 0.8
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * size,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, 0.4)
end

eventRemote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "fx" then
		local style = FX[a] or FX.hit
		burst(b, style[1], style[2])
	end
end)

-- ===== Resaltado de estados (se ve el estado de todos los luchadores) =====
local STATE_STYLE = {
	blocking = { Color3.fromRGB(80, 160, 255), 0.7 },
	dodging = { Color3.fromRGB(255, 255, 255), 0.6 },
	stunned = { Color3.fromRGB(255, 235, 90), 0.55 },
	knocked = { Color3.fromRGB(255, 80, 80), 0.65 },
	grabbed = { Color3.fromRGB(190, 100, 255), 0.55 },
	grabbing = { Color3.fromRGB(190, 100, 255), 0.8 },
	offbalance = { Color3.fromRGB(255, 130, 40), 0.45 },
	invulnerable = { Color3.fromRGB(255, 215, 90), 0.6 },
	pushed = { Color3.fromRGB(255, 255, 255), 0.85 },
}

local function trackFighter(char)
	if not char:IsA("Model") or char:FindFirstChild("OilStateFx") then
		return
	end
	local h = Instance.new("Highlight")
	h.Name = "OilStateFx"
	h.Enabled = false
	h.OutlineTransparency = 0.2
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = char
	local function refresh()
		local s = STATE_STYLE[char:GetAttribute("State")]
		if s then
			h.FillColor = s[1]
			h.OutlineColor = s[1]
			h.FillTransparency = s[2]
			h.Enabled = true
		else
			h.Enabled = false
		end
	end
	char:GetAttributeChangedSignal("State"):Connect(refresh)
	refresh()
end

CollectionService:GetInstanceAddedSignal("OilFighter"):Connect(trackFighter)
CollectionService:GetInstanceRemovedSignal("OilFighter"):Connect(function(char)
	local h = char:FindFirstChild("OilStateFx")
	if h then
		h:Destroy()
	end
end)
for _, char in ipairs(CollectionService:GetTagged("OilFighter")) do
	trackFighter(char)
end
