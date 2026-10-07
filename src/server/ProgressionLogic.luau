-- ProgressionLogic (ModuleScript, ServerScriptService)
-- Reglas de progresion como funciones puras sobre una tabla de datos: no usa DataStore,
-- remotes ni jugadores, asi que se puede probar sin arrancar el juego.
-- Lo usa ProgressionService, que se encarga de sesiones, guardado y red.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = require(ReplicatedStorage:WaitForChild("ProgressionShared"))

local Logic = {}
Logic.SCHEMA = 3

-- ============================================================
-- BALANCE (tocar solo aqui; curva, rangos y misiones estan en ProgressionShared)
-- ============================================================
local CONFIG = {
	MaxCoins = 2000000000,

	-- XP: SOLO se gana al ganar combates
	XPPerWin = 50,
	FirstWinXP = 25,                -- primera victoria del dia

	-- Monedas
	CoinsPerMatch = 10,             -- por cada partida completada
	CoinsPerWin = 30,               -- bonificacion extra al ganar
	CoinsPerPoint = 2,              -- por cada punto anotado (ganes o pierdas)
	MaxPointCoins = 20,             -- tope de monedas por puntos en una partida
	FirstWinCoins = 50,             -- primera victoria del dia
	VsAIMultiplier = 0.75,          -- contra IA se gana un poco menos (evita farmeo)

	-- Racha de victorias (bonus por cada victoria consecutiva previa, hasta StreakMax)
	StreakMax = 5,
	StreakXP = 5,
	StreakCoins = 2,
}
Logic.Config = CONFIG

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = deepCopy(v)
	end
	return c
end
Logic.DeepCopy = deepCopy

local function round(x)
	return math.floor(x + 0.5)
end

-- ============================================================
-- Datos
-- ============================================================
function Logic.DefaultData()
	return {
		schema = Logic.SCHEMA,
		xp = 0, level = 1, coins = 0,
		day = 0, week = 0,
		mp = {}, claimed = {},     -- progreso y reclamos de las misiones diarias
		wp = {}, wclaimed = {},    -- progreso y reclamos de las semanales
		stats = { matches = 0, wins = 0, ringouts = 0, parries = 0, streak = 0, bestStreak = 0 },
	}
end

local function sanitizeCounts(t)
	local c = {}
	if type(t) == "table" then
		for k, v in pairs(t) do
			if type(k) == "string" then
				c[k] = math.max(0, math.floor(tonumber(v) or 0))
			end
		end
	end
	return c
end

local function sanitizeFlags(t)
	local c = {}
	if type(t) == "table" then
		for k, v in pairs(t) do
			if type(k) == "string" and v == true then
				c[k] = true
			end
		end
	end
	return c
end

-- Completa campos que falten, corrige valores invalidos y migra datos de versiones anteriores.
function Logic.Reconcile(data)
	local def = Logic.DefaultData()
	local oldSchema = data.schema

	for _, k in ipairs({ "xp", "coins", "day", "week" }) do
		data[k] = math.max(0, math.floor(tonumber(data[k]) or 0))
	end
	data.level = math.clamp(math.floor(tonumber(data.level) or 1), 1, Shared.MaxLevel)
	data.coins = math.min(data.coins, CONFIG.MaxCoins)

	if type(data.stats) ~= "table" then
		data.stats = deepCopy(def.stats)
	end
	for k, v in pairs(def.stats) do
		-- Misma regla que xp/coins: un contador corrupto nunca queda negativo ni decimal.
		-- Un valor que no es numero vuelve al valor por defecto.
		local n = data.stats[k]
		if type(n) ~= "number" then
			data.stats[k] = v
		else
			data.stats[k] = math.max(0, math.floor(n))
		end
	end

	data.mp = sanitizeCounts(data.mp)
	data.wp = sanitizeCounts(data.wp)
	data.claimed = sanitizeFlags(data.claimed)
	data.wclaimed = sanitizeFlags(data.wclaimed)

	-- Migracion desde versiones 1 y 2: los contadores m_* pasan a mp
	if (oldSchema or 0) < 3 then
		local legacy = { wins = "m_wins", ringouts = "m_ringouts", parry = "m_parrys" }
		for id, key in pairs(legacy) do
			if data.mp[id] == nil then
				data.mp[id] = math.max(0, math.floor(tonumber(data[key]) or 0))
			end
		end
		-- version 1: las misiones ya completadas hoy no se pagan dos veces
		if oldSchema == nil then
			for _, m in ipairs(Shared.DailyCore) do
				if (data.mp[m.id] or 0) >= m.goal then
					data.claimed[m.id] = true
				end
			end
		end
	end
	data.m_wins, data.m_ringouts, data.m_parrys = nil, nil, nil

	data.schema = Logic.SCHEMA
	return data
