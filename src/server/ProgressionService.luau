-- ProgressionService (ModuleScript, ServerScriptService)
-- Sesiones, guardado seguro y red de la progresion: XP y niveles, monedas, misiones
-- diarias y semanales, rachas y rangos. Las reglas viven en ProgressionLogic (puras y
-- probadas) y los datos compartidos con el cliente en ReplicatedStorage.ProgressionShared.
-- Lo usa OilCombat (recompensas) y lo arranca el Script ProgressionSystem.
--
-- API (solo servidor):
--   RecordMatchEnd(info)      info = { completed, winner, winnerScore, participants, vsAI, reason }
--   RecordRingout(player)     el jugador saco a un rival del ring (suma punto)
--   RecordParry(player)       el jugador hizo un parry
--   AddCoins(player, n)       regala monedas (codigos, eventos...)
--   SpendCoins(player, n)     cobra monedas; devuelve true/false (para la tienda)
--   GetCoins(player)          monedas actuales
--   GetLevel(player)          nivel actual
--   GetRank(player)           nombre del rango actual
--   GetData(player)           copia de solo lectura de los datos

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("ProgressionShared"))
local Logic = require(script.Parent:WaitForChild("ProgressionLogic"))

local CONFIG = {
	DataStoreName = "Progression_v1", -- mismo almacen de siempre: el progreso existente se conserva
	AutosaveInterval = 30,
	Leaderstats = true,               -- tabla de jugadores con Nivel / Rango / Victorias / Monedas
}

-- ============================================================
-- Remotes
-- ============================================================
local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local updateEvent = ensureRemote("UpdateProgression")   -- server -> cliente: estado completo
local notifyEvent = ensureRemote("MissionNotify")       -- server -> cliente: avisos (kind, datos)
local requestEvent = ensureRemote("RequestProgression") -- cliente -> server: pide su estado

-- ============================================================
-- Sesiones
-- ============================================================
local sessions = {} -- [Player] = { data, loaded, unsaved, dirty, saving, pushQueued }

local function notify(player, kind, payload)
	if player.Parent then
		notifyEvent:FireClient(player, kind, payload)
	end
end

local function dispatch(player, notes)
	for _, n in ipairs(notes) do
		notify(player, n.kind, n.data)
	end
end

local function buildSnapshot(s)
	local snap = Logic.Snapshot(s.data)
	snap.unsaved = s.unsaved or nil
	return snap
end

local function refreshLeaderstats(player, s)
	if not CONFIG.Leaderstats then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local function set(class, name, value)
		local v = ls:FindFirstChild(name)
		if not v then
			v = Instance.new(class)
			v.Name = name
			v.Parent = ls
		end
		v.Value = value
	end
	set("IntValue", "Nivel", s.data.level)
	set("StringValue", "Rango", Shared.Ranks[Shared.RankIndex(s.data.level)].name)
	set("IntValue", "Victorias", s.data.stats.wins)
	set("IntValue", "Monedas", s.data.coins)
end

-- Envia el estado al cliente (varios cambios en el mismo frame se agrupan en un solo envio)
local function push(player)
	local s = sessions[player]
	if not s or s.pushQueued then
		return
	end
	s.pushQueued = true
	task.defer(function()
		s.pushQueued = false
		if sessions[player] == s and player.Parent then
			updateEvent:FireClient(player, buildSnapshot(s))
			refreshLeaderstats(player, s)
		end
	end)
end

-- ============================================================
-- Guardado
-- ============================================================
local store = nil
do
	local ok, res = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.DataStoreName)
	end)
	if ok then
		store = res
	else
		warn("[Progression] DataStore no disponible:", res)
	end
end

local function withRetry(fn, attempts)
	local lastErr
	for i = 1, attempts do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		if i < attempts then
			task.wait(math.min(2 ^ (i - 1), 8))
		end
	end
	return false, lastErr
end

local inFlightSaves = 0

