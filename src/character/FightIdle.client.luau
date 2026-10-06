local RunService = game:GetService("RunService")
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

local function findMotor(name)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == name then
			return d
		end
	end
	return nil
end

local isR15 = character:FindFirstChild("UpperTorso") ~= nil
local orig = {}
local function reg(j)
	if j then orig[j] = j.C0 end
	return j
end

local root, rSh, lSh, rHip, lHip, neck
if isR15 then
	root = reg(findMotor("Root"))
	rSh  = reg(findMotor("RightShoulder"))
	lSh  = reg(findMotor("LeftShoulder"))
	rHip = reg(findMotor("RightHip"))
	lHip = reg(findMotor("LeftHip"))
	neck = reg(findMotor("Neck"))
else
	root = reg(findMotor("RootJoint"))
	rSh  = reg(findMotor("Right Shoulder"))
	lSh  = reg(findMotor("Left Shoulder"))
	rHip = reg(findMotor("Right Hip"))
	lHip = reg(findMotor("Left Hip"))
	neck = reg(findMotor("Neck"))
end

if not (root and rSh and lSh) then return end

-- Ángulos base de la guardia
local rootX, rsX, rsZ, lsX, lsZ, hipX, neckX
if isR15 then
	rootX = -4
	rsX, rsZ = 70, -8
	lsX, lsZ = 70, 8
	hipX = 6
	neckX = -4
else
	rootX = -4
	rsX, rsZ = 100, 0
	lsX, lsZ = 100, 0
	hipX = 8
	neckX = -4
end

-- Ángulos del EMPUJE (2 manos al frente, cuerpo inclinado)
local pRootX = -20
local pRsX, pRsZ = 100, -5
local pLsX, pLsZ = 100, 5
local pHipX = 10
local pNeckX = 15
if not isR15 then
    pRsX, pRsZ = 110, 0
    pLsX, pLsZ = 110, 0
end

local function lerp(a, b, t) return a + (b - a) * t end

local t0 = os.clock()
local conn
conn = RunService.Heartbeat:Connect(function()
	local t = os.clock()
	local a = math.clamp((t - t0) / 0.4, 0, 1)
	local bob = math.sin(t * 4) * 0.06 * a
	local sway = math.sin(t * 2) * math.rad(3) * a

    -- Calcular qué tan avanzado va el empuje
    local pushStart = character:GetAttribute("PushStartTime") or 0
    local pt = t - pushStart
    local pAlpha = 0
    if pt < 0.15 then
        pAlpha = pt / 0.15 -- Extiende los brazos en 0.15s
    elseif pt < 0.45 then
        pAlpha = 1 - ((pt - 0.15) / 0.3) -- Recoge los brazos en 0.30s
    end
    pAlpha = math.clamp(pAlpha, 0, 1)
    pAlpha = math.sin(pAlpha * math.pi / 2) -- Suavizado

    -- Interpolar entre guardia e impacto
    local curRootX = lerp(rootX, pRootX, pAlpha)
    local curRsX = lerp(rsX, pRsX, pAlpha)
    local curRsZ = lerp(rsZ, pRsZ, pAlpha)
    local curLsX = lerp(lsX, pLsX, pAlpha)
    local curLsZ = lerp(lsZ, pLsZ, pAlpha)
    local curHipX = lerp(hipX, pHipX, pAlpha)
    local curNeckX = lerp(neckX, pNeckX, pAlpha)

	root.C0 = orig[root] * CFrame.Angles(math.rad(curRootX) * a, 0, 0) * CFrame.new(0, bob, 0)
	rSh.C0 = orig[rSh] * CFrame.Angles(math.rad(curRsX) * a + sway, 0, math.rad(curRsZ) * a)
	lSh.C0 = orig[lSh] * CFrame.Angles(math.rad(curLsX) * a - sway, 0, math.rad(curLsZ) * a)
	
	if rHip then rHip.C0 = orig[rHip] * CFrame.Angles(math.rad(curHipX) * a, 0, 0) end
	if lHip then lHip.C0 = orig[lHip] * CFrame.Angles(math.rad(curHipX) * a, 0, 0) end
	if neck then neck.C0 = orig[neck] * CFrame.Angles(math.rad(curNeckX) * a, 0, 0) end
end)

humanoid.Died:Connect(function()
	if conn then conn:Disconnect() end
end)
