-- CharacterAnimator (LocalScript, StarterPlayerScripts)
-- Animacion procedural y fluida para TODOS los luchadores (jugadores y rivales IA), pensada para
-- el ambiente del juego: gladiadores romanos luchando sobre aceite.
--
-- Como funciona:
--  * Corre en cada cliente y anima a todos los personajes (no solo al propio), asi que todos ven
--    lo mismo. Mueve las articulaciones por codigo (Transform de Motor6D / AnimationConstraint),
--    sin necesidad de assets de animacion.
--  * Lee lo que el servidor ya publica en cada luchador: State, Act/ActT, Blocking, Dazed, Held,
--    Charging, Locked, mas la velocidad real del personaje y el aceite (OilSlick).
--  * Lobby: postura erguida de gladiador, marcha y carrera con balanceo, miradas al publico y
--    gestos (saludo romano, flexion de biceps, estiramiento).
--  * Combate: guardia baja y agil, pasos cortos, mirada fija en el rival, y poses propias para
--    empujon, embestida, agarre, lanzamiento, esquiva, bloqueo, aturdimiento, desequilibrio,
--    derribo y cuando te agarran.
--  * Salto, caida y aterrizaje con amortiguacion; derrape al frenar sobre el aceite.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local splashMod = ReplicatedStorage:WaitForChild("OilSplash", 10)
local OilSplash = splashMod and require(splashMod)
local physicsMod = ReplicatedStorage:WaitForChild("OilPhysics", 10)
local OilPhysics = physicsMod and require(physicsMod)
local cfgMod = ReplicatedStorage:WaitForChild("OilConfig", 10)
local SLIDE = (cfgMod and require(cfgMod).SlideBoost) or 1 -- cuanto resbala el suelo (OilConfig.SlideBoost)

local CONFIG = {
	Intensity = 1.0,       -- 0.6 = mas sutil | 1.4 = mas exagerado (marcha y movimientos sutiles)
	Smoothing = 22,        -- mayor = mas reactivo | menor = mas suave
	HeadLook = true,       -- en combate la cabeza sigue al rival
	IdleGestures = true,   -- gestos en el lobby cuando estas quieto
	MaxDistance = 260,     -- no se anima a quien este mas lejos de la camara
	DefaultLegLength = 2.4, -- suma hueso muslo + espinilla de un R15 normal (para escalar)
}

local abs, sin, cos, sqrt, exp, acos, atan2 = math.abs, math.sin, math.cos, math.sqrt, math.exp, math.acos, math.atan2
local clamp, max, min, pi = math.clamp, math.max, math.min, math.pi
local TAU = pi * 2

local function lerp(a, b, t) return a + (b - a) * t end
local function smooth01(x) x = clamp(x, 0, 1) return x * x * (3 - 2 * x) end
local function approach(cur, target, rate, dt) return cur + (target - cur) * (1 - exp(-rate * dt)) end
local function wrapAngle(a) return (a + pi) % TAU - pi end

-- ============================================================
-- PARAMETROS DE POSE (macro). Todos en radianes salvo crouch/bob (studs).
--  lean: inclinacion del cuerpo entero hacia delante | chest: del torso | roll: hacia la derecha
--  twist: torso gira a la izquierda | crouch: bajar la cadera | spread: separar piernas
--  rSh/lSh: brazo hacia delante | rAb/lAb: brazo hacia afuera | rEl/lEl: flexion de codo
--  rHip/lHip: muslo hacia delante | rKnee/lKnee: flexion de rodilla | legComp: 1 = las piernas
--  no siguen la inclinacion del cuerpo (pies plantados), 0 = el cuerpo entero se inclina
-- ============================================================
local KEYS = {
	"lean", "chest", "roll", "twist", "crouch", "spread", "bob", "legComp",
	"headPitch", "headYaw", "headRoll",
	"rSh", "lSh", "rAb", "lAb", "rEl", "lEl", "rWr", "lWr",
	"rHip", "lHip", "rKnee", "lKnee", "rAnk", "lAnk",
}
local function newParams()
	local p = {}
	for i = 1, #KEYS do p[KEYS[i]] = 0 end
	p.legComp = 1
	return p
end
local function full(pose)
	local t = newParams()
	for k, v in pairs(pose) do t[k] = v end
	return t
end
local function copyInto(dst, src)
	for i = 1, #KEYS do
		local k = KEYS[i]
		dst[k] = src[k]
	end
end
local function blend(dst, src, w)
	if w <= 0.002 then return end
	for i = 1, #KEYS do
		local k = KEYS[i]
		dst[k] += (src[k] - dst[k]) * w
	end
end
local function K(t, pose, ease) return { t = t, p = full(pose), e = ease } end