end

-- Reinicios diario y semanal. Devuelve (reinicioDiario, reinicioSemanal).
function Logic.EnsureToday(d, now)
	local dayId = Shared.DayId(now)
	local weekId = Shared.WeekId(now)
	local dailyReset, weeklyReset = false, false
	if d.day ~= dayId then
		d.day = dayId
		d.mp = {}
		d.claimed = {}
		dailyReset = true
	end
	if d.week ~= weekId then
		d.week = weekId
		d.wp = {}
		d.wclaimed = {}
		weeklyReset = true
	end
	return dailyReset, weeklyReset
end

-- ============================================================
-- Monedas, XP y niveles
-- ============================================================
local function addCoins(d, amount)
	amount = math.floor(amount)
	if amount == 0 then
		return 0
	end
	d.coins = math.clamp(d.coins + amount, 0, CONFIG.MaxCoins)
	return amount
end
Logic.AddCoins = addCoins

-- Suma XP y sube de nivel automaticamente (varios niveles de golpe si hace falta).
-- Premios por nivel: monedas base + hito (cada 5 niveles) + rango nuevo.
local function addXP(d, amount, notes)
	if d.level >= Shared.MaxLevel then
		return 0
	end
	d.xp += math.floor(amount)
	local gained = 0
	local req = Shared.XPForLevel(d.level)
	while d.xp >= req and d.level < Shared.MaxLevel do
		d.xp -= req
		local oldRank = Shared.RankIndex(d.level)
		d.level += 1
		gained += 1

		local base = Shared.LevelUpCoins(d.level)
		local milestone = (d.level % Shared.MilestoneEvery == 0) and Shared.MilestoneCoins(d.level) or 0
		local newRank = Shared.RankIndex(d.level)
		local rankUp = newRank > oldRank
		local total = base + milestone + (rankUp and Shared.RankUpCoins or 0)
		addCoins(d, total)

		table.insert(notes, {
			kind = "levelup",
			data = { level = d.level, coins = total, base = base, milestone = milestone, rankUp = rankUp, rank = newRank },
		})
		req = Shared.XPForLevel(d.level)
	end
	if d.level >= Shared.MaxLevel then
		d.xp = 0
	end
	return gained
end
Logic.AddXP = addXP

-- ============================================================
-- Misiones
-- ============================================================
local function advanceMissions(d, list, progress, claimed, bonusAmount, weekly, event, amount, notes)
	for _, m in ipairs(list) do
		if m.event == event and not claimed[m.id] then
			progress[m.id] = math.min((progress[m.id] or 0) + amount, m.goal)
			if progress[m.id] >= m.goal then
				claimed[m.id] = true
				addCoins(d, m.reward)
				table.insert(notes, { kind = "mission", data = { label = m.label, reward = m.reward, weekly = weekly } })

				if not claimed.bonus then
					local all = true
					for _, other in ipairs(list) do
						if not claimed[other.id] then
							all = false
							break
						end
					end
					if all then
						claimed.bonus = true
						addCoins(d, bonusAmount)
						table.insert(notes, { kind = "bonus", data = { reward = bonusAmount, weekly = weekly } })
					end
				end
			end
		end
	end
end

-- Registra una accion (win, winpvp, match, ringout, parry, points). Devuelve la lista de avisos.
function Logic.ApplyEvent(d, event, amount, notes)
	notes = notes or {}
	amount = math.floor(amount or 1)
	if amount <= 0 then
		return notes
	end
	advanceMissions(d, Shared.DailyMissions(d.day), d.mp, d.claimed, Shared.DailyBonus, false, event, amount, notes)
	advanceMissions(d, Shared.WeeklyMissions(), d.wp, d.wclaimed, Shared.WeeklyBonus, true, event, amount, notes)
	return notes
