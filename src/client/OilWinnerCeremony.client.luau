-- OilWinnerCeremony (LocalScript, StarterPlayerScripts)
-- Interfaz ANIMADA del GANADOR: al terminar el combate anuncia al campeón con
-- rayos de luz giratorios, lluvia de confeti, corona y su nombre con brillo animado.
-- Solo dibuja: el servidor (OilCombat) manda el evento "match_end" con el ganador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local eventRemote = ReplicatedStorage:WaitForChild("OilEvent")
local pg = player:WaitForChild("PlayerGui")
local menu = pg:WaitForChild("MainMenu", 20)

local GOLD = Color3.fromRGB(255, 205, 70)
local CREAM = Color3.fromRGB(255, 236, 170)
local WHITE = Color3.new(1, 1, 1)

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(o, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local gui = make("ScreenGui", {
	Name = "OilWinnerCeremony",
	ResetOnSpawn = false,
	DisplayOrder = 62,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, pg)

-- 1) Fondo oscuro que resalta al campeón
local overlay = make("Frame", {
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(8, 6, 3),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, gui)

-- 2) Rayos de luz que giran detrás del ganador
local raysHolder = make("Frame", {
	Name = "Rays",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
}, gui)
local RAY_COUNT = 22
for i = 1, RAY_COUNT do
	local ray = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(1500, 48),
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Rotation = (i - 1) / RAY_COUNT * 360,
	}, raysHolder)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, ray)
end

-- 3) Confeti (detrás del texto para que se lea bien)
local confetti = make("Frame", {
	Name = "Confetti",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = false,
}, gui)
local confettiActive = false
local CONFETTI_COLORS = {
	GOLD, CREAM, Color3.fromRGB(235, 90, 80), Color3.fromRGB(120, 225, 140),
	Color3.fromRGB(255, 145, 60), WHITE, Color3.fromRGB(140, 190, 255),
}

-- 4) Escenario central
local stage = make("Frame", {
	Name = "Stage",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(820, 460),
	BackgroundTransparency = 1,
}, gui)
local stageScale = make("UIScale", {}, stage)

local crown = make("TextLabel", {
	Name = "Crown",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(150, 110),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = GOLD,
	Text = "\u{1F451}",
}, stage)
make("UITextSizeConstraint", { MaxTextSize = 96, MinTextSize = 40 }, crown)

local kicker = make("TextLabel", {
	Name = "Kicker",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 122),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextSize = 26,
	TextColor3 = GOLD,
	TextStrokeTransparency = 0.4,
	Text = "¡TENEMOS GANADOR!",
}, stage)

local nameLabel = make("TextLabel", {
	Name = "WinnerName",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 154),
	Size = UDim2.new(1, -40, 0, 130),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = WHITE,
	TextStrokeTransparency = 0.25,
	Text = "CAMPEÓN",
}, stage)
make("UITextSizeConstraint", { MaxTextSize = 110, MinTextSize = 26 }, nameLabel)
local GOLD_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 235, 150)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 190, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 235, 150)),
})
local PARTY_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 90)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 215, 90)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 240, 150)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(130, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 90)),
})
local nameGradient = make("UIGradient", { Color = GOLD_SEQ, Rotation = 0 }, nameLabel)
local nameStroke = make("UIStroke", { Color = WHITE, Thickness = 2.5, Transparency = 0.3 }, nameLabel)

local sub = make("TextLabel", {
	Name = "Score",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 296),
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 26,
	TextColor3 = CREAM,
	TextStrokeTransparency = 0.55,
	Text = "",
}, stage)

local foot = make("TextLabel", {
	Name = "Foot",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 344),
	Size = UDim2.new(1, 0, 0, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(205, 195, 165),
	TextStrokeTransparency = 0.6,
	Text = "",
}, stage)

-- ===== Confeti =====
local function spawnConfetti()
	confetti:ClearAllChildren()
	confettiActive = true
	for _ = 1, 90 do
		local w = math.random(6, 14)
		local h = math.random(10, 20)
		local p = make("Frame", {
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = CONFETTI_COLORS[math.random(#CONFETTI_COLORS)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			Position = UDim2.new(math.random(), 0, -0.15, 0),
		}, confetti)
		corner(p, 2)
		task.spawn(function()
			while confettiActive and p.Parent do
				local dur = math.random(30, 65) / 10
				local fromX = math.random()
				local toX = math.random()
				p.Position = UDim2.new(fromX, 0, -0.15, 0)
				p.Rotation = math.random(0, 360)
				TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
					Position = UDim2.new(toX, 0, 1.15, 0),
					Rotation = p.Rotation + math.random(-540, 540),
				}):Play()
				task.wait(dur + math.random(0, 15) / 10)
			end
		end)
	end
