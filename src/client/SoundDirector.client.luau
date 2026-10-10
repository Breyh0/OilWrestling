-- SoundDirector (LocalScript en StarterPlayerScripts)
-- Une la biblioteca de sonidos de SoundService con los eventos que el juego ya emite.
--
-- Este script es ADITIVO: no modifica OilCombat ni ningun otro archivo. Solo escucha
-- OilEvent (que el servidor ya emite para el HUD y los efectos) y decide que suena.
-- Si se borra el archivo, el juego se queda exactamente igual.
--
-- Por que faltaba: los 11 sonidos estaban en SoundService, pero ningun script llegaba a
-- reproducirlos (cero referencias a "Sound" en src/). Los recursos de audio viven fuera de
-- los servicios que Rojo gestiona, asi que Rojo nunca los toco; el codigo que los
-- disparaba si vivia en uno de esos servicios y se perdio al sincronizar.
--
-- Reglas que sigue:
--   - Sin timeouts en WaitForChild (provocan la carga congelada; ver MEMORY.md).
--   - Si un sonido no esta, se salta en silencio: nunca bloquea ni da error.
--   - No se tocan los volumenes de SoundService: todo el ajuste se hace aqui, en copia.
--
-- Mezcla (lo importante de este archivo):
--   - Cada sonido tiene prioridad. Las piezas protagonistas (cuenta atras, silbato,
--     victoria) no se pierden nunca: bajan la musica y apartan a las demas.
--   - Las piezas importantes (publico, caida) suenan solas: si ya hay una sonando, no se
--     suma otra encima. Antes al ganar sonaban tres a la vez (salpicadura + publico +
--     victoria) porque el remate no|birth ningun sitio.
--   - La musica se atenua sola mientras suena una pieza y vuelve sola despues. Asi el
--     beep de la cuenta atras se oye sin tener que subir su volumen a tope.
--   - El fondo (esquivar, embestir) nunca entra en la cola de prioridades.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local DEBUG = false -- poner a true para ver que suena en la consola

local player = Players.LocalPlayer

-- ============================================================================
-- Prioridades
-- ============================================================================
local FONDO = 1 -- puede sonar encima de otra cosa sin molestar
local IMPORTANTE = 2 -- no se suma a otra importante
local PROTAGONISTA = 3 -- manda: silencia a las demas mientras dure

-- ============================================================================
-- Mapa de sonidos
-- ============================================================================
-- path       ruta dentro de SoundService
-- gain       ganancia sobre el volumen que ya trae el sonido
-- cooldown   segundos minimos entre dos disparos del MISMO sonido
-- prio       de las constantes de arriba
-- hold       segundos que este sonido "ocupa" la pista de los importantes
-- duck       cuanto baja la musica mientras suena (1 = no baja)
-- duckFor    segundos que dura esa bajada

local FX = {
	-- eventos "fx" del combate (OilCombat los manda con fx(tipo, pos, dir, fuerza);
	-- en el cliente llegan como "fx", a=tipo, b=posicion)
	dodge = { { path = "SFXGroup/Combate/DodgeSound", gain = 0.95, cooldown = 0.15, prio = FONDO } },
	dash = { { path = "SFXGroup/Combate/ChargeSound", gain = 0.85, cooldown = 0.30, prio = FONDO } },
	ringout = {
		-- solo la salpicadura: el publico entra despues con el "point" si el punto cuenta.
		-- Antes sonaban las dos a la vez y, si era el punto de victoria, se sumaba el
		-- Rugido de Gladiador encima: tres sonidos pisandose.
		-- hold corto a proposito: el rugido del "point" tiene que poder entrar justo
		-- despues de la salpicadura, no quedarse esperando.
		{ path = "SFXGroup/Combate/SplashSlip", gain = 1.0, cooldown = 0.40, prio = IMPORTANTE, hold = 0.6, duck = 0.55, duckFor = 0.9 },
	},
	victory = {
		{ path = "SFXGroup/Resultado/VictorySound", gain = 1.0, cooldown = 1.0, prio = PROTAGONISTA, hold = 3.2, duck = 0.35, duckFor = 3.2 },
	},
	-- block, parry, grab, guardbreak y break se quedan sin sonido a proposito: la
	-- biblioteca no tiene uno que encaje y no queremos meter ruido de mas.
}