local function save(userId, s)
	if not store or not s.loaded then
		return false -- nunca se guarda sobre un progreso que no se pudo cargar
	end
	local waited = 0
	while s.saving and waited < 100 do
		task.wait(0.1)
		waited += 1
	end
	if s.saving then
		return false
	end
	s.saving = true
	inFlightSaves += 1
	s.dirty = false
	s.lastSaveAt = os.clock()
	local copy = Logic.DeepCopy(s.data)
	copy.lastSave = os.time()
	local ok, err = withRetry(function()
		store:UpdateAsync(tostring(userId), function()
			return copy
		end)
	end, 3)
	if not ok then
		s.dirty = true
		warn("[Progression] No se pudo guardar a", userId, err)
	elseif s.player and s.player.Parent then
		notify(s.player, "saved", {})
	end
	s.saving = false
	inFlightSaves -= 1
	return ok
end

-- Guardado casi inmediato: tras un cambio se guarda en unos segundos (varios cambios seguidos
-- se agrupan en una sola escritura). El DataStore admite ~1 escritura cada 6 s por jugador.
local MIN_SAVE_GAP = 7
local function queueSave(player)
	local s = sessions[player]
	if not s or not s.loaded or s.saveQueued then
		return
	end
	s.saveQueued = true
	local wait = math.max(2, MIN_SAVE_GAP - (os.clock() - (s.lastSaveAt or -math.huge)))
	task.delay(wait, function()
		s.saveQueued = false
		if sessions[player] == s and s.dirty then
			save(player.UserId, s)
		end
	end)
end

local function loadPlayer(player, s)
	local ok, res
	if store then
		ok, res = withRetry(function()
			return store:GetAsync(tostring(player.UserId))
		end, 5)
	else
		ok, res = false, "sin DataStore"
	end
	if sessions[player] ~= s then
		return -- el jugador ya se fue
	end
	if ok then
		local data = (type(res) == "table") and res or Logic.DefaultData()
		s.data = Logic.Reconcile(data)
		Logic.EnsureToday(s.data)
		s.loaded = true
		s.unsaved = false
		if type(res) == "table" and res.schema ~= Logic.SCHEMA then
			s.dirty = true -- datos migrados: se guardan ya en el formato nuevo
		end
	else
		s.unsaved = true
		warn("[Progression] No se pudo cargar a", player.Name, res)
		notify(player, "warn", { text = "No se pudo cargar tu progreso. Esta sesi\u{00F3}n no se guardar\u{00E1}." })
	end
	push(player)
end

-- Sesion lista para recibir recompensas (aplica los reinicios si tocan).
-- Mientras el progreso se esta cargando no se reparte nada, para no pisar los datos al llegar.
local function activeSession(player)
	local s = sessions[player]
	if not s or not (s.loaded or s.unsaved) then
		return nil
	end
	if Logic.EnsureToday(s.data) then
		s.dirty = true
	end
	return s
end

-- ============================================================
-- API publica
-- ============================================================
local Service = {}
Service.Config = Logic.Config

function Service.RecordParry(player)
	local s = activeSession(player)
	if not s then
		return
	end
	s.data.stats.parries += 1
	s.dirty = true
	dispatch(player, Logic.ApplyEvent(s.data, "parry", 1))
	push(player)
	queueSave(player)
end

function Service.RecordRingout(player)
	local s = activeSession(player)
	if not s then
		return
	end
	s.data.stats.ringouts += 1
	s.dirty = true
	dispatch(player, Logic.ApplyEvent(s.data, "ringout", 1))
	push(player)
	queueSave(player)
end

-- info = {
--   completed    = true si el combate termino con un ganador,
--   winner       = Player ganador (nil si gano la IA),
--   winnerScore  = puntos del ganador,
--   participants = { { player, forfeited, score }, ... },
--   vsAI         = true si hubo un rival IA,
--   reason       = "points" | "forfeit",
-- }
function Service.RecordMatchEnd(info)
	if type(info) ~= "table" or not info.completed then
		return -- partida abortada: sin recompensas
	end
	for _, p in ipairs(info.participants or {}) do
		local player = p.player
		local s = player and activeSession(player)
		if s then
			local notes = Logic.ApplyMatch(s.data, {
				won = (player == info.winner),
				score = p.score,
				vsAI = info.vsAI == true,
				forfeited = p.forfeited == true,
				reason = info.reason,
				winnerScore = info.winnerScore,
			})
			s.dirty = true
			dispatch(player, notes)
			push(player)
			queueSave(player)
		end
	end
