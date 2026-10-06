-- GameHUDClient (cliente)
-- HUD de partida: estado, chip de modo, temporizador, cuenta regresiva y boton de volver al menu.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local pg = player:WaitForChild("PlayerGui", 10)
local hud = pg:WaitForChild("GameHUD", 20)
local menu = pg:WaitForChild("MainMenu", 20)
local bar = hud:WaitForChild("TopBar", 5)
local menuBtn = hud:WaitForChild("MenuBtn", 5)
local status = bar:WaitForChild("Status", 5)
local modeChip = bar:WaitForChild("ModeChip", 5)
local timerLabel = bar:WaitForChild("TimerLabel", 5)
local countdown = hud:WaitForChild("Countdown", 5)
local countScale = countdown:WaitForChild("Pop", 5)
local menuScale = menuBtn:WaitForChild("HoverScale", 5)

local matchEvent = ReplicatedStorage:WaitForChild("MatchUpdate", 10)
local returnEvent = ReplicatedStorage:FindFirstChild("ReturnToMenu")
if not returnEvent then
	returnEvent = Instance.new("RemoteEvent")
	returnEvent.Name = "ReturnToMenu"
	returnEvent.Parent = ReplicatedStorage
end

local CREAM = Color3.fromRGB(240, 220, 120)
local RED = Color3.fromRGB(235, 90, 80)
local MODE_STYLE = {
	solo = { text = "VS IA", color = Color3.fromRGB(70, 150, 70) },
	multi = { text = "MULTIJUGADOR", color = Color3.fromRGB(60, 120, 200) },
}

-- ===== Hover del boton menu =====
local baseCol = Color3.fromRGB(200, 70, 60)
menuBtn.MouseEnter:Connect(function()
	TweenService:Create(menuBtn, TweenInfo.new(0.2), { BackgroundColor3 = baseCol:Lerp(Color3.new(1, 1, 1), 0.25) }):Play()
	TweenService:Create(menuScale, TweenInfo.new(0.2), { Scale = 1.05 }):Play()
end)
menuBtn.MouseLeave:Connect(function()
	TweenService:Create(menuBtn, TweenInfo.new(0.2), { BackgroundColor3 = baseCol }):Play()
	TweenService:Create(menuScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
end)

-- ===== Utilidades =====
local function inGame()
	return not menu.Enabled -- el jugador ya salio del menu principal
end

local function setMode(mode)
	local style = MODE_STYLE[mode]
	if style then
		modeChip.Text = style.text
		modeChip.BackgroundColor3 = style.color
		modeChip.Visible = true
	end
end

-- Temporizador del combate
local timerToken = 0
local function stopTimer()
	timerToken += 1
	timerLabel.Text = ""
end

local function startTimer(seconds)
	timerToken += 1
	local my = timerToken
	task.spawn(function()
		local endTime = os.clock() + seconds
		while timerToken == my do
			local left = math.max(0, math.ceil(endTime - os.clock()))
			timerLabel.Text = string.format("%d:%02d", math.floor(left / 60), left % 60)
			timerLabel.TextColor3 = (left <= 10) and RED or CREAM
			if left <= 0 then break end
			task.wait(0.2)
		end
	end)
end

-- Numero / texto grande en el centro con efecto "pop"
local countToken = 0
local function popCount(text, color)
	countToken += 1
	local my = countToken
	countdown.Text = text
	countdown.TextColor3 = color
	countdown.TextTransparency = 0
	countdown.TextStrokeTransparency = 0.5
	countdown.Visible = true
	countScale.Scale = 1.6
	TweenService:Create(countScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.delay(0.7, function()
		if countToken ~= my then return end
		local tw = TweenService:Create(countdown, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		if countToken == my then countdown.Visible = false end
	end)
end

-- ===== Eventos de la partida =====
matchEvent.OnClientEvent:Connect(function(info)
	-- Renuncia: quien renuncia vuelve al lobby (lo hace el servidor) y su cliente regresa al menu principal
	if info.status == "forfeit" then
		if info.player == player.Name then
			stopTimer()
			countToken += 1
			countdown.Visible = false
			modeChip.Visible = false
			hud.Enabled = false
			menu.Enabled = true -- MainMenu reproduce su animacion de entrada
		end
		return
	end
	if info.status == "returned" then return end
	if not inGame() then return end

	hud.Enabled = true
	setMode(info.mode)

	if info.status == "waiting" then
		stopTimer()
		status.Text = "ESPERANDO JUGADORES"

	elseif info.status == "intermission" then
		stopTimer()
		status.Text = "PREPARANDO COMBATE"
		if info.seconds and info.seconds <= 5 then
			popCount(tostring(info.seconds), CREAM)
		end

	elseif info.status == "started" then
		local isFighter = info.fighters and table.find(info.fighters, player.Name) ~= nil
		status.Text = isFighter and "\u{00A1}EN COMBATE!" or "ESPECTANDO"
		if info.duration then startTimer(info.duration) end
		if not info.scored then
			popCount("\u{00A1}PELEA!", RED) -- con rounds, el marcador (OilRoundsHUD) muestra su propia cuenta atrás
		end

	elseif info.status == "ended" then
		stopTimer()
		status.Text = "COMBATE FINALIZADO"
	end
end)

-- ===== Volver al menu =====
menuBtn.MouseButton1Click:Connect(function()
	returnEvent:FireServer()
	stopTimer()
	countToken += 1
	countdown.Visible = false
	modeChip.Visible = false
	hud.Enabled = false
	menu.Enabled = true -- MainMenu reproduce su animacion de entrada
end)
