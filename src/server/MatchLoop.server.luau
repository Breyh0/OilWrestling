-- MatchLoop (server)
-- Ciclo de combate con modos: SOLITARIO (vs IA) o MULTIJUGADOR.
-- El cliente envia StartGame con el modo elegido al pulsar en el menu.
-- El combate en si (rondas, puntos, equilibrio, stamina, defensa) vive en OilCombat.
-- Renunciar (OilResign) o volver al menu = abandonas: vuelves al lobby y el rival gana.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local OilCombat = require(ServerScriptService:WaitForChild("OilCombat"))

local MIN_PLAYERS = 2
local MAX_FIGHTERS = 4
local INTERMISSION = 15
local AI_NAME = "Gladiador IA"

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local startGameEvent = ensureRemote("StartGame")   -- client -> server (mode)
local matchEvent = ensureRemote("MatchUpdate")     -- server -> clients
local returnEvent = ensureRemote("ReturnToMenu")   -- client -> server (volver al menu)
local resignEvent = ensureRemote("OilResign")      -- client -> server (renunciar a la pelea)

local activeMode = nil  -- "solo" | "multi" | nil
local soloPlayer = nil
local session = 0       -- se incrementa al cancelar, para que las esperas pendientes se descarten
local inMenu = {}       -- jugadores que volvieron al menu: no se les arrastra a un combate
local lastResign = {}
local lastReturn = {}

-- ===== Lobby =====
local function getLobbyCFrame()
	-- Los SpawnLocation del lobby están dentro de BroadcastBooth (no cuelgan directo de Workspace)
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.CFrame * CFrame.new(math.random(-3, 3), 4, math.random(-2, 2))
	end
	return CFrame.new(4, 36, 80)
end

