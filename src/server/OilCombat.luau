-- OilCombat (ModuleScript, ServerScriptService)
-- Lucha en Aceite: empuja al rival fuera del ring. Primero en llegar a 3 puntos gana.
--
-- CONTROLES (el HUD los muestra; fuente única: ReplicatedStorage.OilControls):
--   Clic izquierdo = Empujón     Q = Embestida     F = Agarre y lanzamiento
--   R (mantener)   = Bloqueo     R justo antes del golpe = PARRY (contraataque)
--   E              = Esquiva (invulnerable un instante)
--   X / botón      = Renunciar (vuelves al lobby y el rival gana)
--
-- PROFUNDIDAD (todo se ajusta en ReplicatedStorage.OilConfig):
--   * Equilibrio: cada golpe lo reduce; en 0 quedas DESEQUILIBRADO y el siguiente golpe te lanza muchísimo más lejos.
--   * Stamina: acciones y bloqueo la gastan; sin stamina no puedes actuar y la guardia se rompe.
--   * Estados: idle, pushed (empujado), stunned (aturdido), knocked (derribado), grabbed (agarrado),
--     grabbing, blocking, dodging, offbalance (desequilibrado), invulnerable (al reaparecer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CFG = require(ReplicatedStorage:WaitForChild("OilConfig"))
local OilPhysics = require(ReplicatedStorage:WaitForChild("OilPhysics"))

-- Progresión (XP, monedas, misiones). Si falla, el combate sigue funcionando sin recompensas.
local okProg, Progression = pcall(function()
	return require(game:GetService("ServerScriptService"):WaitForChild("ProgressionService", 10))
end)
if not okProg then
	warn("[OilCombat] ProgressionService no disponible:", Progression)
	Progression = nil
end
local function progress(method, ...)
	if Progression and Progression[method] then
		local ok, err = pcall(Progression[method], ...)
		if not ok then
			warn("[OilCombat] Progression." .. method .. " falló:", err)
		end
	end
end

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local actionRemote = ensureRemote("OilAction") -- cliente -> servidor (acción, dirección)
local eventRemote = ensureRemote("OilEvent")   -- servidor -> clientes (HUD y efectos)
local knockRemote = ensureRemote("OilKnock")   -- servidor -> cliente dueño (impulsos físicos)

local OilCombat = {}
local match = nil

local ACTIONS = { push = "Push", charge = "Charge", grab = "Grab", dodge = "Dodge" }
local ACTION_LIST = { "push", "charge", "grab", "dodge", "block" }
local FIGHTER_ATTRS = { "Locked", "Held", "Charging", "Act", "ActT", "State", "Blocking", "Dazed", "Balance" }

-- ===== Utilidades =====
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v, fallback)
	if v.Magnitude < 0.01 then
		return fallback
	end
	return v.Unit
end

local function charOf(e)
	if e.kind == "player" then
		return e.player and e.player.Character
	end
	return e.model
end

local function partsOf(e)
	local char = charOf(e)
	if not char or not char.Parent then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		return nil
	end
	return char, hum, root
end

local function isAlive(e)
	local char, hum = partsOf(e)
	return char ~= nil and hum.Health > 0
end

local function setAct(char, name)
	char:SetAttribute("Act", name)
	char:SetAttribute("ActT", workspace:GetServerTimeNow())
end

local function setHeld(e, on)
	local char = charOf(e)
	if char then
		char:SetAttribute("Held", on and true or nil)
	end
end

local function fighterList()
	local list = {}
	for _, e in ipairs(match.fighters) do
		table.insert(list, { name = e.name, score = e.score, ai = e.kind == "ai" })
	end
	return list
end

local function fx(kind, pos, dir, force)
	eventRemote:FireAllClients("fx", kind, pos, dir or Vector3.zero, force or 20)
end

-- Aviso breve al jugador (el HUD lo traduce a texto): nostamina, broken, foe_broken, parry, parried, dodged, guardbreak
local function notify(e, kind)
	if e and e.kind == "player" and e.player and e.player.Parent then
		eventRemote:FireClient(e.player, "notice", kind)
	end
end

local function startCooldown(e, action, seconds)
	e.cd[action] = os.clock() + seconds
	if e.kind == "player" and e.player then
		e.player:SetAttribute("cd_" .. action, workspace:GetServerTimeNow() + seconds)
		e.player:SetAttribute("cdlen_" .. action, seconds)
	end
end

local function spendStamina(e, amount)
	if amount <= 0 then
		return
	end
	e.stamina = math.max(0, e.stamina - amount)
	e.staminaSpentAt = os.clock()
end

local function isOut(root)
	local arena = OilPhysics.getArena()
	local rel = arena.CFrame:PointToObjectSpace(root.Position)
	return math.abs(rel.X) > arena.Size.X / 2 + CFG.RingMargin
		or math.abs(rel.Z) > arena.Size.Z / 2 + CFG.RingMargin
		or rel.Y < -3
end

local function spawnCFrame(i, n)
	local arena = OilPhysics.getArena()
	local center = arena.Position
	local topY = arena.Position.Y + arena.Size.Y / 2
	local ang = (i - 1) / n * math.pi * 2 + math.pi / 2
	local p = Vector3.new(center.X + math.cos(ang) * CFG.SpawnRadius, topY + 3.4, center.Z + math.sin(ang) * CFG.SpawnRadius)
	return CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z))
end

-- Impulso físico: jugadores lo reciben en su cliente (dueño de la física); la IA, directo
local function sendKnock(e, impulse, stun, lift, stagger)
	local char = charOf(e)
	if not char then
		return
	end
	if e.kind == "ai" then
		OilPhysics.knock(char, impulse, stun, lift, stagger)
	elseif e.player and e.player.Parent then
		knockRemote:FireClient(e.player, "knock", impulse, stun or 0, lift or 0, stagger or 0)
	end
end

