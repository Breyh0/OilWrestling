-- OilConfig (ModuleScript, ReplicatedStorage)
-- Parámetros de la "Lucha en Aceite": empuja al rival fuera del ring.
-- El primero en llegar a PointsToWin puntos gana el combate.
-- Todo el balance (fuerzas, cooldowns, resbalón) se ajusta desde aquí.

return {
	-- ===== Reglas =====
	PointsToWin = 3,        -- gana quien consiga 3 rounds (hasta 5 rounds en total)
	CountdownSeconds = 3,
	RoundTimeout = 45,      -- seg. sin ring-out => ronda nula
	SlickRampStart = 18,    -- desde aquí el aceite "se calienta" y resbala cada vez más
	SlickMax = 2.0,         -- multiplicador máximo de resbalón al llegar al timeout
	PostPointPause = 2.6,
	VictoryPause = 4.5,
	AssistWindow = 6,       -- seg. en que un golpe aún cuenta como causante del ring-out
	RingMargin = 0.4,       -- cuánto debe pasar el centro del cuerpo del borde para quedar fuera
	SpawnRadius = 13,
	SkinShine = 0.22,       -- brillo de la piel aceitada

	-- ===== Física sobre aceite =====
	WalkSpeed = 15,
	Traction = 2.6,         -- qué tan rápido acelera hacia donde quieres ir (1/s)
	Glide = 1.35,           -- qué tan rápido frena sin input (1/s) -> menor = más resbalón
	AirControl = 0.25,      -- control en el aire (fracción de la tracción)
	StunDrag = 1.1,         -- arrastre del cuerpo derribado
	HeldDrag = 7,           -- arrastre cuando estás agarrado / en cuenta regresiva

	-- ===== Acciones =====
	-- Empujón: golpe corto, el impulso del atacante suma fuerza
	Push = { Cooldown = 0.9, Stamina = 14, Range = 7.5, Cone = 0.25, Force = 24, Momentum = 0.6, Stagger = 0.5, Lift = 6, Windup = 0.12 },
	-- Embestida (torpedo de aceite): te lanzas deslizando; si fallas, te puedes ir tú solo fuera
	Charge = { Cooldown = 4.5, Stamina = 30, Impulse = 34, Duration = 0.65, HitRange = 5.2, Force = 34, Stun = 1.6, Lift = 16, Recovery = 0.8 },
	-- Agarre y lanzamiento romano: el rival puede contraatacar mientras lo sujetas
	Grab = { Cooldown = 6, Stamina = 22, Range = 5.8, Cone = 0.2, Hold = 0.75, Force = 36, Stun = 1.5, Lift = 22, Windup = 0.1 },
	CounterForce = 34,
	InvulnAfterStun = 0.7,

	-- ===== Equilibrio (postura) =====
	-- Cada golpe resta equilibrio. Al llegar a 0 el luchador queda DESEQUILIBRADO: el siguiente
	-- golpe que reciba lo lanza muchísimo más lejos (y lo derriba). Se regenera con el tiempo.
	Balance = {
		Max = 100,
		RegenDelay = 2.0,        -- seg. sin recibir golpes antes de empezar a regenerar
		RegenPerSec = 15,
		LowBalanceBonus = 0.5,   -- hasta +50% de fuerza recibida cuanto menos equilibrio quede
		BrokenTime = 2.6,        -- cuánto dura desequilibrado (si nadie lo remata, se recupera)
		BrokenRecover = 40,      -- equilibrio con el que se recupera solo
		BrokenForceMult = 2.8,   -- multiplicador de fuerza del golpe que lo remata
		BrokenStun = 1.5,        -- derribo al recibir ese golpe
		BrokenLift = 10,
		PostBreakRecover = 35,   -- equilibrio tras comerse el golpe que lo remató
		Damage = { push = 24, charge = 45, throw = 40, counter = 45, parry = 55 },
	},

	-- ===== Stamina =====
	-- Acciones y bloqueo gastan stamina; se regenera solo si dejas de gastarla un momento.
	Stamina = {
		Max = 100,
		RegenDelay = 0.8,
		RegenPerSec = 18,
		BlockDrainPerSec = 9,    -- sostener el bloqueo
		BlockStart = 6,          -- costo de levantar la guardia
		BlockHit = 14,           -- por golpe bloqueado (la embestida cuesta el doble)
		GuardBreakDaze = 1.3,    -- guardia rota (sin stamina): aturdido
	},

	-- ===== Defensa =====
	-- Bloqueo (mantener R): reduce fuerza y daño de equilibrio de golpes frontales; el agarre lo ignora.
	Block = { Arc = 0.1, ForceMult = 0.22, BalanceMult = 0.3, SpeedMult = 0.45, Cooldown = 0.55, MinStamina = 6 },
	-- Parry: si el golpe llega en los primeros instantes de levantar la guardia, el atacante
	-- queda aturdido y tú ganas una ventana de contraataque (próximo empujón más fuerte y gratis).
	Parry = { Window = 0.22, AttackerDaze = 1.2, AttackerKnock = 12, CounterWindow = 1.6, CounterForceMult = 1.7, Invuln = 0.35, StaminaRefund = 20 },
	-- Esquiva: impulso corto con invulnerabilidad breve. Si el golpe falla, el atacante queda expuesto.
	Dodge = { Cooldown = 1.3, Stamina = 20, Duration = 0.4, IFrames = 0.3, Impulse = 30, WhiffDaze = 0.6 },

	-- Invulnerabilidad al empezar cada ronda (se pierde si atacas)
	SpawnInvuln = 2.0,
}
