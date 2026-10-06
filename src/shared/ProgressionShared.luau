-- ProgressionShared (ModuleScript, ReplicatedStorage)
-- Reglas y datos que comparten servidor y cliente: curva de XP, rangos, hitos,
-- misiones (diarias y semanales) y calculo de reinicios.
-- Aqui no hay datos de jugadores ni acceso a DataStore; el cliente solo lo usa para mostrar.

local Shared = {}

Shared.MaxLevel = 100

-- Desfase en horas respecto a UTC para los reinicios diario y semanal.
-- 0 = a las 00:00 UTC (como siempre). Ejemplo: -5 reinicia a la medianoche de UTC-5.
Shared.UtcOffsetHours = 0

-- ============================================================
-- Curva de XP: mas suave que la lineal de antes (100 x nivel).
-- Nivel 1 -> 2: 100 | 10: ~455 | 25: ~1116 | 50: ~2329 | 99: ~4985
-- ============================================================
function Shared.XPForLevel(level)
	local n = math.max(math.floor(level), 1) - 1
	return math.floor(100 + 35 * n + 1.5 * n ^ 1.5 + 0.5)
end

-- ============================================================
-- Rangos (tematica de gladiadores romanos)
-- ============================================================
Shared.Ranks = {
	{ min = 1,   name = "Tiro",         color = Color3.fromRGB(196, 186, 166) },
	{ min = 5,   name = "Gladiador",    color = Color3.fromRGB(205, 150, 95) },
	{ min = 10,  name = "Secutor",      color = Color3.fromRGB(190, 196, 210) },
	{ min = 20,  name = "Retiarius",    color = Color3.fromRGB(110, 190, 200) },
	{ min = 30,  name = "Murmillo",     color = Color3.fromRGB(232, 200, 90) },
	{ min = 45,  name = "Campe\u{00F3}n", color = Color3.fromRGB(240, 130, 70) },
	{ min = 60,  name = "Primus Palus", color = Color3.fromRGB(220, 80, 80) },
	{ min = 80,  name = "Rudiarius",    color = Color3.fromRGB(180, 120, 230) },
	{ min = 100, name = "Imperator",    color = Color3.fromRGB(255, 220, 100) },
}

function Shared.RankIndex(level)
	for i = #Shared.Ranks, 1, -1 do
		if level >= Shared.Ranks[i].min then
			return i
		end
	end
	return 1
end

-- ============================================================
-- Recompensas por nivel
-- ============================================================
function Shared.LevelUpCoins(level)
	return 25 + 5 * level
end

Shared.MilestoneEvery = 5          -- cada 5 niveles hay un hito con premio extra
function Shared.MilestoneCoins(level)
	return 40 + 4 * level
end

Shared.RankUpCoins = 100           -- premio extra al alcanzar un rango nuevo

-- ============================================================
-- Misiones. "event" indica que accion las hace avanzar:
--   win (ganar), winpvp (ganar contra jugadores), match (jugar), ringout, parry,
--   points (puntos anotados en la partida)
-- ============================================================
Shared.DailyCore = {
	{ id = "wins",     event = "win",     goal = 3,  reward = 150, label = "Gana 3 partidas" },
	{ id = "ringouts", event = "ringout", goal = 10, reward = 100, label = "Haz 10 ringouts" },
	{ id = "parry",    event = "parry",   goal = 1,  reward = 50,  label = "Usa un parry" },
}

-- Cada dia se suma una cuarta mision rotativa de este grupo
Shared.DailyPool = {
	{ id = "play5",      event = "match",   goal = 5,  reward = 120, label = "Juega 5 partidas" },
	{ id = "parry5",     event = "parry",   goal = 5,  reward = 120, label = "Usa 5 parries" },
	{ id = "ringouts20", event = "ringout", goal = 20, reward = 160, label = "Haz 20 ringouts" },
	{ id = "winpvp2",    event = "winpvp",  goal = 2,  reward = 180, label = "Gana 2 partidas contra jugadores" },
	{ id = "points12",   event = "points",  goal = 12, reward = 130, label = "Anota 12 puntos" },
}

Shared.Weekly = {
	{ id = "w_wins",     event = "win",     goal = 20, reward = 600, label = "Gana 20 partidas" },
	{ id = "w_ringouts", event = "ringout", goal = 80, reward = 450, label = "Haz 80 ringouts" },
	{ id = "w_play",     event = "match",   goal = 30, reward = 400, label = "Juega 30 partidas" },
}

Shared.DailyBonus = 100            -- por completar todas las misiones del dia
Shared.WeeklyBonus = 500           -- por completar todas las semanales

function Shared.DailyMissions(dayId)
	local list = table.clone(Shared.DailyCore)
	local pool = Shared.DailyPool
	table.insert(list, pool[(dayId % #pool) + 1])
	return list
end

function Shared.WeeklyMissions()
	return Shared.Weekly
end

-- ============================================================
-- Tiempo: los dias y las semanas (lunes a domingo) se cuentan con el desfase configurado
-- ============================================================
local function shifted(now)
	return (now or os.time()) + Shared.UtcOffsetHours * 3600
end

function Shared.DayId(now)
	return math.floor(shifted(now) / 86400)
end

function Shared.WeekId(now)
	-- el 1 de enero de 1970 fue jueves, por eso el +3 para que la semana empiece en lunes
	return math.floor((Shared.DayId(now) + 3) / 7)
end

function Shared.SecondsToDayReset(now)
	local t = shifted(now)
	return (math.floor(t / 86400) + 1) * 86400 - t
end

function Shared.SecondsToWeekReset(now)
	local t = shifted(now)
	local nextWeekStartDay = (Shared.WeekId(now) + 1) * 7 - 3
	return nextWeekStartDay * 86400 - t
end

return Shared