-- ===== Estado del luchador =====
local function resetCombatState(e)
	e.out = false
	e.lastHit = nil
	e.stunUntil = 0          -- derribado
	e.invulnUntil = 0        -- invulnerable tras un derribo / parry
	e.spawnInvulnUntil = 0   -- invulnerable al reaparecer
	e.dazedUntil = 0         -- aturdido
	e.pushedUntil = 0        -- empujado
	e.brokenUntil = 0        -- desequilibrado (equilibrio en 0)
	e.counterUntil = 0       -- ventana de contraataque tras un parry
	e.dodgeUntil = 0
	e.dodgeIFramesUntil = 0
	e.dodgeFxFor = nil
	e.holding = nil
	e.heldBy = nil
	e.holdToken = nil
	e.blocking = false
	e.blockStart = 0
	e.balance = CFG.Balance.Max
	e.balanceHitAt = 0
	e.stamina = CFG.Stamina.Max
	e.staminaSpentAt = 0
	e.cd = { push = 0, charge = 0, grab = 0, dodge = 0, block = 0 }
	e.state = "idle"
end

local function computeState(e, t)
	if t < e.spawnInvulnUntil then
		return "invulnerable"
	end
	if e.heldBy then
		return "grabbed"
	end
	if e.holding then
		return "grabbing"
	end
	if t < e.stunUntil then
		return "knocked"
	end
	if t < e.dazedUntil then
		return "stunned"
	end
	if t < e.dodgeUntil then
		return "dodging"
	end
	if e.blocking then
		return "blocking"
	end
	if t < e.brokenUntil then
		return "offbalance"
	end
	if t < e.pushedUntil then
		return "pushed"
	end
	return "idle"
end

-- Barra de equilibrio sobre la cabeza (la ven todos: sirve para saber cuándo rematar)
local function makeBar(e, char)
	local head = char:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("OilBars")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OilBars"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(130, 32)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 110
	gui.LightInfluence = 0

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = Color3.fromRGB(240, 220, 120)
	name.TextStrokeTransparency = 0.4
	name.Text = e.name
	name.Parent = gui

	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Position = UDim2.new(0, 0, 0.62, 0)
	bg.Size = UDim2.new(1, 0, 0.32, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 24, 20)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 4)
	bgCorner.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(240, 200, 90)
	stroke.Thickness = 1
	stroke.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	gui.Parent = head
	e.bar = { gui = gui, fill = fill, name = name, last = -1, broken = false }
end

local function updateBar(e, t)
	local bar = e.bar
	if not bar or not bar.fill.Parent then
		return
	end
	local pct = math.floor(e.balance / CFG.Balance.Max * 100 + 0.5)
	local broken = t < e.brokenUntil
	if pct == bar.last and broken == bar.broken then
		return
	end
	bar.last = pct
	bar.broken = broken
	if broken then
		bar.fill.Size = UDim2.fromScale(1, 1)
		bar.fill.BackgroundColor3 = Color3.fromRGB(255, 70, 50)
		bar.name.Text = "¡DESEQUILIBRADO!"
		bar.name.TextColor3 = Color3.fromRGB(255, 90, 70)
	else
		bar.fill.Size = UDim2.fromScale(math.clamp(pct / 100, 0, 1), 1)
		bar.fill.BackgroundColor3 = Color3.fromHSV(0.33 * pct / 100, 0.65, 0.85)
		bar.name.Text = e.name
		bar.name.TextColor3 = Color3.fromRGB(240, 220, 120)
	end
end

-- Publica estado, equilibrio y stamina como atributos (el HUD y los efectos los leen)
local function publish(e, t)
	local char = charOf(e)
	if not char then
		return
	end
	local state = computeState(e, t)
	e.state = state
	if char:GetAttribute("State") ~= state then
		char:SetAttribute("State", state)
	end
	local blocking = e.blocking or nil
	if char:GetAttribute("Blocking") ~= blocking then
		char:SetAttribute("Blocking", blocking)
	end
	local dazed = (t < e.dazedUntil) or nil
	if char:GetAttribute("Dazed") ~= dazed then
		char:SetAttribute("Dazed", dazed)
	end
	local bal = math.floor(e.balance + 0.5)
	if char:GetAttribute("Balance") ~= bal then
		char:SetAttribute("Balance", bal)
	end
	if e.kind == "player" and e.player and e.player.Parent then
		local plr = e.player
		local st = math.floor(e.stamina + 0.5)
		local counter = (t < e.counterUntil) or nil
		if plr:GetAttribute("Balance") ~= bal then
			plr:SetAttribute("Balance", bal)
		end
		if plr:GetAttribute("Stamina") ~= st then
			plr:SetAttribute("Stamina", st)
		end
		if plr:GetAttribute("CounterReady") ~= counter then
			plr:SetAttribute("CounterReady", counter)
		end
		if plr:GetAttribute("OilState") ~= state then
			plr:SetAttribute("OilState", state)
		end
	end
	updateBar(e, t)
end

-- ===== Preparación / limpieza de luchadores =====
local startAI -- adelantada

local function prepFighter(e)
	local char, hum = partsOf(e)
	if not char then
		return
	end
	CollectionService:AddTag(char, "OilFighter")
	OilPhysics.slickify(char, true)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d:GetAttribute("OilOrigRefl") == nil then
			d:SetAttribute("OilOrigRefl", d.Reflectance)
			d.Reflectance = math.max(d.Reflectance, CFG.SkinShine)
		end
	end
	e.origDisplay = hum.DisplayDistanceType
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- el nombre va en la barra de equilibrio
	makeBar(e, char)
	if e.kind == "player" then
		e.player:SetAttribute("InOilMatch", true)
	else
		startAI(e)
	end
end

local releaseHold -- declaración adelantada
local stopBlock   -- declaración adelantada

local function releaseFighter(e)
	e.released = true
	stopBlock(e, false)
	local char = charOf(e)
	if e.kind == "player" and e.player and e.player.Parent then
		e.player:SetAttribute("InOilMatch", nil)
		for _, a in ipairs(ACTION_LIST) do
			e.player:SetAttribute("cd_" .. a, nil)
			e.player:SetAttribute("cdlen_" .. a, nil)
		end
		for _, a in ipairs({ "Balance", "Stamina", "CounterReady", "OilState" }) do
			e.player:SetAttribute(a, nil)
		end
		knockRemote:FireClient(e.player, "reset")
	end
	if e.bar and e.bar.gui then
		e.bar.gui:Destroy()
		e.bar = nil
	end
	if char then
		CollectionService:RemoveTag(char, "OilFighter")
		for _, a in ipairs(FIGHTER_ATTRS) do
			char:SetAttribute(a, nil)
		end
		OilPhysics.slickify(char, false)
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then
				local orig = d:GetAttribute("OilOrigRefl")
				if orig ~= nil then
					d.Reflectance = orig
					d:SetAttribute("OilOrigRefl", nil)
				end
			end
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
			hum.DisplayDistanceType = e.origDisplay or Enum.HumanoidDisplayDistanceType.Viewer
		end
		if e.kind == "ai" then
			OilPhysics.detach(char)
		end
	end
