-- OilBlockVFX (ModuleScript, ReplicatedStorage)
-- VFX del BLOQUEO (tecla R). 100% local y cosmético: cada cliente dibuja el escudo de todos los luchadores
-- leyendo lo que el servidor ya publica (atributos Blocking / Act / ActT del personaje) y los eventos fx.
--
--   * Al levantar la guardia nace un círculo mágico (escudo) delante del luchador: anillos que giran en sentidos
--     opuestos, relleno suave, brillo y luz propia. Respira mientras se sostiene y se encoge al bajarlo.
--   * Ventana de PARRY: el escudo nace dorado y un anillo se cierra sobre él durante CFG.Parry.Window;
--     cuando el anillo llega, el escudo pasa a azul. Es la pista visual de cuándo el parry es posible.
--   * fx "block": destello + chispas + onda en el escudo.
--   * fx "parry": destello dorado grande, ráfaga de chispas y onda dorada en el suelo.
--   * fx "guardbreak": el escudo se pone rojo, estalla en fragmentos y se desvanece.
-- Lo usa StarterPlayerScripts.OilBlockVFXClient.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local CFG = require(ReplicatedStorage:WaitForChild("OilConfig"))
local OilPhysics = require(ReplicatedStorage:WaitForChild("OilPhysics"))

local PARRY_WINDOW = (CFG.Parry and CFG.Parry.Window) or 0.22

local STEADY = Color3.fromRGB(110, 170, 255) -- mismo azul que el estado "BLOQUEANDO" del HUD
local READY = Color3.fromRGB(255, 232, 160)  -- ventana de parry
local BREAK = Color3.fromRGB(255, 110, 70)   -- guardia rota
local WHITE = Color3.new(1, 1, 1)

local CANVAS = 512      -- resolución de la interfaz del escudo
local DIAMETER = 9      -- lado del panel (studs); el círculo ocupa CIRCLE de ese lado
local CIRCLE = 0.62
local DIST = 3.2        -- distancia delante del luchador
local RISE = 0.17       -- seg. en levantarse
local FALL = 0.16       -- seg. en bajarse
local MIN_HOLD = 0.3    -- el escudo no se baja antes de esto (el atributo Blocking llega con retraso)

-- La rotura de guardia es el peor momento del bloqueo: el escudo no se apaga, ESTALLA.
-- Por eso comparte el lenguaje visual de block y parry (anillo que sale de la cara, ondas
-- en el suelo, chispas y luz), pero en el rojo de BREAK y con mas fuerza: tiene que leerse
-- como una fractura y no como un simple cambio de tono.
local BREAK_SPAN = 0.24  -- el escudo revienta antes de dar tiempo a que se vea el apagado
local RIPPLE_BREAK = 0.5 -- el anillo de la cara dura mas que en block: es una grieta abriendose
local SHARDS = 20        -- fragmentos: con 14 se perdian entre el aceite y la arena

local M = {}
local controllers = {}
local folder = nil

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function vfxFolder()
	if folder and folder.Parent then
		return folder
	end
	folder = workspace:FindFirstChild("_OilBlockVFX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "_OilBlockVFX" -- creada en el cliente: nadie más la ve
		folder.Parent = workspace
	end
	return folder
end

local function easeOutBack(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- ===== Piezas de interfaz del escudo =====
local function ringFrame(parent, size, thickness, color, transparency)
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, f)
	local st = make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, f)
	return f, st
end

-- Anillo discontinuo: n arcos que ocupan 'fill' de cada tramo (se hace girar con UIGradient.Rotation)
local function dashedSequence(n, fill)
	local eps = 0.002
	local step = 1 / n
	local keys = { NumberSequenceKeypoint.new(0, 0) }
	for i = 0, n - 1 do
		local arcEnd = i * step + step * fill
		table.insert(keys, NumberSequenceKeypoint.new(arcEnd, 0))
		table.insert(keys, NumberSequenceKeypoint.new(arcEnd + eps, 1))
		if i < n - 1 then
			local nextStart = (i + 1) * step
			table.insert(keys, NumberSequenceKeypoint.new(nextStart - eps, 1))
			table.insert(keys, NumberSequenceKeypoint.new(nextStart, 0))
		end
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 1))
	return NumberSequence.new(keys)
