local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local updateEvent = ReplicatedStorage:WaitForChild("UpdateProgression")
local frame = script.Parent:WaitForChild("Frame")
local player = Players.LocalPlayer

-- Actualizar textos cuando hay cambios en el progreso
updateEvent.OnClientEvent:Connect(function(data)
    local req = data.level * 100
    frame.TxtLevel.Text = "⭐ Nivel: " .. data.level .. " (" .. data.xp .. "/"..req.." XP)"
    frame.TxtCoins.Text = "🪙 Monedas: " .. data.coins
    frame.TxtMissions.Text = string.format("📝 Diarias: Victorias(%d/3) Sacar(%d/10) Parry(%d/1)", data.m_wins, data.m_ringouts, data.m_parrys)
end)

-- Sistema de visibilidad: Ocultar si el jugador está en combate
local function updateVisibility()
    local inMatch = player:GetAttribute("InOilMatch")
    script.Parent.Enabled = not inMatch
end

-- Escuchar cambios en el atributo de combate
player:GetAttributeChangedSignal("InOilMatch"):Connect(updateVisibility)

-- Llamada inicial para aplicar la visibilidad correcta apenas carga
updateVisibility()
