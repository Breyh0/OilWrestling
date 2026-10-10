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
--   - No se tocan los volumenes que ya estan puestos en SoundService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local DEBUG = false -- poner a true para ver que sonido suena en la consola

local player = Players.LocalPlayer

-- ============================================================================
-- Mapa de sonidos
-- ============================================================================
-- Cada entrada: { ruta dentro de SoundService, ganancia, espera minima entre repeticiones }
-- La ganancia se aplica sobre el volumen que ya tiene el sonido; no se toca el original.

local FX = {
	-- eventos "fx" del combate (los emite OilCombat con fx("kind", pos, dir, force))
	dodge = { { "SFXGroup/Combate/DodgeSound", 1.0, 0.12 } },
	dash = { { "SFXGroup/Combate/ChargeSound", 0.9, 0.25 } },
	ringout = {
		{ "SFXGroup/Combate/SplashSlip", 1.0, 0.30 },
		{ "SFXGroup/Combate/CrowdCheer", 0.85, 0.30 },
	},
	victory = { { "SFXGroup/Resultado/VictorySound", 1.0, 0.50 } },
	-- block, parry, grab, guardbreak y break se quedan sin sonido a proposito: la biblioteca
	-- no tiene uno que encaje y no queremos meter ruido de mas.
}

local UI = {
	countdown = { "SFXGroup/Ronda/CountdownBeep", 1.0, 0.20 },
	go = { "SFXGroup/Ronda/WhistleGong", 1.0, 0.50 },
	point = { "SFXGroup/Combate/CrowdCheer", 0.9, 0.50 },
	matchStart = { "SFXGroup/Combate/CrowdCheer", 0.8, 1.00 },
	victory = { "SFXGroup/Resultado/VictorySound", 1.0, 1.00 },
	draw = { "SFXGroup/Combate/CrowdCheer", 0.7, 1.00 },
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

-- Cuando se pide el mismo sonido varias veces seguidas (un bloqueo en bucle, dos caidas
-- seguidas) se solaparian y saturarian. Cada sonido lleva su propio reloj.
local lastPlayed = {}
local function throttled(path, cooldown)
	local now = os.clock()
	if (lastPlayed[path] or -99) + cooldown > now then
		return false
	end
	lastPlayed[path] = now
	return true
end

-- Reproduce un sonido suelto. Si se pasa pos, se reproduce en 3D desde ese punto del mundo.
local function play(path, gain, cooldown, pos)
	local template = resolve(path)
	if not template then
		if DEBUG then
			warn("[SoundDirector] no existe: " .. path)
		end
		return
	end
	if not throttled(path, cooldown) then
		return
	end

	local s = template:Clone()
	s.Name = "SD_" .. template.Name
	s.Volume = math.clamp(template.Volume * gain * groupGain(template), 0, 1)

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

	s:Play()
	if DEBUG then
		print(string.format("[SoundDirector] %s%s", s.Name, pos and " (3D)" or ""))
	end
end

-- Igual que play() pero cuelga el clone DENTRO de su SoundGroup, para que el volumen del
-- grupo siga mandando. Para musica y ambiente, que no son 3D.
-- Devuelve el clone, o nil si el sonido no existe.
local function playGrouped(path, gain, looped)
	local template = resolve(path)
	if not template then
		if DEBUG then
			warn("[SoundDirector] no existe: " .. path)
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

local function fadeTo(sound, target, seconds)
	if not sound then
		return
	end
	TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = target }):Play()
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
		-- El servidor manda FireAllClients("fx", kind, pos, dir, force): aqui a es el tipo
		-- de efecto y b es la posicion. En el resto de eventos b no es una posicion, asi
		-- que se comprueba el tipo antes de usarlo.
		local pos = (typeof(b) == "Vector3") and b or nil
		for _, entry in ipairs(sounds) do
			play(entry[1], entry[2], entry[3], pos)
		end
	elseif kind == "countdown" then
		-- solo en los ultimos tres numeros, y algo mas fuerte cuanto mas cerca
		local n = tonumber(a) or 99
		if n >= 1 and n <= 3 then
			play(UI.countdown[1], UI.countdown[2] * (1.15 - 0.1 * n), UI.countdown[3])
		end
	elseif kind == "go" then
		play(UI.go[1], UI.go[2], UI.go[3])
	elseif kind == "point" then
		play(UI.point[1], UI.point[2], UI.point[3])
	elseif kind == "noscore" then
		-- caida sin punto: el golpe ya suena por su cuenta, aqui no se anade nada
	elseif kind == "match_start" then
		play(UI.matchStart[1], UI.matchStart[2], UI.matchStart[3])
	elseif kind == "match_end" or kind == "draw" then
		-- a es el nombre del ganador (nil si hubo empate): con ganador suena la victoria
		if kind == "match_end" and a == nil then
			play(UI.draw[1], UI.draw[2], UI.draw[3])
		else
			play(UI.victory[1], UI.victory[2], UI.victory[3])
		end
	end
end)

-- ============================================================================
-- Musica: lobby en reposo, batalla durante el combate
-- ============================================================================
-- El servidor ya pone el atributo InOilMatch (lo usan OilCombatHUD, OilRoundsHUD,
-- OilWinnerCeremony y CharacterAnimator), asi que no hace falta pedir nada extra.

local music = { lobby = nil, battle = nil, current = nil, lobbyVol = 0, battleVol = 0 }

local function startMusic()
	local lobby = playGrouped("MusicGroup/LobbyMusic", 1.0, true)
	local battle = playGrouped("MusicGroup/BattleMusic", 1.0, true)
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
	music.current = nil --Todavia no se ha elegido ninguna
end

local function setMusic(where)
	if music.current == where then
		return
	end
	music.current = where
	if where == "battle" then
		fadeTo(music.lobby, 0, 1.2)
		fadeTo(music.battle, music.battleVol, 1.2)
	else
		fadeTo(music.battle, 0, 1.2)
		fadeTo(music.lobby, music.lobbyVol, 1.2)
	end
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