end

-- ===== Agarres =====
function releaseHold(grabber, victim)
	if grabber then
		grabber.holding = nil
		setHeld(grabber, false)
	end
	if victim then
		victim.heldBy = nil
		setHeld(victim, false)
	end
end

-- Suelta todo agarre en el que participe el luchador (como agarrador o como agarrado)
local function dropHolds(e)
	if e.holding then
		local v = e.holding
		e.holdToken = nil
		releaseHold(e, v)
	end
	if e.heldBy then
		local g = e.heldBy
		g.holdToken = nil
		releaseHold(g, e)
	end
end

-- ===== Defensa =====
function stopBlock(e, withCooldown)
	if not e.blocking then
		return
	end
	e.blocking = false
	if withCooldown then
		startCooldown(e, "block", CFG.Block.Cooldown)
	end
end

local function startBlock(e)
	local char = charOf(e)
	if not char or e.blocking then
		return
	end
	local t = os.clock()
	if t < e.cd.block then
		return
	end
	if char:GetAttribute("Locked") or char:GetAttribute("Held") or char:GetAttribute("Charging") or e.holding then
		return
	end
	if t < e.stunUntil or t < e.dazedUntil then
		return
	end
	if e.stamina < CFG.Block.MinStamina then
		notify(e, "nostamina")
		return
	end
	spendStamina(e, CFG.Stamina.BlockStart)
	e.blocking = true
	e.blockStart = t
	setAct(char, "block")
end

local function daze(e, seconds)
	local t = os.clock()
	e.dazedUntil = math.max(e.dazedUntil, t + seconds)
	stopBlock(e, false)
	local char = charOf(e)
	if char then
		setAct(char, "stunned")
	end
end

-- Resta equilibrio. Al llegar a 0 queda DESEQUILIBRADO: el siguiente golpe lo lanza muy lejos.
local function applyBalanceDamage(e, dmg, by)
	local t = os.clock()
	if t < e.brokenUntil or dmg <= 0 then
		return
	end
	e.balance = math.max(0, e.balance - dmg)
	e.balanceHitAt = t
	if e.balance <= 0 then
		e.brokenUntil = t + CFG.Balance.BrokenTime
		local _, _, root = partsOf(e)
		if root then
			fx("break", root.Position, Vector3.zero, 30)
		end
		notify(e, "broken")
		if by then
			notify(by, "foe_broken")
		end
	end
end

-- ¿El golpe viene de frente (dentro del arco de la guardia)?
local function frontalTo(vic, vroot, aroot, dir)
	local face = flat(vroot.CFrame.LookVector)
	if face.Magnitude < 0.01 then
		return false
	end
	local from = aroot and aroot.Position or (vroot.Position - dir)
	local toAtt = unitOr(flat(from - vroot.Position), -dir)
	return face.Unit:Dot(toAtt) >= CFG.Block.Arc
end

local function isParrying(vic, t, vroot, aroot, dir)
	return vic.blocking and (t - vic.blockStart) <= CFG.Parry.Window and frontalTo(vic, vroot, aroot, dir)
end

-- Parry: el atacante queda aturdido y tú ganas una ventana de contraataque
local function doParry(att, vic, dir)
	local t = os.clock()
	local P = CFG.Parry
	local _, _, vroot = partsOf(vic)
	stopBlock(vic, false)
	startCooldown(vic, "block", 0.25)
	vic.counterUntil = t + P.CounterWindow
	vic.invulnUntil = math.max(vic.invulnUntil, t + P.Invuln)
	vic.stamina = math.min(CFG.Stamina.Max, vic.stamina + P.StaminaRefund)
	if partsOf(att) then
		daze(att, P.AttackerDaze)
		sendKnock(att, -dir * P.AttackerKnock, 0, 0, P.AttackerDaze)
		att.lastHit = { by = vic, t = t }
		applyBalanceDamage(att, CFG.Balance.Damage.parry, vic)
	end
	if vroot then
		fx("parry", vroot.Position, dir, 40)
	end
	notify(vic, "parry")
	notify(att, "parried")
	if vic.kind == "player" and vic.player then
		progress("RecordParry", vic.player)
	end
end