end

local function buildFace(part, face)
	local sg = make("SurfaceGui", {
		Name = "Face" .. face.Name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(CANVAS, CANVAS),
		LightInfluence = 0,
		Brightness = 1.6, -- más alto y el azul se lava hacia blanco
		AlwaysOnTop = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, part)

	local r = { sg = sg }

	-- relleno suave del círculo
	r.fill = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(CIRCLE, CIRCLE),
		BackgroundColor3 = STEADY,
		BackgroundTransparency = 0.84,
		BorderSizePixel = 0,
	}, sg)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, r.fill)
	make("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.5) }),
		Rotation = 90,
	}, r.fill)

	_, r.ring = ringFrame(sg, CIRCLE, 10, STEADY, 0.05)      -- aro principal
	_, r.inner = ringFrame(sg, CIRCLE * 0.84, 3, WHITE, 0.55)   -- aro fino interior
	_, r.spinA = ringFrame(sg, CIRCLE * 1.12, 7, STEADY, 0.1)  -- arcos que giran
	r.gradA = make("UIGradient", { Transparency = dashedSequence(4, 0.6) }, r.spinA)
	_, r.spinB = ringFrame(sg, CIRCLE * 1.26, 4, STEADY, 0.25) -- arcos que giran al revés
	r.gradB = make("UIGradient", { Transparency = dashedSequence(3, 0.45) }, r.spinB)
	r.closingFrame, r.closing = ringFrame(sg, 0.94, 6, READY, 1) -- anillo que se cierra (ventana de parry)
	r.rippleFrame, r.ripple = ringFrame(sg, CIRCLE, 8, WHITE, 1) -- onda al recibir un golpe
	return r
end

local function buildShield()
	local part = make("Part", {
		Name = "OilShield",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 0.99, -- con Transparency = 1 Roblox no dibuja el SurfaceGui
		Size = Vector3.new(DIAMETER, DIAMETER, 0.2),
	})
	local faces = {
		buildFace(part, Enum.NormalId.Front), -- la ve el rival
		buildFace(part, Enum.NormalId.Back),  -- la ve quien se defiende
	}

	-- lente de luz muy tenue: le da volumen al círculo
	local glow = make("Part", {
		Name = "OilShieldGlow",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = STEADY,
		Transparency = 0.9,
		Size = Vector3.new(DIAMETER * CIRCLE, DIAMETER * CIRCLE, 0.8),
	})
	make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, glow)

	local light = make("PointLight", { Color = STEADY, Range = 11, Brightness = 1, Shadows = false }, part)

	-- chispas: salen hacia delante (hacia el rival) desde el disco del escudo
	local emitter = make("ParticleEmitter", {
		Rate = 0,
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(55, 55),
		EmissionDirection = Enum.NormalId.Front,
		Drag = 3.5,
		Acceleration = Vector3.new(0, -18, 0),
		LightEmission = 1,
		LightInfluence = 0,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	}, part)

	return part, glow, faces, light, emitter
end