local UI = {
	-- la cuenta atras va 3, 2, 1: pitan los ultimos tres, subiendo de volumen
	countdown = { path = "SFXGroup/Ronda/CountdownBeep", gain = 1.5, cooldown = 0.20, prio = PROTAGONISTA, hold = 0.55, duck = 0.20, duckFor = 1.1 },
	go = { path = "SFXGroup/Ronda/WhistleGong", gain = 1.0, cooldown = 0.60, prio = PROTAGONISTA, hold = 1.3, duck = 0.25, duckFor = 1.3 },
	point = { path = "SFXGroup/Combate/CrowdCheer", gain = 0.85, cooldown = 0.80, prio = IMPORTANTE, hold = 1.1, duck = 0.70, duckFor = 1.1 },
	matchStart = { path = "SFXGroup/Combate/CrowdCheer", gain = 0.80, cooldown = 1.20, prio = IMPORTANTE, hold = 1.3, duck = 0.60, duckFor = 1.3 },
	victory = { path = "SFXGroup/Resultado/VictorySound", gain = 1.0, cooldown = 1.20, prio = PROTAGONISTA, hold = 3.2, duck = 0.35, duckFor = 3.2 },
	draw = { path = "SFXGroup/Combate/CrowdCheer", gain = 0.70, cooldown = 1.20, prio = IMPORTANTE, hold = 1.2, duck = 0.70, duckFor = 1.2 },
}

-- ============================================================================
-- Utilidades
-- ============================================================================

-- Devuelve el Sound de SoundService en la ruta "Grupo/Carpeta/Hijo", o nil.
-- Sin WaitForChild a proposito: si un dia falta un sonido, aqui no se espera a nadie.
local function resolve(path)
	local node = SoundService
	for part in path:gmatch("[^/]+") do
		node = node and node:FindFirstChild(part)
		if not node then
			return nil
		end
	end
	return node:IsA("Sound") and node or nil
end

-- El volumen del SoundGroup al que pertenece la plantilla. Los clones en 3D se cuelgan
-- fuera del arbol de SoundService (para poder posicionarlos en el mundo), asi que el grupo
-- ya no les aplica su volumen y hay que compensarlo a mano.
local function groupGain(sound)
	local group = sound:FindFirstAncestorWhichIsA("SoundGroup")
	return group and group.Volume or 1
end

-- Reloj anti-solape por sonido: dos bloqueos seguidos del mismo tipo no se acumulan.
local lastPlayed = {}
local function throttled(path, cooldown)
	local now = os.clock()
	if (lastPlayed[path] or -99) + cooldown > now then
		return false
	end
	lastPlayed[path] = now
	return true
end

local function warn(message)
	warn("[SoundDirector] " .. message)
end

-- Va aqui, antes de la musica: si se declarara mas abajo, pushMusic la capturaria como
-- nil y reventaria al cambiar de pista.
local function fadeTo(sound, target, seconds)
	if not sound then
		return
	end
	TweenService:Create(sound, TweenInfo.new(seconds or 0.25, Enum.EasingStyle.Linear), { Volume = target }):Play()
end

-- ============================================================================
-- Musica y su atenuacion
-- ============================================================================
-- El servidor ya pone el atributo InOilMatch (lo usan OilCombatHUD, OilRoundsHUD,
-- OilWinnerCeremony y CharacterAnimator), asi que no hace falta pedir nada extra.
--
-- La musica de batalla suena por debajo de la de lobby a proposito: con las dos al mismo
-- nivel, los golpes se perdian. El valor exacto de cada pista esta en MUSIC_GAIN.

local MUSIC_GAIN = { lobby = 1.0, battle = 0.45 }