local function sampleKeys(keys, t, out)
	local first, last = keys[1], keys[#keys]
	if t <= first.t then copyInto(out, first.p) return end
	if t >= last.t then copyInto(out, last.p) return end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.t then
			local u = (t - a.t) / (b.t - a.t)
			if b.e == "out" then u = 1 - (1 - u) * (1 - u)
			elseif b.e == "in" then u = u * u
			else u = u * u * (3 - 2 * u) end
			for j = 1, #KEYS do
				local k = KEYS[j]
				out[k] = a.p[k] + (b.p[k] - a.p[k]) * u
			end
			return
		end
	end
	copyInto(out, last.p)
end

-- ============================================================
-- POSES ESTATICAS
-- ============================================================
local POSE = {}

-- Estados de IMPACTO: los que el cuerpo RECIBE (empujon, golpe, caida, desequilibrio,
-- embestida). Entran rapido (el golpe tiene que notarse ya) y se recuperan despacio
-- (la recuperacion es justo lo que se percibe como peso).
-- Los estados sostenidos (guardia, bloqueo, agarre) usan rates suaves.
local IMPACT_STATES = {
	pushed = true, knocked = true, dazed = true, offbalance = true, charge = true,
}
local IMPACT_IN, IMPACT_OUT = 34, 7 -- reactivo
local NEUTRAL_IN, NEUTRAL_OUT = 15, 9 -- sostenido

-- Lobby: erguido, pecho adelante, brazos sueltos y relajados
POSE.lobby = full{ chest = -0.05, rSh = 0.04, lSh = 0.04, rAb = 0.10, lAb = 0.10, rEl = 0.16, lEl = 0.16, headPitch = -0.02, spread = 0.07 }
-- Guardia de luchador: cadera baja, piernas abiertas, manos adelante listas para agarrar
POSE.guard = full{
	lean = 0.20, chest = 0.10, crouch = 0.55, spread = 0.30, twist = 0.18,
	rHip = 0.30, lHip = -0.22, rKnee = 0.12, lKnee = 0.06,
	rSh = 1.05, lSh = 0.85, rAb = 0.20, lAb = 0.20, rEl = 1.30, lEl = 1.40, rWr = 0.10, lWr = 0.10, headPitch = 0.12,
}
POSE.blocking = full{
	lean = 0.12, chest = 0.22, crouch = 0.65, spread = 0.34, twist = 0.15,
	rHip = 0.22, lHip = -0.18, rKnee = 0.10, lKnee = 0.10,
	rSh = 1.40, lSh = 1.35, rAb = 0.35, lAb = 0.35, rEl = 1.95, lEl = 1.95, headPitch = 0.28,
}
POSE.skid = full{
	lean = -0.28, chest = -0.10, crouch = 0.35, spread = 0.36,
	rHip = 0.30, lHip = 0.30, rKnee = 0.22, lKnee = 0.22,
	rSh = 0.70, lSh = 0.70, rAb = 0.95, lAb = 0.95, rEl = 0.35, lEl = 0.35, headPitch = -0.10,
}
-- Resbalon sobre aceite: cuerpo ladeado y brazos abiertos buscando el equilibrio
-- (las piernas van en molinete de forma procedural en la composicion)
POSE.slip = full{
	lean = -0.12, chest = 0.06, crouch = 0.42, spread = 0.44, twist = 0.10, roll = 0.10,
	rHip = 0.36, lHip = -0.30, rKnee = 0.24, lKnee = 0.10,
	rSh = 1.35, lSh = 1.30, rAb = 1.20, lAb = 1.15, rEl = 0.50, lEl = 0.55, headPitch = -0.08,
}
POSE.sit = full{ rHip = 1.5, lHip = 1.5, rKnee = 1.45, lKnee = 1.45, rSh = 0.3, lSh = 0.3, rAb = 0.15, lAb = 0.15, rEl = 0.5, lEl = 0.5 }
POSE.pushed = full{
	chest = -0.45, lean = -0.30, crouch = 0.25, spread = 0.25,
	rHip = -0.30, lHip = 0.25, rSh = 1.9, lSh = 1.8, rAb = 0.55, lAb = 0.55, rEl = 0.30, lEl = 0.30, headPitch = -0.40,
}
POSE.charge = full{
	lean = 1.15, chest = 0.15, legComp = 0, crouch = 0,
	rHip = -0.55, lHip = -0.35, rKnee = 0.65, lKnee = 0.90, rAnk = -0.5, lAnk = -0.5,
	rSh = 3.0, lSh = 3.0, rAb = 0.12, lAb = 0.12, rEl = 0.08, lEl = 0.08, headPitch = -0.6,
}
POSE.grabbing = full{
	lean = -0.22, chest = -0.15, crouch = 0.45, spread = 0.38,
	rHip = 0.15, lHip = -0.10, rSh = 2.85, lSh = 2.85, rAb = 0.30, lAb = 0.30, rEl = 0.45, lEl = 0.45, headPitch = -0.55,
}
POSE.airUp = full{
	lean = 0.10, rHip = 0.90, lHip = -0.25, rKnee = 1.2, lKnee = 0.6,
	rSh = 2.2, lSh = 2.0, rAb = 0.55, lAb = 0.55, rEl = 0.35, lEl = 0.45, headPitch = -0.12,
}
POSE.airDown = full{
	chest = -0.05, spread = 0.12, rHip = 0.35, lHip = 0.10, rKnee = 0.25, lKnee = 0.20,
	rSh = 2.45, lSh = 2.45, rAb = 0.70, lAb = 0.70, rEl = 0.20, lEl = 0.20, headPitch = -0.08,
}
-- Saludo romano: brazo derecho extendido en alto, puno izquierdo al pecho
POSE.salute = full{
	chest = -0.10, rSh = 2.0, rAb = 0.12, rEl = 0.25, lSh = 0.7, lAb = 0.15, lEl = 2.3, headPitch = -0.12, twist = -0.05, spread = 0.08,
}
POSE.flex = full{
	chest = -0.05, crouch = 0.15, spread = 0.25, rSh = 0.2, lSh = 0.2, rAb = 1.45, lAb = 1.45, rEl = 2.2, lEl = 2.2, headPitch = 0.05,
}
POSE.stretch = full{
	lean = -0.06, chest = -0.28, rSh = 2.9, lSh = 2.9, rAb = 0.35, lAb = 0.35, rEl = 0.2, lEl = 0.2, headPitch = -0.35, spread = 0.12,
}

-- ============================================================
-- ACCIONES TEMPORIZADAS (se disparan con el atributo Act del servidor)
-- ============================================================
local ACTIONS = {
	push = { dur = 0.62, fin = 0.05, fout = 0.30, keys = {
		K(0.00, { lean = 0.05, crouch = 0.60, spread = 0.30, rHip = 0.10, rSh = 0.60, lSh = 0.60, rAb = 0.30, lAb = 0.30, rEl = 1.60, lEl = 1.60, twist = 0.10, headPitch = 0.10 }),
		K(0.09, { lean = -0.12, chest = -0.14, crouch = 0.75, spread = 0.34, rHip = -0.15, lHip = 0.25, rSh = 0.25, lSh = 0.25, rAb = 0.45, lAb = 0.45, rEl = 1.75, lEl = 1.75, twist = 0.22, headPitch = 0.05 }),
		K(0.19, { lean = 0.62, chest = 0.20, crouch = 0.80, spread = 0.34, rHip = 0.75, lHip = -0.62, rKnee = 0.35, lKnee = 0.10, rSh = 1.78, lSh = 1.72, rAb = 0.10, lAb = 0.10, rEl = 0.12, lEl = 0.12, twist = -0.18, headPitch = -0.28 }, "out"),
		K(0.32, { lean = 0.50, chest = 0.16, crouch = 0.78, spread = 0.34, rHip = 0.70, lHip = -0.55, rKnee = 0.30, lKnee = 0.10, rSh = 1.65, lSh = 1.60, rAb = 0.12, lAb = 0.12, rEl = 0.25, lEl = 0.25, twist = -0.15, headPitch = -0.20 }),
		K(0.62, POSE.guard),
	} },
	grab = { dur = 0.30, fin = 0.05, fout = 0.16, keys = {
		K(0.00, { lean = 0.10, crouch = 0.60, spread = 0.30, rSh = 0.80, lSh = 0.80, rAb = 0.40, lAb = 0.40, rEl = 1.20, lEl = 1.20 }),
		K(0.12, { lean = 0.40, chest = 0.12, crouch = 0.75, spread = 0.34, rHip = 0.50, lHip = -0.40, rSh = 1.58, lSh = 1.58, rAb = 0.38, lAb = 0.38, rEl = 0.22, lEl = 0.22, headPitch = -0.15, twist = -0.10 }, "out"),
		K(0.30, { lean = 0.35, chest = 0.10, crouch = 0.72, spread = 0.34, rHip = 0.45, lHip = -0.35, rSh = 1.50, lSh = 1.50, rAb = 0.38, lAb = 0.38, rEl = 0.30, lEl = 0.30, headPitch = -0.12, twist = -0.08 }),
	} },
	throw = { dur = 0.58, fin = 0.04, fout = 0.30, keys = {
		K(0.00, POSE.grabbing),
		K(0.07, { lean = -0.30, chest = -0.28, crouch = 0.60, spread = 0.38, rSh = 3.0, lSh = 3.0, rAb = 0.30, lAb = 0.30, rEl = 0.60, lEl = 0.60, headPitch = -0.50 }),
		K(0.20, { lean = 0.70, chest = 0.25, crouch = 0.85, spread = 0.34, rHip = 0.80, lHip = -0.55, rKnee = 0.40, rSh = 1.05, lSh = 1.05, rAb = 0.20, lAb = 0.20, rEl = 0.15, lEl = 0.15, twist = -0.20, headPitch = -0.20 }, "out"),
		K(0.58, POSE.guard),
	} },
	dodge = { dur = 0.50, fin = 0.04, fout = 0.28, keys = {
		K(0.00, { crouch = 0.50, spread = 0.30, rSh = 0.90, lSh = 0.90, rAb = 0.30, lAb = 0.30, rEl = 1.60, lEl = 1.60 }),
		K(0.10, { crouch = 1.05, spread = 0.40, chest = 0.30, rSh = 0.90, lSh = 0.90, rAb = 0.50, lAb = 0.50, rEl = 2.00, lEl = 2.00, headPitch = 0.30, roll = 1, lean = 0.10 }, "out"),
		K(0.28, { crouch = 0.85, spread = 0.36, chest = 0.20, rSh = 1.00, lSh = 1.00, rAb = 0.35, lAb = 0.35, rEl = 1.70, lEl = 1.70, headPitch = 0.20, roll = 0.50, lean = 0.10 }),
		K(0.50, POSE.guard),
	} },
	-- retroceso al recibir un golpe
	stunned = { dur = 0.42, fin = 0.03, fout = 0.30, keys = {
		K(0.00, { chest = -0.50, lean = -0.32, crouch = 0.25, spread = 0.22, headPitch = -0.45, rSh = 1.6, lSh = 1.5, rAb = 0.65, lAb = 0.65, rEl = 0.35, lEl = 0.35, rHip = -0.35, lHip = 0.20 }),
		K(0.14, { chest = -0.30, lean = -0.18, crouch = 0.30, spread = 0.22, headPitch = -0.30, rSh = 1.2, lSh = 1.1, rAb = 0.60, lAb = 0.60, rEl = 0.50, lEl = 0.50, rHip = -0.20, lHip = 0.12 }),
		K(0.42, POSE.guard),
	} },
	-- sacudida al bloquear un golpe
	block = { dur = 0.30, fin = 0.02, fout = 0.22, keys = {
		K(0.00, { lean = -0.18, chest = 0.32, crouch = 0.80, spread = 0.36, rSh = 1.45, lSh = 1.40, rAb = 0.38, lAb = 0.38, rEl = 2.05, lEl = 2.05, headPitch = 0.32, rHip = 0.15, lHip = -0.25 }),
		K(0.30, POSE.blocking),
	} },
}

-- ============================================================
-- POSES DINAMICAS (dependen del tiempo / la velocidad)
-- ============================================================
local function poseAir(S, out)
	local f = smooth01((-S.vy + 4) / 18) -- 0 subiendo, 1 cayendo
	for i = 1, #KEYS do
		local k = KEYS[i]
		out[k] = lerp(POSE.airUp[k], POSE.airDown[k], f)
	end
end

local function poseDazed(S, now, out)
	copyInto(out, POSE.guard)
	local ph = now * 2.6 + S.seed
	out.headPitch = 0.38
	out.headYaw = 0.45 * sin(ph)
	out.headRoll = 0.25 * sin(ph * 0.8 + 1)
	out.roll = 0.12 * sin(ph * 0.9)
	out.lean = 0.22 + 0.06 * sin(ph * 1.7)
	out.chest = 0.25
	out.crouch = 0.50 + 0.08 * sin(ph * 2)
	out.spread = 0.22
	out.rSh = 0.20 + 0.25 * sin(ph)
	out.lSh = 0.20 + 0.25 * sin(ph + pi)
	out.rAb = 0.45
	out.lAb = 0.45
	out.rEl = 0.55
	out.lEl = 0.55
end

local function poseOffbalance(S, now, out)
	copyInto(out, POSE.guard)
	local ph = now * 8.5 + S.seed
	out.rSh = 1.3 + 1.0 * sin(ph)
	out.lSh = 1.3 + 1.0 * sin(ph + 2.9)
	out.rAb = 0.75
	out.lAb = 0.75
	out.rEl = 0.25
	out.lEl = 0.25
	out.roll = 0.20 * sin(now * 4.7 + S.seed)
	out.lean = 0.10 + 0.18 * sin(now * 3.9 + 1 + S.seed)
	out.chest = 0.10 * sin(now * 5.1)
	out.crouch = 0.50
	out.spread = 0.40
	out.rHip = 0.20 * sin(now * 7.3)
	out.lHip = -0.20 * sin(now * 7.3)
	out.headPitch = 0.05
end

local function poseGrabbing(S, now, out)
	copyInto(out, POSE.grabbing)
	local tr = sin(now * 31)
	out.rSh += 0.04 * tr
	out.lSh -= 0.04 * tr
	out.crouch += 0.04 * sin(now * 17)
end

local function poseGrabbed(S, now, out)
	copyInto(out, POSE.pushed)
	local ph = now * 11 + S.seed
	out.legComp = 0
	out.lean = -0.25
	out.chest = -0.20
	out.crouch = 0
	out.rSh = 2.35 + 0.45 * sin(ph)
	out.lSh = 2.35 + 0.45 * sin(ph + 2.2)
	out.rAb = 0.60
	out.lAb = 0.60
	out.rEl = 0.60 + 0.40 * sin(ph * 1.3)
	out.lEl = 0.60 + 0.40 * sin(ph * 1.3 + 1)
	out.rHip = 0.50 * sin(ph * 0.9)
	out.lHip = -0.50 * sin(ph * 0.9)
	out.rKnee = 0.50 + 0.30 * sin(ph)
	out.lKnee = 0.50 + 0.30 * sin(ph + 1.7)
	out.headPitch = -0.40
	out.roll = 0.15 * sin(ph * 0.7)
	out.spread = 0.2
end

local function poseKnocked(S, now, out)
	local k = clamp(S.spd / 20, 0, 1)
	local t = now + S.seed
	copyInto(out, POSE.lobby)
	out.legComp = 0
	out.rSh = lerp(0.9, 2.5, k) + 0.25 * sin(t * 7)
	out.lSh = lerp(0.9, 2.5, k) + 0.25 * sin(t * 6.3 + 2)
	out.rAb = lerp(0.9, 1.0, k)
	out.lAb = lerp(0.9, 1.0, k)
	out.rEl = 0.5 + 0.3 * sin(t * 8)
	out.lEl = 0.5 + 0.3 * sin(t * 7.2 + 1)
	out.rHip = lerp(0.1, 0.7, k) + 0.2 * sin(t * 5.5)
	out.lHip = lerp(-0.1, -0.4, k) + 0.2 * sin(t * 6.1 + 1)
	out.rKnee = 0.4 + 0.2 * sin(t * 6)
	out.lKnee = 0.5 + 0.2 * sin(t * 5 + 2)
	out.spread = 0.35
	out.headPitch = -0.2 * k
end

-- ============================================================
-- RIG: busca las articulaciones (R15 con AnimationConstraint o Motor6D, y R6)
-- ============================================================
local JOINTS_R15 = {
	root = "Root", waist = "Waist", neck = "Neck",
	rSh = "RightShoulder", lSh = "LeftShoulder", rEl = "RightElbow", lEl = "LeftElbow", rWr = "RightWrist", lWr = "LeftWrist",
	rHip = "RightHip", lHip = "LeftHip", rKn = "RightKnee", lKn = "LeftKnee", rAn = "RightAnkle", lAn = "LeftAnkle",
}
local JOINTS_R6 = {
	root = "RootJoint", neck = "Neck", rSh = "Right Shoulder", lSh = "Left Shoulder", rHip = "Right Hip", lHip = "Left Hip",
}

local function frameRotation(joint)
	local cf
	if joint:IsA("Motor6D") then
		cf = joint.C0
	else
		cf = joint.Attachment0 and joint.Attachment0.CFrame or CFrame.new()
	end
	return cf - cf.Position
end

local function buildRig(S)
	local char, hum = S.char, S.hum
	if not char:FindFirstChild("HumanoidRootPart") then return false end
	local byName = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			byName[d.Name] = d
		end
	end
	local isR6 = hum.RigType == Enum.HumanoidRigType.R6
	local names = isR6 and JOINTS_R6 or JOINTS_R15
	local j = {}
	for key, name in pairs(names) do
		local inst = byName[name]
		if inst then
			local rot0 = frameRotation(inst)
			j[key] = { j = inst, rot0 = rot0, inv0 = rot0:Inverse() }
		end
	end
	if not (j.root and j.rSh and j.lSh and j.rHip and j.lHip) then return false end

	local D, hasKnees = 0, false
	if not isR6 and j.rKn and j.lKn then
		local up, lo = char:FindFirstChild("RightUpperLeg"), char:FindFirstChild("RightLowerLeg")
		if up and lo then
			local hip = up:FindFirstChild("RightHipRigAttachment")
			local knee = up:FindFirstChild("RightKneeRigAttachment")
			local knee2 = lo:FindFirstChild("RightKneeRigAttachment")
			local ankle = lo:FindFirstChild("RightAnkleRigAttachment")
			if hip and knee and knee2 and ankle then
				D = (hip.Position - knee.Position).Magnitude + (knee2.Position - ankle.Position).Magnitude
				hasKnees = true
			end
		end
	end
	S.rig = { j = j, D = D, hasKnees = hasKnees, k = (D > 0) and (D / CONFIG.DefaultLegLength) or 1, isR6 = isR6 }
	return true
end

local function setJoint(jd, cf)
	if jd then
		jd.j.Transform = jd.inv0 * cf * jd.rot0
	end
end

-- Convierte los parametros de pose finales en rotaciones de articulaciones
-- ============================================================
-- SEGUNDO MOVIMIENTO (follow-through)
-- ============================================================
-- Hombros, codos y cuello NO siguen al torso al instante: lo persiguen con retardo
-- y rebotan al frenar. Implementado como muelle amortiguado (x'' = k*(obj-x) - c*x')
-- sobre el error entre la pose final (F) y su propia version retrasada, de modo que
-- el rebote sale de la dinamica del muelle y no de un seno fabricationado: responde
-- igual a golpes, giros, frenadas y caidas.
--
-- Se guarda en S.fk (estado por personaje) y devuelve el ajuste ya aplicado sobre F.
local FK_KEYS = { "rSh", "lSh", "rEl", "lEl" }
local FK_HEAD = { "headPitch", "headYaw" }

local function followThrough(S, F, dt, intensity)
	local fk = S.fk

	-- 1) Muelle por articulacion: persiguen la pose final con retardo.
	--    El error (obj - x) es justo "lo que aun no ha llegado".
	for _, key in ipairs(FK_KEYS) do
		local vkey = key .. "V"
		local v = fk[vkey] or 0
		local x = fk[key] or F[key] -- primer frame: sin muelle, arranca en la pose
		local a = (F[key] - x) * 210 - v * 21
		v += a * dt
		x += v * dt
		fk[key] = x
		fk[vkey] = v
	end
	for _, key in ipairs(FK_HEAD) do
		local vkey = key .. "V"
		local v = fk[vkey] or 0
		local x = fk[key] or F[key]
		local a = (F[key] - x) * 145 - v * 17
		v += a * dt
		x += v * dt
		fk[key] = x
		fk[vkey] = v
	end

	-- 2) Aplicar el retraso: la articulacion se queda donde va la inercia,
	--    no donde pide la pose. La velocidad del muelle amplifica el efecto:
	--    cuanto mas rapido se mueve, mas se "estira" (el latigazo del golpe).
	local whip = 0
	for _, key in ipairs(FK_KEYS) do
		local v = fk[key .. "V"]
		whip = math.max(whip, math.abs(v))
	end
	-- tope: con.Management golpes muy rapidos el muelle podria dar una vuelta de mas
	local k = clamp(whip * 0.055, 0, 0.55) * intensity

	for _, key in ipairs(FK_KEYS) do
		F[key] += (fk[key] - F[key]) * k
	end
	for _, key in ipairs(FK_HEAD) do
		F[key] += (fk[key] - F[key]) * k * 1.35 -- la cabeza exagerua un poco mas
	end
	return k