-- ===== Resolución de golpes =====
-- Devuelve "hit" | "blocked" | "parried" | "dodged" | "ignored"
-- spec: { force, stun, lift, stagger, balanceDmg, fx, unblockable, blockCostMult }
local function resolveHit(att, vic, dir, spec)
	local t = os.clock()
	local vchar, vhum, vroot = partsOf(vic)
	if not vchar or vhum.Health <= 0 or vic.out then
		return "ignored"
	end
	if t < vic.invulnUntil or t < vic.spawnInvulnUntil then
		return "ignored"
	end
	local B, S = CFG.Balance, CFG.Stamina
	local _, _, aroot = partsOf(att)

	-- 1) Esquiva: los i-frames dejan pasar el golpe y el atacante queda expuesto
	if t < vic.dodgeIFramesUntil then
		if vic.dodgeFxFor ~= vic.dodgeIFramesUntil then
			vic.dodgeFxFor = vic.dodgeIFramesUntil
			daze(att, CFG.Dodge.WhiffDaze)
			sendKnock(att, Vector3.zero, 0, 0, CFG.Dodge.WhiffDaze)
			fx("dodge", vroot.Position, dir, 20)
			notify(vic, "dodged")
		end
		return "dodged"
	end

	-- 2) Guardia (solo golpes frontales; el agarre y el lanzamiento la ignoran)
	if vic.blocking and not spec.unblockable and frontalTo(vic, vroot, aroot, dir) then
		if t - vic.blockStart <= CFG.Parry.Window then
			doParry(att, vic, dir)
			return "parried"
		end
		vic.lastHit = { by = att, t = t }
		local cost = S.BlockHit * (spec.blockCostMult or 1)
		if vic.stamina - cost <= 0 then
			-- guardia rota: sin stamina para aguantar el golpe
			vic.stamina = 0
			vic.staminaSpentAt = t
			stopBlock(vic, true)
			daze(vic, S.GuardBreakDaze)
			applyBalanceDamage(vic, spec.balanceDmg * 0.6, att)
			sendKnock(vic, dir * spec.force * CFG.Block.ForceMult, 0, 0, S.GuardBreakDaze)
			fx("guardbreak", vroot.Position, dir, 30)
			notify(vic, "guardbreak")
			return "blocked"
		end
		spendStamina(vic, cost)
		applyBalanceDamage(vic, spec.balanceDmg * CFG.Block.BalanceMult, att)
		sendKnock(vic, dir * spec.force * CFG.Block.ForceMult, 0, 0, 0.2)
		fx("block", vroot.Position, dir, 15)
		return "blocked"
	end

	-- 3) Golpe limpio
	local force = spec.force
	local stun = spec.stun or 0
	local lift = spec.lift or 0
	local stagger = spec.stagger or 0
	local fxKind = spec.fx or "hit"

	if t < vic.brokenUntil then
		-- Desequilibrado: este golpe lo lanza MUCHO más lejos y lo derriba
		force *= B.BrokenForceMult
		stun = math.max(stun, B.BrokenStun)
		lift += B.BrokenLift
		vic.brokenUntil = 0
		vic.balance = B.PostBreakRecover
		vic.balanceHitAt = t
		fxKind = "launch"
	else
		-- cuanto menos equilibrio, más lejos te manda cada golpe
		force *= 1 + (1 - vic.balance / B.Max) * B.LowBalanceBonus
		applyBalanceDamage(vic, spec.balanceDmg, att)
	end

	vic.lastHit = { by = att, t = t }
	dropHolds(vic)
	if stun > 0 then
		stopBlock(vic, true)
	end
	sendKnock(vic, dir * force, stun, lift, stagger)
	if stun > 0 then
		vic.stunUntil = t + stun
		vic.invulnUntil = t + stun + CFG.InvulnAfterStun
		setAct(vchar, "stunned")
	else
		vic.pushedUntil = t + math.max(stagger, 0.35)
	end
	fx(fxKind, vroot.Position, dir, force)
	return "hit"
end

local function connected(result)
	return result == "hit" or result == "blocked" or result == "parried"
end

-- ===== Golpes =====
local function targetsInCone(e, dir, range, minDot)
	local _, _, root = partsOf(e)
	local list = {}
	if not root or not match then
		return list
	end
	for _, o in ipairs(match.fighters) do
		if o ~= e and not o.out then
			local _, ohum, oroot = partsOf(o)
			if oroot and ohum.Health > 0 then
				local d = flat(oroot.Position - root.Position)
				local dist = d.Magnitude
				if dist <= range and (dist < 1.5 or d.Unit:Dot(dir) >= minDot) then
					table.insert(list, { entry = o, dist = dist })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	return list
end

