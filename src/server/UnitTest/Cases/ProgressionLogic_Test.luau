-- ProgressionLogic_Test (ModuleScript, ServerScriptService.UnitTest.Cases)
-- Tests de las reglas puras de progresion (Reconcile, EnsureToday, AddCoins,
-- AddXP, ApplyEvent, ApplyMatch). Sin DataStore, sin red y sin reloj real: el
-- tiempo se inyecta con una marca fija, asi que todo es determinista.
-- Se ejecuta con: require(ServerScriptService.UnitTest.RunUnitTest)("ProgressionLogic")

return function(t)
	local Logic = require(game:GetService("ServerScriptService"):WaitForChild("ProgressionLogic"))
	local Shared = require(game:GetService("ReplicatedStorage"):WaitForChild("ProgressionShared"))
	local expect = t.expect
	local C = Logic.Config

	-- Momento fijo: 2026-01-01 00:00 UTC (dayId 20454, par en el ciclo de misiones).
	local T = 1767225600

	local function fresh()
		return Logic.Reconcile(Logic.DefaultData())
	end

	local function resultOf(notes)
		for _, n in ipairs(notes) do
			if n.kind == "result" then
				return n.data
			end
		end
		return nil
	end

	local function countKind(notes, kind)
		local c = 0
		for _, n in ipairs(notes) do
			if n.kind == kind then
				c += 1
			end
		end
		return c
	end

	-- ============================================================
	-- Reconcile
	-- ============================================================

	-- Rellena una tabla vacia con todos los valores por defecto.
	t.test("Reconcile: rellena datos vacios con los valores por defecto", function()
		local d = Logic.Reconcile({})
		expect.equal(d.schema, Logic.SCHEMA)
		expect.equal(d.level, 1)
		expect.equal(d.xp, 0)
		expect.equal(d.coins, 0)
		expect.deepEqual(d.stats, { matches = 0, wins = 0, ringouts = 0, parries = 0, streak = 0, bestStreak = 0 })
		-- Sin schema se Migra desde v1, que siembra los contadores de las misiones diarias
		expect.deepEqual(d.mp, { wins = 0, ringouts = 0, parry = 0 })
		expect.deepEqual(d.wp, {})
	end)

	-- Convierte a cero los contadores que faltan o no son numeros.
	t.test("Reconcile: pone en cero los contadores no numericos", function()
		local d = Logic.Reconcile({ xp = "hola", coins = nil, day = false })
		expect.equal(d.xp, 0)
		expect.equal(d.coins, 0)
		expect.equal(d.day, 0)
	end)

	-- Nunca deja el nivel por debajo de 1.
	t.test("Reconcile: acota el nivel minimo a 1", function()
		expect.equal(Logic.Reconcile({ level = 0 }).level, 1)
		expect.equal(Logic.Reconcile({ level = -5 }).level, 1)
	end)

	-- Nunca deja el nivel por encima del maximo de la curva.
	t.test("Reconcile: acota el nivel maximo a MaxLevel", function()
		expect.equal(Logic.Reconcile({ level = 5000 }).level, Shared.MaxLevel)
	end)

	-- Las monedas no pueden quedar negativas.
	t.test("Reconcile: impide monedas negativas", function()
		expect.equal(Logic.Reconcile({ coins = -500 }).coins, 0)
	end)

	-- Las monedas se topan para no desbordar el rango del DataStore.
	t.test("Reconcile: topa las monedas al maximo del datastore", function()
		expect.equal(Logic.Reconcile({ coins = 3e9 }).coins, C.MaxCoins)
	end)

	-- Migra los contadores m_* de los datos v1/v2 a los ids de mision actuales.
	t.test("Reconcile: migra los contadores antiguos a las misiones", function()
		local d = Logic.Reconcile({ schema = 2, m_wins = 7, m_ringouts = 12, m_parrys = 3 })
		expect.equal(d.mp.wins, 7)
		expect.equal(d.mp.ringouts, 12)
		expect.equal(d.mp.parry, 3)
		expect.equal(d.m_wins, nil)
		expect.equal(d.m_ringouts, nil)
		expect.equal(d.m_parrys, nil)
		expect.equal(d.schema, Logic.SCHEMA)
	end)

	-- Si los datos ya traian progreso en mp, la migracion no lo pisa.
	t.test("Reconcile: respeta el progreso ya migrado en mp", function()
		local d = Logic.Reconcile({ schema = 2, mp = { wins = 5 }, m_wins = 99 })
		expect.equal(d.mp.wins, 5)
	end)

	-- Datos v1 sin schema: las misiones ya completadas quedan reclamadas para no pagar dos veces.
	t.test("Reconcile: marca como reclamadas las misiones ya completadas en datos v1", function()
		local d = Logic.Reconcile({ mp = { wins = 3, ringouts = 10, parry = 1 } })
		expect.equal(d.claimed.wins, true)
		expect.equal(d.claimed.ringouts, true)
		expect.equal(d.claimed.parry, true)
	end)

	-- Los contadores de mision negativos caen a 0 y se redondean hacia abajo.
	t.test("Reconcile: sanea los contadores de mision", function()
		local d = Logic.Reconcile({ mp = { wins = -3, ringouts = 2.7 } })
		expect.equal(d.mp.wins, 0)
		expect.equal(d.mp.ringouts, 2)
	end)

	-- Solo sobreviven los reclamos marcados a true.
	t.test("Reconcile: descarta reclamos que no son true", function()
		local d = Logic.Reconcile({ claimed = { a = true, b = "si", c = 1 } })
		expect.equal(d.claimed.a, true)
		expect.equal(d.claimed.b, nil)
		expect.equal(d.claimed.c, nil)
	end)

	-- ============================================================
	-- EnsureToday
	-- ============================================================

	-- Dentro del mismo dia no se pierde nada.
	t.test("EnsureToday: no reinicia dentro del mismo dia", function()
		local d = fresh()
		d.day, d.week = Shared.DayId(T), Shared.WeekId(T)
		d.mp.wins = 2
		local daily, weekly = Logic.EnsureToday(d, T)
		expect.equal(daily, false)
		expect.equal(weekly, false)
		expect.equal(d.mp.wins, 2)
	end)

	-- Al cambiar de dia se borra el progreso diario y se avisa.
	t.test("EnsureToday: borra el progreso diario al cambiar de dia", function()
		local d = fresh()
		d.day, d.week = Shared.DayId(T) - 1, Shared.WeekId(T)
		d.mp.wins, d.claimed.wins = 2, true
		local daily, weekly = Logic.EnsureToday(d, T)
		expect.equal(daily, true)
		expect.equal(weekly, false)
		expect.deepEqual(d.mp, {})
		expect.deepEqual(d.claimed, {})
	end)

	-- Al cambiar de semana se borra el progreso semanal y se avisa.
	t.test("EnsureToday: borra el progreso semanal al cambiar de semana", function()
		local d = fresh()
		d.day, d.week = Shared.DayId(T), Shared.WeekId(T) - 1
		d.wp.w_wins, d.wclaimed.w_wins = 5, true
		local daily, weekly = Logic.EnsureToday(d, T)
		expect.equal(daily, false)
		expect.equal(weekly, true)
		expect.deepEqual(d.wp, {})
		expect.deepEqual(d.wclaimed, {})
	end)

	-- ============================================================
	-- AddCoins
	-- ============================================================

	-- Importe cero: no toca nada y lo devuelve.
	t.test("AddCoins: un importe de cero no cambia el saldo", function()
		local d = fresh()
		d.coins = 40
		expect.equal(Logic.AddCoins(d, 0), 0)
		expect.equal(d.coins, 40)
	end)

	-- El importe se trunca hacia abajo.
	t.test("AddCoins: trunca el importe hacia abajo", function()
		local d = fresh()
		expect.equal(Logic.AddCoins(d, 7.9), 7)
		expect.equal(d.coins, 7)
	end)

	-- Nunca se puede gastar por debajo de cero.
	t.test("AddCoins: no deja el saldo por debajo de cero", function()
		local d = fresh()
		d.coins = 5
		Logic.AddCoins(d, -10)
		expect.equal(d.coins, 0)
	end)

	-- El saldo se topa igual que en Reconcile.
	t.test("AddCoins: topa el saldo al maximo del datastore", function()
		local d = fresh()
		d.coins = C.MaxCoins
		Logic.AddCoins(d, 500)
		expect.equal(d.coins, C.MaxCoins)
	end)

	-- ============================================================
	-- AddXP
	-- ============================================================

	-- Sin xp suficiente no hay subida ni monedas.
	t.test("AddXP: no sube de nivel por debajo del xp requerido", function()
		local d = fresh()
		local gained = Logic.AddXP(d, Shared.XPForLevel(1) - 1, {})
		expect.equal(gained, 0)
		expect.equal(d.level, 1)
		expect.equal(d.xp, Shared.XPForLevel(1) - 1)
		expect.equal(d.coins, 0)
	end)

	-- Al cruzar el umbral: nivel +1, xp descontado y monedas base.
	t.test("AddXP: sube de nivel y paga las monedas base", function()
		local d = fresh()
		local notes = {}
		local gained = Logic.AddXP(d, Shared.XPForLevel(1), notes)
		expect.equal(gained, 1)
		expect.equal(d.level, 2)
		expect.equal(d.xp, 0)
		expect.equal(d.coins, Shared.LevelUpCoins(2))
		expect.equal(countKind(notes, "levelup"), 1)
		expect.equal(notes[1].data.rankUp, false)
		expect.equal(notes[1].data.milestone, 0)
	end)

	-- Cada 5 niveles hay hito, y ademas coincide con un rango nuevo (Gladiador).
	t.test("AddXP: paga hito y rango nuevo al llegar al nivel 5", function()
		local d = fresh()
		d.level = 4
		Logic.AddXP(d, Shared.XPForLevel(4), {})
		expect.equal(d.level, 5)
		expect.equal(d.coins, Shared.LevelUpCoins(5) + Shared.MilestoneCoins(5) + Shared.RankUpCoins)
	end)

	-- Un importe grande puede subir varios niveles en una sola llamada.
	t.test("AddXP: sube varios niveles de golpe", function()
		local d = fresh()
		local gained = Logic.AddXP(d, Shared.XPForLevel(1) + Shared.XPForLevel(2), {})
		expect.equal(gained, 2)
		expect.equal(d.level, 3)
		expect.equal(d.xp, 0)
		expect.equal(d.coins, Shared.LevelUpCoins(2) + Shared.LevelUpCoins(3))
	end)

	-- En el nivel maximo ya no se acepta xp.
	t.test("AddXP: no acepta xp en el nivel maximo", function()
		local d = fresh()
		d.level = Shared.MaxLevel
		expect.equal(Logic.AddXP(d, 500, {}), 0)
		expect.equal(d.level, Shared.MaxLevel)
		expect.equal(d.xp, 0)
	end)

	-- Al tocar el nivel maximo el xp sobrante se descarta, no se acumula.
	t.test("AddXP: descarta el xp sobrante al alcanzar el nivel maximo", function()
		local d = fresh()
		d.level = Shared.MaxLevel - 1
		d.xp = Shared.XPForLevel(Shared.MaxLevel - 1) + 500
		local gained = Logic.AddXP(d, 0, {})
		expect.equal(gained, 1)
		expect.equal(d.level, Shared.MaxLevel)
		expect.equal(d.xp, 0)
	end)

	-- ============================================================
	-- ApplyEvent (misiones)
	-- ============================================================

	-- Un importe nulo o no positivo no hace nada.
	t.test("ApplyEvent: ignora importes cero o negativos", function()
		local d = fresh()
		local notes = Logic.ApplyEvent(d, "ringout", 0, {})
		Logic.ApplyEvent(d, "ringout", -5, {})
		expect.deepEqual(d.mp, {})
		expect.equal(#notes, 0)
	end)

	-- Sin importe indicado se asume 1.
	t.test("ApplyEvent: asume un importe de 1", function()
		local d = fresh()
		Logic.ApplyEvent(d, "parry", nil, {})
		expect.equal(d.mp.parry, 1)
	end)

	-- El progreso nunca pasa del objetivo y la mision se reclama al llegar.
	t.test("ApplyEvent: acota el progreso al objetivo y paga la recompensa", function()
		local d = fresh()
		Logic.ApplyEvent(d, "ringout", 25, {})
		expect.equal(d.mp.ringouts, 10)
		expect.equal(d.claimed.ringouts, true)
		expect.equal(d.coins, 100)
	end)

	-- Una mision reclamada no vuelve a pagar.
	t.test("ApplyEvent: no paga dos veces la misma mision", function()
		local d = fresh()
		Logic.ApplyEvent(d, "ringout", 10, {})
		local coinsAfterFirst = d.coins
		local notes = Logic.ApplyEvent(d, "ringout", 10, {})
		expect.equal(d.coins, coinsAfterFirst)
		expect.equal(d.mp.ringouts, 10)
		expect.equal(countKind(notes, "mission"), 0)
	end)

	-- Al completar todas las diarias entra el bono diario.
	t.test("ApplyEvent: entrega el bono diario al completar todas las misiones", function()
		local d = fresh()
		d.day = Shared.DayId(T)
		local rot = Shared.DailyPool[(d.day % #Shared.DailyPool) + 1]
		Logic.ApplyEvent(d, "win", 3, {})
		Logic.ApplyEvent(d, "ringout", 10, {})
		Logic.ApplyEvent(d, "parry", 1, {})
		local notes = Logic.ApplyEvent(d, rot.event, rot.goal, {})
		expect.equal(d.claimed.bonus, true)
		expect.equal(countKind(notes, "bonus"), 1)
		expect.equal(d.coins, 150 + 100 + 50 + rot.reward + Shared.DailyBonus)
	end)

	-- El bono semanal necesita las tres semanales completas.
	t.test("ApplyEvent: entrega el bono semanal al completar las tres semanales", function()
		local d = fresh()
		Logic.ApplyEvent(d, "win", 20, {})
		Logic.ApplyEvent(d, "ringout", 80, {})
		local notes = Logic.ApplyEvent(d, "match", 30, {})
		expect.equal(d.wclaimed.bonus, true)
		expect.equal(countKind(notes, "bonus"), 1)
		-- 3 diarias completadas por el camino (wins, ringouts y la rotativa) mas el bono semanal
		expect.equal(d.coins, 150 + 100 + 120 + 600 + 450 + 400 + Shared.WeeklyBonus)
	end)

	-- ============================================================
	-- ApplyMatch
	-- ============================================================

	-- Abandonar rompe la racha y no otorga nada.
	t.test("ApplyMatch: el abandono reinicia la racha y no da recompensas", function()
		local d = fresh()
		d.stats.streak = 3
		local notes = Logic.ApplyMatch(d, { won = true, score = 2, forfeited = true })
		expect.equal(d.stats.streak, 0)
		expect.equal(d.coins, 0)
		expect.equal(d.xp, 0)
		expect.equal(d.stats.matches, 0)
		expect.equal(#notes, 0)
	end)

	-- Ganar por abandono sin puntos no cuenta como partida (anti-farmeo).
	t.test("ApplyMatch: ignora una victoria por abandono sin puntos", function()
		local d = fresh()
		local notes = Logic.ApplyMatch(d, { won = true, score = 0, reason = "forfeit", winnerScore = 0 })
		expect.equal(#notes, 0)
		expect.equal(d.stats.matches, 0)
		expect.equal(d.coins, 0)
	end)

	-- Perder da monedas por jugar y por puntos, pero ni xp ni racha.
	t.test("ApplyMatch: al perder paga monedas por jugar y por puntos, sin xp", function()
		local d = fresh()
		d.stats.streak = 2
		local notes = Logic.ApplyMatch(d, { won = false, score = 2 })
		local r = resultOf(notes)
		expect.equal(r.xp, 0)
		expect.equal(r.coins, C.CoinsPerMatch + 2 * C.CoinsPerPoint)
		expect.equal(r.points, 2)
		expect.equal(d.stats.matches, 1)
		expect.equal(d.stats.streak, 0)
	end)

	-- Ganar contra IA aplica el multiplicador reductor.
	t.test("ApplyMatch: aplica el multiplicador contra la IA", function()
		local d = fresh()
		local notes = Logic.ApplyMatch(d, { won = true, score = 0, vsAI = true })
		local r = resultOf(notes)
		expect.equal(r.xp, 38 + C.FirstWinXP)
		expect.equal(r.coins, 8 + 23 + C.FirstWinCoins)
	end)

	-- La primera victoria del dia suma el bonus extra.
	t.test("ApplyMatch: la primera victoria del dia suma xp y monedas extra", function()
		local d = fresh()
		local notes = Logic.ApplyMatch(d, { won = true, score = 3 })
		local r = resultOf(notes)
		expect.equal(r.firstWin, true)
		expect.equal(r.xp, C.XPPerWin + C.FirstWinXP)
		expect.equal(r.coins, C.CoinsPerMatch + 3 * C.CoinsPerPoint + C.CoinsPerWin + C.FirstWinCoins)
	end)

	-- La primera victoria solo se paga una vez por dia.
	t.test("ApplyMatch: la primera victoria no se repite", function()
		local d = fresh()
		Logic.ApplyMatch(d, { won = true, score = 0 })
		local notes = Logic.ApplyMatch(d, { won = true, score = 0 })
		local r = resultOf(notes)
		expect.equal(r.firstWin, false)
		expect.equal(r.xp, C.XPPerWin + C.StreakXP)
		expect.equal(r.coins, C.CoinsPerMatch + C.CoinsPerWin + C.StreakCoins)
	end)

	-- Las monedas por puntos tienen tope por partida.
	t.test("ApplyMatch: topa las monedas por puntos al maximo de partida", function()
		local d = fresh()
		local notes = Logic.ApplyMatch(d, { won = true, score = 15 })
		local r = resultOf(notes)
		expect.equal(r.coins, C.CoinsPerMatch + C.MaxPointCoins + C.CoinsPerWin + C.FirstWinCoins)
		expect.equal(r.points, 15)
	end)

	-- La bonificacion por racha se congela en StreakMax.
	t.test("ApplyMatch: congela el bono de racha en StreakMax", function()
		local d = fresh()
		for _ = 1, C.StreakMax + 1 do
			Logic.ApplyMatch(d, { won = true, score = 0 })
		end
		local notes = Logic.ApplyMatch(d, { won = true, score = 0 })
		local r = resultOf(notes)
		expect.equal(d.stats.streak, C.StreakMax + 2)
		expect.equal(r.xp, C.XPPerWin + C.StreakMax * C.StreakXP)
		expect.equal(r.coins, C.CoinsPerMatch + C.CoinsPerWin + C.StreakMax * C.StreakCoins)
	end)

	-- Perdiendo tras varias victorias se pierde la racha pero se guarda la maxima.
	t.test("ApplyMatch: perder rompe la racha y conserva la mejor racha", function()
		local d = fresh()
		for _ = 1, 3 do
			Logic.ApplyMatch(d, { won = true, score = 0 })
		end
		Logic.ApplyMatch(d, { won = false, score = 0 })
		expect.equal(d.stats.streak, 0)
		expect.equal(d.stats.bestStreak, 3)
	end)

	-- Una partida ganada avanza las misiones de jugar, puntos y ganar.
	t.test("ApplyMatch: avanza las misiones de la partida", function()
		local d = fresh()
		Logic.ApplyMatch(d, { won = true, score = 2 })
		expect.equal(d.mp.wins, 1)
		expect.equal(d.mp.play5, 1)
		expect.equal(d.wp.w_wins, 1)
		expect.equal(d.wp.w_play, 1)
	end)

	-- Ganar contra la IA no cuenta para las misiones contra jugadores.
	t.test("ApplyMatch: la victoria contra la IA no avanza las misiones pvp", function()
		local d = fresh()
		d.day = Shared.DayId(T)
		Logic.ApplyMatch(d, { won = true, score = 1, vsAI = true })
		expect.equal(d.mp.winpvp2, nil)
	end)

	-- ============================================================
	-- Snapshot
	-- ============================================================

	-- El snapshot que ve el cliente refleja el estado real y no se puede falsear.
	t.test("Snapshot: refleja nivel, monedas y misiones del servidor", function()
		local d = fresh()
		Logic.ApplyMatch(d, { won = true, score = 1 })
		local snap = Logic.Snapshot(d, T)
		expect.equal(snap.wins, 1)
		expect.equal(snap.matches, 1)
		expect.equal(snap.firstWin.available, false)
		expect.equal(snap.coins, d.coins)
		expect.equal(snap.maxLevel, Shared.MaxLevel)
	end)

	-- El progreso de mision enviado al cliente no pasa del objetivo.
	t.test("Snapshot: el progreso de mision no supera el objetivo", function()
		local d = fresh()
		d.day = Shared.DayId(T)
		Logic.ApplyEvent(d, "ringout", 999, {})
		local snap = Logic.Snapshot(d, T)
		for _, row in ipairs(snap.missions) do
			expect.truthy(row.progress <= row.goal)
		end
	end)
end