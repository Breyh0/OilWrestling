-- OilPhysics (ModuleScript compartido cliente/servidor)
-- Movimiento con inercia real sobre aceite: poca tracción, deslizamiento,
-- empujones y derribos con cuerpo libre.
-- Quien tiene autoridad física del luchador ejecuta el paso (step):
--   Jugadores    -> su propio cliente (OilFighterClient)
--   Gladiador IA -> el servidor (OilCombat)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CFG = require(ReplicatedStorage:WaitForChild("OilConfig"))

local M = {}
local states = {}
local arenaCache = nil

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

function M.getArena()
	if arenaCache and arenaCache.Parent then
		return arenaCache
	end
	local ring = workspace:FindFirstChild("OilWrestlingRing")
	arenaCache = ring and ring:FindFirstChild("OilArena") or nil
	return arenaCache
end

function M.isOverArena(position, margin)
	local arena = M.getArena()
	if not arena then
		return false
	end
	local rel = arena.CFrame:PointToObjectSpace(position)
	margin = margin or 0
	return math.abs(rel.X) <= arena.Size.X / 2 + margin
		and math.abs(rel.Z) <= arena.Size.Z / 2 + margin
		and rel.Y < 14
		and rel.Y > -6
end

-- Cuerpo "aceitado": casi sin fricción de contacto (se nota cuando está derribado)
function M.slickify(char, on)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			if on then
				d.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.04, 0, 100, 1)
			else
				d.CustomPhysicalProperties = nil
			end
		end
	end
end

-- ===== Estado por luchador =====
function M.attach(character, opts)
	if states[character] then
		return states[character]
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		return nil
	end
	local look = flat(root.CFrame.LookVector)
	local st = {
		char = character,
		hum = hum,
		root = root,
		vel = Vector3.zero,
		active = false,
		getIntent = opts and opts.getIntent or nil,
		getFace = opts and opts.getFace or nil,
		baseWalk = hum.WalkSpeed,
		baseAuto = hum.AutoRotate,
		stunUntil = nil,
		staggerUntil = 0,
		faceDir = nil,
		faceUntil = 0,
		lastLook = look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1),
		lastIntent = Vector3.zero,
		turnSlick = 0, -- resbalón acumulado al girar brusco (ver stepOne)
	}
	states[character] = st
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			states[character] = nil
		end
	end)
	return st
end

local function activate(st)
	st.active = true
	local v = st.root.AssemblyLinearVelocity
	st.vel = Vector3.new(v.X, 0, v.Z)
	st.hum.AutoRotate = false
end

local function deactivate(st)
	st.active = false
	if st.hum.Parent then
		st.hum.WalkSpeed = st.baseWalk
		st.hum.AutoRotate = st.baseAuto
	end
end

function M.detach(character)
	local st = states[character]
	if st then
		if st.active then
			deactivate(st)
		end
		states[character] = nil
	end
end

function M.getState(character)
	return states[character]
end

function M.getIntent(character)
	local st = states[character]
	return st and st.lastIntent or Vector3.zero
end

-- Levanta al luchador del suelo tras un derribo, conservando el impulso
local function endStun(st)
	st.stunUntil = nil
	local hum, root = st.hum, st.root
	if not (hum.Parent and root.Parent) then
		return
	end
	local v = root.AssemblyLinearVelocity
	local pos = root.Position + Vector3.new(0, 1.2, 0)
	root.CFrame = CFrame.lookAt(pos, pos + st.lastLook)
	root.AssemblyAngularVelocity = Vector3.zero
	hum.PlatformStand = false
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	st.vel = Vector3.new(v.X, 0, v.Z)
	st.staggerUntil = os.clock() + 0.35
end

-- Empujón físico.
--   stun > 0  -> derribo: cuerpo libre (PlatformStand) que se desliza y cae
--   stun == 0 -> el luchador sigue en pie pero sale resbalando; stagger reduce su control
function M.knock(character, impulse, stun, lift, stagger)
	local st = states[character]
	if not st then
		return
	end
	local root, hum = st.root, st.hum
	if not (root.Parent and hum.Parent) or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	local imp = flat(impulse)
	local rv = root.AssemblyLinearVelocity
	local base = st.active and st.vel or Vector3.new(rv.X, 0, rv.Z)
	if stun and stun > 0 then
		st.stunUntil = now + stun
		hum.PlatformStand = true
		local nv = base + imp
		root.AssemblyLinearVelocity = Vector3.new(nv.X, rv.Y + (lift or 0), nv.Z)
		if imp.Magnitude > 0.01 then
			root.AssemblyAngularVelocity = imp.Unit:Cross(Vector3.yAxis) * 4
		end
	else
		st.vel = base + imp
		if stagger and stagger > 0 then
			st.staggerUntil = now + stagger
		end
		if lift and lift > 0 then
			root.AssemblyLinearVelocity = Vector3.new(rv.X, rv.Y + lift, rv.Z)
		end
	end
end