end

local function stopConfetti()
	confettiActive = false
	confetti:ClearAllChildren()
end

-- ===== Utilidades =====
local function parseWinner(raw)
	if type(raw) ~= "string" then
		return nil, nil
	end
	local name, secs = string.match(raw, "^(.*) %(Lobby en (%d+)s%)$")
	if name then
		return name, tonumber(secs)
	end
	return raw, nil
end

local function scoreLine(list)
	if type(list) ~= "table" or #list == 0 then
		return ""
	end
	local ordered = {}
	for _, f in ipairs(list) do
		if f.name == player.Name then
			table.insert(ordered, 1, f)
		else
			table.insert(ordered, f)
		end
	end
	local function nameOf(f)
		return f.name == player.Name and "TÚ" or f.name
	end
	if #ordered == 2 then
		return string.format("%s  %d — %d  %s", nameOf(ordered[1]), ordered[1].score or 0, ordered[2].score or 0, nameOf(ordered[2]))
	end
	local parts = {}
	for _, f in ipairs(ordered) do
		table.insert(parts, nameOf(f) .. " " .. (f.score or 0))
	end
	return table.concat(parts, "   ·   ")
end

-- ===== Mostrar / ocultar =====
local token = 0
local ceremonyShown = false
local ceremonyWinner = nil
local stageBase = 1

local function showCeremony(winner, secs, list)
	token += 1
	local mine = (winner == player.Name)
	gui.Enabled = true
	overlay.BackgroundTransparency = 1
	TweenService:Create(overlay, TweenInfo.new(0.5), { BackgroundTransparency = 0.45 }):Play()

	kicker.Text = mine and "¡VICTORIA! ERES EL CAMPEÓN" or "¡TENEMOS GANADOR!"
	kicker.TextColor3 = mine and GOLD or CREAM
	nameLabel.Text = string.upper(winner)
	nameGradient.Color = mine and GOLD_SEQ or PARTY_SEQ
	sub.Text = scoreLine(list)
	foot.Text = secs and ("Volviendo al lobby en " .. secs .. "s") or ""

	stageScale.Scale = 0.35
	TweenService:Create(stageScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = stageBase }):Play()

	spawnConfetti()
end

local function hideCeremony()
	token += 1
	local my = token
	stopConfetti()
	ceremonyShown = false
	ceremonyWinner = nil
	TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(stageScale, TweenInfo.new(0.3), { Scale = 0.6 }):Play()
	task.delay(0.45, function()
		if token == my then
			gui.Enabled = false
		end
	end)
end

-- ===== Escala según pantalla =====
local function updateScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	stageBase = math.clamp(math.min(vp.X / 1000, vp.Y / 620), 0.5, 1.15)
	stageScale.Scale = stageBase
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- ===== Animación continua =====
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then
		return
	end
	local t = os.clock()
	raysHolder.Rotation = (raysHolder.Rotation + dt * 9) % 360
	local bob = math.sin(t * 2.4)
	crown.Position = UDim2.new(0.5, 0, 0, 12 + bob * 8)
	crown.Rotation = bob * 7
	nameGradient.Offset = Vector2.new(((t * 0.22) % 1) * 2 - 1, 0)
	nameStroke.Transparency = 0.2 + 0.25 * (0.5 + 0.5 * math.sin(t * 3))
end)

-- ===== Eventos del combate =====
eventRemote.OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "match_start" then
		if gui.Enabled then
			hideCeremony()
		end
		return
	elseif kind ~= "match_end" then
		return
	end
	local winner, secs = parseWinner(a)
	if not winner then
		if gui.Enabled then
			hideCeremony()
		end
		return
	end
	if not ceremonyShown or ceremonyWinner ~= winner then
		ceremonyShown = true
		ceremonyWinner = winner
		showCeremony(winner, secs, b, c)
	elseif secs then
		foot.Text = "Volviendo al lobby en " .. secs .. "s"
	end
end)

player:GetAttributeChangedSignal("InOilMatch"):Connect(function()
	if player:GetAttribute("InOilMatch") ~= true and gui.Enabled then
		hideCeremony()
	end
end)

if menu then
	menu:GetPropertyChangedSignal("Enabled"):Connect(function()
		if menu.Enabled and gui.Enabled then
			hideCeremony()
		end
	end)
end