end

local function applyPose(S, F)
	local rig = S.rig
	local J = rig.j
	local k = rig.k
	local comp = F.legComp

	local crouchTotal, h = 0, 0
	if rig.hasKnees then
		crouchTotal = max(F.crouch, 0) * k + rig.D * (1 - cos(F.spread))
		h = acos(clamp(1 - crouchTotal / rig.D, 0.35, 1))
	end

	setJoint(J.root, CFrame.new(0, F.bob * k - crouchTotal, 0) * CFrame.Angles(-F.lean, 0, -F.roll))
	setJoint(J.waist, CFrame.Angles(-F.chest, F.twist, 0))
	setJoint(J.neck, CFrame.Angles(-F.headPitch + (F.lean + F.chest) * 0.65, F.headYaw - F.twist * 0.5, -F.headRoll + F.roll * 0.5))

	setJoint(J.rSh, CFrame.Angles(clamp(F.rSh, -2.2, 3.3), 0, F.rAb))
	setJoint(J.lSh, CFrame.Angles(clamp(F.lSh, -2.2, 3.3), 0, -F.lAb))
	setJoint(J.rEl, CFrame.Angles(max(F.rEl, -0.05), 0, 0))
	setJoint(J.lEl, CFrame.Angles(max(F.lEl, -0.05), 0, 0))
	setJoint(J.rWr, CFrame.Angles(F.rWr, 0, 0))
	setJoint(J.lWr, CFrame.Angles(F.lWr, 0, 0))

	local rHipP = F.rHip + h
	local lHipP = F.lHip + h
	local rFlex = max(F.rKnee, -0.05) + 2 * h
	local lFlex = max(F.lKnee, -0.05) + 2 * h
	setJoint(J.rHip, CFrame.Angles(rHipP + F.lean * comp, 0, F.spread + F.roll * comp))
	setJoint(J.lHip, CFrame.Angles(lHipP + F.lean * comp, 0, -F.spread + F.roll * comp))
	setJoint(J.rKn, CFrame.Angles(-rFlex, 0, 0))
	setJoint(J.lKn, CFrame.Angles(-lFlex, 0, 0))
	setJoint(J.rAn, CFrame.Angles(rFlex - rHipP + F.rAnk, 0, -(F.spread + F.roll * comp)))
	setJoint(J.lAn, CFrame.Angles(lFlex - lHipP + F.lAnk, 0, F.spread - F.roll * comp))
