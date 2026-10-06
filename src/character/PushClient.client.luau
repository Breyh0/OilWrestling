local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PushEvent = ReplicatedStorage:WaitForChild("PushEvent")

local character = script.Parent
local cooldown = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- Detectar Click Izquierdo del ratón o Toque en pantalla (para móviles)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if cooldown then return end
        cooldown = true
        
        -- Actualizar el atributo para que FightIdle renderice el empuje a dos manos
        character:SetAttribute("PushStartTime", os.clock())
        
        -- Enviar la señal de impacto físico al servidor
        PushEvent:FireServer()
        
        task.wait(1.5)
        cooldown = false
    end
end)