-- ===== Embestidas en curso =====
-- Las embestidas se resuelven en el Heartbeat del modulo (una comprobacion por frame) en vez de
-- con un bucle propio de task.wait: asi el impacto se evalua una vez por frame y sin despertares
-- extra por embestida (bug #2 de docs/OILCOMBAT.md).
local activeCharges = {} -- { {char, entry, dir, def, tCheck, tEnd, result} }

-- Termina la embestida: limpia el atributo Charging y aplica rebote o recuperacion.
local function finishCharge(c)
	c.char:SetAttribute("Charging", nil)
	if isAlive(c.entry) and not c.entry.out then
		if c.result == "hit" then
			sendKnock(c.entry, -c.dir * 8, 0, 0, 0.5) -- rebote del impacto
		elseif c.result then
			sendKnock(c.entry, -c.dir * 16, 0, 0, 0.6) -- rebota contra la guardia
		else
			sendKnock(c.entry, Vector3.zero, 0, 0, c.def.Recovery) -- fallo: queda expuesto
		end
	end
end

-- Un paso por frame de todas las embestidas activas.
local function tickCharges()
	if #activeCharges == 0 then
		return
	end
	local keep = {}
	local now = os.clock()
	for _, c in ipairs(activeCharges) do
		local done = false
		if now >= c.tEnd or not match or not match.fighting or c.entry.released
			or not isAlive(c.entry) or c.entry.out then
			-- Se acabo el tiempo o el combate: la embestida termina sin resultado.
			done = true
		elseif now >= c.tCheck then
			-- Primer chequeo a los 30ms, igual que el antiguo bucle (no cambia el balance).
			for _, t in ipairs(targetsInCone(c.entry, c.dir, c.def.HitRange, -0.1)) do
				local r = resolveHit(c.entry, t.entry, c.dir, {
					force = c.def.Force, stun = c.def.Stun, lift = c.def.Lift, stagger = 0,
					balanceDmg = CFG.Balance.Damage.charge, fx = "throw", blockCostMult = 2,
				})
				if connected(r) then
					c.result = r
					done = true
					break
				end
			end
		end
		if done then
			finishCharge(c)
		else
			keep[#keep + 1] = c
		end
	end
	activeCharges = keep
end

local function canKeepActing(e)
	local t = os.clock()
	return match and match.fighting and isAlive(e) and not e.out and t >= e.stunUntil and t >= e.dazedUntil
end

local function doPush(e, dir, counter)
	local def = CFG.Push
	local char = charOf(e)
	setAct(char, "push")
	task.delay(def.Windup, function()
		if not canKeepActing(e) then
			return -- te derribaron o aturdieron durante el golpe: se cancela
		end
		local _, _, root = partsOf(e)
		for _, t in ipairs(targetsInCone(e, dir, def.Range, def.Cone)) do
			local along = math.max(0, flat(root.AssemblyLinearVelocity):Dot(dir))
			local force = def.Force + along * def.Momentum
			local dmg = CFG.Balance.Damage.push
			if counter then
				force *= CFG.Parry.CounterForceMult
				dmg *= 1.5
			end
			local r = resolveHit(e, t.entry, dir, {
				force = force, stun = 0, lift = def.Lift, stagger = def.Stagger,
				balanceDmg = dmg, fx = counter and "counter" or "hit",
			})
			if connected(r) then
				break
			end
		end
	end)
end

local function doCharge(e, dir)
	local def = CFG.Charge
	local char = charOf(e)
	setAct(char, "charge")
	char:SetAttribute("Charging", true)
	sendKnock(e, dir * def.Impulse, 0, 0, 0)
	-- El resto de la embestida lo lleva tickCharges() desde el Heartbeat del modulo.
	local t0 = os.clock()
	activeCharges[#activeCharges + 1] = {
		char = char, entry = e, dir = dir, def = def,
		tCheck = t0 + 0.03, tEnd = t0 + def.Duration, result = nil,
	}
end

local function doGrab(e, dir)
	local def = CFG.Grab
	local char = charOf(e)
	setAct(char, "grab")
	task.delay(def.Windup, function()
		if not canKeepActing(e) then
			return
		end
		local t = os.clock()
		local _, _, root = partsOf(e)
		local list = targetsInCone(e, dir, def.Range, def.Cone)
		local v = list[1] and list[1].entry
		if not v then
			sendKnock(e, Vector3.zero, 0, 0, 0.6) -- el aceite lo hizo escurrirse: falla
			return
		end
		local vchar, _, vroot = partsOf(v)
		if t < v.dodgeIFramesUntil then
			daze(e, CFG.Dodge.WhiffDaze) -- esquivaron el agarre
			sendKnock(e, Vector3.zero, 0, 0, CFG.Dodge.WhiffDaze)
			if vroot then
				fx("dodge", vroot.Position, dir, 20)
			end
			notify(v, "dodged")
			return
		end
		if t < v.invulnUntil or t < v.spawnInvulnUntil or v.heldBy or v.holding then
			sendKnock(e, Vector3.zero, 0, 0, 0.6)
			return
		end
		if vroot and isParrying(v, t, vroot, root, dir) then
			doParry(e, v, dir) -- parry al agarre: el agarrador queda aturdido
			return
		end
		if v.blocking then
			stopBlock(v, true) -- el agarre rompe el bloqueo
		end
		e.holding = v
		v.heldBy = e
		setHeld(e, true)
		setHeld(v, true)
		if vchar then
			setAct(vchar, "grabbed")
			fx("grab", vroot.Position, dir, 20)
		end
		local token = {}
		e.holdToken = token
		task.delay(def.Hold, function()
			if e.holdToken ~= token or e.holding ~= v then
				return -- contraatacado o cancelado
			end
			e.holdToken = nil
			releaseHold(e, v)
			if match and match.fighting and isAlive(e) and isAlive(v) and not e.out and not v.out then
				local echar = charOf(e)
				if echar then
					setAct(echar, "throw")
				end
				resolveHit(e, v, dir, {
					force = def.Force, stun = def.Stun, lift = def.Lift, stagger = 0,
					balanceDmg = CFG.Balance.Damage.throw, fx = "throw", unblockable = true,
				})
			end
		end)
	end)
end

local function doDodge(e, dir)
	local def = CFG.Dodge
	local char = charOf(e)
	local _, _, root = partsOf(e)
	local t = os.clock()
	stopBlock(e, false)
	setAct(char, "dodge")
	e.dodgeUntil = t + def.Duration
	e.dodgeIFramesUntil = t + def.IFrames
	sendKnock(e, dir * def.Impulse, 0, 0, 0)
	if root then
		fx("dash", root.Position, dir, def.Impulse)
	end
end

function OilCombat.perform(e, action, aim)
	if not match or not match.fighting then
		return
	end
	local char, hum, root = partsOf(e)
	if not char or hum.Health <= 0 or e.out then
		return
	end

	-- Bloqueo: se mantiene mientras R esté pulsada
	if action == "block" then
		startBlock(e)
		return
	end
	if action == "unblock" then
		stopBlock(e, true)
		return
	end

	local key = ACTIONS[action]
	if not key then
		return
	end
	local def = CFG[key]
	local now = os.clock()

	local aimed = typeof(aim) == "Vector3" and flat(aim).Magnitude >= 0.1
	local dir = aimed and flat(aim) or flat(root.CFrame.LookVector)
	if action == "dodge" and not aimed then
		dir = -dir -- sin dirección: esquiva hacia atrás
	end
	dir = unitOr(dir, Vector3.new(0, 0, -1))

	-- Contraataque: te tienen agarrado y respondes con un golpe -> el agarrador sale despedido
	if e.heldBy and (action == "push" or action == "charge") then
		local g = e.heldBy
		dropHolds(e)
		local _, _, groot = partsOf(g)
		if groot then
			local back = unitOr(flat(groot.Position - root.Position), dir)
			setAct(char, "push")
			resolveHit(e, g, back, {
				force = CFG.CounterForce, stun = 1.0, lift = 14, stagger = 0,
				balanceDmg = CFG.Balance.Damage.counter, fx = "counter", unblockable = true,
			})
			e.invulnUntil = now + 0.5
		end
		return
	end

	if char:GetAttribute("Locked") or char:GetAttribute("Held") or char:GetAttribute("Charging") or e.holding then
		return
	end
	if now < e.stunUntil or now < e.dazedUntil then
		return
	end

	-- Contraataque tras un parry: el próximo empujón es más fuerte, gratis y sin cooldown
	local isCounter = action == "push" and now < e.counterUntil
	if not isCounter and now < e.cd[action] then
		return
	end
	local cost = isCounter and 0 or (def.Stamina or 0)
	if e.stamina < cost then
		notify(e, "nostamina")
		return
	end

	-- Atacar baja la guardia (con su cooldown) y pierdes la invulnerabilidad de reaparición
	stopBlock(e, true)
	if action ~= "dodge" then
		e.spawnInvulnUntil = 0
	end
	spendStamina(e, cost)
	if isCounter then
		e.counterUntil = 0
	end
	startCooldown(e, action, def.Cooldown)

	if action == "push" then
		doPush(e, dir, isCounter)
	elseif action == "charge" then
		doCharge(e, dir)
	elseif action == "grab" then
		doGrab(e, dir)
	elseif action == "dodge" then
		doDodge(e, dir)
	end
end

-- Anti-abuso: mínimo 0.08s entre acciones iguales (misma tasa que ya deja pasar el
-- cliente) y 0.02s para block/unblock (solo dedupe de red; nunca corta un pulso humano).
local actionAt = setmetatable({}, { __mode = "k" }) -- [player] = { [accion] = reloj }
actionRemote.OnServerEvent:Connect(function(player, action, aim)
	if not match then
		return
	end
	if action ~= "block" and action ~= "unblock" and not ACTIONS[action] then
		return -- whitelist: cualquier otra cadena se descarta aquí mismo
	end
	local now = os.clock()
	local minGap = (action == "block" or action == "unblock") and 0.02 or 0.08
	local stamps = actionAt[player]
	if stamps and stamps[action] and now - stamps[action] < minGap then
		return
	end
	stamps = stamps or {}
	stamps[action] = now
	actionAt[player] = stamps
	if aim ~= nil then
		-- aim debe ser Vector3 finito; NaN/inf u otros tipos -> nil (perform usa la mirada)
		local finite = typeof(aim) == "Vector3"
		if finite then
			local mag = aim.Magnitude
			finite = mag == mag and mag ~= math.huge
		end
		if not finite then
			aim = nil
		end
	end
	for _, e in ipairs(match.fighters) do
		if e.player == player then
			OilCombat.perform(e, action, aim)
			return
		end
	end
end)

-- ===== Regeneración y estados (10 veces por segundo) =====
local function tickMatch(dt)
	local m = match
	if not m then
		return
	end
	local t = os.clock()
	local S, B = CFG.Stamina, CFG.Balance
	for _, e in ipairs(m.fighters) do
		local char = charOf(e)
		if char and char.Parent then
			-- Stamina: sostener el bloqueo la drena; si no gastas nada un rato, se regenera
			if e.blocking then
				e.stamina = math.max(0, e.stamina - S.BlockDrainPerSec * dt)
				e.staminaSpentAt = t
				if e.stamina <= 0 then
					stopBlock(e, true)
					daze(e, S.GuardBreakDaze)
					sendKnock(e, Vector3.zero, 0, 0, S.GuardBreakDaze)
					local _, _, root = partsOf(e)
					if root then
						fx("guardbreak", root.Position, Vector3.zero, 30)
					end
					notify(e, "guardbreak")
				end
			elseif t - e.staminaSpentAt >= S.RegenDelay then
				e.stamina = math.min(S.Max, e.stamina + S.RegenPerSec * dt)
			end

			-- Equilibrio: desequilibrado hasta que pase BrokenTime; si no, regenera tras RegenDelay
			if e.brokenUntil > 0 then
				if t >= e.brokenUntil then
					e.brokenUntil = 0
					e.balance = B.BrokenRecover
					e.balanceHitAt = t
				end
			elseif t - e.balanceHitAt >= B.RegenDelay then
				e.balance = math.min(B.Max, e.balance + B.RegenPerSec * dt)
			end

			-- La guardia se cae si pierdes el control
			if e.blocking and (e.heldBy or t < e.stunUntil or t < e.dazedUntil or char:GetAttribute("Locked")) then
				stopBlock(e, false)
			end

			publish(e, t)
		end
	end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	-- El servidor es dueño de la física del gladiador IA
	OilPhysics.step(dt)
	-- Embestidas en curso: una comprobación de impacto por frame
	tickCharges()
	acc += dt
	if acc >= 0.1 then
		local d = acc
		acc = 0
		local ok, err = pcall(tickMatch, d)
		if not ok then
			warn("[OilCombat] tick:", err)
		end
	end
end)

-- ===== Gladiador IA =====
local function aiThink(e)
	local ai = e.ai
	local char, hum, root = partsOf(e)
	if not char or hum.Health <= 0 or not match or not match.fighting then
		ai.intent = Vector3.zero
		return
	end
	local now = os.clock()
	if char:GetAttribute("Locked") or char:GetAttribute("Held") or now < e.stunUntil or now < e.dazedUntil or e.out then
		ai.intent = Vector3.zero
		return
	end

	local target, tdist, tdir
	for _, o in ipairs(match.fighters) do
		if o ~= e and not o.out then
			local _, ohum, oroot = partsOf(o)
			if oroot and ohum.Health > 0 then
				local d = flat(oroot.Position - root.Position)
				if not tdist or d.Magnitude < tdist then
					target, tdist, tdir = o, d.Magnitude, d
				end
			end
		end
	end
	if not target then
		ai.intent = Vector3.zero
		return
	end
	tdir = unitOr(tdir, flat(root.CFrame.LookVector))
	ai.face = tdir

	local arena = OilPhysics.getArena()
	local rel = arena.CFrame:PointToObjectSpace(root.Position)
	local edge = math.min(arena.Size.X / 2 - math.abs(rel.X), arena.Size.Z / 2 - math.abs(rel.Z))
	local toCenter = unitOr(flat(arena.Position - root.Position), tdir)
	local sideDir = Vector3.new(-tdir.Z, 0, tdir.X)
	local side = sideDir * math.sin(now * 1.6 + ai.seed)

	if edge < 10 then
		-- instinto de supervivencia: volver al centro, más fuerte cuanto más cerca del borde
		local urgency = math.clamp((10 - edge) / 10, 0.3, 1)
		ai.intent = unitOr(toCenter * urgency + tdir * (1 - urgency) * 0.5, toCenter) * 0.9
	elseif tdist > 7 then
		ai.intent = unitOr(tdir + side * 0.45, tdir) * 0.85
	else
		ai.intent = unitOr(tdir * 0.35 + side * 0.9, side) * 0.55
	end

	-- Reacción defensiva: si el rival ataca de cerca, a veces esquiva y a veces bloquea
	if now >= (e.aiReactNext or 0) and not e.blocking then
		local tchar = charOf(target)
		local act = tchar and tchar:GetAttribute("Act")
		local actT = tchar and tchar:GetAttribute("ActT")
		if (act == "push" or act == "charge" or act == "grab") and actT
			and (workspace:GetServerTimeNow() - actT) < 0.3 and tdist < 10 then
			e.aiReactNext = now + 1.2
			local r = math.random()
			if r < 0.2 then
				local away = sideDir * (math.random() < 0.5 and 1 or -1)
				task.delay(0.02 + math.random() * 0.06, function()
					OilCombat.perform(e, "dodge", away)
				end)
			elseif r < 0.5 then
				task.delay(0.02 + math.random() * 0.05, function()
					OilCombat.perform(e, "block")
				end)
				task.delay(0.5 + math.random() * 0.35, function()
					OilCombat.perform(e, "unblock")
				end)
			end
		end
	end

	if now >= e.aiNext and not e.blocking then
		if tdist < CFG.Push.Range - 0.8 and now >= e.cd.push and math.random() < 0.6 then
			e.aiNext = now + 0.25 + math.random() * 0.35
			OilCombat.perform(e, "push", tdir)
		elseif tdist < CFG.Grab.Range - 0.6 and now >= e.cd.grab and math.random() < 0.18 then
			e.aiNext = now + 0.8
			OilCombat.perform(e, "grab", tdir)
		elseif tdist > 10 and tdist < 24 and now >= e.cd.charge and edge > 13 and math.random() < 0.22 then
			e.aiNext = now + 0.8
			OilCombat.perform(e, "charge", tdir)
		end
	end
end

function startAI(e)
	local char, hum, root = partsOf(e)
	if not char then
		return
	end
	e.ai = { intent = Vector3.zero, face = nil, seed = math.random() * 10 }
	e.aiNext = 0
	e.aiReactNext = 0
	hum.DisplayName = e.name
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	OilPhysics.attach(char, {
		getIntent = function()
			return e.ai.intent
		end,
		getFace = function()
			return e.ai.face
		end,
	})
	task.spawn(function()
		while match and match.active and not e.released do
			task.wait(0.1)
			local ok, err = pcall(aiThink, e)
			if not ok then
				warn("[OilCombat] IA:", err)
			end
		end
	end)
end

-- ===== Flujo de rondas =====
local function placeFighters()
	local n = #match.fighters
	for i, e in ipairs(match.fighters) do
		local char, hum, root = partsOf(e)
		if char then
			resetCombatState(e)
			if e.kind == "player" then
				for _, a in ipairs(ACTION_LIST) do
					e.player:SetAttribute("cd_" .. a, 0)
				end
			end
			for _, a in ipairs({ "Held", "Charging", "Act", "ActT", "Blocking", "Dazed" }) do
				char:SetAttribute(a, nil)
			end
			char:SetAttribute("Locked", true)
			hum.PlatformStand = false
			char:PivotTo(spawnCFrame(i, n))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			if e.kind == "ai" then
				OilPhysics.reset(char)
				e.ai.intent = Vector3.zero
			elseif e.player.Parent then
				knockRemote:FireClient(e.player, "reset")
			end
			publish(e, os.clock())
		end
	end
end

local function lockAll(on)
	for _, e in ipairs(match.fighters) do
		local char = charOf(e)
		if char then
			char:SetAttribute("Locked", on and true or nil)
		end
	end
end

local function countdown(m)
	for n = CFG.CountdownSeconds, 1, -1 do
		eventRemote:FireAllClients("countdown", n, m.round)
		task.wait(1)
		if not m.active or #m.fighters < 2 then
			return false
		end
	end
	eventRemote:FireAllClients("go", m.round)
	return true
end

-- Devuelve "out", lista | "timeout" | "abort"
local function runRound(m)
	local t0 = os.clock()
	workspace:SetAttribute("OilSlick", 1)
	while m.active do
		task.wait(0.05)
		local el = os.clock() - t0

		-- El aceite se calienta: cada vez más resbaladizo con el paso del tiempo
		if el > CFG.SlickRampStart then
			local f = math.clamp((el - CFG.SlickRampStart) / (CFG.RoundTimeout - CFG.SlickRampStart), 0, 1)
			workspace:SetAttribute("OilSlick", 1 + (CFG.SlickMax - 1) * f)
		end

		local outList = {}
		for i = #m.fighters, 1, -1 do
			local e = m.fighters[i]
			local char, hum, root = partsOf(e)
			if not char or hum.Health <= 0 then
				-- abandonó o murió
				dropHolds(e)
				releaseFighter(e)
				table.remove(m.fighters, i)
				eventRemote:FireAllClients("roster", fighterList())
			elseif isOut(root) then
				table.insert(outList, e)
			end
		end
		if #m.fighters < 2 then
			return "abort"
		end
		if #outList > 0 then
			return "out", outList
		end
		if el > CFG.RoundTimeout then
			return "timeout"
		end
	end
	return "abort"
end

local function handleOut(m, outList)
	local victim = outList[1]
	for _, e in ipairs(outList) do
		e.out = true
		dropHolds(e)
		stopBlock(e, false)
	end

	local scorer = nil
	if #outList == 1 then
		local lh = victim.lastHit
		if lh and (os.clock() - lh.t) <= CFG.AssistWindow and table.find(m.fighters, lh.by) and isAlive(lh.by) and not lh.by.out then
			scorer = lh.by
		elseif #m.fighters == 2 then
			scorer = (m.fighters[1] == victim) and m.fighters[2] or m.fighters[1]
		end
	end

	local _, _, vroot = partsOf(victim)
	fx("ringout", vroot and vroot.Position or Vector3.zero, Vector3.zero, 70)

	if scorer then
		scorer.score += 1
		if scorer.kind == "player" and scorer.player then
			progress("RecordRingout", scorer.player)
		end
		eventRemote:FireAllClients("point", scorer.name, victim.name, fighterList())
	else
		eventRemote:FireAllClients("noscore", victim.name, fighterList())
	end

	task.wait(CFG.PostPointPause)
	if scorer and scorer.score >= CFG.PointsToWin and table.find(m.fighters, scorer) then
		return scorer
	end
	return nil
end

-- Bloquea hasta que alguien llega a PointsToWin (o solo queda uno porque los demás renunciaron).
-- defs: { {kind="player", player=...}, {kind="ai", model=..., name=...} }
--
-- Este cuerpo puede lanzar errores; quien lo envuelve es OilCombat.runMatch, que garantiza
-- la limpieza del estado global pase lo que pase (bug #1 de docs/OILCOMBAT.md).
local function runMatchBody(defs)
	if match then
		return nil
	end
	local fighters = {}
	for _, d in ipairs(defs) do
		local e = {
			kind = d.kind,
			player = d.player,
			model = d.model,
			name = d.name or (d.player and d.player.Name) or "Luchador",
			score = 0,
			aiNext = 0,
		}
		resetCombatState(e)
		if partsOf(e) then
			table.insert(fighters, e)
		end
	end
	if #fighters < 2 or not OilPhysics.getArena() then
		warn("[OilCombat] No hay suficientes luchadores válidos o falta OilWrestlingRing.OilArena")
		return nil
	end

	local m = { fighters = fighters, active = true, fighting = false, round = 0 }
	match = m
	local participants = {}
	for _, e in ipairs(fighters) do
		participants[#participants + 1] = e
	end
	workspace:SetAttribute("OilMatchActive", true)
	for _, e in ipairs(fighters) do
		prepFighter(e)
	end
	eventRemote:FireAllClients("match_start", fighterList(), CFG.PointsToWin)

	local winner = nil
	local reason = nil
	while m.active and #m.fighters >= 2 do
		m.round += 1
		placeFighters()
		if not countdown(m) then
			break
		end
		lockAll(false)
		local t = os.clock()
		for _, e in ipairs(m.fighters) do
			e.spawnInvulnUntil = t + CFG.SpawnInvuln -- invulnerables al reaparecer (se pierde si atacas)
		end
		m.fighting = true
		local result, extra = runRound(m)
		m.fighting = false
		if not m.active then
			break
		end
		lockAll(true)
		if result == "out" then
			winner = handleOut(m, extra)
			if winner then
				reason = "points"
				break
			end
		elseif result == "timeout" then
			eventRemote:FireAllClients("draw", "timeout")
			task.wait(2.2)
		else
			break
		end
	end

	-- Si solo queda un luchador porque los demás renunciaron o se fueron, gana por abandono
	if not winner and m.active and #m.fighters == 1 then
		winner = m.fighters[1]
		reason = "forfeit"
	end

	-- Recompensas (XP, monedas, misiones, racha). Solo si el combate terminó con un ganador.
	if winner then
		local list, hasAI = {}, false
		for _, e in ipairs(participants) do
			if e.kind == "ai" then
				hasAI = true
			elseif e.player then
				list[#list + 1] = { player = e.player, forfeited = e.forfeited == true, score = e.score }
			end
		end
		progress("RecordMatchEnd", {
			completed = true,
			winner = winner.player,
			winnerScore = winner.score,
			participants = list,
			vsAI = hasAI,
			reason = reason,
		})
	end

	m.active = false
	m.fighting = false
	workspace:SetAttribute("OilMatchActive", nil)
	workspace:SetAttribute("OilSlick", nil)

	if winner then
		local _, _, wroot = partsOf(winner)
		lockAll(true)
		
		-- Conteo regresivo de 5 segundos antes de volver al spawn
		for i = 5, 1, -1 do
			eventRemote:FireAllClients("match_end", string.format("%s (Lobby en %ds)", winner.name, i), fighterList(), reason)
			task.wait(1)
		end
		
		-- Regresar jugadores activos al broadcast spawn
		for _, f in ipairs(m.fighters) do
			if f.player and f.player.Character then
				local root = f.player.Character:FindFirstChild("HumanoidRootPart")
				local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
				if root and spawn then
					root.CFrame = spawn.CFrame * CFrame.new(math.random(-3, 3), 4, math.random(-2, 2))
				end
			end
		end
		
		eventRemote:FireAllClients("match_end", winner.name, fighterList(), reason)
		if wroot then
			fx("victory", wroot.Position, Vector3.zero, 60)
		end
		task.wait(CFG.VictoryPause)
	else
		eventRemote:FireAllClients("match_end", nil, fighterList(), nil)
	end

	for _, e in ipairs(m.fighters) do
		releaseFighter(e)
	end
	match = nil
	return winner and { name = winner.name, player = winner.player, reason = reason } or nil
end

-- Limpieza de emergencia: deja el estado global como si el combate hubiera terminado bien.
-- Es idempotente (releaseFighter ya es idempotente) y segura si runMatchBody falló a mitad:
-- sin esto, match quedaba ~= nil para siempre y el servidor no podia iniciar otro combate.
local function forceCleanup()
	local m = match
	if not m then
		return
	end
	match = nil
	m.active = false
	m.fighting = false
	workspace:SetAttribute("OilMatchActive", nil)
	workspace:SetAttribute("OilSlick", nil)
	for _, e in ipairs(m.fighters or {}) do
		pcall(releaseFighter, e)
	end
end

-- Punto de entrada público. Envuelve el cuerpo del combate en pcall + limpieza para que un
-- error interno no deje el servidor colgado (bug #1 de docs/OILCOMBAT.md).
function OilCombat.runMatch(defs)
	local ok, res = pcall(runMatchBody, defs)
	if not ok then
		-- res es el mensaje de error, no un resultado: se descarta y se devuelve nil.
		warn("[OilCombat] runMatch falló, limpiando estado:", res)
		pcall(forceCleanup)
		return nil
	end
	return res
end

-- RENUNCIAR: el jugador abandona la pelea. Sale del combate y el rival gana (si solo quedaba uno).
-- Devuelve true si estaba peleando. Quien llama (MatchLoop) lo manda al lobby.
function OilCombat.resign(player)
	local m = match
	if not m or not m.active then
		return false
	end
	local idx, e
	for i, f in ipairs(m.fighters) do
		if f.player == player then
			idx, e = i, f
			break
		end
	end
	if not e then
		return false
	end
	dropHolds(e)
	e.forfeited = true
	table.remove(m.fighters, idx)
	releaseFighter(e)
	eventRemote:FireAllClients("forfeit", e.name, fighterList())
	return true
end

function OilCombat.abort()
	if match then
		match.active = false
	end
end

function OilCombat.isRunning()
	return match ~= nil
end

-- Si alguien se desconecta en pleno combate, cuenta como renuncia
Players.PlayerRemoving:Connect(function(player)
	OilCombat.resign(player)
end)

return OilCombat