end

-- ============================================================
-- ESTADO POR PERSONAJE
-- ============================================================
local chars = {}
local rng = Random.new()

local function newState(char, hum)
	local S = {
		char = char, hum = hum, ready = false, tries = 0, nextTry = 0,
		player = Players:GetPlayerFromCharacter(char),
		seed = rng:NextNumber(0, 100),
		phase = 0, spd = 0, vy = 0, vs = 0, vf = 0, n = 0, accel = 0, lastSpd = 0, yawRate = 0, lastYaw = nil,
		grounded = true, wasGrounded = true, airT = 0, lastVy = 0, landX = 0, landV = 0,
		slipPhase = 0, wasKnocked = false, floorPos = nil,
		wGuard = 0, w = {}, act = nil, actStart = 0, lastActT = char:GetAttribute("ActT"),
		lastPushStart = char:GetAttribute("PushStartTime"), localPushAt = -10,
		dodgeRoll = 0, dodgeFwd = 0, gest = nil, nextGest = 0, nextTrackStop = 0,
		rival = nil, nextRival = 0, init = false, dead = false,
		fk = {}, -- segundo movimiento (follow-through): estado del muelle por articulacion
		B = newParams(), tmp = newParams(), cur = newParams(), F = newParams(),
	}
	for _, name in ipairs({ "sit", "air", "skid", "slip", "locked", "blocking", "offbalance", "pushed", "dazed", "grabbing", "grabbed", "knocked", "charge" }) do
		S.w[name] = 0
	end
	S.nextGest = os.clock() + 3 + rng:NextNumber(0, 4)
	S.rayParams = RaycastParams.new()
	S.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	S.rayParams.FilterDescendantsInstances = { char }
	return S