local music = { lobby = nil, battle = nil, current = nil, lobbyVol = 0, battleVol = 0 }
local mix = { duck = 1, duckUntil = 0, duckToken = 0 }

local function musicBase()
	if music.current == "battle" then
		return music.battleVol
	end
	return music.lobbyVol
end

local function pushMusic(seconds)
	local target = musicBase() * mix.duck
	if music.current == "battle" then
		fadeTo(music.battle, target, seconds)
	else
		fadeTo(music.lobby, target, seconds)
	end
end

-- Baja la musica mientras suena una pieza y la devuelve sola al terminar. Si se encadenan
-- varias bajadas, manda la ultima: el token invalida las anteriores.
local function duckMusic(factor, seconds)
	mix.duck = math.clamp(factor, 0, 1)
	mix.duckUntil = os.clock() + (seconds or 1)
	mix.duckToken += 1
	local mine = mix.duckToken
	pushMusic(0.12)
	task.spawn(function()
		while mix.duckToken == mine and os.clock() < mix.duckUntil do
			task.wait(0.1)
		end
		if mix.duckToken == mine then
			mix.duck = 1
			pushMusic(0.6)
		end
	end)
end

-- ============================================================================
-- La pista de los sonidos importantes
-- ============================================================================
-- Solo hay una plaza. Entra lo que sea mas importante que lo que ya esta sonando, y el
-- resto espera: por eso al ganar ya no se pisan la salpicadura, el publico y la victoria.

-- OJO: el campo se llama freeAt y no "until" porque "until" es palabra reservada de Luau
-- y rompe el script entero al compilar.
local lane = { prio = 0, freeAt = 0 }

local function mayPlay(prio)
	if prio <= FONDO then
		return true -- el fondo no ocupa plaza
	end
	local now = os.clock()
	if now >= lane.freeAt then
		return true
	end
	return prio > lane.prio
end

local function claimLane(prio, seconds)
	if prio <= FONDO then
		return
	end
	lane.prio = prio
	lane.freeAt = os.clock() + (seconds or 1)
end

-- ============================================================================
-- Reproduccion
-- ============================================================================

-- entry: { path, gain, cooldown, prio, hold, duck, duckFor }   pos: Vector3 o nil
local function fire(entry, pos)
	local template = resolve(entry.path)
	if not template then
		if DEBUG then
			warn("no existe: " .. entry.path)
		end
		return
	end
	if not mayPlay(entry.prio) then
		if DEBUG then
			print(string.format("[SoundDirector] %s descartado (pista ocupada)", entry.path))
		end
		return
	end
	if not throttled(entry.path, entry.cooldown) then
		return
	end

	claimLane(entry.prio, entry.hold)

	local s = template:Clone()
	s.Name = "SD_" .. template.Name
	s.Volume = math.clamp(template.Volume * entry.gain * groupGain(template), 0, 1)

	if pos then
		-- 3D: un Attachment en el workspace es lo que le da posicion al sonido
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = pos
		s.Parent = anchor
		Debris:AddItem(anchor, 30)
	else
		s.Parent = SoundService
	end

	if not s.Looped then
		s.Ended:Once(function()
			s:Destroy()
		end)
		-- red de seguridad por si Ended no llega (sonido cortado, cierre de partida...)
		Debris:AddItem(s, 30)
	end

	if entry.duck then
		duckMusic(entry.duck, entry.duckFor)
	end

	s:Play()
	if DEBUG then
		print(string.format("[SoundDirector] %s (prio %d%s)", s.Name, entry.prio, pos and " 3D" or ""))
	end
end

-- Clone que cuelga DENTRO de su SoundGroup, para que el volumen del grupo siga mandando.
-- Para musica y ambiente, que no son 3D. Devuelve el clone, o nil si el sonido no existe.
local function playGrouped(path, gain, looped)
	local template = resolve(path)
	if not template then
		if DEBUG then
			warn("no existe: " .. path)
		end
		return nil
	end
	local s = template:Clone()
	s.Name = "SD_" .. template.Name
	s.Volume = math.clamp(template.Volume * gain, 0, 1)
	s.Looped = looped or false
	s.Parent = template:FindFirstAncestorWhichIsA("SoundGroup") or SoundService
	s:Play()
	return s
