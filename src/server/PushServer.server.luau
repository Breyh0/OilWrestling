local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PushEvent = ReplicatedStorage:WaitForChild("PushEvent")

local cooldowns = {}

PushEvent.OnServerEvent:Connect(function(player)
    -- Doble validación de cooldown en el servidor
    if cooldowns[player] and tick() - cooldowns[player] < 1.5 then return end
    cooldowns[player] = tick()

    local character = player.Character
    if not character then return end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid or humanoid.Health <= 0 then return end

    local forwardVector = rootPart.CFrame.LookVector
    
    for _, target in pairs(workspace:GetChildren()) do
        if target ~= character and target:FindFirstChild("Humanoid") and target:FindFirstChild("HumanoidRootPart") then
            local targetRoot = target.HumanoidRootPart
            local targetHum = target.Humanoid
            
            if targetHum.Health > 0 then
                local distance = (targetRoot.Position - rootPart.Position).Magnitude
                local directionToTarget = (targetRoot.Position - rootPart.Position).Unit
                local dotProduct = forwardVector:Dot(directionToTarget)
                
                -- Misma lógica original: 6 studs de distancia, mirando hacia el objetivo
                if distance < 6 and dotProduct > 0.5 then
                    local mass = 0
                    for _, part in pairs(target:GetChildren()) do
                        if part:IsA("BasePart") then
                            mass = mass + part.Mass
                        end
                    end
                    
                    targetRoot:ApplyImpulse(forwardVector * mass * 60 + Vector3.new(0, mass * 20, 0))
                    targetHum.PlatformStand = true
                    task.delay(1.5, function()
                        if targetHum then targetHum.PlatformStand = false end
                    end)
                end
            end
        end
    end
end)