end

function Service.AddCoins(player, amount)
	local s = sessions[player]
	if not s or type(amount) ~= "number" or amount <= 0 then
		return false
	end
	Logic.AddCoins(s.data, amount)
	s.dirty = true
	push(player)
	queueSave(player)
	return true
end

-- Cobra monedas. Solo funciona con datos cargados y saldo suficiente.
function Service.SpendCoins(player, amount)
	local s = sessions[player]
	if not s or not s.loaded or type(amount) ~= "number" or amount <= 0 then
		return false
	end
	amount = math.floor(amount)
	if s.data.coins < amount then
		return false
	end
	Logic.AddCoins(s.data, -amount)
	s.dirty = true
	push(player)
	queueSave(player)
	return true
end

function Service.GetCoins(player)
	local s = sessions[player]
	return s and s.data.coins or 0
end

function Service.GetLevel(player)
	local s = sessions[player]
	return s and s.data.level or 1
end

function Service.GetRank(player)
	local s = sessions[player]
	return Shared.Ranks[Shared.RankIndex(s and s.data.level or 1)].name
end

function Service.GetData(player)
	local s = sessions[player]
	return s and Logic.DeepCopy(s.data) or nil
end

-- ============================================================
-- Ciclo de vida de los jugadores
-- ============================================================
local function onPlayerAdded(player)
	if sessions[player] then
		return
	end
	local s = { data = Logic.DefaultData(), loaded = false, unsaved = false, dirty = false, saving = false, pushQueued = false, saveQueued = false, player = player }
	Logic.EnsureToday(s.data)
	sessions[player] = s
	push(player)          -- estado inicial mientras carga
	loadPlayer(player, s) -- carga con reintentos
end

local function onPlayerRemoving(player)
	local s = sessions[player]
	if not s then
		return
	end
	if s.loaded then
		save(player.UserId, s)
	end
	sessions[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- El cliente pide su estado al arrancar (evita perder el primer envio)
local lastRequest = setmetatable({}, { __mode = "k" })
requestEvent.OnServerEvent:Connect(function(player)
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < 1 then
		return
	end
	lastRequest[player] = t
	push(player)
end)

-- Autoguardado
task.spawn(function()
	while true do
		task.wait(CONFIG.AutosaveInterval)
		for _, player in ipairs(Players:GetPlayers()) do
			local s = sessions[player]
			if s and s.loaded and s.dirty then
				task.spawn(save, player.UserId, s)
				task.wait(0.25)
			end
		end
	end
end)

-- Reinicios en vivo (sin esperar a que el jugador reentre)
task.spawn(function()
	while true do
		task.wait(20)
		for _, player in ipairs(Players:GetPlayers()) do
			local s = sessions[player]
			if s and (s.loaded or s.unsaved) then
				local daily, weekly = Logic.EnsureToday(s.data)
				if daily or weekly then
					s.dirty = true
					notify(player, "info", {
						text = weekly and "\u{00A1}Nuevas misiones diarias y semanales!" or "\u{00A1}Nuevas misiones diarias!",
					})
					push(player)
				end
			end
		end
	end
end)

-- Al cerrar el servidor se guarda todo y se espera a que termine
game:BindToClose(function()
	for player, session in pairs(sessions) do
		if session.loaded then
			task.spawn(save, player.UserId, session)
		end
	end
	local t0 = os.clock()
	task.wait(0.2)
	while inFlightSaves > 0 and os.clock() - t0 < 25 do
		task.wait(0.1)
	end
end)

return Service