local function sendToLobby(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	char:PivotTo(getLobbyCFrame())
end

-- ===== Oponente IA =====
local function getContainer()
	local container = workspace:FindFirstChild("ActiveFighters")
	if not container then
		container = Instance.new("Folder")
		container.Name = "ActiveFighters"
		container.Parent = workspace
	end
	return container
end

local function spawnAI()
	local template = ServerStorage:FindFirstChild("FighterTemplate")
	if not template then
		warn("[MatchLoop] Falta ServerStorage.FighterTemplate: no se puede crear la IA")
		return nil
	end
	local model = template:Clone()
	model.Name = "AI_Fighter"
	model.Parent = getContainer() -- OilCombat lo coloca en su posición de salida al empezar cada ronda
	return model
end

local function clearAIFighters()
	local container = workspace:FindFirstChild("ActiveFighters")
	if container then
		for _, c in ipairs(container:GetChildren()) do
			if c.Name == "AI_Fighter" then
				c:Destroy()
			end
		end
	end
end

-- Espera a que termine un combate anterior (p.ej. la pausa de victoria tras una renuncia)
local function waitForMatchEnd(mySession)
	while OilCombat.isRunning() and mySession == session do
		task.wait(0.25)
	end
	return mySession == session
end

-- ===== Modo SOLITARIO =====
local function runSoloFight(mySession)
	local player = soloPlayer
	if not player or not player.Parent or not player.Character then
		return
	end
	if not waitForMatchEnd(mySession) then
		return
	end
	local ai = spawnAI()
	if not ai then
		matchEvent:FireAllClients({ status = "ended", mode = "solo" })
		return
	end
	matchEvent:FireAllClients({ status = "started", mode = "solo", fighters = { player.Name, AI_NAME }, scored = true })
	local result = OilCombat.runMatch({
		{ kind = "player", player = player },
		{ kind = "ai", model = ai, name = AI_NAME },
	})
	clearAIFighters()
	if mySession == session then
		matchEvent:FireAllClients({ status = "ended", mode = "solo", winner = result and result.name or nil })
	end
end

-- ===== Modo MULTIJUGADOR =====
local function getAvailablePlayers()
	local avail = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and hum and hum.Health > 0 and not inMenu[plr] then
			table.insert(avail, plr)
		end
	end
	return avail
end

local function shuffle(list)
	local c = {}
	for i, v in ipairs(list) do
		c[i] = v
	end
	for i = #c, 2, -1 do
		local j = math.random(1, i)
		c[i], c[j] = c[j], c[i]
	end
	return c
end

local function runMultiFight(mySession)
	if not waitForMatchEnd(mySession) then
		return
	end
	local available = getAvailablePlayers()
	if #available < MIN_PLAYERS then
		matchEvent:FireAllClients({ status = "waiting", needed = MIN_PLAYERS, players = #available })
		return
	end
	local shuffled = shuffle(available)
	local defs, names = {}, {}
	for i = 1, math.min(MAX_FIGHTERS, #shuffled) do
		defs[i] = { kind = "player", player = shuffled[i] }
		names[i] = shuffled[i].Name
	end
	matchEvent:FireAllClients({ status = "started", mode = "multi", fighters = names, scored = true })
	local result = OilCombat.runMatch(defs)
	if mySession == session then
		matchEvent:FireAllClients({ status = "ended", mode = "multi", winner = result and result.name or nil })
	end
end

-- ===== Intermisión =====
local function runIntermission(mode, mySession)
	for t = INTERMISSION, 1, -1 do
		if mySession ~= session then
			return false
		end
		matchEvent:FireAllClients({ status = "intermission", seconds = t, mode = mode })
		task.wait(1)
	end
	return mySession == session
end

-- ===== Evento de inicio desde el menu =====
startGameEvent.OnServerEvent:Connect(function(player, mode)
	if mode ~= "solo" and mode ~= "multi" then
		return
	end
	inMenu[player] = nil
	if activeMode ~= nil then
		return
	end
	activeMode = mode
	session += 1
	local mySession = session
	if mode == "solo" then
		soloPlayer = player
		clearAIFighters()
	end
	task.spawn(function()
		local ok, err = pcall(function()
			if runIntermission(mode, mySession) then
				if mode == "solo" then
					runSoloFight(mySession)
				else
					runMultiFight(mySession)
				end
			end
		end)
		if not ok then
			warn("[MatchLoop] Error en el ciclo de combate:", err)
		end
		if mySession == session then
			activeMode = nil
			soloPlayer = nil
		end
	end)
end)

-- Cancela el modo solitario si el jugador se va (menu / renuncia / desconexion)
local function cancelSoloFor(player)
	if soloPlayer == player then
		session += 1
		activeMode = nil
		soloPlayer = nil
		clearAIFighters()
	end
end

-- ===== Volver al menu =====
returnEvent.OnServerEvent:Connect(function(player)
	local t = os.clock()
	if lastReturn[player] and t - lastReturn[player] < 1 then
		return -- anti-spam: el cliente ya hace su parte al pulsar MENÚ
	end
	lastReturn[player] = t
	OilCombat.resign(player) -- salir en pleno combate cuenta como renuncia: el rival gana
	inMenu[player] = true
	cancelSoloFor(player)
	sendToLobby(player)
	matchEvent:FireAllClients({ status = "returned", player = player.Name })
end)

-- ===== Renunciar =====
-- El jugador abandona la pelea: vuelve al lobby automáticamente y su rival gana.
resignEvent.OnServerEvent:Connect(function(player)
	local t = os.clock()
	if lastResign[player] and t - lastResign[player] < 1 then
		return
	end
	lastResign[player] = t
	if not OilCombat.resign(player) then
		return -- no estaba peleando
	end
	inMenu[player] = true
	cancelSoloFor(player)
	sendToLobby(player)
	-- el cliente de quien renuncia vuelve al menú principal al recibir esto (ver GameHUDClient)
	matchEvent:FireAllClients({ status = "forfeit", player = player.Name })
end)

Players.PlayerRemoving:Connect(function(player)
	cancelSoloFor(player)
	inMenu[player] = nil
	lastResign[player] = nil
	lastReturn[player] = nil
end)

return true
