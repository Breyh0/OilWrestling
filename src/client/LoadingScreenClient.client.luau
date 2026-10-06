-- LoadingScreenClient (cliente)
-- Pantalla de carga: precarga assets, anima la barra, muestra tips y hace fade al terminar.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui", 10)
local gui = pg:WaitForChild("LoadingScreen", 10)

local bg = gui:WaitForChild("Background", 5)
local content = bg:WaitForChild("Content", 5)
local particles = bg:WaitForChild("Particles", 5)
local title = content:WaitForChild("Title", 5)
local barBg = content:WaitForChild("BarBg", 5)
local barFill = barBg:WaitForChild("BarFill", 5)
local shine = barFill:WaitForChild("Shine", 5)
local loadingText = content:WaitForChild("LoadingText", 5)
local percent = barBg:WaitForChild("Percent", 5)
local tip = content:WaitForChild("Tip", 5)

local MIN_TIME = 3     -- tiempo minimo visible (segundos)
local MAX_TIME = 10    -- tope por si la precarga tarda demasiado

local TIPS = {
	"El aceite te hace resbaladizo: controla tus pasos.",
	"Haz que tu rival toque el suelo con la espalda.",
	"Elige bien el momento para empujar.",
	"Cuidado con el borde de la arena.",
	"La pr\u{00E1}ctica hace al campe\u{00F3}n del aceite.",
}

local PHASES = {
	{0.00, "Preparando la arena..."},
	{0.35, "Engrasando el ring..."},
	{0.70, "Calentando a los luchadores..."},
	{0.95, "\u{00DA}ltimos detalles..."},
}

tip.Text = "TIP: " .. TIPS[math.random(1, #TIPS)]

-- ===== Animaciones decorativas =====
-- Brillo que recorre la barra
TweenService:Create(shine, TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
	Position = UDim2.new(1, 0, 0, 0)
}):Play()

-- Pulso del titulo
local pulse = title:FindFirstChild("Pulse")
if pulse then
	TweenService:Create(pulse, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Scale = 1.04
	}):Play()
end

-- Gotas de aceite flotando
local function spawnOilDrop()
	local drop = Instance.new("Frame")
	drop.BackgroundColor3 = Color3.fromRGB(240, 200, 90)
	drop.BackgroundTransparency = math.random(70, 90) / 100
	drop.BorderSizePixel = 0
	local size = math.random(8, 22)
	drop.Size = UDim2.fromOffset(size, size)
	local x = math.random(0, 100) / 100
	drop.Position = UDim2.new(x, 0, 1.1, 0)
	drop.Parent = particles
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = drop

	local tween = TweenService:Create(drop, TweenInfo.new(math.random(6, 12), Enum.EasingStyle.Linear), {
		Position = UDim2.new(x, 0, -0.15, 0)
	})
	tween:Play()
	tween.Completed:Connect(function() drop:Destroy() end)
end

task.spawn(function()
	while gui.Parent do
		spawnOilDrop()
		task.wait(math.random(30, 70) / 100)
	end
end)

-- ===== Precarga real de assets =====
local assetsDone = false
task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	pcall(function()
		ContentProvider:PreloadAsync(workspace:GetDescendants())
	end)
	assetsDone = true
end)

-- ===== Progreso =====
local startTime = os.clock()
local shown = 0

while true do
	local dt = RunService.RenderStepped:Wait()
	local elapsed = os.clock() - startTime

	local target = math.min(elapsed / MIN_TIME, 1)
	if not assetsDone and elapsed < MAX_TIME then
		target = math.min(target, 0.92) -- no llega al 100% hasta que todo este cargado
	else
		target = 1
	end

	shown = shown + (target - shown) * math.min(1, dt * 6)
	barFill.Size = UDim2.new(shown, 0, 1, 0)
	percent.Text = math.floor(shown * 100) .. "%"

	for i = #PHASES, 1, -1 do
		if shown >= PHASES[i][1] then
			loadingText.Text = PHASES[i][2]
			break
		end
	end

	if target >= 1 and shown >= 0.995 then break end
end

barFill.Size = UDim2.new(1, 0, 1, 0)
percent.Text = "100%"
loadingText.Text = "\u{00A1}Listo!"
task.wait(0.6)

-- Activar el menu principal ANTES del fade (es opaco, tapa el juego)
local mainMenu = pg:FindFirstChild("MainMenu")
if mainMenu then
	mainMenu.Enabled = true
end

-- ===== Fade out de todo =====
local FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function fade(obj, props)
	TweenService:Create(obj, FADE, props):Play()
end

for _, d in ipairs(bg:GetDescendants()) do
	if d:IsA("TextLabel") or d:IsA("TextButton") then
		fade(d, {TextTransparency = 1, BackgroundTransparency = 1, TextStrokeTransparency = 1})
	elseif d:IsA("Frame") then
		fade(d, {BackgroundTransparency = 1})
	elseif d:IsA("UIStroke") then
		fade(d, {Transparency = 1})
	end
end
fade(bg, {BackgroundTransparency = 1})

task.wait(0.7)
gui:Destroy()
