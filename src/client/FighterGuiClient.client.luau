-- FighterGuiClient (cliente)
-- Muestra estado del ciclo: esperando, intermision (cuenta regresiva), pelea, fin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FighterGui")
local panel = gui:WaitForChild("Panel")
local status = panel:WaitForChild("Status")
local sub = panel:WaitForChild("Sub")

local matchEvent = ReplicatedStorage:WaitForChild("MatchUpdate")

-- Solo visible cuando el jugador ya salio del menu principal
local menu = player:WaitForChild("PlayerGui"):WaitForChild("MainMenu")
local function syncVisibility()
	gui.Enabled = not (menu and menu.Enabled)
end
syncVisibility()
if menu then
	menu:GetPropertyChangedSignal("Enabled"):Connect(syncVisibility)
end

matchEvent.OnClientEvent:Connect(function(info)
	if info.status == "waiting" then
		status.Text = "Esperando jugadores..."
		sub.Text = "M\u{00ED}nimo "..info.needed.." | Hay "..info.players
	elseif info.status == "intermission" then
		status.Text = "Intermisi\u{00F3}n: "..info.seconds.."s"
		sub.Text = "Prep\u{00E1}rate para el combate..."
	elseif info.status == "started" then
		status.Text = "\u{00A1}A la arena!"
		sub.Text = "Luchadores: "..table.concat(info.fighters, ", ")
	elseif info.status == "ended" then
		status.Text = "Combate finalizado"
		sub.Text = "Siguiente ronda pronto..."
	end
end)