end

local function startAct(S, name, now)
	local def = ACTIONS[name]
	if not def then return end
	S.act, S.actStart = name, now
	if name == "dodge" then
		local hrp = S.char:FindFirstChild("HumanoidRootPart")
		local v = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
		local lv = hrp and hrp.CFrame:VectorToObjectSpace(v) or Vector3.zero
		local side, fwd = lv.X, -lv.Z
		if abs(side) >= abs(fwd) then
			S.dodgeRoll, S.dodgeFwd = clamp(side / 20, -1, 1) * 0.55, 0
		else
			S.dodgeRoll, S.dodgeFwd = 0, clamp(fwd / 20, -1, 1)
		end
	end
end

local function findRival(S, now)
	if now < S.nextRival then return end
	S.nextRival = now + 0.25
	local hrp = S.char:FindFirstChild("HumanoidRootPart")
	local best, bestD = nil, 80
	for other, O in pairs(chars) do
		if other ~= S.char and other.Parent and other:GetAttribute("State") ~= nil then
			local oh = other:FindFirstChild("HumanoidRootPart")
			if oh and hrp then
				local d = (oh.Position - hrp.Position).Magnitude
				if d < bestD then best, bestD = oh, d end
			end
		end
	end
	S.rival = best
end

-- ============================================================
-- ACTUALIZACION POR FRAME
-- ============================================================
local function step(S, dt, now)
	local char, hum = S.char, S.hum
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or hum.Health <= 0 then return end

	-- Los rivales IA o el Animate por defecto pueden reproducir pistas: aqui mandan las poses procedurales
	if now >= S.nextTrackStop then
		S.nextTrackStop = now + 0.3
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do tr:Stop(0.1) end
		end
	end

	-- ===== cinematica =====
	local v = hrp.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local spd = flat.Magnitude
	local look = hrp.CFrame.LookVector
	local lf = Vector3.new(look.X, 0, look.Z)
	lf = (lf.Magnitude > 0.05) and lf.Unit or Vector3.new(0, 0, -1)
	local rf = lf:Cross(Vector3.yAxis)
	S.spd, S.vy = spd, v.Y
	S.vf, S.vs = flat:Dot(lf), flat:Dot(rf)
	S.n = clamp(spd / max(hum.WalkSpeed, 8), 0, 1.8)

	-- Filtros de inercia. El rate determina cuanto tarda el cuerpo en "creer" el
	-- movimiento: con rates altos (30-40) el cuerpo responde al instante y la
	-- inercia sale de las poses, no del retraso del filtro. Antes iban en 12 y 10,
	-- que es lo que hacia que el luchador se deslizara.
	S.accel = approach(S.accel, (spd - S.lastSpd) / dt, 30, dt)
	S.lastSpd = spd
	local yaw = atan2(-look.X, -look.Z)
	if S.lastYaw then S.yawRate = approach(S.yawRate, wrapAngle(yaw - S.lastYaw) / dt, 26, dt) end
	S.lastYaw = yaw

	-- ===== suelo / aire / aterrizaje =====
	local state = char:GetAttribute("State")
	local knockedState = (state == "knocked") or hum.PlatformStand
	local hip = hum.HipHeight + hrp.Size.Y / 2 + 1.6
	local hit = Workspace:Raycast(hrp.Position, Vector3.new(0, -hip, 0), S.rayParams)
	S.wasGrounded = S.grounded
	S.grounded = hit ~= nil
	if S.grounded then
		S.airT = 0
		S.floorPos = hit.Position
	else
		S.airT += dt
	end
	if S.grounded and not S.wasGrounded and not knockedState then
		local impact = max(0, -S.lastVy)
		if impact > 10 then S.landV = min(impact * 0.55, 16) end
		if impact > 6 and OilSplash and OilPhysics and OilPhysics.isOverArena(hit.Position, 1) then
			OilSplash.land(hit.Position, impact)
		end
	end
	S.lastVy = v.Y
	-- Derribo: el cuerpo se estrella contra el charco y salpica hacia donde vuela
	if knockedState and not S.wasKnocked and OilSplash and S.floorPos then
		OilSplash.knock(S.floorPos, Vector3.new(v.X, 0, v.Z))
	end
	S.wasKnocked = knockedState
	-- amortiguador del aterrizaje (resorte)
	local acc = -220 * S.landX - 16 * S.landV
	S.landV += acc * dt
	S.landX += S.landV * dt

	-- ===== modo: lobby o combate =====
	local inMatch = (state ~= nil) or (S.player ~= nil and S.player:GetAttribute("InOilMatch") == true)
	S.wGuard = approach(S.wGuard, inMatch and 1 or 0, 7, dt)

	-- ===== acciones del servidor =====
	local actT = char:GetAttribute("ActT")
	if actT ~= S.lastActT then
		S.lastActT = actT
		local actName = char:GetAttribute("Act")
		if actName and ACTIONS[actName] and not (actName == "push" and now - S.localPushAt < 0.75) then
			startAct(S, actName, now)
		end
	end
	local ps = char:GetAttribute("PushStartTime") -- el cliente propio lo marca al instante (sin esperar al servidor)
	if ps and ps ~= S.lastPushStart then
		S.lastPushStart, S.localPushAt = ps, now
		startAct(S, "push", now)
	end

	-- ===== pesos de los estados =====
	local blocking = (char:GetAttribute("Blocking") == true) or state == "blocking"
	local held = char:GetAttribute("Held") == true
	local slick = Workspace:GetAttribute("OilSlick") or 1
	local tg = {
		sit = hum.Sit and 1 or 0,
		air = (not S.grounded and S.airT > 0.08 and not knockedState) and 1 or 0,
		skid = inMatch and S.grounded and clamp(-S.accel / (14 / SLIDE), 0, 1) * smooth01((spd - 5) / 6) or 0,
		slip = inMatch and S.grounded and smooth01((spd - 6) / 8) * clamp(abs(S.yawRate) / 4.5, 0, 1) or 0,
		locked = (char:GetAttribute("Locked") == true and not held) and 1 or 0,
		blocking = (blocking and not held) and 1 or 0,
		offbalance = (state == "offbalance") and 1 or 0,
		pushed = (state == "pushed") and 1 or 0,
		dazed = (char:GetAttribute("Dazed") == true or state == "stunned") and 1 or 0,
		grabbing = (state == "grabbing") and 1 or 0,
		grabbed = (state == "grabbed" or held) and 1 or 0,
		knocked = knockedState and 1 or 0,
		charge = (char:GetAttribute("Charging") == true) and 1 or 0,
	}
	-- Rates distintos por tipo de estado: es lo que da "peso" al movimiento.
	-- Antes todos usaban 15 al entrar y 9 al salir, asi que un empujon seco
	-- tardaba lo mismo en aplicarse que un cambio sutil de guardia.
	for name, target in pairs(tg) do
		local cur = S.w[name]
		local isImpact = IMPACT_STATES[name]
		local inRate = isImpact and IMPACT_IN or NEUTRAL_IN
		local outRate = isImpact and IMPACT_OUT or NEUTRAL_OUT
		S.w[name] = approach(cur, target, (target > cur) and inRate or outRate, dt)
	end
	local W = S.w

	-- ===== gestos de lobby =====
	local gestW = 0
	if CONFIG.IdleGestures then
		local idle = (not inMatch) and S.grounded and spd < 0.8 and W.sit < 0.1 and W.locked < 0.1
		if S.gest then
			local g = S.gest
			local t = now - g.t0
			if t >= g.dur or not idle then
				S.gest = nil
			else
				gestW = smooth01(t / 0.4) * smooth01((g.dur - t) / 0.4)
			end
		elseif idle and now >= S.nextGest then
			local r = rng:NextNumber()
			local name = (r < 0.4) and "salute" or ((r < 0.75) and "flex" or "stretch")
			S.gest = { name = name, t0 = now, dur = (name == "salute") and 2.4 or 2.8 }
			S.nextGest = now + S.gest.dur + rng:NextNumber(6, 12)
		end
	end

	-- ===== composicion: base + capas por prioridad =====
	local O = S.B
	copyInto(O, POSE.lobby)
	blend(O, POSE.guard, S.wGuard)
	if S.gest and gestW > 0.002 then
		local gp = POSE[S.gest.name]
		if S.gest.name == "flex" then
			copyInto(S.tmp, gp)
			S.tmp.twist = 0.22 * sin((now - S.gest.t0) * 3.2)
			S.tmp.rEl = 2.2 - 0.25 * abs(sin((now - S.gest.t0) * 3.2))
			S.tmp.lEl = 2.2 - 0.25 * abs(sin((now - S.gest.t0) * 3.2 + 1))
			gp = S.tmp
		end
		blend(O, gp, gestW)
	end
	blend(O, POSE.sit, W.sit)
	if W.air > 0.002 then poseAir(S, S.tmp) blend(O, S.tmp, W.air) end
	blend(O, POSE.skid, W.skid)
	if W.slip > 0.002 then
		-- piernas que se escapan: molinete procedural + cuerpo ladeado buscando el equilibrio
		S.slipPhase = (S.slipPhase + dt * TAU * 2.6) % TAU
		copyInto(S.tmp, POSE.slip)
		local sp = sin(S.slipPhase)
		S.tmp.rHip += 0.60 * sp
		S.tmp.lHip -= 0.60 * sp
		S.tmp.rKnee += 0.35 * max(0, sp)
		S.tmp.lKnee += 0.35 * max(0, -sp)
		S.tmp.twist += 0.12 * sp
		S.tmp.rSh += 0.18 * sp
		S.tmp.lSh -= 0.18 * sp
		blend(O, S.tmp, W.slip)
	end
	if W.locked > 0.002 then
		copyInto(S.tmp, POSE.salute)
		S.tmp.rSh += 0.05 * sin(now * 2.2)
		blend(O, S.tmp, W.locked)
	end
	blend(O, POSE.blocking, W.blocking)
	if W.offbalance > 0.002 then poseOffbalance(S, now, S.tmp) blend(O, S.tmp, W.offbalance) end
	blend(O, POSE.pushed, W.pushed)
	if W.dazed > 0.002 then poseDazed(S, now, S.tmp) blend(O, S.tmp, W.dazed) end
	if W.grabbing > 0.002 then poseGrabbing(S, now, S.tmp) blend(O, S.tmp, W.grabbing) end
	if W.charge > 0.002 then
		copyInto(S.tmp, POSE.charge)
		S.tmp.twist = 0.18 * sin(now * 16)
		S.tmp.roll = 0.10 * sin(now * 9)
		blend(O, S.tmp, W.charge)
	end
	if W.grabbed > 0.002 then poseGrabbed(S, now, S.tmp) blend(O, S.tmp, W.grabbed) end
	if W.knocked > 0.002 then poseKnocked(S, now, S.tmp) blend(O, S.tmp, W.knocked) end

	local actW = 0
	if S.act then
		local def = ACTIONS[S.act]
		local t = now - S.actStart
		if t >= def.dur then
			S.act = nil
		else
			sampleKeys(def.keys, t, S.tmp)
			if S.act == "dodge" then
				local r = S.tmp.roll
				S.tmp.roll = r * S.dodgeRoll
				S.tmp.lean += r * S.dodgeFwd * 0.45
			end
			actW = smooth01(t / def.fin) * smooth01((def.dur - t) / def.fout)
			blend(O, S.tmp, actW)
		end
	end

	-- ===== suavizado =====
	if not S.init then
		copyInto(S.cur, O)
		S.init = true
	end
	-- Suavizado final. Durante una accion el rate BAJA en vez de subir: asi el
	-- golpe entra nitido y la recuperacion se asienta despacio (mas pesada).
	-- Antes era al reves (1 + 0.6 * actW) y por eso las poses se veian blandas.
	local rate = CONFIG.Smoothing * (1 - 0.35 * clamp(actW, 0, 1))
	for i = 1, #KEYS do
		local key = KEYS[i]
		S.cur[key] = approach(S.cur[key], O[key], max(rate, 6), dt)
	end

	-- ===== capas aditivas (marcha, respiracion, mirada...) =====
	local F = S.F
	copyInto(F, S.cur)
	local busy = max(W.air * 0.9, W.knocked, W.grabbed, W.charge, W.grabbing * 0.7, W.dazed * 0.5, W.offbalance * 0.5, W.slip * 0.7, W.sit, actW)
	local calm = 1 - busy
	local I = CONFIG.Intensity

	-- marcha / carrera: la cadencia sigue a la velocidad real
	local moveW = smooth01((spd - 0.5) / 2.5)
	if S.grounded and spd > 0.6 then
		local dir = (S.vf < -0.35 * spd) and -1 or 1
		S.phase = (S.phase + dir * dt * TAU * clamp(spd / 6.2, 0.6, 5)) % TAU
	end
	local glide = clamp(-S.accel / (14 / SLIDE), 0, 1) * (inMatch and 1 or 0)
	local g = moveW * calm * (1 - 0.7 * glide) * I
	if g > 0.002 then
		local n = S.n
		local A = clamp(0.20 + 0.42 * n, 0, 0.85) * g
		local s, c = sin(S.phase), cos(S.phase)
		local armK = lerp(1, 0.12, S.wGuard)
		local legK = lerp(1, 0.60, S.wGuard)
		local la = A * legK
		F.rHip += la * s
		F.lHip -= la * s
		local kmax = (0.22 + 0.80 * clamp(n, 0, 1.4)) * g * legK
		F.rKnee += kmax * (0.15 + 0.85 * max(0, c))
		F.lKnee += kmax * (0.15 + 0.85 * max(0, -c))
		F.rAnk += -0.42 * max(0, -s) * g
		F.lAnk += -0.42 * max(0, s) * g
		local arm = (0.30 + 0.95 * A) * armK
		F.rSh += -arm * s
		F.lSh += arm * s
		local el = (0.10 + 0.85 * clamp(n, 0, 1.2)) * g * armK
		F.rEl += el * (0.6 + 0.4 * max(0, -s))
		F.lEl += el * (0.6 + 0.4 * max(0, s))
		F.twist += -0.30 * A * s * armK
		F.roll += 0.035 * A * c
		F.lean += (0.03 + 0.17 * clamp(n, 0, 1.5)) * g * (1 - S.wGuard * 0.6)
		F.bob += (0.03 + 0.11 * clamp(n, 0, 1.5)) * g * (0.5 + 0.5 * cos(2 * S.phase))
		local side = clamp(abs(S.vs) / max(spd, 1), 0, 1)
		F.spread += 0.10 * side * sin(2 * S.phase) * g * S.wGuard
	end
	-- inclinacion al girar a velocidad
	F.roll += clamp(-S.yawRate * 0.06 * clamp(spd / 16, 0, 1.5), -0.28, 0.28) * calm * I

	-- respiracion, peso y rebote de guardia
	local br = sin(now * (1.7 + S.wGuard * 1.2) + S.seed)
	F.chest += 0.018 * br * calm * I
	F.rSh += 0.02 * br * calm
	F.lSh += 0.02 * br * calm
	F.roll += 0.035 * sin(now * 0.9 + S.seed * 1.3) * calm * (1 - S.wGuard * 0.5) * (1 - moveW)
	F.crouch += S.wGuard * 0.06 * sin(now * 4.4 + S.seed) * calm * I
	F.rWr += S.wGuard * 0.25 * sin(now * 6.5 + S.seed) * calm
	F.lWr += S.wGuard * 0.25 * sin(now * 6.1 + S.seed + 1) * calm

	-- aceite caliente: mas temblor de equilibrio cuanto mas resbala
	if inMatch and slick > 1.05 then
		local k = (slick - 1) * calm * 0.6
		F.roll += 0.05 * k * sin(now * 3.1 + S.seed)
		F.rAb += 0.10 * k * sin(now * 3.7 + S.seed)
		F.lAb += 0.10 * k * sin(now * 3.3 + S.seed + 1)
	end

	-- amortiguacion al aterrizar
	local lx = clamp(S.landX, -0.25, 1.2)
	F.crouch += lx
	F.rSh += lx * 0.5
	F.lSh += lx * 0.5
	F.chest += lx * 0.25

	-- cabeza: sigue al rival en combate, mira al publico en el lobby
	if CONFIG.HeadLook and S.wGuard > 0.05 then
		findRival(S, now)
		local rv = S.rival
		if rv and rv.Parent then
			local rel = hrp.CFrame:PointToObjectSpace(rv.Position + Vector3.new(0, 1.5, 0))
			local horiz = max(sqrt(rel.X * rel.X + rel.Z * rel.Z), 0.5)
			local wl = S.wGuard * (1 - W.knocked) * (1 - W.grabbed)
			F.headYaw += clamp(atan2(-rel.X, -rel.Z), -1.1, 1.1) * 0.7 * wl
			F.headPitch += clamp(-atan2(rel.Y - 1.5, horiz), -0.5, 0.5) * 0.6 * wl
		end
	end
	local scan = (1 - S.wGuard) * calm * (1 - moveW * 0.7)
	F.headYaw += scan * (0.28 * sin(now * 0.45 + S.seed) + 0.10 * sin(now * 1.3 + S.seed * 2))
	F.headPitch += scan * 0.05 * sin(now * 0.7 + S.seed)

	-- ===== segundo movimiento (follow-through) =====
	-- Hombros, codos y cuello van detras del torso y rebotan: el golpe tiene inercia.
	followThrough(S, F, dt, I)

	applyPose(S, F)