end

-- ============================================================================
-- Sonido segun el evento del combate
-- ============================================================================

local eventRemote = ReplicatedStorage:WaitForChild("OilEvent")

eventRemote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "fx" then
		local sounds = FX[a]
		if not sounds then
			return
		end
		-- a es el tipo de efecto y b la posicion; en el resto de eventos b no es una
		-- posicion, asi que se comprueba el tipo antes de usarlo.
		local pos = (typeof(b) == "Vector3") and b or nil
		for _, entry in ipairs(sounds) do
			fire(entry, pos)
		end
	elseif kind == "countdown" then
		-- el servidor cuenta 3, 2, 1: solo pitan los ultimos tres, cada vez mas fuerte
		local n = tonumber(a) or 99
		if n >= 1 and n <= 3 then
			local entry = UI.countdown
			fire({
				path = entry.path,
				gain = entry.gain * (1.05 + 0.08 * (3 - n)),
				cooldown = entry.cooldown,
				prio = entry.prio,
				hold = entry.hold,
				duck = entry.duck,
				duckFor = entry.duckFor,
			})
		end
	elseif kind == "go" then
		fire(UI.go)
	elseif kind == "point" then
		fire(UI.point)
	elseif kind == "noscore" then
		-- caida sin punto: el golpe ya suena por su cuenta, aqui no se anade nada
	elseif kind == "match_start" then
		fire(UI.matchStart)
	elseif kind == "match_end" then
		-- a es el nombre del ganador; si no hay, se empato
		fire(a and UI.victory or UI.draw)
	elseif kind == "draw" then
		fire(UI.draw)
	end
end)

-- ============================================================================
-- Arranque de musica y ambiente
-- ============================================================================

local function startMusic()
	local lobby = playGrouped("MusicGroup/LobbyMusic", MUSIC_GAIN.lobby, true)
	local battle = playGrouped("MusicGroup/BattleMusic", MUSIC_GAIN.battle, true)
	music.lobby, music.battle = lobby, battle
	music.lobbyVol = lobby and lobby.Volume or 0
	music.battleVol = battle and battle.Volume or 0
	-- Las dos arrancan a cero: se sube la que corresponda, sin solape al entrar en partida.
	if lobby then
		lobby.Volume = 0
	end
	if battle then
		battle.Volume = 0
	end
	music.current = nil -- Todavia no se ha elegido ninguna
end

local function setMusic(where)
	if music.current == where then
		return
	end
	-- La pista que se deja se baja a cero: si no, al entrar en partida siguen sonando
	-- las dos musicas a la vez.
	local from = music.current
	music.current = where
	if from == "lobby" then
		fadeTo(music.lobby, 0, 1.2)
	elseif from == "battle" then
		fadeTo(music.battle, 0, 1.2)
	end
	pushMusic(1.2)
	if DEBUG then
		print("[SoundDirector] musica -> " .. where)
	end
end

-- Ambiente del publico: solo en el lobby, y se apaga al entrar en combate
local ambience = nil

local function setAmbience(on)
	if on and not ambience then
		ambience = playGrouped("SFXGroup/Ambiente/CrowdAmbience", 1.0, true)
	elseif not on and ambience then
		local a = ambience
		ambience = nil
		fadeTo(a, 0, 1.0)
		Debris:AddItem(a, 2)
	end
end

local function applyPlace()
	local inMatch = player:GetAttribute("InOilMatch") == true
	setMusic(inMatch and "battle" or "lobby")
	setAmbience(not inMatch)
end

-- Antes de mirar el atributo: se crean los dos loops de musica. Si el jugador ya estaba en
-- partida cuando este script arranco, el atributo ya venia puesto y applyPlace lo recoge.
startMusic()
player:GetAttributeChangedSignal("InOilMatch"):Connect(applyPlace)
applyPlace()