-- Onda dorada expandiéndose por el suelo (usa el aro como el escudo)
local function shockwave(pos, color, maxSize)
	local arena = OilPhysics.getArena()
	local y = arena and (arena.Position.Y + arena.Size.Y / 2 + 0.1) or (pos.Y - 2.8)
	local p = make("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 0.99,
		Size = Vector3.new(2, 0.05, 2),
		CFrame = CFrame.new(pos.X, y, pos.Z),
	})
	local sg = make("SurfaceGui", {
		Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(256, 256),
		LightInfluence = 0,
		Brightness = 2.5,
		AlwaysOnTop = false,
	}, p)
	local _, st = ringFrame(sg, 0.92, 14, color, 0.05)
	p.Parent = vfxFolder()
	TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(maxSize, 0.05, maxSize),
	}):Play()
	TweenService:Create(st, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(p, 0.6)
end

-- ===== Controlador por luchador =====
local Controller = {}
Controller.__index = Controller

function Controller:show()
	if self.visible then
		return
	end
	self.visible = true
	local f = vfxFolder()
	self.part.Parent = f
	self.glow.Parent = f
end

function Controller:hide()
	if not self.visible then
		return
	end
	self.visible = false
	self.part.Parent = nil
	self.glow.Parent = nil
end

function Controller:sparks(count, color, power)
	if not self.visible then
		return
	end
	local pe = self.emitter
	pe.Color = ColorSequence.new(color, WHITE)
	pe.Speed = NumberRange.new(14 * power, 26 * power)
	pe:Emit(count)
end

-- La rotura suelta el escudo a pedazos en DOS oleadas: una roja y lenta que se abre
-- hacia fuera (el escudo soltandose) y otra blanca y disparada desde el centro (el golpe
-- que lo rompe). Con una sola oleada el efecto pasaba desapercibido.
function Controller:shatter(color)
	local cf = self.part.CFrame
	local f = vfxFolder()
	local function trozo(c, disp, vida, tr)
		local a = math.random() * math.pi * 2
		local rad = 0.3 + math.random() * 2.4
		local x, y = math.cos(a) * rad, math.sin(a) * rad
		local shard = make("Part", {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = c,
			Transparency = tr,
			Size = Vector3.new(0.35 + math.random() * 0.4, 0.5 + math.random() * 0.5, 0.1),
			CFrame = cf * CFrame.new(x, y, 0),
		}, f)
		local target = cf * CFrame.new(x * disp, y * disp - 2.6, -2.5 - math.random() * 2)
			* CFrame.Angles(math.random() * 4, math.random() * 4, math.random() * 4)
		TweenService:Create(shard, TweenInfo.new(vida, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = target,
			Transparency = 1,
		}):Play()
		Debris:AddItem(shard, vida + 0.1)
	end
	for _ = 1, SHARDS - 6 do
		trozo(color, 1.9, 0.55, 0.1)   -- el escudo rojo deshaciendose
	end
	for _ = 1, 6 do
		trozo(WHITE, 2.7, 0.34, 0)     -- nucleo incandescente, sale disparado
	end
end

function Controller:raise(root)
	self:show()
	self.pulse = 0
	self.flash = 0.35
	self:sparks(6, READY, 0.6)
end

-- kind: "block" | "parry" | "guardbreak"
function Controller:react(kind)
	local now = os.clock()
	local root = self.char:FindFirstChild("HumanoidRootPart")
	if kind == "block" then
		if not self.visible then
			return
		end
		self.flash = 1
		self.pulse = 1
		self.rippleT = now
		self.rippleDur = 0.35
		self.rippleColor = WHITE:Lerp(STEADY, 0.4)
		self:sparks(14, WHITE:Lerp(STEADY, 0.5), 1)
	elseif kind == "parry" then
		if not self.visible then
			self.on = true
			self.t0 = now
			self:show()
		end
		self.colorOverride = READY
		self.colorUntil = now + 0.4
		self.holdUntil = now + 0.45 -- el servidor suelta la guardia al parar el golpe: dejamos lucir el efecto
		self.flash = 1.4
		self.pulse = 2.2
		self.rippleT = now
		self.rippleDur = 0.35
		self.rippleColor = READY
		self:sparks(34, READY, 1.4)
		if root then
			shockwave(root.Position, READY, 16)
		end
	elseif kind == "guardbreak" then
		self.broken = true
		self.on = false
		self.tOff = now
		self.noRaiseUntil = now + 0.4
		-- Mas fuerte que el parry: el parry salvaba al luchador, la rotura lo deja
		-- vendido y sin escudo. Es el aviso mas caro del juego, tiene que notarse.
		self.flash = 1.7
		self.pulse = 2.8
		self.rippleT = now
		self.rippleDur = RIPPLE_BREAK
		self.rippleColor = BREAK
		self:sparks(26, BREAK, 1.2)
		-- Segunda rafaga blanca justo despues: da el golpe al principio y luego la estela
		self:sparks(10, WHITE, 1.6)
		if self.visible then
			self:shatter(BREAK)
			-- Dos ondas en el suelo, igual que el parry. Ademas de dar peso al impacto,
			-- avisan al rival de que este luchador ya no tiene guardia que romper.
			if root then
				shockwave(root.Position, BREAK, 22)
				task.delay(0.08, function()
					local r2 = self.char and self.char:FindFirstChild("HumanoidRootPart")
					if r2 then
						shockwave(r2.Position, READY, 13)
					end
				end)
			end
		end
	end
end

function Controller:update(now)
	local char = self.char
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local dt = math.clamp(now - (self.lastNow or now), 0, 0.1)
	self.lastNow = now

	local serverNow = workspace:GetServerTimeNow()
	local blocking = char:GetAttribute("Blocking") == true
	local act, actT = char:GetAttribute("Act"), char:GetAttribute("ActT")
	-- "Act = block" lo pone el servidor al instante de levantar la guardia (antes que el atributo Blocking)
	local fresh = act == "block" and actT ~= nil and actT ~= self.lastActT and (serverNow - actT) < 0.6
	self.lastActT = actT

	if not self.on then
		if now >= self.noRaiseUntil and (fresh or (blocking and now - self.tOff > 0.05)) then
			self.on = true
			self.broken = false
			local late = fresh and math.clamp(serverNow - actT, 0, 0.5) or 0 -- descuenta la latencia de red
			self.t0 = now - late
			self:raise(root)
		end
	elseif not blocking and now - self.t0 > MIN_HOLD and now >= self.holdUntil then
		self.on = false
		self.tOff = now
	end

	if not self.visible then
		return
	end

	-- visibilidad y escala
	local age = now - self.t0
	local k, scale
	if self.on then
		local x = math.clamp(age / RISE, 0, 1)
		scale = 0.35 + 0.65 * easeOutBack(x)
		k = math.clamp(age / (RISE * 0.6), 0, 1)
	else
		local span = self.broken and BREAK_SPAN or FALL
		local x = (now - self.tOff) / span
		if x >= 1 then
			self:hide()
			return
		end
		k = 1 - x
		scale = self.broken and (1 + 0.45 * x) or (1 - 0.35 * x)
	end

	self.pulse = math.max(0, self.pulse - dt * 6)
	self.flash = math.max(0, self.flash - dt * 5)
	local flash = self.flash

	-- color: dorado durante la ventana de parry, luego azul (rojo si la guardia se rompió)
	local color = STEADY
	if self.broken then
		color = BREAK
	elseif self.on and age < PARRY_WINDOW then
		color = READY
	elseif self.on and age < PARRY_WINDOW + 0.12 then
		color = READY:Lerp(STEADY, (age - PARRY_WINDOW) / 0.12)
	end
	if now < self.colorUntil then
		color = self.colorOverride
	end
	color = color:Lerp(WHITE, math.clamp(flash * 0.35, 0, 0.6))

	-- geometría: sigue al luchador, respira y "golpea" al recibir impactos
	local breathe = 1 + 0.025 * math.sin(now * 8 + self.seed)
	local s = scale * breathe * (1 + self.pulse * 0.14)
	local cf = root.CFrame
		* CFrame.new(0, 0.6 + 0.05 * math.sin(now * 5 + self.seed), -DIST)
		* CFrame.Angles(math.rad(-5), 0, 0)
	self.part.Size = Vector3.new(DIAMETER * s, DIAMETER * s, 0.2)
	self.part.CFrame = cf
	self.glow.Size = Vector3.new(DIAMETER * CIRCLE * s * 0.92, DIAMETER * CIRCLE * s * 0.92, 0.9 * s)
	self.glow.CFrame = cf * CFrame.new(0, 0, 0.1)
	self.glow.Color = color
	self.glow.Transparency = 1 - math.clamp(0.1 + 0.3 * flash, 0, 0.9) * k
	self.light.Color = color
	self.light.Brightness = (1 + 2.4 * flash) * k

	-- anillo de ventana de parry: se cierra sobre el escudo
	local closeSize, closeAlpha = 0.94, 0
	if self.on and age < PARRY_WINDOW then
		local p = age / PARRY_WINDOW
		closeSize = 0.94 + (CIRCLE * 1.05 - 0.94) * p
		closeAlpha = 0.95 * (1 - p ^ 4)
	end

	-- onda al recibir un golpe
	local rippleSize, rippleAlpha = CIRCLE, 0
	local rDur = self.rippleDur or 0.35
	local rt = now - self.rippleT
	if rt < rDur then
		local p = rt / rDur
		rippleSize = CIRCLE + (1.28 - CIRCLE) * p
		rippleAlpha = 0.95 * (1 - p)
	end

	-- Al romperse los arcos giran y engordan a lo bestia: el escudo se esta deshaciendo.
	-- Es el mismo giro del resto del bloqueo pero acelerado, para que se note que algo
	-- se ha roto y no un simple cambio de color.
	local velA, velB, gord = 110, 70, 1
	if self.broken then
		velA, velB, gord = 640, 430, 2.6
	end
	local spinA = (now * velA) % 360
	local spinB = -((now * velB) % 360)
	for _, f in ipairs(self.faces) do
		f.fill.BackgroundColor3 = color
		f.fill.BackgroundTransparency = 1 - math.clamp(0.16 + 0.34 * flash, 0, 1) * k
		f.ring.Color = color
		f.ring.Thickness = 10 + flash * 8
		f.ring.Transparency = 1 - math.clamp(0.95 + flash * 0.05, 0, 1) * k
		f.inner.Transparency = 1 - 0.45 * k
		f.spinA.Color = color
		f.spinA.Thickness = 7 * gord
		f.spinA.Transparency = 1 - 0.9 * k
		f.spinB.Color = color
		f.spinB.Thickness = 4 * gord
		f.spinB.Transparency = 1 - 0.75 * k
		f.gradA.Rotation = spinA
		f.gradB.Rotation = spinB
		f.closingFrame.Size = UDim2.fromScale(closeSize, closeSize)
		f.closing.Transparency = 1 - closeAlpha * k
		f.rippleFrame.Size = UDim2.fromScale(rippleSize, rippleSize)
		f.ripple.Color = self.rippleColor
		f.ripple.Transparency = 1 - rippleAlpha
	end
end

-- ===== API =====
function M.attach(char)
	if controllers[char] then
		return controllers[char]
	end
	local c = setmetatable({
		char = char,
		on = false,
		visible = false,
		broken = false,
		t0 = 0,
		tOff = -10,
		pulse = 0,
		flash = 0,
		colorOverride = STEADY,
		colorUntil = 0,
		holdUntil = 0,
		noRaiseUntil = 0,
		rippleT = -10,
		rippleDur = 0.35,
		rippleColor = WHITE,
		lastActT = char:GetAttribute("ActT"),
		seed = math.random() * 10,
	}, Controller)
	c.part, c.glow, c.faces, c.light, c.emitter = buildShield()
	controllers[char] = c
	return c
end

function M.detach(char)
	local c = controllers[char]
	if c then
		c.part:Destroy()
		c.glow:Destroy()
		controllers[char] = nil
	end
end

function M.get(char)
	return controllers[char]
end

-- Evento fx del servidor: busca al luchador que está bloqueando más cerca del punto del impacto
function M.onFx(kind, pos)
	if kind ~= "block" and kind ~= "parry" and kind ~= "guardbreak" then
		return
	end
	if typeof(pos) ~= "Vector3" then
		return
	end
	local best, bestD = nil, 6
	for char, c in pairs(controllers) do
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and (kind == "guardbreak" or c.visible) then
			local d = (root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = c, d
			end
		end
	end
	if best then
		best:react(kind)
	end
end

function M.step()
	local now = os.clock()
	for char, c in pairs(controllers) do
		if not char.Parent then
			M.detach(char)
		else
			local ok, err = pcall(c.update, c, now)
			if not ok and not c.warned then
				c.warned = true
				warn("[OilBlockVFX]", err)
			end
		end
	end
end

return M