end

-- ============================================================
-- Fin de partida (un participante)
-- ctx = { won, score, vsAI, forfeited, reason, winnerScore }
-- ============================================================
function Logic.ApplyMatch(d, ctx)
	local notes = {}
	local stats = d.stats

	if ctx.forfeited then
		stats.streak = 0 -- abandonar rompe la racha y no da recompensas
		return notes
	end
	-- Ganar por abandono sin haber anotado ni un punto no cuenta (evita farmeo entre cuentas)
	if ctx.reason == "forfeit" and (ctx.winnerScore or 0) <= 0 then
		return notes
	end

	local mult = ctx.vsAI and CONFIG.VsAIMultiplier or 1
	local score = math.max(0, math.floor(tonumber(ctx.score) or 0))
	stats.matches += 1

	local xp = 0
	local coins = round(CONFIG.CoinsPerMatch * mult)
	coins += round(math.min(score * CONFIG.CoinsPerPoint, CONFIG.MaxPointCoins) * mult)
	local firstWin = false

	if ctx.won then
		local steps = math.min(stats.streak, CONFIG.StreakMax)
		xp = round(CONFIG.XPPerWin * mult) + steps * CONFIG.StreakXP
		coins += round(CONFIG.CoinsPerWin * mult) + steps * CONFIG.StreakCoins
		if not d.claimed.firstwin then
			d.claimed.firstwin = true
			xp += CONFIG.FirstWinXP
			coins += CONFIG.FirstWinCoins
			firstWin = true
		end
		stats.wins += 1
		stats.streak += 1
		stats.bestStreak = math.max(stats.bestStreak, stats.streak)
	else
		stats.streak = 0
	end

	addCoins(d, coins)
	local result = {
		win = ctx.won == true, xp = xp, coins = coins, streak = stats.streak,
		levels = 0, firstWin = firstWin, points = score,
	}
	table.insert(notes, { kind = "result", data = result })

	if ctx.won then
		result.levels = addXP(d, xp, notes)
	end

	Logic.ApplyEvent(d, "match", 1, notes)
	Logic.ApplyEvent(d, "points", score, notes)
	if ctx.won then
		Logic.ApplyEvent(d, "win", 1, notes)
		if not ctx.vsAI then
			Logic.ApplyEvent(d, "winpvp", 1, notes)
		end
	end
	return notes
end

-- ============================================================
-- Estado que se envia al cliente
-- ============================================================
local function missionRows(list, progress, claimed)
	local rows = {}
	for _, m in ipairs(list) do
		table.insert(rows, {
			id = m.id, label = m.label, goal = m.goal, reward = m.reward,
			progress = math.min(progress[m.id] or 0, m.goal),
			done = claimed[m.id] == true,
		})
	end
	return rows
end

function Logic.Snapshot(d, now)
	return {
		level = d.level, xp = d.xp, xpReq = Shared.XPForLevel(d.level), maxLevel = Shared.MaxLevel,
		rank = Shared.RankIndex(d.level),
		coins = d.coins,
		streak = d.stats.streak, bestStreak = d.stats.bestStreak,
		wins = d.stats.wins, matches = d.stats.matches,
		firstWin = { available = d.claimed.firstwin ~= true, xp = CONFIG.FirstWinXP, coins = CONFIG.FirstWinCoins },
		missions = missionRows(Shared.DailyMissions(d.day), d.mp, d.claimed),
		bonus = Shared.DailyBonus, bonusDone = d.claimed.bonus == true,
		resetIn = Shared.SecondsToDayReset(now),
		weekly = {
			missions = missionRows(Shared.WeeklyMissions(), d.wp, d.wclaimed),
			bonus = Shared.WeeklyBonus, bonusDone = d.wclaimed.bonus == true,
			resetIn = Shared.SecondsToWeekReset(now),
		},
	}
end

return Logic