function M.reset(character)
	local st = states[character]
	if not st then
		return
	end
	st.vel = Vector3.zero
	st.stunUntil = nil
	st.staggerUntil = 0
	if st.hum.Parent then
		st.hum.PlatformStand = false
	end
	if st.root.Parent then
		st.root.AssemblyLinearVelocity = Vector3.zero
		st.root.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Mira hacia una dirección durante un rato (apuntar un ataque)
function M.faceFor(character, dir, duration)
	local st = states[character]
	if not st then
		return
	end
	local d = flat(dir)
	if d.Magnitude < 0.05 then
		return
	end
	st.faceDir = d.Unit
	st.faceUntil = os.clock() + (duration or 0.4)
	st.lastLook = st.faceDir
	local pos = st.root.Position
	st.root.CFrame = CFrame.lookAt(pos, pos + st.faceDir)
end

local function stepOne(st, dt, now, slick)
	local hum, root, char = st.hum, st.root, st.char
	local prevIntent = st.lastIntent -- intención del frame anterior (para detectar giros bruscos)

	-- Derribado: cuerpo libre deslizando con arrastre
	if st.stunUntil then
		if now < st.stunUntil then
			local v = root.AssemblyLinearVelocity
			local k = math.exp(-CFG.StunDrag / slick * dt)
			root.AssemblyLinearVelocity = Vector3.new(v.X * k, v.Y, v.Z * k)
			return
		end
		endStun(st)
	end

	-- Fuera del aceite: control normal del Humanoid
	if not M.isOverArena(root.Position, 0.5) then
		if st.active then
			deactivate(st)
		end
		return
	end
	if not st.active then
		activate(st)
	end

	local locked = char:GetAttribute("Locked") == true
	local held = char:GetAttribute("Held") == true
	local charging = char:GetAttribute("Charging") == true

	-- Intención de movimiento (input del jugador o decisión de la IA)
	local intent = Vector3.zero
	if not (locked or held) then
		local raw = st.getIntent and st.getIntent() or hum.MoveDirection
		intent = flat(raw)
		if intent.Magnitude > 1 then
			intent = intent.Unit
		end
		st.lastIntent = intent
		if charging then
			intent *= 0.15
		end
		if now < st.staggerUntil then
			intent *= 0.3
		end
		if char:GetAttribute("Blocking") == true then
			intent *= CFG.Block.SpeedMult -- guardia arriba: te mueves más lento
		end
		if char:GetAttribute("Dazed") == true then
			intent *= 0.1 -- aturdido: casi sin control
		end
	else
		st.lastIntent = Vector3.zero
		hum.Jump = false
	end

	-- Giro brusco: el aceite no engancha y las piernas se te escapan un instante
	if intent.Magnitude > 0.1 and prevIntent and prevIntent.Magnitude > 0.1 then
		local dot = intent.Unit:Dot(prevIntent.Unit)
		if dot < 0.98 then
			local kick = (1 - dot) * CFG.TurnSlick * 2
			st.turnSlick = math.min(math.max(st.turnSlick or 0, kick), CFG.TurnSlickMax)
		end
	end
	st.turnSlick = (st.turnSlick or 0) * math.exp(-CFG.TurnSlickDecay * dt)

	-- Modelo de tracción: velocidad exponencial hacia la deseada, con poca fricción
	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local rate
	if locked or held then
		rate = CFG.HeldDrag
	elseif intent.Magnitude > 0.1 then
		rate = CFG.Traction / (slick * (1 + (st.turnSlick or 0)))
	else
		rate = CFG.Glide / slick
	end
	if not grounded then
		rate *= CFG.AirControl
	end
	local alpha = 1 - math.exp(-rate * dt)
	st.vel += (intent * CFG.WalkSpeed - st.vel) * alpha

	-- Aplicar al Humanoid: su propio controlador mueve el cuerpo a la velocidad calculada
	local speed = st.vel.Magnitude
	if speed > 0.4 then
		hum.WalkSpeed = speed
		hum:Move(st.vel / speed, false)
	else
		st.vel = Vector3.zero
		hum.WalkSpeed = 0
		hum:Move(Vector3.zero, false)
	end

	-- Orientación
	local faceVec = st.getFace and st.getFace() or nil
	if not faceVec and st.faceDir and now < st.faceUntil then
		faceVec = st.faceDir
	end
	if not faceVec and intent.Magnitude > 0.2 then
		faceVec = intent
	end
	if faceVec then
		faceVec = flat(faceVec)
		if faceVec.Magnitude > 0.05 then
			faceVec = faceVec.Unit
			st.lastLook = faceVec
			local pos = root.Position
			local target = CFrame.lookAt(pos, pos + faceVec)
			root.CFrame = root.CFrame:Lerp(target, 1 - math.exp(-14 * dt))
		end
	end
end

function M.step(dt)
	local now = os.clock()
	local slick = workspace:GetAttribute("OilSlick") or 1
	for char, st in pairs(states) do
		if not (char.Parent and st.hum.Parent and st.root.Parent) then
			states[char] = nil
		elseif st.hum.Health <= 0 then
			if st.active then
				deactivate(st)
			end
		else
			stepOne(st, dt, now, slick)
		end
	end
end

return M