end

-- ============================================================
-- SEGUIMIENTO DE PERSONAJES
-- ============================================================
local function track(hum)
	local char = hum.Parent
	if not char or not char:IsA("Model") or chars[char] then return end
	chars[char] = newState(char, hum)
	char.AncestryChanged:Connect(function()
		if not char:IsDescendantOf(Workspace) then
			chars[char] = nil
		end
	end)
end

Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") then
		task.defer(track, d)
	end
end)
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("Humanoid") then track(d) end
end

local camera = Workspace.CurrentCamera
RunService.PreSimulation:Connect(function(dt)
	dt = min(dt, 0.1)
	local now = os.clock()
	local camPos = camera and camera.CFrame.Position
	for char, S in pairs(chars) do
		if not S.dead then
			if not S.ready then
				if now >= S.nextTry then
					S.tries += 1
					S.nextTry = now + 0.3
					if buildRig(S) then
						S.ready = true
						S.hrp = char:FindFirstChild("HumanoidRootPart")
						char:SetAttribute("ProcAnim", true)
					elseif S.tries > 40 then
						S.dead = true
					end
				end
			else
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp and (not camPos or (hrp.Position - camPos).Magnitude <= CONFIG.MaxDistance) then
					local ok, err = pcall(step, S, dt, now)
					if not ok then
						S.errors = (S.errors or 0) + 1
						if S.errors == 1 then warn("[CharacterAnimator] Error animando a " .. char.Name .. ": " .. tostring(err)) end
						if S.errors > 30 then S.dead = true end
					end
				end
			end
		end
	end
end)
